-- Run against the pinned release using its own offline client emulator.
local root,package=assert(arg[1]),assert(arg[2])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction="Alliance",classFile="WARRIOR",locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
assert(db.RequireContract(4))
local zones=assert(db.Support.Get("ZoneDB"))
local lines={}
for instance,area in pairs(zones.instanceIdToAreaId) do
    lines[#lines+1]=string.format("M\t%d\t%d",instance,area)
end
for area,d in pairs(zones.private.dungeons) do
    lines[#lines+1]=string.format("A\t%d\t%d",area,area)
    for _,alias in ipairs(d[2] or {}) do lines[#lines+1]=string.format("A\t%d\t%d",area,alias) end
end
table.sort(lines)
io.write(table.concat(lines,"\n"),"\n")
