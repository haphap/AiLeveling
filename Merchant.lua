local _,A=...
A.Merchant={}
local M=A.Merchant

local function accessible(value)
    return not canaccessvalue or canaccessvalue(value)
end
local function number(value,minimum)
    return accessible(value) and type(value)=="number" and value>=minimum and value<math.huge and value%1==0
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
    local shop={npcId=id,name=accessible(name) and type(name)=="string" and name or nil,items={},pending=false}
    state.merchant=shop
    if CanMerchantRepair then
        local value=CanMerchantRepair()
        if accessible(value) and type(value)=="boolean" then shop.canRepair=value end
    end
    local key={"merchant",id,tostring(shop.canRepair)}
    if not GetMerchantNumItems or not GetMerchantItemLink or not C_MerchantFrame or not C_MerchantFrame.GetItemInfo then
        shop.pending=true;return table.concat(key,":")..":api-pending"
    end
    local count=GetMerchantNumItems()
    if not number(count,0) then shop.pending=true;return table.concat(key,":")..":list-pending" end
    for index=1,count do
        local info=C_MerchantFrame.GetItemInfo(index)
        local link=GetMerchantItemLink(index)
        local item=accessible(link) and type(link)=="string" and tonumber(link:match("item:(%d+)"))
        if info and item then
            local offer={index=index,name=accessible(info.name) and type(info.name)=="string" and info.name or nil,
                pack=number(info.stackCount,1) and info.stackCount or nil,
                available=number(info.numAvailable,-1) and info.numAvailable or nil}
            shop.items[item]=shop.items[item] or {};table.insert(shop.items[item],offer)
            key[#key+1]=table.concat({item,index,tostring(offer.pack),tostring(offer.available)},",")
        elseif not info or (not info.currencyID and not info.spellID) then shop.pending=true end
    end
    key[#key+1]=tostring(shop.pending)
    return table.concat(key,":")
end

function M.Offer(shop,id,needed)
    local best
    for _,offer in ipairs(shop.items[id] or {}) do
        local row={name=offer.name,index=offer.index,needed=needed,pack=offer.pack,available=offer.available}
        if offer.pack then row.quantity=math.ceil(needed/offer.pack)*offer.pack end
        row.stock=offer.available and (offer.available==-1 or row.quantity and offer.available>=row.quantity) or false
        row.ready=row.quantity~=nil and row.stock
        row.reason=(not row.quantity or offer.available==nil) and "商品资料待加载" or (not row.stock and "库存不足") or nil
        if not best or row.ready and not best.ready then best=row end
    end
    return best
end

function M.ServiceState(action,state)
    local shop=state.merchant
    if not shop or action.kind~="service" or shop.npcId~=action.npcId then return end
    local result={items={},ready=true}
    if action.serviceKind=="repair" then
        result.ready=shop.canRepair==true
        if shop.canRepair==false then result.issue="当前商店不提供维修"
        elseif shop.canRepair==nil then result.issue="维修服务待加载" end
    elseif action.serviceKind=="supply" then
        local ids={};for id in pairs(action.serviceGoal.items or {}) do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids) do
            local needed=math.max(0,action.serviceGoal.items[id]-(state.bags[id] or 0))
            if needed>0 then
                local row=M.Offer(shop,id,needed) or {reason=shop.pending and "商品资料待加载" or "调整商店筛选以查看所需商品"}
                row.id=id;result.items[#result.items+1]=row
                if not row.ready then result.ready=false end
            end
        end
    end
    return result
end

function M.CurrentService(state,kind,missing)
    local shop=state.merchant
    if not shop or not state.position or state.dead or state.inInstance then return end
    local targets={}
    if kind=="repair" and shop.canRepair~=true then return end
    if kind=="supply" then
        for id,count in pairs(missing or {}) do
            local offer=M.Offer(shop,id,count)
            if offer and offer.stock then targets[id]=(state.bags[id] or 0)+count end
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
    local service=M.ServiceState(action,state)
    if not service then return {} end
    local lines={}
    if service.issue then lines[#lines+1]=service.issue end
    if action.serviceKind=="supply" then
        for _,row in ipairs(service.items) do
            local name=row.name or (state.itemMetadata and state.itemMetadata[row.id] and state.itemMetadata[row.id].name) or ("物品 #"..row.id)
            local value=row.quantity and ("购买 "..row.quantity.." 件（每份 "..row.pack.." 件）") or ""
            if row.available~=nil then value=value..(row.available==-1 and " · 库存不限" or (" · 库存 "..row.available)) end
            if row.reason then value=value.." · "..row.reason end
            lines[#lines+1]=name.."："..value
        end
    end
    return lines
end
