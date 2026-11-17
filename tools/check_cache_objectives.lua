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
local count,targets=0,0
for _,id in ipairs(A.Data.ids) do
    local q=A.Data:GetQuest(id)
    local raw=db.Quest.Get(id,"objectives") or {}
    local entries=A.Data:ObjectiveEntries(q,s)
    if next(raw) then assert(same(entries,raw),"changed provider objectives "..id)
    elseif next(entries) then
        count=count+1
        local descriptions,positions=A.Data:ReferenceObjectiveTargets(q,s)
        for _,o in ipairs(descriptions) do
            if o.targetId then
                assert(o.numRequired and o.numRequired>0,"count missing "..id)
                targets=targets+1
            else assert(o.type=="event" and (o.areaTriggerId or o.criteriaTreeId or db.Quest.Get(id,"triggerEnd")),"unexplained target "..id) end
        end
        s.quests[id]={objectives=descriptions}
        local identities=A.Data:ObjectiveIdentities(q,s)
        for index,o in ipairs(descriptions) do
            if o.targetId then assert(identities[index] and identities[index].id==o.targetId,"lost cached identity "..id)
            else assert(identities[index]==nil,"event gained a false entity "..id) end
        end
        assert(not s.quests[id].ready and not s.completed[id])
        s.quests[id]=nil
    end
end
for _,id in ipairs({91740,96652}) do
    local q=A.Data:GetQuest(id)
    local expected=id==91740 and 247826 or 275022
    local descriptions=A.Data:ReferenceObjectiveTargets(q,s)
    assert(#descriptions==1 and descriptions[1].targetId==expected and descriptions[1].numRequired==1)
    assert(not descriptions[1].finished)
    s.bags[expected]=1
    local held,positions=A.Data:ReferenceObjectiveTargets(q,s)
    assert(held[1].finished and not next(positions))
    local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="accept",position=A.Data:Target(q,s)})
    assert(#stages==2 and stages[2].kind=="turnin" and stages[2].position)
    s.quests[id]={objectives={{text=held[1].text,type="item",finished=false}}}
    local identities=A.Data:ObjectiveIdentities(q,s)
    assert(identities[1].id==expected and not s.quests[id].objectives[1].finished)
    s.quests[id].ready=true
    local finish=A.Data:Target(q,s);assert(finish and finish.entityId)
    assert(not s.completed[id]);s.quests[id]=nil;s.bags[expected]=nil
end
assert(count>0 and targets>0)
print("PASS",faction,class,count,targets,"cached targets; held items; native completion preserved")
