return function(test,eq,F,A,plan)
local function setup()
    local B={};for k,v in pairs(A) do B[k]=v end
    B.settings={guides={}};B.char={guideProgress={},turnIns={},skipped={}}
    B.state=F.State();B.state.faction="Alliance";B.state.race="Human";B.state.level=10
    B.Data=F.Data({[1]=F.Quest(1),[2]=F.Quest(2)})
    B.Data.Target=function(_,q,s) return {map=1,x=(s.quests[q.id] and not s.quests[q.id].ready) and 0.2 or 0,y=0,objectiveIndex=1} end
    for _,file in ipairs({"Planner/Planner.lua","Planner/Selection.lua","Guides.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    B.Navigation={manual=nil};B.ready=true
    B.State={Refresh=function() B.Guides:Snapshot(B.state) end}
    B.Guides:Normalize()
    return B
end
local source=[[#name 原创验证指南
#group 验证
step << Horde
.accept 2
step << Alliance Human Warrior
.accept 1
step
.complete 1,1
step
.turnin 1
step
.collect 100,3
.xp 11
step
>> 继续下一片区域
]]
test("指南导入校验、角色步骤、真实接交与重载续接",function()
    local B=setup();local G,s=B.Guides,B.state
    assert(G.Applies("Horde / Alliance !Mage",s));eq(G.Applies("Alliance !Warrior",s),false)
    local key=assert(G:Import(source));assert(G:Select(key));eq(s.guide.step,2)
    local p=plan(s,B.Data,nil,B);G.Apply(p,s,B.Data);eq(p.guideActive,true);eq(p.fallback.kind,"accept");eq(p.fallback.questId,1)
    local empty={taskChoices={}};G.Apply(empty,s,B.Data);eq(empty.taskChoices[1].questId,1)
    s.position={map=1,x=0,y=0};G:Snapshot(s);eq(s.guide.step,2);eq(s.completed[1],nil)
    s.quests[1]={title="真实任务",objectives={{finished=false}}};G:Snapshot(s);eq(s.guide.step,3)
    p=plan(s,B.Data,nil,B);G.Apply(p,s,B.Data);eq(p.fallback.kind,"objective")
    assert(loadfile("Guides.lua"))("AiLeveling",B);G=B.Guides;G:Normalize();G:Snapshot(s);eq(s.guide.step,3)
    s.quests[1].objectives[1].finished=true;G:Snapshot(s);eq(s.guide.step,4)
    s.quests[1].ready=true;G:Snapshot(s);eq(s.guide.step,4)
    B.char.turnIns[1]=1;s.quests[1]=nil;s.completed[1]=true;G:Snapshot(s);eq(s.guide.step,5)
    s.bags[100]=3;G:Snapshot(s);eq(s.guide.step,5)
    s.level=11;G:Snapshot(s);eq(s.guide.step,6)
    G:Skip();eq(s.guide.finished,true);eq(s.completed[2],nil)
    assert(G:Select(key,true));eq(s.guide.step,6) -- Real facts still satisfy earlier steps.
    assert(G:Import(source));eq(s.guide.step,6)
    local before=B.settings.guides[key].source
    for _,line in ipairs({".unknown 1",".accept 0",".complete 1,0",".collect 1",".xp 61","print('unsafe')","step << Mage (Human)","#bad field"}) do
        local _,why=G:Import("#name 错误\nstep\n"..line);assert(why,line);eq(B.settings.guides[key].source,before)
    end
    assert(not G.Parse(string.rep("a",65537)))
    B.char.guideProgress[key].step="bad";G:Snapshot(s);eq(s.guide.step,6)
    local other={guides=B.settings.guides};B.char={turnIns={}};G:Normalize();eq(next(B.char.guideProgress),nil)
    assert(G:Select(key));eq(s.guide.step,6)
    assert(B.Selection:Automatic());eq(s.guide,nil);eq(other.guides[key].source,source)
end)
test("指南手动覆盖、重复任务、未知任务与快照隔离",function()
    local B=setup();local G,s=B.Guides,B.state
    B.Data.GetQuest=function(_,id) return id==1 and {id=1,title="重复",repeatable=true} end
    s.completed[1]=true;B.char.turnIns[1]=5
    local key=assert(G:Import("#name 重复\nstep\n.turnin 1\nstep\n.accept 999"));assert(G:Select(key));eq(s.guide.step,1)
    local snapshot={};for k,v in pairs(s) do snapshot[k]=v end
    B.char.turnIns[1]=6;G:Snapshot(s);eq(s.guide.step,2);eq(snapshot.guide.step,1);eq(snapshot.turnIns[1],5)
    local p={best={id="manual"}};s.locked=2;G.Apply(p,s,B.Data);eq(p.guideActive,nil);eq(p.best.id,"manual")
    s.locked=nil;G.Apply(p,s,B.Data);eq(p.guideActive,true);eq(p.fallback.kind,"guide");assert(p.fallback.title:find("999"))
    assert(G:Import("#name 重复\nstep\n>> 新步骤"));eq(s.guide.step,1)
    local current=B.char.guideProgress[key];assert(G:Import("#name 另一份\nstep\n>> 说明"));eq(B.char.guideProgress[key],current)
    local revision=B.settings.guides[key].revision
    G:Remove(key);eq(B.char.activeGuide,nil);eq(B.settings.guides[key],nil)
    assert(G:Import("#name 重复\nstep\n>> 再次导入"));assert(B.settings.guides[key].revision>revision)
end)
end
