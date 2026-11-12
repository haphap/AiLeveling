return function(test,eq,F,A)
local function fixture()
    local B={UI={},Content={gearSources={}},settings={}}
    for _,file in ipairs({"Data/WeaponSkills.lua","State.lua","Planner/Gear.lua","QuestAssist.lua","UI/Main.lua","UI/Gear.lua"}) do
        assert(loadfile(file))("AiLeveling",B)
    end
    local s=F.State();s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    s.weaponSkills={[43]={rank=100,maxRank=100,modifier=5,tempPoints=0},[44]={rank=1,maxRank=100,modifier=0,tempPoints=0}}
    B.state=s
    return B,s
end
local function weapon(id,sub,dps,loc)
    return {id=id,classID=2,subClassID=sub,equipLoc=loc or "INVTYPE_WEAPON",usable=true,weaponDPS=dps,stats={}}
end

test("跨武器类型换装保留低熟练度说明，同类型与练满后恢复明确收益",function()
    local B,s=fixture();s.equipment[16]=weapon(1,7,10)
    local candidate=weapon(2,0,20)
    local r=B.Gear.Upgrade(candidate,s);eq(r.delta,30)
    assert(table.concat(r.notes):find("单手斧熟练度 1/100",1,true))
    local best,unknown,manual=B.QuestAssist.CompareRewards({candidate},s)
    eq(best,nil);assert(not unknown);assert(manual)
    s.weaponSkills[44].rank=100;s.weaponSkills[44].modifier=5
    r=B.Gear.Upgrade(candidate,s);eq(#r.notes,0)
    best,unknown,manual=B.QuestAssist.CompareRewards({candidate},s);assert(best);eq(manual,nil)
    s.weaponSkills[43]=nil;candidate.subClassID=7;r=B.Gear.Upgrade(candidate,s);eq(#r.notes,0)
end)
test("武器熟练度合并任务要求只读采集，缺失接口和异常值保持未知",function()
    local B,s=fixture();local old=C_SkillInfo;local calls={}
    C_SkillInfo={GetSkillLineInfoByID=function(id)
        calls[id]=(calls[id] or 0)+1
        if id==43 then return {rank=80,maxRank=100,modifier=5,tempPoints=2} end
        if id==44 then return {rank=0/0,maxRank=100,modifier=0,tempPoints=0} end
        if id==162 then return {rank=50,maxRank=100,modifier=0,tempPoints=0} end
    end}
    local requirements={skills={[43]=true}}
    B.State:Qualifications(s,requirements);eq(calls[43],1);eq(calls[162],1);eq(calls[473],nil)
    eq(s.weaponSkills[43].modifier,5);eq(s.weaponSkills[43].tempPoints,2);eq(s.weaponSkills[44],nil)
    eq(s.weaponSkills[45],nil);eq(requirements.skills[162],nil)
    local ref,skill=B.Gear.WeaponSkill(weapon(1,13,10),s);eq(ref.skill,162);eq(skill.rank,50)
    s.clientBuild="other";B.State:Qualifications(s,requirements);eq(s.weaponSkills,nil)
    s.clientBuild="70862";C_SkillInfo=nil;B.State:Qualifications(s,requirements);eq(next(s.weaponSkills),nil)
    C_SkillInfo=old
end)
test("技能加成影响武器权衡，未知类型与缺失熟练度不假设练满",function()
    local B,s=fixture();s.equipment[16]=weapon(1,7,10);local candidate=weapon(2,0,20)
    s.weaponSkills[44]={rank=100,maxRank=100,modifier=5,tempPoints=0}
    eq(#B.Gear.Upgrade(candidate,s).notes,0)
    s.weaponSkills[43].tempPoints=5;assert(#B.Gear.Upgrade(candidate,s).notes>0)
    s.weaponSkills[44]=nil;assert(table.concat(B.Gear.Upgrade(candidate,s).notes):find("熟练度：在技能面板查看",1,true))
    candidate.subClassID=17;assert(table.concat(B.Gear.Upgrade(candidate,s).notes):find("在技能面板查看武器熟练度",1,true))
    s.clientBuild="other";eq(#B.Gear.Upgrade(candidate,s).notes,0)
    s.clientBuild="70862";candidate.usable=false;eq(B.Gear.Upgrade(candidate,s),nil)
end)
test("远程武器使用远程熟练度，属性用途和投掷武器不套近战伤害分",function()
    local B,s=fixture();s.class="HUNTER"
    s.weaponSkills[45]={rank=100,maxRank=100,modifier=0,tempPoints=0}
    s.weaponSkills[46]={rank=1,maxRank=100,modifier=0,tempPoints=0}
    s.equipment[18]=weapon(1,2,10,"INVTYPE_RANGED")
    local gun=weapon(2,3,20,"INVTYPE_RANGEDRIGHT")
    assert(#B.Gear.Upgrade(gun,s).notes>0)
    eq(B.Gear.Score(weapon(3,7,100),s),0)
    s.class="WARRIOR";eq(B.Gear.Score(weapon(4,16,100,"INVTYPE_THROWN"),s),0)
    s.class="MAGE";s.equipment[16]=weapon(1,7,10)
    eq(#B.Gear.Upgrade(weapon(2,0,20),s).notes,0)
end)
test("整套双手替换和背包副手均保留熟练度权衡，装备详情显示实际数值",function()
    local B,s=fixture();s.equipment[16]=weapon(1,7,10)
    s.weaponSkills[172]={rank=1,maxRank=100,modifier=0,tempPoints=0}
    local candidate=weapon(2,1,20,"INVTYPE_2HWEAPON")
    assert(#B.Gear.Upgrade(candidate,s).notes>0)
    s.equipment[16]=candidate;s.capabilities={dualWield=true}
    local main,off=weapon(3,7,15),weapon(4,0,15,"INVTYPE_WEAPONOFFHAND")
    s.bagEquipment={off}
    local r=B.Gear.Upgrade(main,s);assert(r.replacements[17]);assert(table.concat(r.notes):find("单手斧",1,true))
    s.bagEquipment={}
    assert(loadfile("UI/Browser.lua"))("AiLeveling",B)
    local row=B.UI.Browser:GearRows()[1];assert(row.skill:find("双手斧熟练度 1/100",1,true))

end)
test("武器熟练度权衡抑制自动装备绕路而手选目标保持",function()
    local B,s=fixture();s.equipment[16]=weapon(1,7,10);s.items={[7]=weapon(7,0,20)}
    local content={gearSources={wanted={verified=true,kind="quest",questId=7,itemId=7}}}
    local base={rate=100,priority=0};local route={rate=96,priority=0,actions={{kind="turnin",questId=7}}}
    B.Gear.Benefits({base,route},s,content);assert(route.gearSources.wanted);eq(route.gear,nil)
    eq(B.Gear.Prefer({base,route},base,s,{}),base)
    s.gearTarget="wanted";eq(B.Gear.Prefer({base,route},base,s,{}),route)
end)
end
