local _,A=...
A.Supplies={}
local S=A.Supplies
function S:IgnoreRepair()
    if not A.ready then return end
    A.char.ignoreRepair=true
    A:RequestRefresh()
end
local function clone(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=clone(item) end
    return result
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
local function matches(family,itemFamily)
    if family==0 then return true end
    if not family or not itemFamily then return false end
    while family>0 and itemFamily>0 do
        if family%2==1 and itemFamily%2==1 then return true end
        family,itemFamily=math.floor(family/2),math.floor(itemFamily/2)
    end
    return false
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

function S.Cursor(state)
    local cursor=S.QuestLog(state)
    cursor.bags=clone(state.bags or {})
    cursor.inventory=clone(state.inventory or {bags={{family=0,free=state.freeSlots or 0}},slots={}})
    cursor.durability,cursor.unlocked,cursor.level=state.durability,clone(state.unlocked or {}),state.level
    cursor.ignoreRepair=state.ignoreRepair
    return cursor
end
local function remove(cursor,id,count)
    local all=(cursor.bags[id] or 0)==count
    cursor.bags[id]=(cursor.bags[id] or 0)-count
    for index=#cursor.inventory.slots,1,-1 do
        local slot=cursor.inventory.slots[index]
        if slot.id==id then
            local used=math.min(slot.count,count);slot.count,count=slot.count-used,count-used
            if all then
                cursor.inventory.bags[slot.bag].free=cursor.inventory.bags[slot.bag].free+1
                table.remove(cursor.inventory.slots,index)
            end
        end
    end
    -- Partial consumption may empty different stacks; only a whole-item clear guarantees free slots.
end
local function gain(cursor,id,count,metadata)
    local item=metadata[id]
    if not item or not item.stackSize then return false,{kind="metadata",text="物品堆叠资料待加载 #"..id} end
    for _,slot in ipairs(cursor.inventory.slots) do
        if slot.id==id then
            local used=math.min(count,math.max(0,item.stackSize-slot.count));slot.count,count=slot.count+used,count-used
        end
    end
    while count>0 do
        local selected
        for index,bag in pairs(cursor.inventory.bags) do
            if bag.free>0 and matches(bag.family,item.family) and (not selected or
                (bag.family~=0 and cursor.inventory.bags[selected].family==0)) then selected=index end
        end
        if not selected then return false,{kind="space",text="背包空间不足",capacityItems={[id]=count}} end
        local used=math.min(count,item.stackSize)
        cursor.inventory.slots[#cursor.inventory.slots+1]={id=id,count=used,bag=selected,questKnown=false}
        cursor.inventory.bags[selected].free=cursor.inventory.bags[selected].free-1
        count=count-used
    end
    return true
end
local function space(cursor,action,metadata)
    local minimum=math.max(action.minFreeSlots or 0,action.reserveSlots or 0)
    if general(cursor.inventory)<minimum then return false,{kind="space",text="通用背包空间不足",freeSlots=minimum} end
    for _,id in ipairs(ids(action.gainItems)) do
        local ok,issue=gain(cursor,id,action.gainItems[id],metadata)
        if not ok then
            if issue.kind=="space" then issue.capacityItems=action.gainItems;issue.freeSlots=minimum end
            return false,issue
        end
        cursor.bags[id]=(cursor.bags[id] or 0)+action.gainItems[id]
    end
    local reserved=action.reserveSlots or 0
    for _,bag in pairs(cursor.inventory.bags) do
        if bag.family==0 then local used=math.min(reserved,bag.free);bag.free,reserved=bag.free-used,reserved-used end
    end
    return true
end
function S.Apply(action,cursor,metadata)
    local projected=clone(cursor)
    local logOK,logIssue=S.ApplyQuestLog(action,projected)
    if not logOK then return nil,{kind="log",text=logIssue} end
    if not projected.ignoreRepair and action.minDurability and (not projected.durability or projected.durability<action.minDurability) then
        return nil,{kind="repair",text=projected.durability and "装备耐久低于本段要求" or "装备耐久尚未确认",durability=action.minDurability}
    end
    local required={}
    for _,map in ipairs({action.requiredItems or {},action.items or {},action.consumeItems or {}}) do
        for id,count in pairs(map) do required[id]=math.max(required[id] or 0,count) end
    end
    local missing={}
    for id,count in pairs(required) do if (projected.bags[id] or 0)<count then missing[id]=count-(projected.bags[id] or 0) end end
    if next(missing) then
        local names={}
        for _,id in ipairs(ids(missing)) do names[#names+1]=((metadata[id] and metadata[id].name) or ("#"..id)).."×"..missing[id] end
        return nil,{kind="items",text="缺少必需物品："..table.concat(names,"、"),missing=missing}
    end
    for id,count in pairs(action.consumeItems or {}) do remove(projected,id,count) end
    local ok,issue=space(projected,action,metadata)
    if not ok then return nil,issue end
    if action.repairTo then projected.durability=action.repairTo end
    if action.durabilityLoss then
        if not projected.durability then return nil,{kind="unknown",text="耐久消耗模型缺少当前耐久"} end
        projected.durability=math.max(0,projected.durability-action.durabilityLoss)
    end
    if action.unlockAfter then projected.unlocked[action.unlockAfter]=true end
    for _,key in ipairs(action.unlocksAfter or {}) do projected.unlocked[key]=true end
    if action.levelAfter then projected.level=action.levelAfter end
    return projected
end
function S.Done(action,state)
    local goal=action.serviceGoal
    if not goal then return false end
    if goal.items then for id,count in pairs(goal.items) do if (state.bags[id] or 0)<count then return false end end end
    if goal.absentItems then for id in pairs(goal.absentItems) do if (state.bags[id] or 0)>0 then return false end end end
    if goal.durability and (not state.durability or state.durability<goal.durability) then return false end
    if goal.capacityItems or goal.freeSlots then
        local cursor=S.Cursor(state)
        local ok=space(cursor,{gainItems=goal.capacityItems,minFreeSlots=goal.freeSlots},state.itemMetadata or {})
        if not ok then return false end
    end
    return true
end
function S.Key(cursor)
    local parts={tostring(cursor.questCount),tostring(cursor.durability),tostring(cursor.ignoreRepair)}
    for _,id in ipairs(ids(cursor.bags)) do parts[#parts+1]=id..":"..cursor.bags[id] end
    for index,bag in pairs(cursor.inventory.bags) do parts[#parts+1]="bag"..index..":"..bag.free end
    for _,id in ipairs(ids(cursor.activeQuests)) do parts[#parts+1]="quest"..id end
    for _,slot in ipairs(cursor.inventory.slots) do parts[#parts+1]="slot"..tostring(slot.bag)..":"..tostring(slot.id)..":"..slot.count end
    for _,key in ipairs(ids(cursor.unlocked)) do if cursor.unlocked[key] then parts[#parts+1]="unlock"..key end end
    parts[#parts+1]="level"..tostring(cursor.level)
    return table.concat(parts,"|")
end
function S.Available(point,state,content)
    return point.verified and content.sources[point.source] and content.nodes[point.node] and
        (not point.faction or point.faction=="Neutral" or point.faction==state.faction) and
        (not point.minLevel or state.level>=point.minLevel) and
        (not point.maxLevel or state.level<=point.maxLevel) and
        (not point.unlock or (state.unlocked and state.unlocked[point.unlock]))
end
local function recover(issue,cursor,state,content,protected)
    local results={}
    for _,id in ipairs(ids(content.services)) do
        local service=content.services[id]
        if S.Available(service,{level=cursor.level,faction=state.faction,unlocked=cursor.unlocked},content) then
            local action={kind="service",serviceId=id,node=service.node,title=service.title,sampleKind="recovery"}
            if issue.kind=="repair" and cursor.durability~=nil and service.repair then
                action.serviceKind,action.repairTo="repair",1
                action.seconds=service.repair.seconds
                action.serviceGoal={durability=issue.durability}
                action.text="维修装备。"
            elseif issue.kind=="items" and service.stock then
                local gains,targets={},{}
                for item,count in pairs(issue.missing) do
                    local stock=service.stock[item]
                    if stock then
                        gains[item],targets[item]=count,(cursor.bags[item] or 0)+count
                    end
                end
                if next(gains) then
                    action.serviceKind,action.gainItems="supply",gains
                    action.seconds=service.purchaseSeconds;action.serviceGoal={items=targets}
                    action.text="购买所列必需物品。"
                end
            elseif issue.kind=="space" and service.vendorSeconds then
                local sales,unsafe={},{}
                for _,slot in ipairs(cursor.inventory.slots) do
                    local item=state.itemMetadata and state.itemMetadata[slot.id]
                    if slot.id and (protected[slot.id] or not slot.questKnown or slot.questItem or slot.locked or
                        not item or item.quality~=0 or not item.sellPrice or item.sellPrice<=0) then unsafe[slot.id]=true end
                end
                for _,slot in ipairs(cursor.inventory.slots) do
                    if slot.id and not unsafe[slot.id] and slot.count>0 then sales[slot.id]=(sales[slot.id] or 0)+slot.count end
                end
                if next(sales) then
                    action.serviceKind,action.consumeItems="vendor",sales
                    action.seconds=service.vendorSeconds
                    action.serviceGoal={capacityItems=issue.capacityItems,freeSlots=issue.freeSlots}
                    action.text="整理背包或出售灰色物品。"
                end
            end
            if action.seconds then
                action.referenceSeconds=action.seconds
                action.seconds=A.State.Estimate(action.seconds,state.samples and state.samples.recovery)
                results[#results+1]=action
            end
        end
    end
    return results
end
function S.Compile(actions,state,content)
    local metadata,protected=state.itemMetadata or {},clone(state.protectedItems or {})
    for _,action in ipairs(actions) do
        for _,map in ipairs({action.requiredItems or {},action.consumeItems or {},action.items or {},action.gainItems or {}}) do
            for id in pairs(map) do protected[id]=true end
        end
    end
    local reason
    local function fulfill(action,cursor,seen)
        if action.kind=="service" and (action.serviceKind=="repair" and cursor.ignoreRepair or
            S.Done(action,{bags=cursor.bags,inventory=cursor.inventory,durability=cursor.durability,itemMetadata=metadata})) then
            return {{cursor=cursor,actions={}}}
        end
        local after,issue=S.Apply(action,cursor,metadata)
        if after then
            return {{cursor=after,actions={action}}}
        end
        reason=issue.text
        local key=S.Key(cursor)..":"..(action.serviceId or action.kind)..":"..issue.kind
        if seen[key] then return {} end
        local visited=clone(seen);visited[key]=true
        local results={}
        for _,recovery in ipairs(recover(issue,cursor,state,content,protected)) do
            recovery.questId,recovery.dungeonId=action.questId,action.dungeonId
            recovery.stage=action.stage
            for _,prepared in ipairs(fulfill(recovery,cursor,visited)) do
                for _,finished in ipairs(fulfill(action,prepared.cursor,visited)) do
                    local combined={}
                    for _,step in ipairs(prepared.actions) do combined[#combined+1]=step end
                    for _,step in ipairs(finished.actions) do combined[#combined+1]=step end
                    results[#results+1]={cursor=finished.cursor,actions=combined}
                end
            end
        end
        return results
    end
    local paths={{cursor=S.Cursor(state),actions={}}}
    for _,action in ipairs(actions) do
        local expanded={}
        for _,path in ipairs(paths) do
            for _,nextPath in ipairs(fulfill(action,path.cursor,{})) do
                local combined={}
                for _,step in ipairs(path.actions) do combined[#combined+1]=step end
                for _,step in ipairs(nextPath.actions) do combined[#combined+1]=step end
                expanded[#expanded+1]={cursor=nextPath.cursor,actions=combined}
            end
        end
        paths=expanded
        if #paths==0 then return nil,reason end
    end
    return paths
end
function S:Snapshot(state)
    local wanted,links={},{}
    state.itemMetadata,state.protectedItems={},{}
    for _,entry in ipairs(state.bagEntries or {}) do wanted[entry.id]=true;links[entry.id]=entry.link end
    local function inspect(q)
        if not q then return end
        for _,field in ipairs({"gainItems","consumeItems","requiredItems","items"}) do
            for id in pairs(q[field] or {}) do wanted[id]=true end
        end
        for _,action in ipairs(q.actions or {}) do
            for _,field in ipairs({"gainItems","consumeItems","requiredItems","items"}) do
                for id in pairs(action[field] or {}) do wanted[id]=true end
            end
        end
    end
    for id,quest in pairs(state.quests) do
        if quest.itemId then state.protectedItems[quest.itemId]=true end
        local q=A.Data and A.Data.GetQuest and A.Data:GetQuest(id)
        if q then
            if q.sourceItemId and q.sourceItemId>0 then state.protectedItems[q.sourceItemId]=true end
            for _,item in ipairs(q.requiredSourceItems or {}) do state.protectedItems[item]=true end
            for item in pairs(q.itemRules or {}) do state.protectedItems[item]=true end
        end
    end
    for _,d in pairs(A.Content.dungeons or {}) do if d.verified then inspect(d) end end
    for id in pairs(wanted) do
        local overlay=(A.Content.items or {})[id]
        local item={}
        if overlay and overlay.verified and A.Content.sources[overlay.source] then
            item.stackSize,item.family=overlay.stackSize,overlay.family
        end
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

function S.Itinerary(content,from,actions,state)
    local scripts,reason=S.Compile(actions,state,content)
    if not scripts then return nil,reason end
    local groups,results={},{}
    for _,script in ipairs(scripts) do
        local paths,why=A.Travel.Itinerary(content,from,script.actions,state)
        reason=why or reason
        local key=S.Key(script.cursor)
        groups[key]=groups[key] or {}
        for _,path in ipairs(paths or {}) do
            path.resources.supplies=script.cursor
            groups[key][#groups[key]+1]=path
        end
    end
    for _,paths in pairs(groups) do
        for _,path in ipairs(A.Travel.Prune(paths,state.now)) do results[#results+1]=path end
    end
    table.sort(results,function(a,b) return a.seconds<b.seconds end)
    if #results==0 then return nil,reason end
    return results
end

function S.Fallback(state,data)
    local need=not state.ignoreRepair and state.durability and state.durability<0.2 and "repair" or (state.freeSlots==0 and "vendor")
    if not need then return end
    local text=need=="repair" and "维修装备" or "背包已满，整理背包或出售物品"
    local current=A.Merchant and A.Merchant.CurrentService(state,need,nil,data)
    if current then return current,text end
    local best
    for _,id in ipairs(ids(data.content.services)) do
        local point=data.content.services[id]
        local seconds=need=="repair" and point.repair and point.repair.seconds or need=="vendor" and point.vendorSeconds
        if S.Available(point,state,data.content) and seconds then
            local route=A.Travel.Route(data.content,state.position and (state.position.node or state.position),point.node,state)
            if route then
                local actions={}
                for _,action in ipairs(route.actions) do actions[#actions+1]=action end
                actions[#actions+1]={kind="service",serviceKind=need,serviceId=id,node=point.node,
                    position=data.content.nodes[point.node].position,title=point.title,text=text.."。",
                    serviceGoal=need=="repair" and {durability=0.2} or {freeSlots=1},referenceSeconds=seconds,sampleKind="recovery"}
                local total=route.seconds+seconds
                if not best or total<best.seconds then best={id="service:"..id,title=point.title,kind="service",actions=actions,seconds=total,xp=0,rate=0} end
            end
        end
    end
    if not best and data.ServicePoints and state.position and not state.dead and not state.inInstance then
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

local function number(value,minimum,maximum,integer)
    return type(value)=="number" and value>=minimum and value<=maximum and value<math.huge and (not integer or value%1==0)
end
function S.ValidAction(action)
    for _,field in ipairs({"gainItems","consumeItems","requiredItems","items"}) do
        if action[field]~=nil and type(action[field])~="table" then return false,"物品数量模型无效" end
        for id,count in pairs(action[field] or {}) do
            if not number(id,1,math.huge,true) or not number(count,1,math.huge,true) then return false,"物品 ID 或数量无效" end
        end
    end
    for _,field in ipairs({"minFreeSlots","reserveSlots","lootSlots"}) do
        if action[field]~=nil and not number(action[field],0,math.huge,true) then return false,"容量模型无效" end
    end
    for _,field in ipairs({"minDurability","repairTo"}) do
        if action[field]~=nil and not (number(action[field],0,1) and action[field]>0) then return false,"耐久模型无效" end
    end
    if action.durabilityLoss~=nil and not number(action.durabilityLoss,0,1) then return false,"耐久消耗无效" end
    if action.kind=="service" then
        local goal=action.serviceGoal
        if type(goal)~="table" or not next(goal) then return false,"服务完成条件缺失" end
        local effective=false
        for key,value in pairs(goal) do
            if key=="items" or key=="capacityItems" or key=="absentItems" then
                if type(value)~="table" then return false,"服务物品条件无效" end
                for id,count in pairs(value) do
                    if not number(id,1,math.huge,true) or not number(count,1,math.huge,true) then return false,"服务物品数量无效" end
                    effective=true
                end
            elseif key=="durability" then
                if not number(value,0,1) or value==0 then return false,"维修完成条件无效" end
                effective=true
            elseif key=="freeSlots" then
                if not number(value,0,math.huge,true) then return false,"整理完成条件无效" end
                if value>0 then effective=true end
            else return false,"未知服务完成条件" end
        end
        if not effective then return false,"服务完成条件无效" end
    end
    return true
end
function S.ValidService(point,content)
    if not content.nodes[point.node] then return false,"服务点位置缺失" end
    if point.verified and not content.sources[point.source] then return false,"服务点来源缺失" end
    if type(point.title)~="string" or point.title=="" then return false,"服务点名称缺失" end
    if point.minLevel and not number(point.minLevel,1,60,true) then return false,"服务等级无效" end
    if point.maxLevel and not number(point.maxLevel,1,60,true) then return false,"服务等级无效" end
    if point.minLevel and point.maxLevel and point.minLevel>point.maxLevel then return false,"服务等级范围无效" end
    if point.unlock and type(point.unlock)~="string" then return false,"服务解锁条件无效" end
    if point.faction and point.faction~="Alliance" and point.faction~="Horde" and point.faction~="Neutral" then return false,"服务阵营无效" end
    if point.repair then
        if type(point.repair)~="table" or not number(point.repair.seconds,0,math.huge) or point.repair.seconds==0 then return false,"维修耗时无效" end
    end
    for _,field in ipairs({"purchaseSeconds","vendorSeconds"}) do
        if point[field]~=nil and not (number(point[field],0,math.huge) and point[field]>0) then return false,"服务耗时无效" end
    end
    if point.stock then
        if type(point.stock)~="table" or not point.purchaseSeconds then return false,"补给耗时或出售物品无效" end
        for id,stock in pairs(point.stock) do
            if not number(id,1,math.huge,true) or type(stock)~="table" then return false,"出售物品条目无效" end
        end
    end
    if not point.repair and not point.vendorSeconds and not (point.stock and next(point.stock)) then return false,"服务能力缺失" end
    return true
end
