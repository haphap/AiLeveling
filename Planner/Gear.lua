local _, A = ...
A.Gear = {}
local G = A.Gear
-- Reference weights compare attributes only; calibrated execution models remain separate.
local weights = {
    strength={STRENGTH=1,AGILITY=0.4,STAMINA=0.25,ATTACK_POWER=0.5,CRIT_RATING=0.5},
    agility={AGILITY=1,STRENGTH=0.3,STAMINA=0.25,ATTACK_POWER=0.5,CRIT_RATING=0.5},
    ranged={AGILITY=1,STAMINA=0.25,ATTACK_POWER=0.5,RANGED_ATTACK_POWER=0.5,CRIT_RATING=0.5},
    caster={INTELLECT=1,SPIRIT=0.4,STAMINA=0.25,SPELL_POWER=1,CRIT_RATING=0.3},
    healer={INTELLECT=1,SPIRIT=0.8,STAMINA=0.25,HEALING=1},
    tank={STAMINA=1,STRENGTH=0.4,AGILITY=0.4,DEFENSE_SKILL_RATING=1,DODGE_RATING=1,BLOCK_RATING=1},
    hybrid={STRENGTH=0.5,AGILITY=0.5,INTELLECT=0.5,STAMINA=0.25,SPIRIT=0.25},
}
local default = {WARRIOR="strength",PALADIN="hybrid",ROGUE="agility",HUNTER="ranged",MAGE="caster",
    PRIEST="caster",WARLOCK="caster",DRUID="hybrid",SHAMAN="hybrid"}
local labels={strength="近战力量",agility="近战敏捷",ranged="远程物理",caster="施法输出",healer="治疗续航",tank="坦克生存",hybrid="混合属性"}
local slots={INVTYPE_HEAD={1},INVTYPE_NECK={2},INVTYPE_SHOULDER={3},INVTYPE_BODY={4},INVTYPE_CHEST={5},INVTYPE_ROBE={5},
    INVTYPE_WAIST={6},INVTYPE_LEGS={7},INVTYPE_FEET={8},INVTYPE_WRIST={9},INVTYPE_HAND={10},INVTYPE_FINGER={11,12},
    INVTYPE_TRINKET={13,14},INVTYPE_CLOAK={15},INVTYPE_WEAPONMAINHAND={16},INVTYPE_WEAPONOFFHAND={17},
    INVTYPE_SHIELD={17},INVTYPE_HOLDABLE={17},INVTYPE_RANGED={18},INVTYPE_RANGEDRIGHT={18},INVTYPE_THROWN={18},INVTYPE_RELIC={18},INVTYPE_TABARD={19}}

function G.Model(state)
    local style=state.damageStyle or "auto"
    local key=state.role=="HEALER" and "healer" or state.role=="TANK" and "tank" or
        (style~="auto" and style or default[state.class])
    return weights[key],labels[key],key
end

local function physicalWeapon(item,state)
    local _,_,key=G.Model(state)
    local loc=item.equipLoc
    return key=="ranged" and (loc=="INVTYPE_RANGED" or loc=="INVTYPE_RANGEDRIGHT") or
        (key=="strength" or key=="agility") and (loc=="INVTYPE_WEAPON" or loc=="INVTYPE_WEAPONMAINHAND" or
            loc=="INVTYPE_WEAPONOFFHAND" or loc=="INVTYPE_2HWEAPON")
end

function G.WeaponSkill(item,state)
    local data=A.WeaponSkills
    if not item or item.classID~=2 or not data or state.clientVersion~=data.version or
        tostring(state.clientBuild)~=data.build or state.interface~=data.interface then return end
    local reference=data.subclasses[item.subClassID]
    return reference,reference and (state.weaponSkills or {})[reference.skill],true
end

local function skillNote(item,old,state)
    if not physicalWeapon(item,state) then return end
    local reference,skill,enabled=G.WeaponSkill(item,state)
    if not enabled then return end
    if not reference then return "在技能面板查看武器熟练度。" end
    local previous,previousSkill=G.WeaponSkill(old,state)
    if previous and previous.skill==reference.skill then return end
    if not skill then return reference.name.."熟练度：在技能面板查看。" end
    local effective=skill.rank+skill.modifier+skill.tempPoints
    if old and physicalWeapon(old,state) and not previousSkill then return "在技能面板查看当前武器熟练度。" end
    local before=previousSkill and previousSkill.rank+previousSkill.modifier+previousSkill.tempPoints or skill.maxRank
    if effective<before then
        return string.format("%s熟练度 %d/%d（有效 %d），低于%s %d；换装后需先练习。",
            reference.name,skill.rank,skill.maxRank,effective,previousSkill and "当前武器" or "当前上限",before)
    end
