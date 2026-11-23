local _, A = ...
A.UI.Gear = {}
local UI=A.UI.Gear

-- Reuse the exact bag instance, including its enchant and random suffix.
local function bagItem(state,key,link)
    for _,item in ipairs(state.bagEquipment or {}) do
        if item.instanceKey==key and item.link==link and not item.pending then return item end
    end
end

-- Specs sharing an AILeveling model can reuse the same comparison.
local specModels={
    PALADIN={{"strength","惩戒"},{"tank","防骑"},{"healer","奶骑"}},
    WARRIOR={{"strength","武器","狂暴"},{"tank","防战"}},
    PRIEST={{"caster","暗牧"},{"healer","戒律","神牧"}},
    DRUID={{"caster","鸟德"},{"agility","猫德"},{"tank","熊德"},{"healer","奶德"}},
    SHAMAN={{"caster","元素"},{"agility","增强"},{"healer","奶萨"}},
    HUNTER={{"ranged","兽王","射击","生存"}},
    ROGUE={{"agility","奇袭","战斗","敏锐"}},
    MAGE={{"caster","奥法","火法","冰法"}},
    WARLOCK={{"caster","痛苦","恶魔","毁灭"}},
}
local function percent(upgrade)
    if not upgrade or upgrade.provisional or upgrade.oldScore<=0 then return end
    local change=upgrade.delta*100/upgrade.oldScore
    local rounded=change<0 and math.ceil(change-0.5) or math.floor(change+0.5)
    return math.max(-999,math.min(999,rounded))
end

local function percentageText(p,label)
    local color=p>0 and "78d973" or p<0 and "eb6b61" or "a8adbd"
    return string.format("|cff%s%s%+d%%|r",color,label,p)
end

local function scoreRows(item,state)
    local rows,changed={},false
    local view=setmetatable({},{__index=state})
    local paired=item.equipLoc=="INVTYPE_FINGER" or item.equipLoc=="INVTYPE_TRINKET"
    for _,group in ipairs(specModels[state.class] or {}) do
        local model=group[1]
        view.role=model=="tank" and "TANK" or model=="healer" and "HEALER" or "DAMAGER"
        view.damageStyle=model
        local p,parts
        if paired then
            parts={}
            for index,slot in ipairs(A.Gear.Slots(item,view)) do
                if state.equipment[slot] then
                    local change=percent(A.Gear.Loadout({[slot]=item},view))
                    if change then
                        parts[#parts+1]=percentageText(change,"#"..index.." ")
                        changed=changed or change~=0
                    end
                end
            end
        else
            p=percent(A.Gear.Upgrade(item,view))
            changed=changed or (p~=nil and p~=0)
        end
        for i=2,#group do
            if p then rows[#rows+1]=percentageText(p,group[i].." ")
            elseif parts and #parts>0 then rows[#rows+1]=group[i].."  "..table.concat(parts," · ") end
        end
    end
    if changed then return rows end
end

local lastBagItem,lastRows
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
    if bag and bag==lastBagItem then rows=lastRows
    else
        if key and not bag then item.instanceKey=key end
        rows=scoreRows(item,state)
        if bag then lastBagItem,lastRows=bag,rows end
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
