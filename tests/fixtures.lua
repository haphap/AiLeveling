-- Deliberately synthetic. Never included in the addon package or coverage counts.
local F = {}
F.Navigation={Distance=function(_,a,b)
    if a and b and a.map and a.map==b.map and a.x and b.x and a.y and b.y then
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*700
    end
end}
function F.Node(x,map) return {position={map=map or 1,x=x,y=0}} end
function F.State()
    return { revision = 1, level = 20, class = "WARRIOR", raceMask = 1, classMask = 1,
        completed = {}, quests = {}, bags = {}, skipped = {}, samples = {}, equipment = {},
        instanceLocksKnown=true,instanceLockouts={},pendingResets={},locale="zhCN",instanceDifficultyId=1,
        questLimit=20,freeSlots=16,durability=1,itemMetadata={},
        runSpeed=7,groupSize = 1, role = "DAMAGER", position = {node = "start",map=1,x=0,y=0}, skills = {}, reputations = {},xp=0,maxXP=100000 }
end
function F.Party(s)
    s.groupSize=5
    s.group={raid=false,online=5,offline=0,connectionUnknown=0,tank=1,healer=1,damage=3,unknown=0}
end
function F.Quest(id)
    return {id = id, title = "测试任务 " .. id, verified = true, requiredLevel = 1,
        requiredSpell = 0, requiredSpecialization = 0, requiredRaces = 0, requiredClasses = 0,
        xp = 1000, seconds = 100, actions = {
            {kind="accept",node="start",seconds=5},
            {kind="objective",node="goal",objectiveIndex=1},
            {kind="turnin",node="start",seconds=5},
        }}
end
function F.Data(quests)
    return {content={nodes={start=F.Node(0),near=F.Node(0.1),goal=F.Node(0.2)},edges={
        start={{to="near",seconds=10,verified=true},{to="goal",seconds=90,verified=true}},
        near={{to="goal",seconds=10,verified=true}},
        goal={{to="start",seconds=20,verified=true}},
    },dungeons={}},
    GetQuest=function(_,id) return quests[id] end,
    Candidates=function() local ids={} for id in pairs(quests) do ids[#ids+1]=id end table.sort(ids) return ids end,
    Target=function() return nil end}
end
return F
