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
    if event=="MERCHANT_SHOW" then self.open=true
    elseif event=="MERCHANT_CLOSED" or event=="PLAYER_ENTERING_WORLD" then self.open=false end
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
