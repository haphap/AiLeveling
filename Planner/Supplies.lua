local _,A=...
A.Supplies={}
local S=A.Supplies
function S:IgnoreRepair()
    if not A.ready then return end
    A.char.ignoreRepair=true
    A:RequestRefresh()
end
local function ids(map)
    local result={}
    for id in pairs(map or {}) do result[#result+1]=id end
    table.sort(result,function(a,b) if type(a)==type(b) then return a<b end return tostring(a)<tostring(b) end)
    return result
end
local function general(inventory)
    local count=0
    for _,bag in pairs(inventory.bags) do if bag.family==0 then count=count+bag.free end end
    return count
end
function S.QuestLog(state)
    local active,count={},0
    for id in pairs(state.activeQuests or state.quests or {}) do active[id]=true;count=count+1 end
    return {questCount=state.questCount or count,questLimit=state.questLimit,activeQuests=active}
end

function S.AcceptIssue(state)
    local limit=state.questLimit
    if type(limit)~="number" or limit<=0 or limit>=math.huge or limit%1~=0 then return "普通任务日志上限尚未确认" end
    local count=state.questCount
    if count==nil then
        count=0;for _ in pairs(state.activeQuests or state.quests or {}) do count=count+1 end
    end
    if count>=limit then return "任务日志已满，先交付或整理已有任务再接取" end
end

-- Only the private planning ledger changes here; the live quest log remains authoritative.
function S.ApplyQuestLog(action,log)
    local id=action.questId
    if action.kind=="accept" and not log.activeQuests[id] then
        local why=S.AcceptIssue(log)
        if why then return nil,why end
        log.activeQuests[id]=true;log.questCount=log.questCount+1
    elseif action.kind=="turnin" and log.activeQuests[id] then
        log.activeQuests[id]=nil;log.questCount=math.max(0,log.questCount-1)
    end
    return true
end

function S.Done(action,state)
    local goal=action.serviceGoal
    if not goal then return false end
    if goal.items then for id,count in pairs(goal.items) do if (state.bags[id] or 0)<count then return false end end end
    if goal.absentItems then for id in pairs(goal.absentItems) do if (state.bags[id] or 0)>0 then return false end end end
    if goal.durability and (not state.durability or state.durability<goal.durability) then return false end
    if goal.freeSlots and (state.inventory and general(state.inventory) or state.freeSlots or 0)<goal.freeSlots then return false end
    return true
end
function S:Snapshot(state)
    local wanted,links={},{}
    state.itemMetadata,state.protectedItems={},{}
    for _,entry in ipairs(state.bagEntries or {}) do wanted[entry.id]=true;links[entry.id]=entry.link end
    for id,quest in pairs(state.quests) do
        if quest.itemId then state.protectedItems[quest.itemId]=true end
        local q=A.Data and A.Data.GetQuest and A.Data:GetQuest(id)
        if q then
            if q.sourceItemId and q.sourceItemId>0 then state.protectedItems[q.sourceItemId]=true end
            for _,item in ipairs(q.requiredSourceItems or {}) do state.protectedItems[item]=true end
            for item in pairs(q.itemRules or {}) do state.protectedItems[item]=true end
        end
    end
    for id in pairs(wanted) do
        local item={}
        local name,_,quality,_,_,_,_,stackSize,_,_,sellPrice=C_Item.GetItemInfo(links[id] or id)
        if name then item.name,item.quality,item.stackSize,item.sellPrice=name,quality,stackSize,sellPrice end
        if C_Item.GetItemFamily then item.family=C_Item.GetItemFamily(links[id] or id) or item.family end
        state.itemMetadata[id]=item
        if not item.stackSize and not A.requestedItems[id] then
            A.requestedItems[id]=true;C_Item.RequestLoadItemDataByID(id)
        end
    end
    for _,entry in ipairs(state.bagEntries or {}) do
        local info=C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(entry.bag,entry.slot)
        state.inventory.slots[#state.inventory.slots+1]={id=entry.id,count=entry.count,bag=entry.bag,
            questKnown=info~=nil,questItem=info and (info.isQuestItem or info.questID~=nil),locked=entry.locked}
    end
    local durabilityKnown
    if GetInventoryItemDurability then
        state.durability=1
        for slot=1,19 do
            local current,maximum=GetInventoryItemDurability(slot)
            if current and maximum and maximum>0 then
                durabilityKnown=true;state.durability=math.min(state.durability,current/maximum)
            end
        end
    end
    if A.char and durabilityKnown and state.durability>=0.2 then A.char.ignoreRepair=nil end
    state.ignoreRepair=A.char and A.char.ignoreRepair==true or false
    local key={tostring(state.questCount),tostring(state.questLimit),tostring(state.durability),tostring(state.ignoreRepair)}
    for bag,space in pairs(state.inventory.bags) do key[#key+1]="bag"..bag..":"..tostring(space.family)..":"..space.free end
    for _,id in ipairs(ids(state.itemMetadata)) do
        local item=state.itemMetadata[id]
        key[#key+1]=id..":"..tostring(item.stackSize)..":"..tostring(item.family)..":"..tostring(item.sellPrice)..":"..tostring(item.quality)
    end
    for _,slot in ipairs(state.inventory.slots) do key[#key+1]="item"..slot.id..":"..tostring(slot.questKnown)..":"..tostring(slot.questItem)..":"..tostring(slot.locked) end
    table.sort(key)
    return table.concat(key,"|")
end

function S.Fallback(state,data)
    local need=not state.ignoreRepair and state.durability and state.durability<0.2 and "repair" or (state.freeSlots==0 and "vendor")
    if not need then return end
    local text=need=="repair" and "维修装备" or "背包已满，整理背包或出售物品"
    local current=A.Merchant and A.Merchant.CurrentService(state,need,nil,data)
    if current then return current,text end
    local best
    if data.ServicePoints and state.position and not state.dead and not state.inInstance then
        local points=data:ServicePoints(state,need)
        for _,point in ipairs(points) do
            point.distance=A.Navigation and A.Navigation.Distance and A.Navigation:Distance(state.position,point.position)
        end
        local selected,distance
        for _,point in ipairs(points) do
            local cost=point.distance
            if cost and (not selected or cost<distance) then selected,distance=point,cost end
        end
        if selected then
            local action={kind="service",serviceKind=need,serviceId="npc:"..selected.npcId,npcId=selected.npcId,
                position=selected.position,title=selected.title,text=text.."。",
                serviceGoal=need=="repair" and {durability=0.2} or {freeSlots=1}}
            best={id="service:npc:"..selected.npcId,title=selected.title,kind="service",reference=true,
                actions={action}}
        end
    end
    return best,text
end
