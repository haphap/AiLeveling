local _, A = ...
A.Selection = {}
local S=A.Selection

function S.Parse(sequence)
    if type(sequence)~="string" or #sequence>512 or sequence=="" or sequence:find("[^%d:>]") then return end
    local groups,seen,count={},{},0
    for token in (sequence..">"):gmatch("(.-)>") do
        local group={}
        for value in (token..":"):gmatch("(.-):") do
            local id=tonumber(value)
            if not id or id<=0 or id>=2147483648 or id%1~=0 or seen[id] then return end
            seen[id]=true;count=count+1;group[#group+1]=id
        end
        if #group==0 or #group>3 then return end
        groups[#groups+1]=group
    end
    if #groups==0 or #groups>3 or count>9 then return end
    return groups
end

local function sequence(groups)
    local parts={}
    for _,group in ipairs(groups) do parts[#parts+1]=table.concat(group,":") end
    return table.concat(parts,">")
end

function S.Valid(selection)
    if type(selection)~="table" or not S.Parse(selection.sequence) or type(selection.baselines)~="table" then return false end
    if selection.preferredKey~=nil and (type(selection.preferredKey)~="string" or #selection.preferredKey>65536) then return false end
    if selection.version~=nil and type(selection.version)~="string" and type(selection.version)~="number" then return false end
    local groups=S.Parse(selection.sequence)
    for _,group in ipairs(groups) do for _,id in ipairs(group) do
        local n=selection.baselines[id]
        if type(n)~="number" or n<0 or n>=math.huge or n%1~=0 then return false end
    end end
    return true
end

function S:Clear()
    A.char.itinerary,A.char.locked,A.char.taskBatch=nil,nil,nil
end

function S:Snapshot(state)
    state.itinerary=nil
    local selected=A.char.itinerary
    if not selected then
        local id=A.char.locked
        local q=id and A.Data:GetQuest(id)
        if q and not q.repeatable and state.completed[id] and not state.quests[id] then self:Clear();state.locked=nil end
        return ""
    end
    if not S.Valid(selected) or (A.char.dungeon and A.char.dungeon.phase~="complete") then
        self:Clear();state.locked=nil;return ""
    end
    local remaining,baselines={},{}
    for _,group in ipairs(S.Parse(selected.sequence)) do
        local pending={}
        for _,id in ipairs(group) do
            local q=A.Data:GetQuest(id)
            local done=(A.char.turnIns[id] or 0)>selected.baselines[id] or
                (not state.quests[id] and state.completed[id] and q and not q.repeatable)
            if not done then pending[#pending+1]=id;baselines[id]=selected.baselines[id] end
        end
        if #pending>0 then remaining[#remaining+1]=pending end
    end
    if #remaining==0 then self:Clear();state.locked=nil;return "" end
    local current=sequence(remaining)
    if current~=selected.sequence or selected.version~=A.Content.version then selected.preferredKey=nil end
    selected.sequence,selected.baselines,selected.version=current,baselines,A.Content.version
    A.char.locked=remaining[1][1]
    state.locked=A.char.locked
    state.itinerary={sequence=current,preferredKey=selected.preferredKey,version=selected.version}
    return current.."|"..(selected.preferredKey or "").."|"..tostring(selected.version)
end

function S.CanChoose(candidate,revision)
    if not A.ready then return false,"角色与任务数据尚未就绪" end
    if A.refreshAt then return false,"角色状态正在更新，请稍后选择" end
    if A.Transport and A.Transport:InFlight() then return false,"落地后再选择行程" end
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先在副本页结束当前行程" end
    local plan=A.plan
    if not plan or revision~=plan.revision or plan.revision~=A.state.revision then return false,"行程正在更新，请查看新结果后选择" end
    if not candidate then return false,"当前没有可选择的完整方案" end
    local origin,pos=plan.origin,A.state.position
    if not origin or not pos or origin.map~=pos.map or origin.node~=pos.node then return false,"位置已改变，等待当前位置的行程结果" end
    local found=plan.best==candidate
    for _,c in ipairs(plan.alternatives or {}) do if c==candidate then found=true;break end end
    for _,c in ipairs(plan.taskChoices or {}) do if c==candidate then found=true;break end end
    if not candidate or not found then return false,"该备选已失效，请重新选择" end
    if candidate.kind=="task" then return true end
    if candidate.requiresAcceptance and candidate.kind=="dungeon" then return true end
    if not S.Parse(candidate.sequence) then return false,"该行动由当前状态自动安排，无可锁定的任务顺序" end
    return true
end

function S:Lock(candidate,revision)
    local ok,reason=S.CanChoose(candidate,revision)
    if not ok then return false,reason end
    if candidate.requiresAcceptance then return false,"副本须通过接受副本行程入口确认" end
    if candidate.kind=="task" then
        A.char.paused=false
        return self:LockQuest(candidate.questId)
    end
    self:Clear()
    local groups=S.Parse(candidate.sequence)
    local baselines={}
    for _,group in ipairs(groups) do for _,id in ipairs(group) do baselines[id]=A.char.turnIns[id] or 0 end end
    A.char.itinerary={sequence=sequence(groups),preferredKey=candidate.routeKey,version=A.Content.version,baselines=baselines}
    A.char.locked,A.char.paused=groups[1][1],false
    A.char.gearTarget,A.char.gearBaseline=nil,nil
    A.Navigation.manual=nil
    A.State:Refresh(true)
    return true
end

function S:Automatic()
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先在副本页结束当前行程" end
    self:Clear()
    A.char.activeGuide=nil
    A.char.serviceStop=nil
    if A.Services then A.Services.binding=nil end
    A.char.gearTarget,A.char.gearBaseline=nil,nil
    A.char.paused=false;A.Navigation.manual=nil
    if A.ready then A.State:Refresh(true) end
    return true
end

function S:LockQuest(id)
    if type(id)~="number" or id<=0 or id%1~=0 then return false,"当前没有可锁定任务" end
    if (A.state.skipped and A.state.skipped[id]) or (A.state.chainDeferred and A.state.chainDeferred[id]) then
        return false,"此任务已暂缓，请先恢复相应任务或整链偏好"
    end
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先结束当前副本行程" end
    self:Clear();A.char.locked=id
    A.char.gearTarget,A.char.gearBaseline=nil,nil
    A.Navigation.manual=nil
    if A.ready then A.State:Refresh(true) end
    return true
end

function S:Skip(id)
    if not id then return end
    if A.char.taskBatch then A.char.taskBatch.baselines[id]=nil else self:Clear() end
    A.char.skipped[id]=true
    local source=A.Gear and A.Gear.GetSource and A.Gear.GetSource(A.char.gearTarget) or (A.Content.gearSources or {})[A.char.gearTarget]
    if source and source.questId==id then A.char.gearTarget,A.char.gearBaseline=nil,nil end
    if A.ready then A.State:Refresh(true) end
end

function S.Evaluate(selection,state,data,options)
    local groups=S.Parse(selection.sequence)
    if not groups then return nil,"所选任务顺序格式无效" end
    local paths={false}
    for step,ids in ipairs(groups) do
        local expanded,why={},nil
        for _,path in ipairs(paths) do
            if path and path.forecast and (path.forecast.uncertain or path.forecast.level>=60) then
                why="后续等级门槛未知或已达到升级目标"
            else
                local virtual=path and A.Planner.Project(state,path) or state
                local remaining={}
                for k,v in pairs(options) do remaining[k]=v end
                remaining.minutes=options.minutes-(path and path.seconds or 0)/60
                local quests={}
                for _,id in ipairs(ids) do
                    local q=data:GetQuest(id)
                    if not q then return nil,"第 "..step.." 组任务 #"..id.." 资料缺失" end
                    quests[#quests+1]=q
                end
                local best,reason,variants=A.Planner.EvaluateMany(quests,virtual,data,remaining,path and path.lastNode or (state.position and state.position.node))
                why=reason or why
                if best then
                    for _,candidate in ipairs(variants) do expanded[#expanded+1]=path and A.Planner.Join(path,candidate) or candidate end
                end
            end
        end
        if #expanded==0 then return nil,"第 "..step.." 组："..(why or "当前条件不足") end
        table.sort(expanded,function(a,b) return a.seconds<b.seconds end)
        paths=A.Planner.Select(expanded,1)
        local thread,main=coroutine.running()
        if thread and not main then coroutine.yield() end
    end
    return paths
end
