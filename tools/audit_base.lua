-- Offline inventory of the pinned upstream base file. Effective corrections are
-- audited separately through /ail audit in the actual QuestieDB runtime.
local path = assert(arg[1], "usage: lua5.1 tools/audit_base.lua /path/foreverQuestDB.lua")
local db = {}
local chunk = assert(loadfile(path))
setfenv(chunk, {QuestieLoader={ImportModule=function(_,name) assert(name=="QuestieDB");return db end}})
chunk()
local rows = assert(loadstring(db.questData))
setfenv(rows,{})
rows = rows()
local report = {source="Questie/QuestieDB",version="v1.0.12",scope="raw Forever base; corrections excluded",
    source_blob="f4ea75ca02efc2333fd02dd955f42b68f4ffb14a",total=0,byRequiredLevel={},
    missingPrerequisiteIds={},negativePrerequisiteEntries=0,noStarter=0,noFinisher=0,
    andPrerequisiteQuests=0,orPrerequisiteQuests=0,mutuallyExclusiveQuests=0,sourceItemQuests=0,
    classRestrictedQuests=0,highRaceMaskQuests=0,zoneCount=0}
local missing,zones={},{}
for _,q in pairs(rows) do
    report.total=report.total+1
    local level=tostring(q[4] or 0)
    report.byRequiredLevel[level]=(report.byRequiredLevel[level] or 0)+1
    local function hasGroup(g)
        return g and ((g[1] and #g[1]>0) or (g[2] and #g[2]>0) or (g[3] and #g[3]>0))
    end
    if not hasGroup(q[2]) then report.noStarter=report.noStarter+1 end
    if not hasGroup(q[3]) then report.noFinisher=report.noFinisher+1 end
    if q[12] and #q[12]>0 then report.andPrerequisiteQuests=report.andPrerequisiteQuests+1 end
    if q[13] and #q[13]>0 then report.orPrerequisiteQuests=report.orPrerequisiteQuests+1 end
    if q[16] and #q[16]>0 then report.mutuallyExclusiveQuests=report.mutuallyExclusiveQuests+1 end
    if q[11] and q[11]>0 then report.sourceItemQuests=report.sourceItemQuests+1 end
    if q[7] and q[7]>0 then report.classRestrictedQuests=report.classRestrictedQuests+1 end
    if q[6] and q[6]>=4294967296 then report.highRaceMaskQuests=report.highRaceMaskQuests+1 end
    if q[17] then zones[q[17]]=true end
    for _,i in ipairs({12,13}) do
        for _,id in ipairs(q[i] or {}) do
            if id<0 then report.negativePrerequisiteEntries=report.negativePrerequisiteEntries+1 end
            if not rows[math.abs(id)] then missing[math.abs(id)]=true end
        end
    end
end
for _ in pairs(zones) do report.zoneCount=report.zoneCount+1 end
for id in pairs(missing) do report.missingPrerequisiteIds[#report.missingPrerequisiteIds+1]=id end
table.sort(report.missingPrerequisiteIds)
local function json(v)
    if type(v)=="string" then return string.format('%q',v) end
    if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
    local keys,parts={},{}
    for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do parts[#parts+1]=string.format('%q',tostring(k))..":"..json(v[k]) end
    return "{"..table.concat(parts,",").."}"
end
io.write(json(report),"\n")