end

function G.Score(item,state)
    if not item or not item.stats then return nil end
    local model,_,key=G.Model(state)
    if not model then return nil end
    local stats,score=item.stats,0
    for stat,weight in pairs(model) do
        local value=stats["ITEM_MOD_"..stat.."_SHORT"] or 0
        if stat=="SPELL_POWER" then value=stats.ITEM_MOD_SPELL_POWER_SHORT or stats.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT or 0 end
        if stat=="HEALING" then value=stats.ITEM_MOD_SPELL_HEALING_DONE_SHORT or stats.ITEM_MOD_SPELL_POWER_SHORT or 0 end
        score=score+value*weight
    end
    if key=="tank" then score=score+(stats.RESISTANCE0_NAME or stats.ITEM_MOD_ARMOR_SHORT or 0)*0.02 end
    local dps=item.weaponDPS or stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
    if dps and physicalWeapon(item,state) then score=score+dps*3 end
    return score
end

function G.Usable(item,state)
    if item.pending then return nil,"装备属性加载中" end
    if item.requiredLevel and item.requiredLevel>state.level then return false,"等级不足" end
    if item.classes and not item.classes[state.class] then return false,"职业不适配" end
    if item.roles and not item.roles[state.role] then return false,"职责不适配" end
    if item.usable==false then return false,"客户端确认当前无法使用" end
    if item.usable~=true and not (item.classes and item.classes[state.class]) then return nil,"装备可用性待确认" end
    if item.usable~=true and item.requiredSkill then
        local skill=state.skills and state.skills[item.requiredSkill[1]]
        if not skill or skill<item.requiredSkill[2] then return false,"装备技能不足或未知" end
    end
    return true
end

local function isOffWeapon(item)
    return item.equipLoc=="INVTYPE_WEAPON" or item.equipLoc=="INVTYPE_WEAPONOFFHAND" or item.equipLoc=="INVTYPE_2HWEAPON"
end
function G.Slots(item,state)
    local cap=state.capabilities or {}
    if item.equipLoc=="INVTYPE_WEAPON" then return cap.dualWield and {16,17} or {16} end
    if item.equipLoc=="INVTYPE_2HWEAPON" then return cap.titanGrip and {16,17} or {16} end
    return slots[item.equipLoc] or (item.slot and {item.slot}) or {}
end

function G.Compare(candidate,equipped,state)
    local ok,reason=G.Usable(candidate,state)
    if not ok then return nil,reason end
    local new,old=G.Score(candidate,state),equipped and G.Score(equipped,state) or 0
    if not new or old==nil then return nil,"装备属性加载中" end
    return {delta=new-old,qualitative=true,label="属性评分变化"}
end

