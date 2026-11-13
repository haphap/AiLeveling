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
        minLevel=10,maxLevel=30}
    local B={Navigation=F.Navigation,Data=data,state=s,char={samples={}},
        settings={dungeons=true,minutes=60,gearPreference="xp",role="DAMAGER"},RequestRefresh=function(self) self.refreshes=(self.refreshes or 0)+1 end}
    for _,file in ipairs({"State.lua","Instances.lua","Planner/Travel.lua","Planner/Dungeon.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    B.State.Refresh=function() B.Instances:Snapshot(s) end
    B.Instances:Capture();B.Instances:Snapshot(s)
    return B,d,s
end
test("原生锁定在更新事件后就绪并按本地化名称与难度匹配",function()
    rows={{name="夹具副本",reset=300,difficulty=1,locked=true}}
    local B,d,s=context();eq(s.instanceLockouts[1].name,"夹具副本");eq(s.instanceLockouts[1].difficulty,1)
    B.Instances:Request();B.Instances:Snapshot(s);eq(s.instanceLocksKnown,false)
end)
test("锁定到期唤醒一次且普通时间流逝不反复更改指纹",function()
    now=100;rows={{name="夹具副本",reset=10,difficulty=1,locked=true}}
    local B,d,s=context();local key=B.Instances:Snapshot(s)
    s.now=105;eq(B.Instances:Snapshot(s),key)
    now=110;B.Instances:Update();B.Instances:Update();eq(B.refreshes,1)
    s.now=110;B.Instances:Snapshot(s);eq(#s.instanceLockouts,0)
end)

test("客户端实例次数错误阻止再入并由显式重新检查发起查询",function()
    rows={}
    local B,d,s=context()
    GetGameMessageInfo=function(id) return id==99 and "TRANSFER_ABORT_TOO_MANY_INSTANCES" or "OTHER" end
    B.Instances:Error(1);eq(B.Instances.entryError,nil)
    B.Instances:Error(99);B.Instances:Snapshot(s);assert(s.instanceEntryError)
    local calls=0;RequestRaidInfo=function() calls=calls+1 end
    eq(B.Instances:Retry(),true);eq(calls,1);eq(s.instanceLocksKnown,false)
    B.Instances:Capture();B.Instances:Snapshot(s);eq(s.instanceEntryError,nil)
end)
for _,key in ipairs(globals) do _G[key]=saved[key] end
end
