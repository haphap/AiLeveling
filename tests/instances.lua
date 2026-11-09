return function(test,eq,F)
local saved={}
local globals={"GetNumSavedInstances","GetSavedInstanceInfo","RequestRaidInfo","GetTime","GetLocale","GetGameMessageInfo","INSTANCE_RESET_SUCCESS"}
for _,key in ipairs(globals) do saved[key]=_G[key] end
local now,rows=100,{}
GetTime=function() return now end;GetLocale=function() return "zhCN" end
GetNumSavedInstances=function() return #rows end
GetSavedInstanceInfo=function(index)
    local r=rows[index];return r.name,999999,r.reset,r.difficulty,r.locked,r.extended
end
RequestRaidInfo=function() end
INSTANCE_RESET_SUCCESS="%s 已重置。"
local function context()
    local data,s=F.Data({}),F.State();s.now=now;s.instanceName="夹具副本"
    local d={id=1,title="夹具副本",instanceId=42,lockoutNames={zhCN="夹具副本"},difficultyId=1,
        verified=true,minLevel=10,maxLevel=30,entryNode="goal",exitNode="goal",returnNode="start",actions={},runSeconds=600,xp=1000,waitSeconds=0}
    data.content.dungeons[1]=d
    local B={Navigation=F.Navigation,Content=data.content,Data=data,state=s,char={samples={},pendingResets={}},
        settings={dungeons=true,minutes=60,gearPreference="xp",role="DAMAGER"},RequestRefresh=function(self) self.refreshes=(self.refreshes or 0)+1 end}
    for _,file in ipairs({"State.lua","Instances.lua","Planner/Travel.lua","Planner/Dungeon.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    B.State.Refresh=function() B.Dungeon:Sync(s,{});B.Instances:Snapshot(s) end
    B.Instances:Capture();B.Instances:Snapshot(s)
    return B,d,s
end
test("原生锁定在更新事件后就绪并按本地化名称与难度匹配",function()
    rows={{name="夹具副本",reset=300,difficulty=1,locked=true}}
    local B,d,s=context();eq(B.Instances.Check(d,s),false)
    d.difficultyId=2;eq(B.Instances.Check(d,s),true)
    d.difficultyId=1;s.instanceLockouts[1].name="另一个副本";eq(B.Instances.Check(d,s),true)
    d.lockoutNames=nil;eq(B.Instances.Check(d,s),false)
    B.Instances:Request();B.Instances:Snapshot(s);eq(s.instanceLocksKnown,false)
end)
test("锁定到期唤醒一次且普通时间流逝不反复更改指纹",function()
    now=100;rows={{name="夹具副本",reset=10,difficulty=1,locked=true}}
    local B,d,s=context();local key=B.Instances:Snapshot(s)
    s.now=105;eq(B.Instances:Snapshot(s),key)
    now=110;B.Instances:Update();B.Instances:Update();eq(B.refreshes,1)
    s.now=110;B.Instances:Snapshot(s);eq(#s.instanceLockouts,0);eq(B.Instances.Check(d,s),true)
end)
test("已进入记录不能绕过实际难度检查且错误难度不写入重置记录",function()
    rows={};now=100
    local B,d,s=context();eq(B.Dungeon:Accept(1),true)
    s.inInstance,s.instanceId,s.instanceDifficultyId=true,42,213;B.State:Refresh()
    eq(B.char.pendingResets[42],nil);eq(B.Instances.Check(d,s),false)
    s.instanceDifficultyId=1;B.State:Refresh()
    assert(B.char.pendingResets[42]);eq(B.Instances.Check(d,s),true)
    s.instanceDifficultyId=213;B.State:Refresh();eq(B.Instances.Check(d,s),false)
    s.instanceDifficultyId=nil;B.State:Refresh();eq(B.Instances.Check(d,s),false)
    s.instanceDifficultyId=1;B.State:Refresh();eq(B.Instances.Check(d,s),true)
end)
test("再刷须离开并确认重置且延续原有预算",function()
    rows={};now=100
    local B,d,s=context();eq(B.Dungeon:Accept(1),true)
    s.inInstance,s.instanceId=true,42;B.State:Refresh();eq(B.char.pendingResets[42].name,"夹具副本")
    B.char.dungeon.elapsed=100
    B.Dungeon:Control("finish");eq(B.Instances:ConfirmReset(1),false)
    s.inInstance=false;B.State:Refresh();eq(B.Dungeon:Control("again"),false)
    eq(B.Instances:ConfirmReset(1),true);eq(B.Dungeon:Control("again"),true)
    eq(B.char.dungeon.round,2);eq(B.char.dungeon.elapsed,100);eq(B.char.dungeon.budget,3600)
end)
test("停止行程或重新登录保留待重置事实且暂离允许重入旧轮",function()
    rows={}
    local B,d,s=context();B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.State:Refresh()
    s.inInstance=false;B.State:Refresh();eq(B.Instances.Check(d,s),true)
    eq(B.Instances:ConfirmReset(1),false)
    B.Dungeon:Control("stop");s.dungeon=nil;B.Instances:Snapshot(s)
    eq(B.Dungeon:Accept(1),false)
    assert(loadfile("Instances.lua"))("AiLeveling",B)
    B.Instances:Capture();B.Instances:Snapshot(s);eq(B.Dungeon:Accept(1),false)
end)
test("已进入轮次暂离后拒绝再次入口导航，真实本内和结束后返程继续",function()
    rows={};now=100
    local B,d,s=context();assert(B.Dungeon:Accept(1))
    s.inInstance,s.instanceId=true,42;B.State:Refresh()
    s.inInstance=false;B.State:Refresh()
    B.Instances.entryError="实例次数受限";B.Instances:Snapshot(s)
    local actions=B.Dungeon.ActivePlan(d,s,B.Data)
    eq(actions[1].kind,"dungeonBlocked");eq(actions[1].position,nil)
    eq(B.char.dungeon.entered,true);eq(B.char.dungeon.settled,nil)
    s.inInstance=true;B.State:Refresh();eq(B.Instances.Check(d,s),true)
    eq(B.Dungeon.ActivePlan(d,s,B.Data)[1].kind,"dungeonRun")
    eq(B.Instances:Retry(),false)
    B.Dungeon:Control("finish");s.inInstance=false;B.State:Refresh()
    actions=B.Dungeon.ActivePlan(d,s,B.Data);eq(actions[#actions].kind,"dungeonEnd")
    assert(B.Instances:Retry());eq(s.instanceEntryError,nil)
end)
test("只匹配该副本的原生重置成功文字且重复消息不重复刷新",function()
    rows={}
    local B,d,s=context();B.char.pendingResets[42]={name="夹具副本"}
    B.Instances:SystemMessage("另一个副本 已重置。");assert(B.char.pendingResets[42])
    B.Instances:SystemMessage("夹具副本 已重置。");eq(B.char.pendingResets[42],nil);eq(B.refreshes,1)
    B.Instances:SystemMessage("夹具副本 已重置。");eq(B.refreshes,1)
end)
test("客户端实例次数错误阻止再入并由显式重新检查发起查询",function()
    rows={}
    local B,d,s=context()
    GetGameMessageInfo=function(id) return id==99 and "TRANSFER_ABORT_TOO_MANY_INSTANCES" or "OTHER" end
    B.Instances:Error(1);eq(B.Instances.entryError,nil)
    B.Instances:Error(99);B.Instances:Snapshot(s);eq(B.Instances.Check(d,s),false)
    local calls=0;RequestRaidInfo=function() calls=calls+1 end
    eq(B.Instances:Retry(),true);eq(calls,1);eq(s.instanceLocksKnown,false)
    B.Instances:Capture();B.Instances:Snapshot(s);eq(B.Instances.Check(d,s),true)
end)
for _,key in ipairs(globals) do _G[key]=saved[key] end
end
