local root=assert(arg[1])
local A=dofile(root.."/tools/quest_runtime.lua")
local faction,class=arg[3],arg[4]

local s={clientVersion="1.60.1",clientBuild="70862",interface=16001,level=10,
    faction=faction,quests={},completed={},bags={}}
local function same(a,b)
    if type(a)~="table" or type(b)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local count,located,approximate=0,0,0
for _,id in ipairs(A.Data.ids) do
    local q=A.Data:GetQuest(id)
    local facts=A.Data:CacheQuest(q,s)
    for _,fact in ipairs(facts and facts.objectives or {}) do
        if fact.kind=="areaTrigger" or fact.kind=="areaTriggerEnter" or fact.kind=="criteriaTree" then
            count=count+1
            local field=fact.kind=="criteriaTree" and "criteriaTreeId" or "areaTriggerId"
            local descriptions,positions,complex=A.Data:ReferenceObjectiveTargets(q,s)
            local matches,index=0,nil
            for i,o in ipairs(descriptions) do
                if o[field]==fact.id then
                    matches=matches+1;index=i
                    assert(o.type=="event" and not o.targetId and not o.targetKind and not o.finished)
                    assert(o.numRequired==(fact.count>0 and fact.count or nil))
                end
            end
            assert(matches==1,"missing or duplicated exploration "..id)
            assert(not A.Data:DeliveryOnly(q,s),"exploration treated as delivery "..id)
            local point=positions[index]
            if point then located=located+1;if point.approximate then approximate=approximate+1 end end
            local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="accept",position=A.Data:Target(q,s)})
            local found=0
            for _,stage in ipairs(stages) do if stage[field]==fact.id then found=found+1 end end
            assert(found==1,"missing exploration step "..id)
            s.quests[id]={objectives=descriptions}
            local identities=A.Data:ObjectiveIdentities(q,s)
            assert(not identities[index],"exploration received an entity identity "..id)
            A.Data:ObjectiveTargets(q,s)
            assert(not descriptions[index].finished and not s.quests[id].ready and not s.completed[id])
            s.quests[id]=nil
        end
    end
end
assert(count>0)
local inventory=dofile(root.."/tools/continuous_inventory.lua")
for _,case in ipairs({{870,216},{62,44590},{944,223}}) do
    local id,trigger=case[1],case[2]
    local q=A.Data:GetQuest(id)
    local active=assert(inventory.Accept(q,s,A.Data))
    assert(#active.objectives==1 and active.objectives[1].areaTriggerId==trigger and not active.ready)
    assert(not pcall(inventory.TurnIn,id,s))
    inventory.Objective(id,1,s)
    assert(active.ready);inventory.TurnIn(id,s);assert(s.completed[id])
end
local q=assert(A.Data:GetQuest(95885))
local active=assert(inventory.Accept(q,s,A.Data))
assert(#active.objectives==3 and A.TaskGuide.XP(q,21,s)==1850)
local criteria={}
for index,o in ipairs(active.objectives) do
    if o.criteriaTreeId then criteria[o.criteriaTreeId]=true end
    assert(not active.ready and not pcall(inventory.TurnIn,95885,s))
    inventory.Objective(95885,index,s)
end
assert(criteria[224929] and criteria[224931] and active.ready)
inventory.TurnIn(95885,s);assert(s.completed[95885])
print("PASS",faction,class,count,located,approximate,"event objectives; explicit simulated completion")
