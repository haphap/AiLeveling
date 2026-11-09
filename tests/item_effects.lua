return function(test,eq,F,A,plan)
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    B.Content={items={},sources={}};B.requestedItems={};B.char={}
    B.clientVersion,B.build,B.interface="1.60.1","70862",16001
    for _,f in ipairs({"Data/ItemEffects.lua","Items.lua","Planner/Gear.lua"}) do assert(loadfile(f))("AiLeveling",B) end
    return B,F.State()
end
local function native(run)
    local saved={C_Item=C_Item,C_PlayerInfo=C_PlayerInfo,C_TooltipInfo=C_TooltipInfo,C_Spell=C_Spell,Enum=Enum}
    local names={"C_Item","C_PlayerInfo","C_TooltipInfo","C_Spell","Enum"}
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
    c=B.Items:Read(167648);assert(c.effects[1].text:find("待核对",1,true))
    C_TooltipInfo={GetHyperlink=function() return {lines={{type=0,leftText="物品名"}}} end}
    c=B.Items:Read(11815);eq(#c.effects,1)
    for _,key in ipairs({"clientVersion","build","interface"}) do
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
    assert(lines:find("-4.0",1,true));assert(lines:find("+1.0",1,true));assert(not lines:find("奖励建议：",1,true))
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
