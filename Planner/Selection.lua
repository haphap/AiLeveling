local _, A = ...
A.Selection = {}
local S=A.Selection

function S:Clear()
    A.char.itinerary,A.char.locked,A.char.taskBatch=nil,nil,nil
end

function S:Snapshot(state)
    local id=A.char.locked
    local q=id and A.Data:GetQuest(id)
    if q and not q.repeatable and state.completed[id] and not state.quests[id] then self:Clear();state.locked=nil end
    return ""
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
    return false,"当前行动由自动规划安排"
end

function S:Lock(candidate,revision)
    local ok,reason=S.CanChoose(candidate,revision)
    if not ok then return false,reason end
    if candidate.requiresAcceptance then return false,"副本须通过接受副本行程入口确认" end
    if candidate.kind=="task" then
        A.char.paused=false
        return self:LockQuest(candidate.questId)
    end
    return false,"当前行动由自动规划安排"
end

function S:Automatic()
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先在副本页结束当前行程" end
    self:Clear()
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
