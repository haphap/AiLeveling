local _, A = ...
A.Items = {}
local I = A.Items

function I:SpellText(id)
    if not (C_Spell and C_Spell.GetSpellDescription) then return end
    local ok,text=pcall(function()
        local value=C_Spell.GetSpellDescription(id)
        if type(value)=="string" and value~="" then return value end
    end)
    self.spellData=self.spellData or {}
    if ok and text then self.spellData[id]=nil;return text end
    self.spellData[id]=true
end

local function effects(item,link)
    local reference=A.ItemEffects
    local record=reference and A.clientVersion==reference.version and tostring(A.build)==reference.build and
        A.interface==reference.interface and reference.items[item.id]
    local covered=record and not record.complex
    if covered then
        for stat,amount in pairs(record.stats) do
            local value=item.stats and item.stats["ITEM_MOD_"..stat.."_SHORT"]
            if not value and (stat=="SPELL_DAMAGE_DONE" or stat=="SPELL_HEALING_DONE") then
                value=item.stats and item.stats.ITEM_MOD_SPELL_POWER_SHORT
            end
            if type(value)~="number" or value~=value or value<amount then covered=false;break end
        end
    end
    local types=Enum and Enum.TooltipDataLineType
    local passive={}
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink and types then
        local ok,result=pcall(function()
            local data=C_TooltipInfo.GetHyperlink(link)
            if type(data)~="table" then return end
            if type(data.dataInstanceID)=="number" then
                I.tooltipData=I.tooltipData or {};I.tooltipData[data.dataInstanceID]=true
            end
            if type(data.lines)~="table" or #data.lines==0 then return end
            local found={}
            for _,line in ipairs(data.lines) do
                local kind=types.ItemSpellTriggerOnUse and line.type==types.ItemSpellTriggerOnUse and "use" or
                    types.ItemSpellTriggerOnProc and line.type==types.ItemSpellTriggerOnProc and "proc"
                if kind then
                    local text=line.leftText
                    found[#found+1]={kind=kind,text=type(text)=="string" and text~="" and text or
                        (kind=="use" and "主动效果" or "命中触发效果")}
                elseif types.ItemSpellTriggerOnEquip and line.type==types.ItemSpellTriggerOnEquip then
                    passive[#passive+1]={kind="equip",text=type(line.leftText)=="string" and line.leftText~="" and
                        line.leftText or "装备被动效果"}
                end
            end
            return found
        end)
        if ok and result then item.effects=result else item.effectsPending=true end
    end
    if covered and #passive>#record.spells then covered=false end
    if not covered then
        item.effects=item.effects or {}
        if #passive>0 then
            for _,effect in ipairs(passive) do item.effects[#item.effects+1]=effect end
        elseif record then
            for _,spell in ipairs(record.spells) do
                local text=I:SpellText(spell)
                item.effects[#item.effects+1]={kind="equip",text=(record.conditional and "条件被动：" or "装备被动：")..
                    (text or ("效果 #"..spell))}
            end
            if #record.spells==0 then item.effects[#item.effects+1]={kind="equip",text="被动效果"} end
        end
    end
end

function I:Read(id,link)
    local item={id=id,link=link}
    local overlay=A.Content.items and A.Content.items[id]
    if overlay and overlay.verified and A.Content.sources[overlay.source] then
        for key,value in pairs(overlay) do item[key]=value end
    end
    local sets=A.ItemSets
    if sets and A.clientVersion==sets.version and tostring(A.build)==sets.build and A.interface==sets.interface then
        item.setId=item.setId or sets.items[id]
        item.setInfo=item.setId and sets.sets[item.setId]
        item.setUnknown=not item.setId and sets.ambiguous[id] or nil
    end
    local name,fullLink,quality,itemLevel,requiredLevel,_,_,_,equipLoc,icon,_,classID,subClassID=C_Item.GetItemInfo(link or id)
    if name then
        fullLink=fullLink or link or id
        item.name,item.link,item.quality,item.itemLevel,item.requiredLevel=name,fullLink,quality,itemLevel,requiredLevel
        item.equipLoc,item.icon,item.classID,item.subClassID=equipLoc,icon,classID,subClassID
        item.stats=C_Item.GetItemStats(fullLink) or item.stats
        if equipLoc=="" then item.stats=item.stats or {} end
        if C_PlayerInfo and C_PlayerInfo.CanUseItem then item.usable=C_PlayerInfo.CanUseItem(id) end
        if C_Item.GetItemUniqueness then
            local category,limit=C_Item.GetItemUniqueness(fullLink)
            if category and category>0 then item.uniqueCategory,item.uniqueLimit=category,limit end
        end
        if C_Item.GetItemSpell then item.useSpell=select(2,C_Item.GetItemSpell(fullLink)) end
        if equipLoc and equipLoc~="" then effects(item,fullLink) end
    elseif C_Item.GetItemInfoInstant then
        local _,_,_,loc,texture,cls,sub=C_Item.GetItemInfoInstant(id)
        item.equipLoc,item.icon,item.classID,item.subClassID=loc,texture,cls,sub
    end
    if (not name or not item.stats) and not A.requestedItems[id] then
        A.requestedItems[id]=true
        C_Item.RequestLoadItemDataByID(id)
    end
    item.pending=not name or not item.stats
    return item
end

function I.Key(item)
    local parts={"item:"..tostring(item.link or item.id),"pending:"..tostring(item.pending),
        "usable:"..tostring(item.usable),"effectsPending:"..tostring(item.effectsPending)}
    for key,value in pairs(item.stats or {}) do parts[#parts+1]=key.."="..tostring(value) end
    for _,effect in ipairs(item.effects or {}) do parts[#parts+1]=effect.kind..":"..effect.text end
    table.sort(parts)
    return table.concat(parts,"\031")
end

function I:Snapshot(state)
    self.tooltipData,self.spellData={},{}
    state.items,state.bagEquipment={},{}
    for slot,worn in pairs(state.equipment) do
        local item=self:Read(worn.id,worn.link)
        state.equipment[slot],state.items[item.id]=item,item
    end
    local ids={}
    for _,entry in ipairs(state.bagEntries or {}) do
        local id=entry.id
        local _,_,_,equipLoc=C_Item.GetItemInfoInstant(id)
        if equipLoc and equipLoc~="" then
            local item=self:Read(id,entry.link)
            item.instanceKey=entry.key
            state.bagEquipment[#state.bagEquipment+1]=item
        end
    end
    for _,source in pairs(A.Content.gearSources or {}) do ids[source.itemId]=true end
    local target=A.char and A.char.gearTarget and A.Gear and A.Gear.GetSource and A.Gear.GetSource(A.char.gearTarget,nil,state)
    if target then ids[target.itemId]=true end
    for id in pairs(ids) do state.items[id]=self:Read(id) end
    local known=C_SpellBook and C_SpellBook.IsSpellKnown
    state.capabilities={titanGrip=known and known(46917)}
    if CanDualWield then state.capabilities.dualWield=CanDualWield() else state.capabilities.dualWield=known and known(674) end
end
