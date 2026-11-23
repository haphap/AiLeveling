local root=assert(arg[1])
local A,db=dofile(root.."/tools/quest_runtime.lua")
local faction,class=arg[3],arg[4]

local s={clientVersion="1.60.1",clientBuild="70862",interface=16001,level=10,
    faction=faction,quests={},completed={},bags={}}
local function same(a,b)
    if type(a)~="table" or type(b)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local count,located,unmapped=0,0,0
local qualifying,hints={},{}
for _,id in ipairs(A.Data.ids) do
    local q=A.Data:GetQuest(id)
    if A.Data:DeliveryOnly(q,s) then
        count=count+1;qualifying[id]=true
        if next(db.Quest.Get(id,"extraObjectives") or {}) then
            assert(id==5904 or id==5931 or id==5932,"review new delivery hint "..id)
            hints[id]=true
        end
        local pickup=A.Data:Target(q,s)
        local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="accept",position=pickup})
        assert(#stages==2 and stages[1].kind=="accept" and stages[2].kind=="turnin","invented objective "..id)
        local finish=stages[2].position
        s.position=pickup and not pickup.areaOnly and pickup or nil
        s.quests[id]={objectives={}}
        local target=A.Data:Target(q,s)
        if target then
            assert(finish and same(target,finish),"different recipient target "..id)
            located=located+1
        elseif A.Data:UnmappedTargetArea(q,s) then unmapped=unmapped+1 end
        local activeStages=A.TaskGuide.Stages(q,s,A.Data,{kind="objective",position=target})
        local step=activeStages[1]
        assert(step.kind=="objective" and (step.text:find("对话",1,true) or target and target.travelHint==step.text),"lost contact instruction "..id)
        if id==5902 or id==5904 then
            assert(target.entityId==177491 and step.text:find("放置白蚁桶",1,true) and stages[2].text==step.text)
        end
        assert(not s.quests[id].ready and not s.completed[id],"changed native completion "..id)
        s.quests[id].objectives={{text="native requirement",finished=false}}
        assert(not A.Data:DeliveryOnly(q,s),"ignored native requirement "..id)
        s.quests[id],s.position=nil,nil
    end
end
for _,id in ipairs({1489,96627,97281,5931,5932}) do assert(qualifying[id],"missing known delivery "..id) end
assert(hints[5931] and hints[5932],"missing travel hint cases")
for _,id in ipairs({117,91740,96652}) do assert(not qualifying[id],"lost item requirement "..id) end
assert(count>0 and located>0)
print("PASS",faction,class,count,located,unmapped,"delivery previews; actual recipients; native completion retained")
