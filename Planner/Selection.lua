local _, A = ...
A.Selection = {}
local S=A.Selection

function S:Clear()
    A.char.itinerary,A.char.locked,A.char.taskBatch,A.char.regionTarget=nil,nil,nil,nil
    if A.Dungeon then A.Dungeon.taskActivity=nil end
end

function S:Snapshot(state)
    if state.level and state.level~=(A.state or {}).level then
        for questId,level in pairs(A.char.skipped) do
            if type(level)=="number" and level<state.level then A.char.skipped[questId]=nil end
        end
    end
    local id=A.char.locked
    local q=id and A.Data:GetQuest(id)
    if id and (not q or not q.repeatable) and state.completed[id] and not state.quests[id] then self:Clear();state.locked=nil end
    state.regionTarget=not state.inInstance and A.char.regionTarget or nil
    return state.regionTarget and "region:"..state.regionTarget.map or ""
end

function S.CanChoose(candidate,revision)
    if not A.ready then return false,"角色与任务数据尚未就绪" end
    if A.refreshAt then return false,"角色状态正在更新，请稍后选择" end
    if A.Transport and A.Transport:InFlight() then return false,"落地后再选择行程" end
    local plan=A.plan
    if not plan or revision~=plan.revision or plan.revision~=A.state.revision then return false,"行程正在更新，请查看新结果后选择" end
    if not candidate then return false,"当前没有可选择的完整方案" end
    local origin,pos=plan.origin,A.state.position
    if not origin or not pos or origin.map~=pos.map then return false,"位置已改变，等待当前位置的行程结果" end
    local found=plan.best==candidate or plan.suggestedDungeon==candidate
    for _,c in ipairs(plan.taskChoices or {}) do if c==candidate then found=true;break end end
    for _,c in ipairs(plan.dungeonChoices or {}) do if c==candidate then found=true;break end end
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
        return self:LockQuest(candidate.unlock and candidate.unlock.questId or candidate.questId)
    end
    return false,"当前行动由自动规划安排"
end

local function selectLeveling(region)
    S:Clear()
    A.char.regionTarget=region
    A.char.serviceStop=nil
    if A.Services then A.Services.binding=nil end
    A.char.gearTarget,A.char.gearBaseline=nil,nil
    A.char.paused=false;A.Navigation.manual=nil
    if A.ready then A.State:Refresh(true) end
    return true
end

function S:Automatic()
    if A.state.inInstance and A.Dungeon then A.Dungeon.dismissedHandins=A.state.instanceId end
    return selectLeveling(nil)
end

function S:StartRegion(entry)
    if not A.ready or not A.indexReady or A.state.completionKnown==false then return false,"区域任务记录正在载入" end
    if A.state.inInstance then return false,"离开副本后可开始区域规划" end
    local visit=entry.region
    local map=entry.map or visit and visit.map
    if not map then return false,"没有区域资料" end
    local ids={}
    if entry.catalogZone then
        for _,q in ipairs(entry.catalogZone.quests) do ids[#ids+1]=q.id end
    elseif visit then
        for _,c in ipairs(visit.choices) do ids[#ids+1]=c.questId end
        for _,r in ipairs(visit.revisit or {}) do ids[#ids+1]=r.choice.questId end
    end
    if #ids==0 then return false,"本区没有收录任务" end
    return selectLeveling({map=map,title=entry.title,ids=ids})
end

function S:LockQuest(id)
    if type(id)~="number" or id<=0 or id%1~=0 then return false,"当前没有可锁定任务" end
    if (A.state.skipped and A.state.skipped[id]) or (A.state.chainDeferred and A.state.chainDeferred[id]) then
        return false,"请先恢复此任务的推荐或取消整链暂缓"
    end
    self:Clear();A.char.locked=id
    A.char.gearTarget,A.char.gearBaseline=nil,nil
    A.Navigation.manual=nil
    if A.ready then A.State:Refresh(true) end
    return true
end

function S:Skip(id,ignore)
    if type(id)~="number" or id<=0 or id%1~=0 then return end
    local previous=A.char.skipped[id]
    if previous and (not ignore or previous=="ignored") then return end
    A.char.skipped[id]=ignore and "ignored" or A.state.level or true
    local lock=A.char.locked
    if lock==id then self:Clear()
    elseif lock and A.plan and A.plan.preparingQuest and A.plan.preparingQuest.id==lock then
        local frontier,closed=A.Chains.Preparation(lock,A.Data,A.state)
        if closed and #frontier==0 then self:Clear() end
    end
    local manual=A.Navigation and A.Navigation.manual
    if manual and manual.action and manual.action.questId==id then A.Navigation:ClearManual(false) end
    local source=A.Gear and A.Gear.GetSource and A.Gear.GetSource(A.char.gearTarget)
    if source and source.questId==id then A.char.gearTarget,A.char.gearBaseline=nil,nil end
    if A.ready then A.State:Refresh(true) end
end

function S:ResumeQuest(id)
    if not A.char.skipped[id] then return end
    A.char.skipped[id]=nil
    if A.ready then A.State:Refresh(true) end
end
