-- Run from the pinned QuestieDB source root; load the separate release runtime.
local root, package, faction, class = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4])
local client, metadata = dofile("emulator/client.lua"), dofile("emulator/metadata.lua")
client.install({expansion="Forever", faction=faction, classFile=class, locale="zhCN"})
metadata.load(package .. "/QuestieDB_Forever.toc", "QuestieDB")
local db = metadata.loadAddon(package .. "/QuestieDB_Forever.toc", "QuestieDB", package)
local A = {}
for _, file in ipairs({ "Data/Questie.lua", "Planner/Chains.lua", "Data/Audit.lua"}) do
    assert(loadfile(root .. "/" .. file))("AiLeveling", A)
end
assert(A.Data:Connect(db))
local job = coroutine.create(function() A.Data:BuildIndex() end)
repeat
    local ok, err = coroutine.resume(job)
    assert(ok, err)
until coroutine.status(job) == "dead"
assert(A.Data.count == #A.Data.ids and A.Data.count >= #db.Quest.GetAllIds())
assert(A.Data:GetQuest(7).requiredLevel == 1)
local report = A.Audit.Build(A.Data, true)
report.adapter = {indexed=A.Data.count, maps=0, requirements={}}
report.adapter.chainRelations=#A.Data.chainIndex.edges
report.adapter.chainKinds={}
for _,edge in ipairs(A.Data.chainIndex.edges) do
    assert(A.Data.chainIndex.nodes[edge.from] and A.Data.chainIndex.nodes[edge.to])
    report.adapter.chainKinds[edge.kind]=(report.adapter.chainKinds[edge.kind] or 0)+1
end
for _ in pairs(A.Data.maps) do report.adapter.maps = report.adapter.maps + 1 end
for kind, entries in pairs(A.Data.requirements) do
    local n = 0
    for _ in pairs(entries) do n = n + 1 end
    report.adapter.requirements[kind] = n
end
report.persona = {faction=faction, class=class, locale="zhCN"}
local function json(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
            if c == '"' then return '\\"' end
            if c == '\\' then return '\\\\' end
            return string.format('\\u%04x', c:byte())
        end) .. '"'
    end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if value == nil then return "null" end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    if #keys > 0 and #keys == #value then
        local array = true
        for _, key in ipairs(keys) do if type(key) ~= "number" or key < 1 or key > #keys then array = false end end
        if array then
            for i = 1, #keys do parts[i] = json(value[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
    end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = json(tostring(key)) .. ":" .. json(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
io.write(json(report), "\n")
