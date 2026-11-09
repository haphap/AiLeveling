-- Effective provider evidence only; region markers do not invent exact coordinates.
local root,package,faction,class=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction=faction,classFile=class,locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
assert(db.RequireContract(4))
local lines,seen={},{}
local function row(qid,phase,targetKind,targetId,source,entityId,area,precise)
    local text=table.concat({qid,phase,targetKind,targetId,source,entityId,area,precise and 1 or 0},"\t")
    if not seen[text] then seen[text]=true;lines[#lines+1]=text end
end
local function entity(qid,phase,tk,tid,kind,id,source)
    local found=false
    for area,points in pairs(db[kind].Get(id,"spawns") or {}) do
        if type(area)=="number" and area>0 and #points>0 then
            local precise=false
            for _,p in ipairs(points) do
                if type(p[1])=="number" and type(p[2])=="number" and p[1]>=0 and p[1]<=100 and p[2]>=0 and p[2]<=100 and
                    (not p[3] or p[3]==0) then precise=true end
            end
            row(qid,phase,tk,tid,source or kind,id,area,precise);found=true
        end
    end
    if not found then row(qid,phase,tk,tid,source or kind,id,0,false) end
end
local function item(qid,phase,id)
    local found=false
    for _,pair in ipairs({{"Npc","npcDrops"},{"Object","objectDrops"},{"Npc","vendors"}}) do
        for _,sourceId in ipairs(db.Item.Get(id,pair[2]) or {}) do
            entity(qid,phase,"Item",id,pair[1],sourceId,pair[2]);found=true
        end
    end
    if not found then row(qid,phase,"Item",id,"unknown",0,0,false) end
end
for _,qid in ipairs(db.Quest.GetAllIds()) do
    for _,pair in ipairs({{"accept","startedBy"},{"turnin","finishedBy"}}) do
        local group=db.Quest.Get(qid,pair[2]) or {}
        for kind=1,2 do
            for _,id in ipairs(group[kind] or {}) do
                local entityKind=kind==1 and "Npc" or "Object"
                entity(qid,pair[1],entityKind,id,entityKind,id)
            end
        end
        for _,id in ipairs(group[3] or {}) do item(qid,pair[1],id) end
    end
    local objectives=db.Quest.Get(qid,"objectives") or {}
    for kind=1,3 do
        for _,objective in ipairs(objectives[kind] or {}) do
            local id=objective[1]
            if kind==3 then item(qid,"objective",id)
            else local ek=kind==1 and "Npc" or "Object";entity(qid,"objective",ek,id,ek,id) end
        end
    end
end
table.sort(lines);io.write(table.concat(lines,"\n"),"\n")
