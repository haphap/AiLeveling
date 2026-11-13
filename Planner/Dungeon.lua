local _, A = ...
A.Dungeon = {}
local D = A.Dungeon
function D.EncounterIdentity(id)
    local catalog=A.DungeonCatalog
    return catalog and catalog.encounters and catalog.encounters[id]
end

local function encounterMatches(record,instanceId,difficulty)
    -- Zero leaves difficulty unspecified; only explicit conflicting values reject an identity.
    return record.instanceId==instanceId and (record.difficultyId==0 or record.difficultyId==difficulty)
end

-- Keep native observations separate from the catalog's (possibly partial) boss list.
function D:EncounterEvent(event,id,name,difficulty,groupSize,success)
    if event=="PLAYER_ENTERING_WORLD" then
        self.encounterVisit,self.encounterPull=nil,nil
        return
    end
    if event~="ENCOUNTER_START" and event~="ENCOUNTER_END" then return end
    local pull=self.encounterPull
    self.encounterPull=nil
    if not GetInstanceInfo then return end
    local _,kind,actualDifficulty,_,_,_,_,instanceId=GetInstanceInfo()
    if kind~="party" or type(instanceId)~="number" or instanceId<=0 or
        actualDifficulty~=difficulty or type(id)~="number" or id<=0 or id>=2147483648 or id%1~=0 or
        type(difficulty)~="number" or difficulty<=0 or difficulty>=math.huge or difficulty%1~=0 then return end
    local known=false
    for _,d in pairs(D.Catalog()) do
        if d.instanceId==instanceId then known=true;break end
    end
    if not known then return end
    local record=D.EncounterIdentity(id)
    if record and not encounterMatches(record,instanceId,difficulty) then return end
    if event=="ENCOUNTER_START" then
        self.encounterPull={id=id,instanceId=instanceId,difficulty=difficulty}
        return
    end
    if not pull or pull.id~=id or pull.instanceId~=instanceId or pull.difficulty~=difficulty or success~=1 then return end
    local visit=self.encounterVisit
    if not visit or visit.instanceId~=instanceId or visit.difficulty~=difficulty then
        visit={instanceId=instanceId,difficulty=difficulty,kills={},count=0};self.encounterVisit=visit
    end
    if not visit.kills[id] and visit.count<64 then
        local title=type(name)=="string" and name~="" and name or record and record.title or ("首领 #"..id)
        visit.kills[id]=title:gsub("|","||")
        visit.count=visit.count+1
    end
    A.dirty=true
    A:RequestRefresh()
end

function D.EncounterProgress(d,state)
    local visit=D.encounterVisit
    if not d or not visit or not state.inInstance or state.instanceId~=visit.instanceId or
        d.instanceId~=visit.instanceId or state.instanceDifficultyId~=visit.difficulty or
        d.difficultyId and d.difficultyId~=visit.difficulty then return end
    local ids,names={},{}
    for id in pairs(visit.kills) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do names[#names+1]=visit.kills[id] end
    if #names>0 then return "本次进入已击败："..table.concat(names,"、") end
end

function D.GroupStatus(d,state)
    local size,needed=state.groupSize or 1,d.groupSize or 5
    local g=state.group
    local text=string.format("队伍 %d/%d 人",size,needed)
    if size==1 and needed>1 then return false,text.." · 尚未组队" end
    if not g then return false,text..(size<needed and (" · 还差 "..(needed-size).." 人") or " · 已满员") end
    if g.raid and needed<=5 then return false,text.." · 当前为团队，请转为小队" end
    text=text..string.format(" · 坦克 %d · 治疗 %d · 输出 %d",g.tank,g.healer,g.damage)
    local hints={}
    if size<needed then hints[#hints+1]="还差 "..(needed-size).." 人" end
    if g.offline>0 then hints[#hints+1]=g.offline.." 人离线" end
    if g.connectionUnknown>0 then hints[#hints+1]=g.connectionUnknown.." 人在线状态待确认" end
    if g.unknown>0 then hints[#hints+1]=g.unknown.." 人职责未确认"
    elseif g.connectionUnknown==0 and g.offline==0 and needed==5 then
        if g.tank==0 then hints[#hints+1]="需要坦克" end
        if g.healer==0 then hints[#hints+1]="需要治疗" end
    end
    local ready=g.online>=needed and g.unknown==0 and (needed~=5 or g.tank>0 and g.healer>0)
    if #hints>0 then text=text.."\n"..table.concat(hints,"；")
    elseif ready then text=text..(state.inInstance and "\n人员与职责齐备。" or "\n人员与职责齐备，可前往副本入口。") end
    return ready,text
end
