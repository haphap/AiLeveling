-- Fixed QuestieDB release and native offerings, with offline map/character stubs.
local root,package=assert(arg[1]),assert(arg[2])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction="Horde",classFile="PRIEST",locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
local A={Navigation={Distance=function(_,a,b) return a.map==b.map and math.abs(a.x-b.x)*1000 or nil end}}
for _,file in ipairs({"Services.lua","Data/Trainers.lua","Data/Questie.lua"}) do assert(loadfile(root.."/"..file))("AiLeveling",A) end
assert(A.Data:Connect(db))
C_Map={GetMapInfo=function(id) return {mapID=id,mapType=3} end}
local co=coroutine.create(function() A.Data:BuildServices() end)
repeat local ok,why=coroutine.resume(co);assert(ok,why) until coroutine.status(co)=="dead"
local state={clientVersion="1.60.1",clientBuild="70862",interface=16001,revision=1,position={map=1454,x=0.5,y=0.5},
    faction="Horde",skills={[165]=75,[202]=0}}
A.state=state
local count,classes,professions=0,0,0
for id,profile in pairs(A.Trainers.npcs) do
    assert(db.Npc.Exists(id),id)
    local flags=db.Npc.Get(id,"npcFlags") or 0
    assert(math.floor(flags/db.Enum.npcFlags.TRAINER)%2==1,id)
    if profile.classMask then
        state.classMask=profile.classMask;assert(A.Services.TrainerFit(state,id)==0)
        state.classMask=profile.classMask==16 and 128 or 16;assert(A.Services.TrainerFit(state,id)==3)
        classes=classes+1
    elseif profile.skill then
        state.skills[profile.skill]=1;assert(A.Services.TrainerFit(state,id)==0)
        state.skills[profile.skill]=0;assert(A.Services.TrainerFit(state,id)==2)
        state.skills[profile.skill]=nil;assert(A.Services.TrainerFit(state,id)==1)
        professions=professions+1
    end
    count=count+1
end
assert(count==22 and classes==9 and professions==11)
state.classMask=16;state.skills[165]=75
local rows=A.Services:Choices("train");assert(#rows>0)
local last=-1;local seen={}
for _,row in ipairs(rows) do assert(row.trainingRank>=last);last=row.trainingRank;seen[row.npcId]=true end
assert(seen[3324] and seen[3365] and seen[3412])
print(string.format("22 real NPC identities/flags checked; 9 class and 11 profession profiles; %d Orgrimmar trainer points ordered",#rows))
