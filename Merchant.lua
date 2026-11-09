local _,A=...
A.Merchant={}
local M=A.Merchant

local function accessible(value)
    return not canaccessvalue or canaccessvalue(value)
end
function M.NpcId(guid)
    if not accessible(guid) or type(guid)~="string" then return end
    local kind,id=guid:match("^([^-]+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
    if (kind=="Creature" or kind=="Vehicle") and tonumber(id)>0 then return tonumber(id) end
end

function M:Event(event)
    if event=="MERCHANT_SHOW" then
        if not self.open then self.junkPending=true;self.junkTried={} end
        self.open=true
    elseif event=="MERCHANT_CLOSED" or event=="PLAYER_ENTERING_WORLD" then
        self.open,self.junkPending,self.junkTried=false,nil,nil
    end
end

function M:SellJunk()
    if not self.junkPending then return end
    self.junkPending=nil
    local state=A.state
    if not self.open or not A.settings.autoSellJunk or A.char.paused or InCombatLockdown() or IsShiftKeyDown() then return end
    if not MerchantFrame or not MerchantFrame:IsShown() or MerchantFrame.selectedTab~=1 or not state.merchant or
        M.NpcId(UnitGUID("npc"))~=state.merchant.npcId then return end
    local container,items=C_Container,A.Data and A.Data.db and A.Data.db.Item
    if not container or not container.UseContainerItem or not container.GetContainerItemQuestInfo or not items then return end
    local keep={}
    for id in pairs(state.quests or {}) do
        for _,item in ipairs(A.QuestAssist.Requirements({kind="objective",questId=id},state,A.Data)) do keep[item.id]=true end
    end
    for _,entry in ipairs(state.bagEntries or {}) do
        if not self.open or not MerchantFrame:IsShown() or MerchantFrame.selectedTab~=1 then return end
        if entry.bag>=0 then
            local info=container.GetContainerItemInfo(entry.bag,entry.slot)
            if info and accessible(info.itemID) and accessible(info.stackCount) and accessible(info.quality) and
                accessible(info.isLocked) and accessible(info.hasNoValue) and accessible(info.hasLoot) and info.itemID==entry.id and info.stackCount==entry.count then
                local key=table.concat({entry.bag,entry.slot,entry.id,entry.count},":")
                if not self.junkTried[key] then
                    if info.quality==nil or info.quality==0 and info.isLocked then self.junkPending=true
                    elseif info.quality==0 and info.hasNoValue==false and not info.hasLoot and not keep[entry.id] then
                        local quest=container.GetContainerItemQuestInfo(entry.bag,entry.slot)
                        local starter=items.Get(entry.id,"startQuest")
                        local needed=(starter or 0)>0
                        for _,id in ipairs(items.Get(entry.id,"relatedQuests") or {}) do
                            if (state.quests or {})[id] then needed=true;break end
                        end
                        if quest and accessible(quest.isQuestItem) and accessible(quest.questID) and accessible(quest.isActive) and
                            quest.isQuestItem==false and not quest.isActive and (not quest.questID or quest.questID==0) and not needed then
                            self.junkTried[key]=true
                            container.UseContainerItem(entry.bag,entry.slot)
                        end
                    end
                end
            end
        end
    end
end

function M:Snapshot(state)
    state.merchant=nil
    if not self.open then return "merchant:closed" end
    local id=UnitGUID and M.NpcId(UnitGUID("npc"))
    if not id then return "merchant:identity-pending" end
    local name=UnitName and UnitName("npc")
    local shop={npcId=id,name=accessible(name) and type(name)=="string" and name or nil}
    state.merchant=shop
    if CanMerchantRepair then
        local value=CanMerchantRepair()
        if accessible(value) and type(value)=="boolean" then shop.canRepair=value end
    end
    return table.concat({"merchant",id,tostring(shop.canRepair)},":")
end

function M.CurrentService(state,kind,missing,data)
    local shop=state.merchant
    if not shop or not state.position or state.dead or state.inInstance then return end
    local targets={}
    if kind=="repair" and shop.canRepair~=true then return end
    if kind=="supply" then
        for _,point in ipairs(data and data.ServicePoints and data:ServicePoints(state,"supply",missing) or {}) do
            if point.npcId==shop.npcId then targets=point.targets or {};break end
        end
        if not next(targets) then return end
    end
    if kind~="repair" and kind~="vendor" and kind~="supply" then return end
    local p=state.position
    return {reference=true,id="service:current:"..shop.npcId,kind="service",title=shop.name or ("NPC #"..shop.npcId),
        actions={{kind="service",serviceId="npc:"..shop.npcId,npcId=shop.npcId,serviceKind=kind,
            title=shop.name or ("NPC #"..shop.npcId),position={map=p.map,x=p.x,y=p.y,label="当前商店交互点"},
            text="在当前商店维修、整理背包或购买补给。",
            serviceGoal=kind=="repair" and {durability=0.2} or kind=="supply" and {items=targets} or {freeSlots=1}}}}
end

function M.Lines(action,state)
    local lines={}
    if action.kind~="service" or action.serviceKind~="supply" then return lines end
    local ids={};for id in pairs(action.serviceGoal.items or {}) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do
        local needed=math.max(0,action.serviceGoal.items[id]-(state.bags[id] or 0))
        if needed>0 then
            local item=state.itemMetadata and state.itemMetadata[id]
            lines[#lines+1]=(item and item.name or ("物品 #"..id)).."：还需购买 "..needed.." 件"
        end
    end
    return lines
end
