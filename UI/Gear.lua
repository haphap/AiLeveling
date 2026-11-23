local _, A = ...
A.UI.Gear = {}
local UI=A.UI.Gear

-- Reuse the exact bag instance, including its enchant and random suffix.
local function bagItem(state,key,link)
    for _,item in ipairs(state.bagEquipment or {}) do
        if item.instanceKey==key and item.link==link and not item.pending then return item end
    end
end

-- Bag entries are recreated when the character's equipment or scoring profile refreshes.
local lastBagItem,lastUpgrade
local function addScore(tip,data)
    if tip~=GameTooltip and tip~=ShoppingTooltip1 and tip~=ShoppingTooltip2 then return end
    local state=A.state
    if not (state and state.class and state.equipment and A.settings and A.settings.rewardAdvice~=false) or tip:IsForbidden() then return end
    local info=tip:GetPrimaryTooltipInfo()
    if not info or tip:GetProcessingTooltipInfo()~=info then return end
    if canaccessvalue and (not canaccessvalue(data.guid) or not canaccessvalue(data.hyperlink)) then return end
    local _,link=TooltipUtil.GetDisplayedItem(tip)
    if (canaccessvalue and not canaccessvalue(link)) or type(link)~="string" then return end
    local id,_,_,loc=C_Item.GetItemInfoInstant(link)
    if not loc or loc=="" then return end
    local args=info.getterArgs
    local key=info.getterName=="GetBagItem" and args and args[1] and args[2] and (args[1]..":"..args[2])
    local bag=key and bagItem(state,key,link)
    local item=bag or A.Items:Read(id,link,data)
    if item.pending or #A.Gear.Slots(item,state)==0 then return end
    local score=A.Gear.Score(item,state)
    if not score then return end
    local _,model,profile=A.Gear.Model(state)
    local value=string.format("%.2f 分",score)
    local worn=tip~=GameTooltip or (info.getterName=="GetInventoryItem" and args and args[1]=="player")
    if not worn then
        local upgrade
        if bag and bag==lastBagItem then
            upgrade=lastUpgrade
        else
            if key and not bag then item.instanceKey=key end
            upgrade=A.Gear.Upgrade(item,state)
            if bag then lastBagItem,lastUpgrade=bag,upgrade end
        end
        if upgrade and not upgrade.provisional then
            local diff=upgrade.delta
            local color=diff>0 and "66dd99" or diff<0 and "ff9999" or "aaaaaa"
            value=value..string.format("  |cff%s换装 %+.2f|r",color,diff)
        end
    end
    tip:AddDoubleLine("AILeveling · "..(profile=="protection" and "防骑" or model),value,0.95,0.78,0.45,1,1,1)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and TooltipUtil and TooltipUtil.GetDisplayedItem then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,addScore)
end

function UI:Ids()
    local ids,seen={},{}
    local function add(id) if not seen[id] then ids[#ids+1]=id;seen[id]=true end end
    for _,choice in ipairs(A.plan and A.plan.taskChoices or {}) do
        for id in pairs(choice.gearSources or {}) do add(id) end
    end
    for id,source in pairs(A.Gear.DungeonSources(A.state)) do
        local value=A.Gear.Source(source,A.state,A.Data)
        if value and not value.owned and (value.upgrade.delta>0 or #(value.upgrade.notes or {})>0) then add(id) end
    end
    local target=A.char and A.char.gearTarget
    if target and A.Gear.GetSource(target) then add(target) end
    table.sort(ids,function(a,b) return tostring(a)<tostring(b) end)
    return ids
end
