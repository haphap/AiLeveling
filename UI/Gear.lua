local _, A = ...
A.UI.Gear = {}
local UI=A.UI.Gear

-- Reuse the exact bag instance, including its enchant and random suffix.
local function bagItem(state,key,link)
    for _,item in ipairs(state.bagEquipment or {}) do
        if item.instanceKey==key and item.link==link and not item.pending then return item end
    end
end

local function comparison(upgrade,label)
    if not upgrade or upgrade.provisional then return end
    local delta=upgrade.delta
    local color=delta>0 and "78d973" or delta<0 and "eb6b61" or "a8adbd"
    local text
    if upgrade.oldScore==0 then
        if delta==0 then return end
        text=string.format("%+.2f 分",delta)
    else
        local p=delta*100/upgrade.oldScore
        if p~=0 and math.abs(p)<0.5 then text=p>0 and "+<1%" or "−<1%"
        else text=string.format("%+d%%",p<0 and math.ceil(p-0.5) or math.floor(p+0.5)) end
    end
    return "|cff"..color..label..text.."|r",delta~=0
end

local function scoreRows(item,state)
    local rows,changed={},false
    local view=setmetatable({},{__index=state})
    local paired=item.equipLoc=="INVTYPE_FINGER" or item.equipLoc=="INVTYPE_TRINKET"
    for _,spec in ipairs(A.GearSpecs[state.class] or {}) do
        view.gearSpec=spec
        view.role=spec.role=="tank" and "TANK" or spec.role=="healer" and "HEALER" or "DAMAGER"
        local row,changes
        if paired then
            local parts={}
            for index,slot in ipairs(A.Gear.Slots(item,view)) do
                local text,different=comparison(A.Gear.Loadout({[slot]=item},view),"#"..index.." ")
                if text then parts[#parts+1]=text end
                changes=changes or different
            end
            if #parts>0 then row=spec.label.."  "..table.concat(parts," · ") end
        else
            row,changes=comparison(A.Gear.Upgrade(item,view),spec.label.." ")
        end
        if row then rows[#rows+1]=row end
        changed=changed or changes
    end
    if changed then return rows end
end

local lastBagItem,lastState,lastRows
local function addScore(tip,data)
    if tip~=GameTooltip then return end
    local state=A.state
    if not (state and state.class and state.equipment and A.settings and A.settings.rewardAdvice~=false) or tip:IsForbidden() then return end
    local info=tip:GetPrimaryTooltipInfo()
    if not info or tip:GetProcessingTooltipInfo()~=info then return end
    local args=info.getterArgs
    if info.getterName=="GetInventoryItem" and args and args[1]=="player" then return end
    if canaccessvalue and (not canaccessvalue(data.guid) or not canaccessvalue(data.hyperlink)) then return end
    local _,link=TooltipUtil.GetDisplayedItem(tip)
    if (canaccessvalue and not canaccessvalue(link)) or type(link)~="string" then return end
    local id,_,_,loc=C_Item.GetItemInfoInstant(link)
    if not loc or loc=="" then return end
    local key=info.getterName=="GetBagItem" and args and args[1] and args[2] and (args[1]..":"..args[2])
    local bag=key and bagItem(state,key,link)
    local item=bag or A.Items:Read(id,link,data)
    if item.pending or #A.Gear.Slots(item,state)==0 then return end
    local rows
    if bag and bag==lastBagItem and state==lastState then rows=lastRows
    else
        if key and not bag then item.instanceKey=key end
        rows=scoreRows(item,state)
        if bag then lastBagItem,lastState,lastRows=bag,state,rows end
    end
    if not rows then return end
    tip:AddLine(" ")
    tip:AddLine("|TInterface\\AddOns\\AiLeveling\\Media\\gear:16:16|t AILeveling 评分",0.66,0.68,0.74)
    for _,row in ipairs(rows) do tip:AddLine("    "..row,0.66,0.68,0.74,true) end
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