function G.Loadout(replacements,state)
    local after,removed,added,setUnknown={},0,0
    for slot,item in pairs(state.equipment) do
        if item.pending then return nil,"当前装备属性加载中" end
        if item.setUnknown then setUnknown=true end
        after[slot]=item
    end
    for slot,item in pairs(replacements) do
        if after[slot] then
            local score=G.Score(after[slot],state)
            if not score then return nil,"当前装备属性加载中" end
            removed=removed+score
        end
        if item~=false then
            local ok,reason=G.Usable(item,state)
            if not ok then return nil,reason end
            local score=G.Score(item,state)
            if not score then return nil,"候选装备属性加载中" end
            added=added+score
            if item.setUnknown then setUnknown=true end
            after[slot]=item
        else after[slot]=nil end
    end
    local cap=state.capabilities or {}
    if after[16] and after[16].equipLoc=="INVTYPE_2HWEAPON" and after[17] and not cap.titanGrip then return nil,"双手武器占用主副手" end
    if after[17] and isOffWeapon(after[17]) and not cap.dualWield then return nil,"双持技能未确认" end
    local categories,limits,unique={},{},{}
    for _,item in pairs(after) do
        if item.uniqueEquip then
            if unique[item.id] then return nil,"唯一装备冲突" end
            unique[item.id]=true
        end
        if item.uniqueCategory and item.uniqueCategory>0 then
            local category=item.uniqueCategory
            categories[category]=(categories[category] or 0)+1
            limits[category]=math.min(limits[category] or math.huge,item.uniqueLimit or 1)
            if categories[category]>limits[category] then return nil,"唯一装备类别冲突" end
        end
    end
    local notes,sets={},{}
    if setUnknown then notes[#notes+1]="查看套装效果" end
    local function effects(item,verb)
        if not item then return end
        local prefix=(item.link or item.name or ("物品 #"..item.id)).." · "..verb.."："
        if item.effectText then notes[#notes+1]=prefix..item.effectText end
        local hasUse
        for _,effect in ipairs(item.effects or {}) do
            notes[#notes+1]=prefix..effect.text
            if effect.kind=="use" then hasUse=true end
        end
        if item.useSpell and not hasUse then notes[#notes+1]=prefix.."主动效果 #"..item.useSpell end
        if item.effectsPending then notes[#notes+1]=prefix.."效果资料待加载" end
        if item.setId then sets[item.setId]=item.setInfo or sets[item.setId] or true end
    end
    for slot,item in pairs(replacements) do
        local old=state.equipment[slot]
        if old~=item then
            effects(old,"失去")
            if item~=false then effects(item,"获得") end
            local note=item~=false and skillNote(item,old,state)
            if note then notes[#notes+1]=(item.link or item.name or ("物品 #"..item.id)).." · "..note end
        end
    end
    for id,info in pairs(sets) do
        local beforeCount,afterCount=0,0
        for _,item in pairs(state.equipment) do if item.setId==id then beforeCount=beforeCount+1 end end
        for _,item in pairs(after) do if item.setId==id then afterCount=afterCount+1 end end
        if beforeCount~=afterCount then
            if type(info)~="table" or not info.bonuses then
                notes[#notes+1]="套装 #"..id.."："..beforeCount.." → "..afterCount.." 件"
            else
                local rank=info.skill and (state.skills or {})[info.skill]
                for _,bonus in ipairs(info.bonuses) do
                    local count,spell=bonus[1],bonus[2]
                    if (beforeCount>=count)~=(afterCount>=count) then
                        if info.skill and rank==nil then
                            notes[#notes+1]=info.name.."：需要 "..info.rank.." 点技能"
                        elseif not info.skill or rank>=info.rank then
                            local text=info.name.."："..(afterCount>=count and "获得 " or "失去 ")..count.." 件套效果"
                            local description=A.Items and A.Items.SpellText and A.Items:SpellText(spell)
                            if description then text=text.." · "..description end
                            notes[#notes+1]=text
                        end
                    end
                end
            end
        end
    end
    local function missingWeapon(item)
        return item and physicalWeapon(item,state) and not (item.weaponDPS or (item.stats and item.stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT))
    end
    local missing
    for slot,item in pairs(replacements) do
        if missingWeapon(state.equipment[slot]) or missingWeapon(item) then missing=true;break end
    end
    if missing then notes[#notes+1]="武器伤害加载中" end
    return {delta=added-removed,oldScore=removed,newScore=added,replacements=replacements,provisional=missing,
        qualitative=true,notes=notes,label="属性评分变化"}
end

function G.Upgrade(candidate,state)
    local ok,reason=G.Usable(candidate,state)
    if not ok then return nil,reason end
    local best,lastReason
    local function compare(replacements)
        local result,why=G.Loadout(replacements,state)
        if result and (not best or result.delta>best.delta) then best=result else lastReason=why or lastReason end
    end
    for _,slot in ipairs(G.Slots(candidate,state)) do
        local replacements={[slot]=candidate}
        if slot==16 and candidate.equipLoc=="INVTYPE_2HWEAPON" and not (state.capabilities or {}).titanGrip then replacements[17]=false end
        compare(replacements)
        -- Compare a two-hand swap with an actually owned compatible companion.
        if slot==16 or slot==17 then
            local other=slot==16 and 17 or 16
            local companions={}
            if state.bagEquipment then companions=state.bagEquipment
            else for id,count in pairs(state.bags or {}) do if count>0 and state.items and state.items[id] then companions[#companions+1]=state.items[id] end end end
            for _,item in ipairs(companions) do
                local distinct=item.id~=candidate.id or candidate.futureCopy or
                    (candidate.instanceKey and item.instanceKey and candidate.instanceKey~=item.instanceKey) or
                    (not candidate.instanceKey and (state.bags[item.id] or 0)>1)
                if distinct then
                    for _,supported in ipairs(G.Slots(item,state)) do
                        if supported==other then compare({[slot]=candidate,[other]=item}) end
                    end
                end
            end
        end
    end
    return best,lastReason or "槽位或搭配未确认"
end

function G.RewardSources(q)
    local sources={}
    local facts=q and q.taskFacts
    if not facts or type(facts.level)~="number" or facts.level~=q.questLevel or not facts.rewards then return sources end
    for _,kind in ipairs({"items","choices"}) do
        for _,reward in ipairs(facts.rewards[kind] or {}) do
            local id=reward.id
            if type(id)=="number" and id>0 and id%1==0 then
                local key="reward:"..q.id..":"..id
                sources[key]={id=key,kind="quest",questId=q.id,itemId=id,title=q.title,
                    reference=true,choice=kind=="choices"}
            end
        end
    end
    return sources
end

function G.BagUpgrade(state,ignored)
    local best
    for _,item in ipairs(state.bagEquipment or {}) do
        local key=tostring(item.link or item.id)
        if not (ignored or {})[key] then
            local upgrade=G.Upgrade(item,state)
            for _,replacement in pairs(upgrade and upgrade.replacements or {}) do
                if replacement and (ignored or {})[tostring(replacement.link or replacement.id)] then upgrade=nil;break end
            end
            if upgrade and upgrade.delta>0 and not upgrade.provisional and #upgrade.notes==0 and
                (not best or upgrade.delta>best.upgrade.delta) then best={item=item,upgrade=upgrade,key=key} end
        end
    end
    return best
end

function G.UpgradeText(value)
    local upgrade=value.upgrade
    if upgrade.oldScore==0 then return "新增有效属性" end
    local percent=upgrade.delta/upgrade.oldScore*100
    return string.format(percent<1 and "属性评分 +%.1f%%" or "属性评分 +%.0f%%",percent)
end

function G:EquipAdvice(value)
    if InCombatLockdown() then return false,"脱离战斗后再换装" end
    A.State:Refresh(true)
    local current=G.BagUpgrade(A.state,A.char.ignoredGear)
    if not current or not value or current.key~=value.key then return false,"装备建议已更新" end
    for slot=1,19 do
        local item=current.upgrade.replacements[slot]
        if item then C_Item.EquipItemByName(item.link or item.id,slot) end
    end
    return true
end

function G.DungeonSources(state,instanceId)
    local catalog=A.DungeonCatalog
    if not catalog or not state or state.clientVersion~=catalog.version or tostring(state.clientBuild)~=catalog.build then return {} end
    local sources={}
    for id,source in pairs(catalog.loot or {}) do
        if not instanceId or source.instanceId==instanceId then sources[id]=source end
    end
    return sources
end

function G.GetSource(id,data,state)
    data=data or A.Data
    local content=data and data.content or A.Content
    local authored=content and content.gearSources and content.gearSources[id]
    if authored then return authored end
    if type(id)~="string" then return end
    if id:match("^drop:") then return G.DungeonSources(state or A.state)[id] end
    if not data or not data.GetQuest then return end
    local quest,item=id:match("^reward:(%d+):(%d+)$")
    if quest and item then return G.RewardSources(data:GetQuest(tonumber(quest)))[id] end
end

function G.Source(source,state,content,data)
    if not source.verified then
        local reference=source.reference and G.GetSource(source.id,data,state)
        if not reference or not reference.reference or reference.kind~=source.kind or reference.questId~=source.questId or
            reference.itemId~=source.itemId or reference.dungeonId~=source.dungeonId or reference.encounterId~=source.encounterId then
            return nil,"当前暂无可用的装备来源"
        end
        source=reference
    end
    local item=state.items and state.items[source.itemId]
    if not item and source.reference and A.Items and C_Item and C_Item.GetItemInfo then item=A.Items:Read(source.itemId) end
    if not item then return nil,"物品数据加载中" end
    local future={}
    for key,value in pairs(item) do future[key]=value end
    future.futureCopy=true
    local upgrade,reason=G.Upgrade(future,state)
    if not upgrade then return nil,reason end
    local low,high
    if source.kind=="quest" then low,high=1,1
    else
        low,high=source.chanceLow or source.chance,source.chanceHigh or source.chance
        if not low or not high then low,high=0,1 end
        if source.shareChance then low,high=low*source.shareChance,high*source.shareChance else low=0 end
    end
    if low~=low or high~=high or low<0 or high>1 or low>high then return nil,"来源概率无效" end
    return {source=source,item=item,upgrade=upgrade,chanceLow=low,chanceHigh=high,
        owned=(state.bags[item.id] or 0)>0,expectedAttemptsLow=high>0 and 1/high or nil,
        expectedAttemptsHigh=low>0 and 1/low or nil}
end

function G:SetTarget(id)
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先结束当前副本行程，再选择装备目标" end
    local source=G.GetSource(id)
    if not source then return false,"装备来源不存在" end
    local value,reason=G.Source(source,A.state,A.Content)
    if not value then return false,reason end
    if source.reference and source.kind=="quest" then
        local q=A.Data:GetQuest(source.questId)
        if A.state.completed[source.questId] and not A.state.quests[source.questId] and not q.repeatable then return false,"该奖励任务已经交付" end
        if A.state.skipped[source.questId] or (A.state.chainDeferred or {})[source.questId] then return false,"先恢复暂缓的任务或任务线" end
    end
    if value.owned then return false,"已经携带目标物品，可直接比较装备" end
    if value.chanceHigh<=0 then return false,"当前来源无法获得目标物品" end
    if value.upgrade.provisional then return false,"武器属性加载中" end
    if value.upgrade.delta<=0 and #(value.upgrade.notes or {})==0 then return false,"这件装备没有提升" end
    A.char.gearTarget=id
    local count=0
    for _,item in pairs(A.state.equipment) do if item.id==source.itemId then count=count+1 end end
    A.char.gearBaseline=count
    A.char.locked=nil
    if A.Selection then A.Selection:Clear();A.Navigation.manual=nil end
    A.State:Refresh(true)
    return true
end

function G:SyncTarget(state)
    local id=A.char.gearTarget
    if not id then return end
    local source=G.GetSource(id,nil,state)
    if source then
        local count=state.bags[source.itemId] or 0
        for _,item in pairs(state.equipment) do if item.id==source.itemId then count=count+1 end end
        if count>(A.char.gearBaseline or 0) then A.char.gearTarget,A.char.gearBaseline=nil,nil;state.gearAcquired=source.itemId
        elseif source.reference and source.kind=="quest" then
            local q=A.Data:GetQuest(source.questId)
            if state.completed[source.questId] and not state.quests[source.questId] and not q.repeatable then
                A.char.gearTarget,A.char.gearBaseline=nil,nil
            end
        end
    end
    state.gearTarget=A.char.gearTarget
end

function G.DungeonBenefits(d,state,data)
    local values={}
    for id,source in pairs(G.DungeonSources(state,d.instanceId)) do
        local value=G.Source(source,state,data.content,data)
        if value and not value.owned and (value.upgrade.delta>0 or #(value.upgrade.notes or {})>0) then
            value.sourceId=id;values[#values+1]=value
        end
    end
    table.sort(values,function(a,b)
        if a.upgrade.delta~=b.upgrade.delta then return a.upgrade.delta>b.upgrade.delta end
        return a.sourceId<b.sourceId
    end)
    return values
end

-- An explicit equipment target guides the visit; only actually receiving the item settles it.
function G.PlanDungeonTarget(plan,source,state,data)
    local d=A.DungeonCatalog.entries[source.dungeonId]
    local boss=A.Dungeon.EncounterIdentity(source.encounterId,state)
    if not d or not boss then return end
    local item=state.items and state.items[source.itemId]
    local name=item and (item.link or item.name) or ("物品 #"..source.itemId)
    local action={kind="dungeonRun",title="获取「"..name.."」",areaId=d.areas[1],
        text="在"..d.title.."击败"..boss.title.."，拾取「"..name.."」。"}
    local visit=A.Dungeon.encounterVisit
    if state.inInstance and state.instanceId==d.instanceId and visit and visit.instanceId==d.instanceId and
        visit.difficulty==state.instanceDifficultyId and visit.kills[source.encounterId] then
        action.text=boss.title.."已击败，先拾取装备。未获得时可结束本轮，或出本重置后再刷。"
    end
    action=A.Dungeon.TaskApproach(action,state,data)
    if action.kind=="dungeonEnter" then action.text="前往"..d.title.."，目标装备："..name.."；首领："..boss.title.."。" end
    plan.best,plan.gearTargetBlocked=nil,nil
    plan.gearPlan,plan.preferenceApplied=true,true
    plan.fallback=action
    local routes=action.position and A.Flights and A.Flights.Itinerary(state.position,{action},state,A.Navigation)
    local journey=routes and routes[1]
    local actions=journey and A.Flights.Actions(journey.firstRoute,action,A.Navigation)
    if actions then plan.travelActions,plan.referenceJourney=actions,journey end
end

function G.TaskBenefits(choice,q,state,data)
    choice.gearSources={}
    for id,source in pairs(G.RewardSources(q)) do
        local value=G.Source(source,state,data.content,data)
        if value and not value.owned and (value.upgrade.delta>0 or #(value.upgrade.notes or {})>0) then
            value.sourceId=id;choice.gearSources[id]=value
            if not value.upgrade.provisional and #(value.upgrade.notes or {})==0 and
                (not choice.gear or value.upgrade.delta>choice.gear.upgrade.delta) then choice.gear=value end
        end
    end
end

function G.PreferTask(choices,state,options)
    if state.locked or state.gearTarget or options.gearPreference=="xp" then return end
    local base,best,gain,rate
    for _,choice in ipairs(choices) do
        if not choice.lowValue and not choice.acceptBlocked and not choice.entryBlocked and not choice.requireCheck then
            if choice.status~="accept" then return end
            local seconds=choice.timing and choice.timing.seconds
            if not seconds or choice.remainingXP==nil then return end
            local current=A.TaskGuide.MovementRate(seconds,choice.remainingXP)
            if not base then base,best,rate=choice,choice,current;gain=choice.gear and choice.gear.upgrade.delta or 0 end
            local delta=choice.gear and choice.gear.upgrade.delta or 0
            if current>=rate*0.95 and delta>gain then best,gain=choice,delta end
        end
    end
    if best~=base then return best end
end

function G.Benefits(candidates,state,content)
    local sources=G.DungeonSources(state)
    for id,source in pairs(content.gearSources or {}) do sources[id]=source end
    for _,candidate in ipairs(candidates) do
        local best
        candidate.gearSources={}
        for id,source in pairs(sources) do
            local dungeon=candidate.dungeonId and content.dungeons[candidate.dungeonId]
            local matches=source.kind=="dungeon" and (candidate.dungeonId==source.dungeonId or
                source.instanceId and dungeon and dungeon.instanceId==source.instanceId)
            if source.kind=="quest" then
                for _,action in ipairs(candidate.actions or {}) do
                    if action.kind=="turnin" and action.questId==source.questId then matches=true;break end
                end
            end
            if matches then
                local value=G.Source(source,state,content)
                if value and not value.owned and (value.upgrade.delta>0 or #(value.upgrade.notes or {})>0) and not value.upgrade.provisional then
                    value.sourceId=id
                    candidate.gearSources[id]=value
                    if #(value.upgrade.notes or {})==0 and
                        (not best or value.upgrade.delta*value.chanceLow>best.upgrade.delta*best.chanceLow) then best=value end
                end
            end
        end
        candidate.gear=best
    end
end

function G.Prefer(candidates,base,state,options)
    if state.gearTarget then
        for _,candidate in ipairs(candidates) do
            if candidate.gearSources and candidate.gearSources[state.gearTarget] then
                if candidate.requiresAcceptance then return base,"请在副本页明确接受装备来源行程" end
                return candidate
            end
        end
        return base,"装备目标暂无可执行行程"
    end
    if not base then return nil end
    if options.gearPreference=="xp" then return base end
    local best,gain=base,0
    for _,candidate in ipairs(candidates) do
        if not candidate.requiresAcceptance and (candidate.priority or 0)==(base.priority or 0) and candidate.rate>=base.rate*0.95 then
            local value=candidate.gear
            local delta=value and value.upgrade.delta*value.chanceLow or 0
            if delta>gain then best,gain=candidate,delta end
        end
    end
    return best
end
