return function(test,eq,F,A,plan)
local function setup()
    local B={};for k,v in pairs(A) do B[k]=v end
    B.Navigation={Distance=function(_,a,b) if a and b and a.map==b.map then return math.abs(a.x-b.x)*1000 end end}
    B.Roads=nil;B.TaskGuide=nil
    for _,file in ipairs({"Data/Questie.lua","Planner/Supplies.lua","Planner/Planner.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local rows={
        [1]={name="联盟商人",npcFlags=4,friendlyToFaction="A",spawns={[10]={{15,50}}}},
        [2]={name="联盟铁匠",npcFlags=16,friendlyToFaction="A",spawns={[10]={{25,50}}}},
        [3]={name="部落商人",npcFlags=4,friendlyToFaction="H",spawns={[10]={{10,50}}}},
        [4]={name="中立商人",npcFlags=4,friendlyToFaction="AH",spawns={[10]={{20,50}}}},
        [5]={name="楼层未知",npcFlags=4,friendlyToFaction="A",spawns={[10]={{5,50,2}}}},
        [6]={name="阵营未知",npcFlags=4,spawns={[10]={{1,50}}}},
        [7]={name="其他地图",npcFlags=4,friendlyToFaction="A",spawns={[20]={{1,50}}}},
        [8]={name="普通居民",npcFlags=0,friendlyToFaction="A",spawns={[10]={{1,50}}}},
        [9]={name="无效坐标",npcFlags=4,friendlyToFaction="A",spawns={[10]={{200,50}}}},
        [10]={name="联盟旅店",npcFlags=128,friendlyToFaction="A",spawns={[10]={{10,50}}}},
        [11]={name="训练师",subName="专业训练师",npcFlags=32,friendlyToFaction="AH",spawns={[10]={{12,50}}}},
        [12]={name="敌方旅店",npcFlags=128,friendlyToFaction="H",spawns={[10]={{10,50}}}},
        [13]={name="楼层不明旅店",npcFlags=128,friendlyToFaction="A",spawns={[10]={{10,50,2}}}}}
    B.Data.db={Enum={npcFlags={VENDOR=4,REPAIR=16,TRAINER=32,INNKEEPER=128}},Npc={GetAllIds=function() return {1,2,3,4,5,6,7,8,9,10,11,12,13} end,
        Get=function(id,key) return rows[id] and rows[id][key] end},Item={Get=function(id,key) if key=="vendors" then return id==100 and {1,3} or {4} end end}}
    B.Data.maps={[10]=1,[20]=2}
    local co=coroutine.create(function() B.Data:BuildServices() end)
    repeat local ok,why=coroutine.resume(co);assert(ok,why) until coroutine.status(co)=="dead"
    local oldMap=C_Map;C_Map={GetMapInfo=function(id) return {mapID=id} end}
    local s=F.State();s.position={map=1,x=0,y=0.5};s.freeSlots=0;s.durability=1;s.faction="Alliance"
    local d=F.Data({})
    d.ServicePoints=function(_,state,kind,missing) return B.Data:ServicePoints(state,kind,missing) end
    return B,s,d,rows,function() C_Map=oldMap end
end

test("服务索引遵守当前数据库枚举阵营坐标楼层和商品关系",function()
    local B,s,d,rows,finish=setup();eq(B.Data.serviceCount,6)
    local points=B.Data:ServicePoints(s,"vendor");eq(#points,2);eq(points[1].npcId,1);eq(points[2].npcId,4)
    points=B.Data:ServicePoints(s,"repair");eq(#points,1);eq(points[1].npcId,2)
    s.bags[100]=2;points=B.Data:ServicePoints(s,"supply",{[100]=3,[101]=1})
    eq(#points,2);eq(points[1].targets[100],5);eq(points[2].targets[101],1)
    s.faction="Horde";points=B.Data:ServicePoints(s,"vendor");eq(points[1].npcId,3)
    finish()
end)

test("旅店和训练师目录采用实际枚举并过滤阵营地图楼层而不猜职业资格",function()
    local B,s,d,rows,finish=setup();eq(B.Data.amenityCount,3)
    local points=B.Data:AmenityPoints(s,"bind");eq(#points,1);eq(points[1].npcId,10)
    points=B.Data:AmenityPoints(s,"train");eq(#points,1);eq(points[1].npcId,11);eq(points[1].description,"专业训练师")
    s.faction="Horde";points=B.Data:AmenityPoints(s,"bind");eq(points[1].npcId,12)
    s.faction=nil;points=B.Data:AmenityPoints(s,"bind");eq(#points,0)
    s.position=nil;eq(#B.Data:AmenityPoints(s,"train"),0)
    finish()
end)

test("服务目录扩展任务经过的室外地图并保留阵营去重与实例排除",function()
    local B,s,d,rows,finish=setup()
    B.Data.maps[30]=3
    rows[10].spawns[20]={{10,50}};rows[10].spawns[30]={{10,50}}
    rows[11].spawns[20]={{12,50}};rows[12].spawns[20]={{10,50}}
    rows[13].spawns[20]={{10,50,2}}
    C_Map.GetMapInfo=function(id) return {mapID=id,mapType=id==3 and 4 or 3} end
    local co=coroutine.create(function() B.Data:BuildServices() end)
    repeat local ok,why=coroutine.resume(co);assert(ok,why) until coroutine.status(co)=="dead"
    local maps={[1]=true,[2]=true,[3]=true}
    local points=B.Data:AmenityPoints(s,"bind",maps);eq(#points,2)
    local seen={};for _,p in ipairs(points) do eq(p.npcId,10);assert(not seen[p.position.map]);seen[p.position.map]=true end
    assert(seen[1] and seen[2]);eq(seen[3],nil)
    eq(#B.Data:AmenityPoints(s,"bind"),1)
    eq(#B.Data:AmenityPoints(s,"train",maps),2)
    s.faction="Horde";points=B.Data:AmenityPoints(s,"bind",maps);eq(#points,2);eq(points[1].npcId,12)
    s.faction="Alliance";maps[2]=false;eq(#B.Data:AmenityPoints(s,"bind",maps),1);maps[2]=true
    B.Dungeon={TaskInstance=function(p) if p.sourceAreaId==20 then return {} end end}
    eq(#B.Data:AmenityPoints(s,"bind",maps),1)
    C_Map.GetMapInfo=function() return nil end;eq(#B.Data:AmenityPoints(s,"bind",maps),0)
    finish()
end)

test("真实服务入口无价格耗时也可导航且实际腾空或维修后恢复任务",function()
    local B,s,d,rows,finish=setup()
    local result=plan(s,d,{minutes=60,mode="fast",dungeons=false},B)
    eq(result.best,nil);eq(result.maintenance,true);eq(result.fallback.npcId,1);eq(result.fallback.kind,"service")
    eq(result.fallback.seconds,nil);eq(result.fallback.moneyCost,nil);eq(B.Supplies.Done(result.fallback,s),false)
    s.freeSlots=1;s.inventory={bags={{family=0,free=1}},slots={}}
    eq(B.Supplies.Done(result.fallback,s),true)
    d.GetQuest=function(_,id) if id==42 then return {id=42,title="保留的任务"} end end
    d.Target=function() return {map=1,x=0.4,y=0.5} end
    s.quests[42]={title="保留的任务",objectives={}};s.locked=42
    result=plan(s,d,{minutes=60,mode="fast",dungeons=false},B)
    eq(result.maintenance,nil);eq(result.fallback.questId,42)
    s.durability=0.1;result=plan(s,d,{minutes=60,mode="fast",dungeons=false},B)
    eq(result.maintenance,true);eq(result.fallback.npcId,2);eq(s.locked,42)
    eq(B.Supplies.Done(result.fallback,s),false);s.durability=0.8;eq(B.Supplies.Done(result.fallback,s),true)
    finish()
end)

test("服务点仅按直线距离选择且直接指向服务目的地",function()
    local B,s,d,rows,finish=setup();B.Navigation.hbd={}
    B.Roads={Route=function(_,a,b) return {complete=true,length=b.x==0.15 and 1000 or 200} end,
        Actions=function(_,route,action) return {{kind="move",position={map=1,x=0.1,y=0.5}},action} end}
    local result=plan(s,d,{minutes=60,mode="fast",dungeons=false},B)
    eq(result.fallback.npcId,1);eq(#result.travelActions,1);eq(result.travelActions[1].kind,"service")
    B.Roads.Route=function(_,a,b) if b.x==0.2 then return end;return {complete=true,length=1000} end
    result=plan(s,d,{minutes=60,mode="fast",dungeons=false},B);eq(result.fallback.npcId,1)
    s.dead=true;result=plan(s,d,{minutes=60,mode="fast",dungeons=false},B);eq(result.maintenance,nil)
    finish()
end)
end
