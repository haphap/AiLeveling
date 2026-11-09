return function(test,eq,F,A,plan)
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    B.Content={items={},sources={}};B.requestedItems={};B.char={}
    B.clientVersion,B.build,B.interface="1.60.1","70862",16001
    for _,file in ipairs({"Data/ItemSets.lua","Items.lua","Planner/Gear.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local s=F.State();s.skills={}
    return B,s
end
local function item(B,id,slot,strength)
    local sid=B.ItemSets.items[id]
    return {id=id,equipLoc=slot,usable=true,stats={ITEM_MOD_STRENGTH_SHORT=strength or 1},
        setId=sid,setInfo=sid and B.ItemSets.sets[sid]}
end

test("原生套装归属按当前构建接入，冲突与缺失套装效果表保留未知",function()
    local B,s=fixture();local oldItem,oldPlayer,oldTooltip=C_Item,C_PlayerInfo,C_TooltipInfo
    C_Item={GetItemInfo=function(id) return "装备","item:"..id,2,20,1,nil,nil,1,"INVTYPE_CHEST" end,
        GetItemStats=function() return {ITEM_MOD_STRENGTH_SHORT=1} end}
    C_PlayerInfo={CanUseItem=function() return true end};C_TooltipInfo=nil
    local c=B.Items:Read(10399);eq(c.setId,161);eq(c.setInfo.name,"迪菲亚皮甲");eq(#c.setInfo.bonuses,4)
    eq(B.Items:Read(276538).setId,2111)
    c=B.Items:Read(221785);eq(c.setId,nil);eq(c.setUnknown,true)
    eq(B.ItemSets.sets[1969].bonuses,nil)
    for _,field in ipairs({"clientVersion","build","interface"}) do
        local saved=B[field];B[field]="other";eq(B.Items:Read(10399).setId,nil);B[field]=saved
    end
    B.Content.sources.test=true;B.Content.items[221785]={verified=true,source="test",setId=1700}
    c=B.Items:Read(221785);eq(c.setId,1700);eq(c.setUnknown,nil)
    C_Item,C_PlayerInfo,C_TooltipInfo=oldItem,oldPlayer,oldTooltip
end)

test("实际套装跨门槛才列出失去或获得效果，单件变化不虚报",function()
    local B,s=fixture();s.equipment={[5]=item(B,10399,"INVTYPE_CHEST"),[10]=item(B,10401,"INVTYPE_HAND")}
    local plain=item(B,999,"INVTYPE_CHEST",3)
    local r=B.Gear.Upgrade(plain,s);eq(r.delta,2);eq(#r.notes,1)
    assert(r.notes[1]:find("迪菲亚皮甲",1,true));assert(r.notes[1]:find("失去 2 件套效果",1,true))
    s.equipment[10]=nil;r=B.Gear.Upgrade(plain,s);eq(#r.notes,0)
    s.equipment={[10]=item(B,10401,"INVTYPE_HAND")}
    r=B.Gear.Upgrade(item(B,10399,"INVTYPE_CHEST",3),s);eq(#r.notes,1)
    assert(r.notes[1]:find("获得 2 件套效果",1,true))
end)

test("套装效果说明使用客户端文本，缺文本仍保留门槛提示",function()
    local B,s=fixture();s.equipment={[10]=item(B,10401,"INVTYPE_HAND")}
    local oldSpell=C_Spell
    C_Spell={GetSpellDescription=function(id) eq(id,14707);return "护甲提高。" end}
    local r=B.Gear.Upgrade(item(B,10399,"INVTYPE_CHEST"),s)
    assert(r.notes[1]:find("护甲提高。",1,true))
    C_Spell.GetSpellDescription=function() return "" end
    r=B.Gear.Upgrade(item(B,10399,"INVTYPE_CHEST"),s);assert(r.notes[1]:find("获得 2 件套效果",1,true))
    C_Spell.GetSpellDescription=function() error("加载中") end
    assert(B.Gear.Upgrade(item(B,10399,"INVTYPE_CHEST"),s))
    C_Spell=oldSpell
end)

test("套装专业要求使用真实技能等级，未知条件不猜生效",function()
    local B,s=fixture();local set=B.ItemSets.sets[421];eq(set.skill,197);eq(set.rank,300)
    local a=item(B,19682,"INVTYPE_CHEST");local b=item(B,19683,"INVTYPE_LEGS");local c=item(B,19684,"INVTYPE_FEET")
    s.equipment={[5]=a,[7]=b};s.skills[197]=299
    local r=B.Gear.Upgrade(c,s);eq(#r.notes,0)
    s.skills[197]=300;r=B.Gear.Upgrade(c,s);assert(#r.notes>0);assert(r.notes[1]:find("获得",1,true))
    s.skills[197]=nil;r=B.Gear.Upgrade(c,s);assert(r.notes[1]:find("需要 ",1,true))
end)

test("已穿套装归属有冲突时不把不确定件数作为明确装备收益",function()
    local B,s=fixture();s.equipment[1]=item(B,1,"INVTYPE_HEAD");s.equipment[1].setUnknown=true
    local r=B.Gear.Upgrade(item(B,2,"INVTYPE_HAND",5),s)
    assert(#r.notes>0);assert(r.notes[1]:find("查看套装效果",1,true))
end)
test("套装专业状态采集与任务要求合并且按构建启用",function()
    local B,s=fixture();assert(loadfile("State.lua"))("AiLeveling",B)
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    local old=C_SkillInfo;local calls={}
    C_SkillInfo={GetSkillLineInfoByID=function(id) calls[id]=(calls[id] or 0)+1;return id==197 and {rank=300} or nil end}
    local requirements={skills={[197]=true,[999]=true}}
    B.State:Qualifications(s,requirements);eq(s.skills[197],300);eq(s.skills[164],0);eq(s.skills[165],0)
    eq(calls[197],1);eq(s.skills[999],0);eq(requirements.skills[164],nil)
    s.clientBuild="other";B.State:Qualifications(s,requirements);eq(s.skills[164],nil)
    s.clientBuild="70862";C_SkillInfo=nil;B.State:Qualifications(s,requirements);eq(s.skills[197],nil)
    C_SkillInfo=old
end)
end
