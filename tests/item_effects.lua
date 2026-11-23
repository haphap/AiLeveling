return function(test,eq,F,A,plan)
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    B.requestedItems={};B.char={}
    B.clientVersion,B.build,B.interface="1.60.1","70862",16001
    for _,f in ipairs({"Data/ItemEffects.lua","Items.lua","Planner/Gear.lua"}) do assert(loadfile(f))("AiLeveling",B) end
    return B,F.State()
end
local function native(run)
    local saved={}
    local names={"C_Item","C_PlayerInfo","C_TooltipInfo","C_Spell","Enum","ITEM_SPELL_TRIGGER_ONEQUIP",
        "TOOLTIP_ITEM_STAT_SPELL_POWER_INCREASE","TOOLTIP_ITEM_STAT_HOLY_DAMAGE_INCREASE","C_ClassTalents","C_Traits"}
    for _,name in ipairs(names) do saved[name]=_G[name] end
    C_Item={GetItemInfo=function(id) return "物品",tostring(id),2,1,1,nil,nil,1,"INVTYPE_CHEST" end,
        GetItemStats=function() return {ITEM_MOD_STRENGTH_SHORT=5} end}
    C_PlayerInfo={CanUseItem=function() return true end}
    Enum={TooltipDataLineType={ItemSpellTriggerOnUse=44,ItemSpellTriggerOnEquip=45,ItemSpellTriggerOnProc=46}}
    C_TooltipInfo={GetHyperlink=function() return {dataInstanceID=9,lines={{type=45,leftText="装备：有一定几率获得额外攻击。"}}} end}
    C_Spell={GetSpellDescription=function(id) return "效果说明 #"..id end}
    local ok,err=pcall(run)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    assert(ok,err)
end

test("角树柄的常驻法伤在防骑背包和交付奖励比较中只计一次",function() native(function()
    local B,s=fixture()
    assert(loadfile("QuestAssist.lua"))("AiLeveling",B)
    local raw={ITEM_MOD_STRENGTH_SHORT=6}
    C_Item.GetItemInfo=function() return "角树柄","item:271664",2,33,0,nil,nil,1,"INVTYPE_WEAPON" end
    C_Item.GetItemStats=function() return raw end
    ITEM_SPELL_TRIGGER_ONEQUIP="装备："
    TOOLTIP_ITEM_STAT_SPELL_POWER_INCREASE="装备：提高法术和魔法效果所造成的伤害和治疗效果，最多%1$d点。"
    TOOLTIP_ITEM_STAT_HOLY_DAMAGE_INCREASE="装备：使神圣法术和效果所造成的伤害提高最多%1$d点。"
    local lines={{type=0,leftText="装备：提高所有法术和魔法效果所造成的伤害和治疗效果，最多26点。"}}
    C_TooltipInfo.GetHyperlink=function() return {lines=lines} end
    s.class,s.role,s.protectionTalents="PALADIN","DAMAGER",true
    local axe=B.Items:Read(271664)
    eq(B.Gear.Score(axe,s),28.4);eq(raw.ITEM_MOD_SPELL_POWER_SHORT,nil);eq(#axe.effects,0)
    raw.ITEM_MOD_SPELL_POWER_SHORT=26;raw.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT=26
    eq(B.Gear.Score(B.Items:Read(271664),s),28.4)
    local strength={id=100,usable=true,equipLoc="INVTYPE_WEAPON",stats={ITEM_MOD_STRENGTH_SHORT=12}}
    s.equipment={[16]=strength,[17]={id=101,equipLoc="INVTYPE_SHIELD",stats={ITEM_MOD_STAMINA_SHORT=5}}}
    local best=B.QuestAssist.CompareRewards({strength,axe},s)
    eq(best.index,2);eq(best.upgrade.replacements[17],nil)
    B.indexReady=true;B.Gear:ScanBagOffers(s)
    s.bags[axe.id]=1;s.bagEquipment={axe};B.Gear:ScanBagOffers(s)
    eq(B.Gear.BagUpgrade(s).item.id,axe.id)
    local twoHand=B.Gear.Upgrade({id=102,usable=true,equipLoc="INVTYPE_2HWEAPON",stats={ITEM_MOD_SPELL_POWER_SHORT=65}},s)
    assert(table.concat(twoHand.notes):find("失去格挡",1,true))
    raw={ITEM_MOD_FIRE_DAMAGE_DONE_SHORT=20,ITEM_MOD_SPELL_HEALING_DONE_SHORT=30}
    lines={{type=45,leftText="使神圣法术和效果所造成的伤害提高最多8点。"},
        {type=46,leftText="触发时增加26点法术强度"}}
    local holy=B.Items:Read(103);eq(B.Gear.Score(holy,s),8);eq(#holy.effects,1)
    s.role="TANK";eq(B.Gear.Score(axe,s),28.4)
    s.class="WARRIOR";assert(math.abs(B.Gear.Score(axe,s)-2.4)<0.0001)
end) end)

test("激流堡兜帽的命中等级进入防骑背包和奖励评分",function() native(function()
    local B,s=fixture()
    assert(loadfile("QuestAssist.lua"))("AiLeveling",B)
    local stats={
        [278567]={ITEM_MOD_STAMINA_SHORT=8,RESISTANCE0_NAME=152,ITEM_MOD_HIT_RATING_SHORT=5},
        [252456]={ITEM_MOD_STAMINA_SHORT=13,RESISTANCE0_NAME=84,ITEM_MOD_SPELL_POWER_SHORT=12},
    }
    C_Item.GetItemInfo=function(id)
        local hood=id==278567
        return hood and "激流堡兜帽" or "图腾师的皮头盔","item:"..id,hood and 2 or 3,hood and 39 or 30,0,nil,nil,1,"INVTYPE_HEAD"
    end
    C_Item.GetItemStats=function(link) return stats[tonumber(link:match("item:(%d+)"))] end
    C_TooltipInfo.GetHyperlink=function(link)
        return {lines={{type=0,leftText=link=="item:278567" and "+0.5% 命中几率" or "+12 法术强度"}}}
    end
    local hood,helm=B.Items:Read(278567),B.Items:Read(252456)
    s.class,s.role,s.level="PALADIN","TANK",39
    eq(math.floor(B.Gear.Score(hood,s)*100+0.5),1489)
    s.equipment={[1]=hood}
    local bag=B.Gear.Upgrade(helm,s)
    eq(math.floor(bag.delta*100+0.5),1179)
    s.role,s.protectionTalents="DAMAGER",true
    local reward=B.QuestAssist.CompareRewards({hood,helm},s)
    eq(reward.index,2);eq(reward.upgrade.delta,bag.delta)
end) end)

test("自动评分采用已应用的防护天赋，切换配置及手动选择生效",function() native(function()
    local B,s=fixture();assert(loadfile("Talents.lua"))("AiLeveling",B)
    local config,staged,spent,reads=1,false,15,0
    C_ClassTalents={GetActiveConfigID=function() return config end}
    C_Traits={ConfigHasStagedChanges=function() return staged end,GetConfigInfo=function() return {treeIDs={22}} end,
        GetGroupDisplayInfoByTreeID=function() return {{groupID=8,skillLineID=267},{groupID=7},{groupID=9}} end,
        GetGroupCurrencyInfo=function()
            reads=reads+1
            return {{traitNodeGroupID=7,currencyInfos={{spent=10}}},{traitNodeGroupID=8,currencyInfos={{spent=spent}}}}
        end}
    s.class="PALADIN";s.protectionTalents=B.Talents:ProtectionMain();eq(select(3,B.Gear.Model(s)),"protection")
    eq(B.Talents:ProtectionMain(),true);eq(reads,1)
    B.Talents.protectionDirty=true;staged=true;spent=5;eq(B.Talents:ProtectionMain(),true);eq(reads,1)
    staged=false;spent=10;eq(B.Talents:ProtectionMain(),false)
    config=2;spent=20;eq(B.Talents:ProtectionMain(),true)
    s.role="HEALER";eq(select(3,B.Gear.Model(s)),"healer")
    s.role,s.damageStyle="DAMAGER","strength";eq(select(3,B.Gear.Model(s)),"strength")
end) end)

test("原生装备后被动触发进入新旧装备效果比较且不重复附加数据库说明",function() native(function()
    local B,s=fixture();local c=B.Items:Read(11815)
    eq(#c.effects,1);eq(c.effects[1].kind,"equip");assert(c.effects[1].text:find("额外攻击",1,true))
    s.equipment={[5]=c}
    local plain={id=999,usable=true,equipLoc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=6}}
    local r=B.Gear.Upgrade(plain,s);eq(r.delta,1);assert(r.notes[1]:find("失去",1,true));assert(r.notes[1]:find("额外攻击",1,true))
    s.equipment={[5]=plain};r=B.Gear.Upgrade(c,s);eq(r.delta,-1);assert(r.notes[1]:find("获得",1,true))
end) end)

test("固定被动属性须在原生属性完整出现才算已覆盖，评分不重复相加",function() native(function()
    local B,s=fixture();C_Item.GetItemStats=function() return {ITEM_MOD_SPIRIT_SHORT=16} end
    C_TooltipInfo.GetHyperlink=function() return {lines={{type=45,leftText="装备：精神提高16点。"}}} end
    local c=B.Items:Read(18470);eq(#c.effects,0);s.class="MAGE";s.damageStyle="caster";s.equipment={}
    eq(B.Gear.Score(c,s),6.4)
    C_Item.GetItemStats=function() return {ITEM_MOD_SPIRIT_SHORT=15} end
    c=B.Items:Read(18470);eq(#c.effects,1);assert(c.effects[1].text:find("精神",1,true))
    C_Item.GetItemStats=function() return {ITEM_MOD_SPIRIT_SHORT=16} end
    C_TooltipInfo.GetHyperlink=function() return {lines={{type=45,leftText="精神"},{type=45,leftText="另有未知效果"}}} end
    c=B.Items:Read(18470);eq(#c.effects,2)
end) end)

test("纯属性多条法术汇总核对，攻击与远程攻击属性分别处理",function() native(function()
    local B=fixture();local stats={ITEM_MOD_ATTACK_POWER_SHORT=42,ITEM_MOD_RANGED_ATTACK_POWER_SHORT=42}
    C_Item.GetItemStats=function() return stats end
    C_TooltipInfo.GetHyperlink=function() return {lines={{type=45,leftText="攻击强度"},{type=45,leftText="远程攻击强度"}}} end
    eq(#B.Items:Read(19120).effects,0)
    stats.ITEM_MOD_RANGED_ATTACK_POWER_SHORT=41;assert(#B.Items:Read(19120).effects>0)
end) end)

test("提示接口缺失或未列被动时从当前构建效果表保留说明，缺表关系保留未知",function() native(function()
    local B=fixture();C_TooltipInfo=nil
    local c=B.Items:Read(11815);eq(#c.effects,1);assert(c.effects[1].text:find("15600",1,true))
    c=B.Items:Read(167648);assert(c.effects[1].text:find("被动效果",1,true))
    C_TooltipInfo={GetHyperlink=function() return {lines={{type=0,leftText="物品名"}}} end}
    c=B.Items:Read(11815);eq(#c.effects,1)
    for _,key in ipairs({"clientVersion","interface"}) do
        local value=B[key];B[key]="other";eq(#B.Items:Read(11815).effects,0);B[key]=value
    end
end) end)

test("未知物品仍读取原生被动类型，不依赖固定库覆盖",function() native(function()
    local B=fixture();local c=B.Items:Read(999999);eq(c.effects[1].kind,"equip")
    C_TooltipInfo.GetHyperlink=function() return {lines={{type=45}}} end
    c=B.Items:Read(999999);eq(c.effects[1].text,"装备被动效果")
end) end)

test("被动说明异步加载保留法术身份并只跟踪本轮待加载文本",function() native(function()
    local B,s=fixture();C_TooltipInfo=nil;C_Spell.GetSpellDescription=function() return "" end
    local c=B.Items:Read(11815);assert(c.effects[1].text:find("15600",1,true));eq(B.Items.spellData[15600],true)
    C_Spell.GetSpellDescription=function() return "完整被动说明" end
    c=B.Items:Read(11815);assert(c.effects[1].text:find("完整被动说明",1,true));eq(B.Items.spellData[15600],nil)
    C_Spell.GetSpellDescription=function() error("尚未加载") end
    assert(B.Items:Read(11815));eq(B.Items.spellData[15600],true)
    s.equipment={};s.bagEntries={};B.Items:Snapshot(s);eq(next(B.Items.spellData),nil)
end) end)
test("群体被动即使本人的属性已有数值仍保留独立效果",function() native(function()
    local B=fixture();C_Item.GetItemStats=function() return {ITEM_MOD_SPIRIT_SHORT=4} end
    assert(B.ItemEffects.items[6182].complex);eq(#B.Items:Read(6182).effects,1)
end) end)

test("交任务时列出低属性被动奖励与普通提升的权衡，不直接选属性最高项",function() native(function()
    local B,s=fixture();assert(loadfile("QuestAssist.lua"))("AiLeveling",B)
    local quest,choices,link=GetQuestID,GetNumQuestChoices,GetQuestItemLink
    local first=11815;GetQuestID=function() return 42 end;GetNumQuestChoices=function() return 2 end
    GetQuestItemLink=function(_,i) return "item:"..(i==1 and first or 999) end
    C_Item.GetItemStats=function(value) return {ITEM_MOD_STRENGTH_SHORT=value:find("11815",1,true) and 1 or 6} end
    C_TooltipInfo.GetHyperlink=function(value)
        return {lines=value:find("11815",1,true) and {{type=45,leftText="装备：额外攻击"}} or {{type=0,leftText="普通装备"}}}
    end
    s.equipment={[5]={id=998,usable=true,equipLoc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=5}}}
    B.state,B.settings=s,{};B.QuestAssist.rewardQuest=42
    local lines=table.concat(B.QuestAssist:RewardLines(),"\n")
    GetQuestID,GetNumQuestChoices,GetQuestItemLink=quest,choices,link
    assert(lines:find("额外攻击",1,true));assert(lines:find("第 1 项",1,true));assert(lines:find("第 2 项",1,true))
    assert(lines:find("-4.0",1,true));assert(lines:find("+1.0",1,true));assert(lines:find("交付奖励：悬停比较",1,true))
    local a=B.Items:Read(11815,"item:11815");local b=B.Items:Read(999,"item:999")
    local best,unknown,comparisons=B.QuestAssist.CompareRewards({a,b},s)
    eq(best,nil);eq(unknown,nil);eq(#comparisons,2)
    a.effects={};a.stats.ITEM_MOD_STRENGTH_SHORT=5
    best,unknown,comparisons=B.QuestAssist.CompareRewards({a,b},s);eq(best.index,2);eq(comparisons,nil)
end) end)
test("法术强度按伤害与治疗加成分别核对，不能用较低伤害值覆盖治疗效果",function() native(function()
    local B=fixture();local stats={ITEM_MOD_SPELL_POWER_SHORT=22}
    C_Item.GetItemStats=function() return stats end
    eq(B.ItemEffects.items[279863].stats.SPELL_DAMAGE_DONE,8)
    eq(B.ItemEffects.items[279863].stats.SPELL_HEALING_DONE,22)
    eq(#B.Items:Read(279863).effects,0)
    stats.ITEM_MOD_SPELL_POWER_SHORT=8;assert(#B.Items:Read(279863).effects>0)
end) end)
end
