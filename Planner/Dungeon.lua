local _, A = ...
A.Dungeon = {}
local D = A.Dungeon
D.phases = {preparing="准备与等队",travel="前往入口",inside="副本中",outside="暂时离开",
    recovering="死亡恢复",disbanded="队伍已解散",finished="本轮结束／返程",complete="行程已结束"}
local function copy(value)
    local result = {}
    for key, v in pairs(value) do result[key] = v end
    return result
end
local questDone

function D.ValidSession(s)
    local valid = type(s)=="table" and (type(s.id)=="number" or type(s.id)=="string") and D.phases[s.phase] and
        type(s.round)=="number" and s.round>=1 and s.round%1==0 and
        type(s.budget)=="number" and s.budget>0 and s.budget<math.huge and
        type(s.elapsed)=="number" and s.elapsed>=0 and s.elapsed<math.huge and type(s.done)=="table" and
        (s.waited==nil or (type(s.waited)=="number" and s.waited>=0 and s.waited<math.huge)) and
        (s.entered==nil or type(s.entered)=="boolean") and (s.settled==nil or type(s.settled)=="boolean")
    if not valid then return false end
    for index,done in pairs(s.done) do
        if type(index)~="number" or index<1 or index%1~=0 or type(done)~="boolean" then return false end
    end
    return true
end

function D.EncounterIdentity(id,state)
    local catalog=A.DungeonCatalog
    if not catalog or state and (state.clientVersion~=catalog.version or tostring(state.clientBuild)~=catalog.build) then return end
    return catalog.encounters and catalog.encounters[id]
end

local function encounterMatches(record,instanceId,difficulty)
    -- Zero leaves difficulty unspecified; only explicit conflicting values reject an identity.
    return record.instanceId==instanceId and (record.difficultyId==0 or record.difficultyId==difficulty)
end

function D.Workflow(d, content, state)
    if type(d.instanceId)~="number" or d.instanceId<=0 or d.instanceId==math.huge or d.instanceId%1~=0 then return false,"实例 ID 无效" end
    if type(d.difficultyId)~="number" or d.difficultyId<=0 or d.difficultyId>=math.huge or d.difficultyId%1~=0 then return false,"副本行程未指定有效难度" end
    if type(d.minLevel)~="number" or type(d.maxLevel)~="number" or d.minLevel<1 or d.maxLevel>60 or d.minLevel>d.maxLevel then return false,"副本等级范围无效" end
    if type(d.runSeconds)~="number" or d.runSeconds<=0 or d.runSeconds==math.huge or
        type(d.xp)~="number" or d.xp<0 or d.xp>=math.huge then return false,"副本耗时或经验无效" end
    if not d.instanceId or not d.entryNode or not d.exitNode or not d.returnNode then return false, "实例与往返节点待补齐" end
    for _, id in ipairs({d.entryNode,d.exitNode,d.returnNode}) do
        if not content.nodes[id] then return false, "副本目的地缺失" end
    end
    if not d.actions then return false, "副本任务行动待补齐" end
    for _,field in ipairs({"completionQuests","completionEncounters"}) do
        local ids=d[field]
        if ids~=nil then
            if type(ids)~="table" or #ids==0 or #ids>64 then return false,"副本完成条件无效："..field end
            local seen,count={},0
            for index,id in pairs(ids) do
                if type(index)~="number" or index%1~=0 or index<1 or index>#ids or
                    type(id)~="number" or id<=0 or id>=2147483648 or id%1~=0 or seen[id] then
                    return false,"副本完成条件无效："..field
                end
                seen[id]=true
                count=count+1
                if field=="completionEncounters" then
                    local record=D.EncounterIdentity(id,state)
                    if record and not encounterMatches(record,d.instanceId,d.difficultyId) then
                        return false,"完成首领与副本或难度不符："..record.title
                    end
                end
            end
            if count~=#ids then return false,"副本完成条件无效："..field end
        end
    end
    local order,previous = {before=1,inside=2,after=3},0
    for _, action in ipairs(d.actions) do
        if action.stage ~= "before" and action.stage ~= "inside" and action.stage ~= "after" then return false, "副本行动阶段缺失" end
        if order[action.stage]<previous then return false,"副本行动阶段顺序无效" end
        previous=order[action.stage]
        if not action.node or not content.nodes[action.node] then return false, "副本行动节点缺失" end
        if action.kind ~= "accept" and action.kind ~= "objective" and action.kind ~= "turnin" and action.kind ~= "move" and action.kind~="service" then return false, "副本行动类型无效" end
        if action.kind ~= "move" and action.kind~="service" and not action.questId then return false,"任务行动 ID 缺失" end
        if action.stage ~= "inside" and action.kind ~= "move" and (type(action.seconds)~="number" or action.seconds<0) then return false,"副本准备或交付耗时缺失" end
    end
    return true
end

function D.InstanceMatches(d,state)
    if not state.inInstance or state.instanceId~=d.instanceId then
        return false,"当前实例尚未确认或与目标不同，保留本轮选择"
    end
    if not state.instanceDifficultyId or state.instanceDifficultyId<=0 then
        return false,"当前副本难度尚未确认，稍后继续本轮"
    end
    if not d.difficultyId or state.instanceDifficultyId~=d.difficultyId then
        return false,"当前副本难度与所选行程不一致，离开后确认难度"
    end
    return true
end

-- Keep native observations separate from the catalog's (possibly partial) boss list.
function D:EncounterEvent(event,id,name,difficulty,groupSize,success)
    if event=="PLAYER_ENTERING_WORLD" then
        self.encounterVisit,self.encounterPull=nil,nil
        if self.runSample then self.runSample.valid=false end
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
    for _,d in pairs(D.Catalog(A.state,A.Content)) do
        if d.instanceId==instanceId then known=true;break end
    end
    if not known then return end
    local record=D.EncounterIdentity(id,A.state)
    if record and not encounterMatches(record,instanceId,difficulty) then return end
    if event=="ENCOUNTER_START" then
        self.encounterPull={id=id,instanceId=instanceId,difficulty=difficulty,sample=self.runSample}
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
    local sample,session=self.runSample,A.char.dungeon
    local d=session and A.Content.dungeons[session.id]
    if sample and sample==pull.sample and sample.valid and session and not session.settled and
        d and d.instanceId==instanceId and d.difficultyId==difficulty then
        sample.encounters=sample.encounters or {}
        sample.encounters[id]=true
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

function D.Preparation(d)
    local required={}
    for _,map in ipairs({d.items or {},d.consumeItems or {},d.requiredItems or {}}) do
        for id,count in pairs(map) do required[id]=math.max(required[id] or 0,count) end
    end
    return {kind="dungeonPrepare",stage="before",dungeonId=d.id,seconds=0,requiredItems=required,
        minFreeSlots=d.minFreeSlots,minDurability=d.minDurability or 0.2}
end

function D.WaitActivities(d,state,options,data,wait)
    local activities={}
    for _,action in ipairs(d.actions or {}) do
        if action.stage=="before" and action.kind~="move" and not questDone(action,state) then return activities end
    end
    if A.Supplies and not A.Supplies.Apply(D.Preparation(d),A.Supplies.Cursor(state),state.itemMetadata or {}) then return activities end
    for _,id in ipairs(d.interruptibleQuestIds or {}) do
        local q=data:GetQuest(id)
        if q and q.interruptible then
            local candidate,_,variants=A.Planner.Evaluate(q,state,data,
                {minutes=math.min(options.minutes,wait/60),mode=options.mode},state.position and (state.position.node or state.position))
            if candidate then for _,variant in ipairs(variants) do activities[#activities+1]=variant end end
        end
    end
    table.sort(activities,function(a,b) if a.rate~=b.rate then return a.rate>b.rate end return tostring(a.id)<tostring(b.id) end)
    return activities
end

function D.WaitActivity(d,state,options,data,wait)
    return D.WaitActivities(d,state,options,data,wait)[1]
end

function D.GroupStatus(d,state)
    local size,needed=state.groupSize or 1,d.groupSize or 5
    local g=state.group
    local text=string.format("队伍 %d/%d",size,needed)
    if not g then return false,text.." · 请确认队伍职责与就绪情况" end
    if g.raid and needed<=5 then return false,text.." · 当前为团队，请先确认小队安排" end
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
    if #hints>0 then text=text.."\n"..table.concat(hints,"；") end
    return ready,text
end

function D.Evaluate(d,state,options,data)
    if not options.dungeons then return nil,"已关闭副本建议" end
    if not d.verified then return nil,"副本行程待验证" end
    if data then
        local valid,reason=D.Workflow(d,data.content,state)
        if not valid then return nil,reason end
    end
    if A.Instances then
        local allowed,reason=A.Instances.Check(d,state)
        if not allowed then return nil,reason end
    end
    if state.level<d.minLevel or state.level>d.maxLevel then return nil,"等级不适配" end
    if not data then
        for _,id in ipairs(d.preQuests or {}) do if not state.completed[id] then return nil,"前置未交付" end end
    end
    if not A.Supplies then
        for id,count in pairs(d.items or {}) do if (state.bags[id] or 0)<count then return nil,"缺少进入物品 #"..id end end
    end
    if d.roles and not d.roles[options.role] then return nil,"职责不适配" end
    if not d.runSeconds or not d.xp then return nil,"收益或耗时待补齐" end
    local assembled=D.GroupStatus(d,state)
    local wait=assembled and 0 or (options.waitMinutes and options.waitMinutes*60 or d.waitSeconds)
    if wait==nil then return nil,"组队等待时间未知" end
    if state.dungeon and state.dungeon.id==d.id and not state.dungeon.settled then
        wait=state.dungeon.phase=="preparing" and math.max(0,wait-(state.dungeon.waited or 0)) or 0
    end
    local run=A.State.Estimate(d.runSeconds,state.samples and state.samples["dungeon:"..d.id])
    local choices={false}
    if data and wait>0 and not options.ignoreWaitActivities then
        for _,activity in ipairs(D.WaitActivities(d,state,options,data,wait)) do choices[#choices+1]=activity end
    end
    local function evaluate(activity)
        local travel=d.travelSeconds
        local resources,previewActions,plannedTurnins=nil,nil,{}
        if data then
            local context,forecast=copy(state),copy(state)
            forecast.completed,forecast.quests=copy(state.completed),copy(state.quests)
            context.now=(state.now or 0)+(activity and wait or 0)
            local from=state.position and (state.position.node or state.position)
            if activity then
                from=activity.lastNode
                context.money,context.hearthReady,context.unlocked=activity.resources.money,activity.resources.hearthReady,activity.resources.unlocked
                for _,action in ipairs(activity.actions) do
                    if action.kind=="turnin" then forecast.completed[action.questId],forecast.quests[action.questId]=true,nil end
                end
                if activity.forecast then forecast.level=activity.forecast.level end
                if A.Supplies and activity.resources.supplies then A.Supplies.Project(context,activity.resources.supplies) end
            end
            context.quests,context.completed=forecast.quests,forecast.completed
            local eligibility=copy(forecast)
            eligibility.completed,eligibility.quests=copy(forecast.completed),copy(forecast.quests)
            local entryChecked=false
            local function entryAllowed()
                entryChecked=true
                for _,id in ipairs(d.preQuests or {}) do
                    if not eligibility.completed[id] then return false,"进入前尚需交付前置 #"..id end
                end
                return true
            end
            for _,action in ipairs(d.actions) do
                if action.stage~="before" and not entryChecked then
                    local ok,why=entryAllowed()
                    if not ok then return nil,why end
                end
                if action.questId then
                    local q=data:GetQuest(action.questId)
                    if not q then return nil,"副本关联任务资料缺失 #"..action.questId end
                    if not eligibility.completed[q.id] or eligibility.quests[q.id] then
                        if action.kind=="accept" then
                            local ok,why=A.Eligibility.Check(q,eligibility,data)
                            if not ok then return nil,why end
                            eligibility.quests[q.id]=eligibility.quests[q.id] or {objectives={}}
                        elseif not eligibility.quests[q.id] then
                            if action.stage~="after" or action.kind~="turnin" then return nil,"副本任务尚未接取 #"..q.id end
                        elseif action.kind=="turnin" then
                            plannedTurnins[q.id]=true
                            eligibility.completed[q.id],eligibility.quests[q.id]=true,nil
                        end
                    end
                end
            end
            if not entryChecked then
                local ok,why=entryAllowed()
                if not ok then return nil,why end
            end
            local itinerary={}
            local ongoing=state.dungeon and state.dungeon.id==d.id and not state.dungeon.settled and state.dungeon
            local function stage(name)
                for index,action in ipairs(d.actions) do
                    if action.stage==name and not (ongoing and ongoing.done[index]) and not questDone(action,forecast) and
                        (name~="after" or action.kind~="turnin" or plannedTurnins[action.questId]) then
                        local step=copy(action)
                        local q=step.questId and data:GetQuest(step.questId)
                        step.dungeonId,step.dungeonStep=d.id,index
                        step.title=step.title or (q and q.title) or d.title
                        if step.kind=="turnin" then step.unlockAfter="quest:"..step.questId end
                        itinerary[#itinerary+1]=step
                    end
                end
            end
            stage("before")
            itinerary[#itinerary+1]=D.Preparation(d)
            if not activity then itinerary[#itinerary+1]={kind="dungeonWaitEstimate",seconds=wait,stage="wait"} end
            itinerary[#itinerary+1]={kind="dungeonEnter",node=d.entryNode,seconds=0,stage="entry",dungeonId=d.id,title=d.title,
                text="到入口后由玩家进入副本"}
            for _,action in ipairs(d.actions) do
                if action.stage=="inside" and not questDone(action,forecast) then
                    local effect=copy(action)
                    effect.node,effect.arriveNode,effect.seconds=nil,action.node,0
                    if effect.kind=="turnin" then effect.unlockAfter="quest:"..effect.questId end
                    itinerary[#itinerary+1]=effect
                end
            end
            itinerary[#itinerary+1]={kind="dungeonRun",seconds=run,arriveNode=d.exitNode,consumeItems=d.consumeItems,
                reserveSlots=d.lootSlots,durabilityLoss=d.durabilityLoss}
            stage("after")
            itinerary[#itinerary+1]={kind="move",node=d.returnNode,seconds=0}
            context.maxSeconds=options.minutes*60-(activity and wait or 0)-(d.failureProbability or 0)*(d.recoverySeconds or 0)
            local paths,reason
            if A.Supplies then paths,reason=A.Supplies.Itinerary(data.content,from,itinerary,context)
            else paths,reason=A.Travel.Itinerary(data.content,from,itinerary,context) end
            if not paths then return nil,reason end
            travel,resources,previewActions=paths[1].seconds-run-(activity and 0 or wait),paths[1].resources,paths[1].actions
        end
        if not travel then return nil,"往返路线待补齐" end
        local nearby=activity and activity.seconds or (not data and d.interruptibleSeconds or 0)
        local seconds=travel+run+math.max(wait,nearby)+(d.failureProbability or 0)*(d.recoverySeconds or 0)
        if seconds>options.minutes*60 then return nil,"超出本次游戏时间" end
        if resources then resources.now=(state.now or 0)+seconds end
        local xp=d.xp+(activity and activity.xp or (not data and d.interruptibleXP or 0))
        local turnins={}
        for _,action in ipairs(d.actions or {}) do if action.kind=="turnin" then turnins[action.questId]=true end end
        for _,action in ipairs(activity and activity.actions or {}) do if action.kind=="turnin" then turnins[action.questId]=nil end end
        for id,reward in pairs(d.questXP or {}) do
            if turnins[id] and (not data or plannedTurnins[id]) and (state.quests[id] or not state.completed[id]) then xp=xp+reward end
        end
        return {id="dungeon:"..d.id,dungeonId=d.id,title=d.title,seconds=seconds,xp=xp,rate=xp/math.max(1,seconds),
            actions=d.actions,rewardSources=d.rewardSources,kind="dungeon",requiresAcceptance=true,
            waitActivity=activity or nil,waitSeconds=wait,resources=resources,previewActions=previewActions}
    end
    local best,reason
    for _,activity in ipairs(choices) do
        local candidate,why=evaluate(activity)
        if candidate and (not best or candidate.rate>best.rate or (candidate.rate==best.rate and candidate.seconds<best.seconds)) then best=candidate end
        reason=why or reason
    end
    return best,reason
end

function D.Transition(session,event)
    if event == "accept" and not session.phase then session.phase = "preparing"
    elseif event == "ready" and not session.settled then session.phase = "travel"
    elseif event == "enter" and not session.settled then session.phase,session.entered = "inside",true
    elseif event == "leave" and session.entered and not session.settled then session.phase = "outside"
    elseif event == "wipe" and session.entered and not session.settled then session.phase = "recovering"
    elseif event == "disband" and not session.settled then session.phase = "disbanded"
    elseif event == "finish" and session.entered and not session.settled then
        session.phase,session.settled = "finished",true
        return true
    end
    return false
end

questDone = function(action,state)
    if action.kind=="service" and A.Supplies then return A.Supplies.Done(action,state) end
    if not action.questId then return false end
    local active = state.quests[action.questId]
    if state.completed[action.questId] and not active then return true end
    if action.kind == "accept" then return active ~= nil end
    if action.kind == "objective" and active then
        local objective = active.objectives[action.objectiveIndex or 1]
        return active.ready or (objective and objective.finished)
    end
    return false
end

function D.ActivePlan(d,state,data)
    local session,actions = state.dungeon,{}
    local function gate(kind,text,node)
        return {kind=kind,title=d.title,text=text,dungeonId=d.id,node=node,
            position=node and data.content.nodes[node] and data.content.nodes[node].position}
    end
    local valid,reason = D.Workflow(d,data.content,state)
    if not d.verified or not valid then return {gate("dungeonBlocked",reason or "副本内容待验证")} end
    if state.inInstance then
        local matching,why=D.InstanceMatches(d,state)
        if not matching then return {gate("dungeonBlocked",why)} end
    end
    if state.dead then return {gate("dungeonRecover","死亡恢复后继续本轮，或明确结束本轮")} end
    if session.phase == "disbanded" then return {gate("dungeonWait","队伍已解散，可重新准备或结束行程")} end
    local stage = session.settled and "after" or (session.entered and state.inInstance and "inside" or "before")
    if stage=="before" and not session.entered then
        if session.phase=="preparing" then
            local prepared=true
            for _,action in ipairs(d.actions) do
                if action.stage=="before" and action.kind~="move" and not questDone(action,state) then prepared=false;break end
            end
            if prepared and A.Supplies then prepared=A.Supplies.Apply(D.Preparation(d),A.Supplies.Cursor(state),state.itemMetadata or {})~=nil end
            if prepared then return {gate("dungeonWait","准备已就绪，等队期间可执行已验证的可中断任务")} end
        end
        local options=copy(A.settings)
        options.minutes=math.max(0,session.budget-session.elapsed)/60
        options.ignoreWaitActivities=true
        local evaluation,why=D.Evaluate(d,state,options,data)
        if not evaluation then return {gate("dungeonBlocked",why)} end
        for _,action in ipairs(evaluation.previewActions or {}) do
            if action.kind~="dungeonPrepare" and (action.stage=="before" or (session.phase~="preparing" and action.stage=="entry")) then actions[#actions+1]=action end
        end
        if session.phase=="preparing" then actions[#actions+1]=gate("dungeonWait","队伍就绪后点击“队伍就绪”；等待时可执行已验证的可中断任务") end
        return actions
    end
    local current,context = state.position and (state.position.node or state.position),copy(state)
    local function append(action)
        actions[#actions+1]=action
        return true
    end
    local function routed()
        -- An accepted round still needs its return route after the preferred budget expires.
        context.maxSeconds=nil
        local paths,why
        if A.Supplies then paths,why=A.Supplies.Itinerary(data.content,current,actions,context)
        else paths,why=A.Travel.Itinerary(data.content,current,actions,context) end
        return paths and paths[1].actions or {gate("dungeonBlocked",why)}
    end
    if session.settled and state.inInstance then return {gate("dungeonLeave","本轮已结束，请离开后继续交付与返程")} end
    if not session.settled and session.entered and not state.inInstance then
        if state.instanceEntryError then return {gate("dungeonBlocked",state.instanceEntryError.."；可在副本页重新检查。")} end
        append(gate("dungeonEnter","暂离期间保留进度；重新进入继续，或明确结束本轮",d.entryNode))
        return routed()
    end
    local incomplete=false
    for index,source in ipairs(d.actions) do
        if source.stage == stage and not (session.done and session.done[index]) and not questDone(source,state) and
            not (source.kind=="service" and A.Supplies and A.Supplies.Done(source,state)) then
            local active=source.questId and state.quests[source.questId]
            if stage=="after" and source.kind=="turnin" and not (active and active.ready) then incomplete=true
            else
                local action = copy(source)
                action.dungeonId,action.dungeonStep = d.id,index
                local q = action.questId and data:GetQuest(action.questId)
                action.title = source.title or (q and q.title) or d.title
                if not append(action) then return actions end
            end
        end
    end
    if stage == "before" then
        if session.phase == "preparing" then actions[#actions+1] = gate("dungeonWait","队伍就绪后点击“队伍就绪”；等待时可执行已验证的可中断任务")
        else append(gate("dungeonEnter","到入口后由玩家进入副本",d.entryNode)) end
    elseif stage == "inside" then actions[#actions+1] = gate("dungeonRun","继续本轮；完成后点击“本轮结束”，暂时离开会保留进度")
    else append(gate("dungeonEnd",incomplete and "相关任务尚未可交付，返程后按实际任务状态接续练级" or "返程完成，自动接续练级",d.returnNode)) end
    return routed()
end

function D:Accept(id,repeatRun)
    local d,old = A.Content.dungeons[id],A.char.dungeon
    if not d then return false,"副本资料不存在" end
    if old and old.phase ~= "complete" and not (repeatRun and old.settled) then return false,"先结束当前副本行程" end
    if repeatRun and (not old or old.id ~= id or not old.settled or A.state.inInstance) then return false,"本轮结束并离开后才能比较下一轮" end
    local options = copy(A.settings)
    if repeatRun then options.minutes = math.max(0,old.budget-old.elapsed)/60 end
    local candidate,reason = D.Evaluate(d,A.state,options,A.Data)
    if not candidate then return false,reason end
    A.char.dungeon = {id=id,round=repeatRun and old.round+1 or 1,budget=repeatRun and old.budget or options.minutes*60,
        elapsed=repeatRun and old.elapsed or 0,done={}}
    D.Transition(A.char.dungeon,"accept")
    self.lastTick,self.runSample = nil,nil
    self.sampleFromEntrance=not A.state.inInstance
    self.budgetTick = nil
    A.char.locked = nil
    if A.Selection then A.Selection:Clear();A.Navigation.manual=nil end
    A.State:Refresh(true)
    return true
end

function D:Control(event)
    local session = A.char.dungeon
    if not session then return false,"当前未接受副本行程" end
    if event == "again" then return self:Accept(session.id,true) end
    if event == "stop" then A.char.dungeon,self.runSample = nil,nil
    elseif event == "finish" then
        if not D.Transition(session,"finish") then return false,"本轮尚未进入，或已结算" end
        -- An end declaration settles the round; only verified completion goals calibrate a successful run.
        local sample,d = self.runSample,A.Content.dungeons[session.id]
        local complete = d and ((d.completionQuests and #d.completionQuests>0) or
            (d.completionEncounters and #d.completionEncounters>0))
        local fresh=false
        for _, id in ipairs(d and d.completionQuests or {}) do
            if not A.state.completed[id] and not (A.state.quests[id] and A.state.quests[id].ready) then complete=false end
            if sample and not sample.initialCompleted[id] then fresh=true end
        end
        for _,id in ipairs(d and d.completionEncounters or {}) do
            if not (sample and sample.encounters and sample.encounters[id]) then complete=false
            else fresh=true end
        end
        if complete and fresh and sample and sample.valid and D.InstanceMatches(d,A.state) and A.settings.learn then
            local kind,ratio = "dungeon:"..d.id,sample.seconds/d.runSeconds
            if ratio >= 0.25 and ratio <= 4 then
                if A.char.samples[kind] and A.char.samples[kind].unit~="ratio" then A.char.samples[kind]=nil end
                A.State.Observe(A.char.samples,kind,ratio)
                A.char.samples[kind].unit = "ratio"
            end
        end
        self.runSample = nil
    elseif event == "ready" then
        if session.settled then return false,"本轮已经结束" end
        if A.Instances then
            local d=A.Content.dungeons[session.id]
            if not d then return false,"副本资料不存在" end
            local ok,reason=A.Instances.Check(d,A.state)
            if not ok then return false,reason end
        end
        D.Transition(session,"ready")
    else return false,"未知副本操作" end
    A.State:Refresh(true)
    return true
end

function D:Sync(state,previous)
    local session = A.char.dungeon
    if not session then return end
    state.dungeon = copy(session)
    state.dungeon.done = copy(session.done or {})
    local d = A.Content.dungeons[session.id]
    if not d then state.dungeonUnavailable=true; return end
    if session.contentVersion ~= (d.version or A.Content.version) then
        session.done = {}
        session.contentVersion = d.version or A.Content.version
        if self.runSample then self.runSample.valid=false end
    end
    local matching = D.InstanceMatches(d,state)
    if matching and not session.settled and session.phase ~= "disbanded" then
        if not session.entered then
            if A.Instances then A.Instances:Entered(state,d) end
            self.runSample={seconds=0,valid=self.sampleFromEntrance==true,initialCompleted={}}
            for _,id in ipairs(d.completionQuests or {}) do
                self.runSample.initialCompleted[id]=state.completed[id] or (state.quests[id] and state.quests[id].ready) or false
            end
        end
        if state.dead then D.Transition(session,"wipe") else D.Transition(session,"enter") end
    elseif session.entered and not session.settled and session.phase ~= "disbanded" then D.Transition(session,"leave") end
    if previous.groupSize and previous.groupSize > 1 and state.groupSize == 1 then D.Transition(session,"disband") end
    if self.runSample and (session.phase=="recovering" or session.phase=="outside" or session.phase=="disbanded") then self.runSample.valid=false end
    state.dungeon = copy(session)
    state.dungeon.done = copy(session.done or {})
end

function D:Arrived(action)
    local session = A.char.dungeon
    if not session or action.dungeonId ~= session.id then return end
    if action.dungeonStep then
        local d=A.Content.dungeons[session.id]
        local source=d and d.actions and d.actions[action.dungeonStep]
        if not source or source.stage=="inside" and not D.InstanceMatches(d,A.state) then return end
    end
    if action.dungeonStep then session.done[action.dungeonStep]=true end
    if action.kind == "dungeonEnd" and session.settled then session.phase="complete" end
    A:RequestRefresh()
end

function D:Update()
    local session,now = A.char.dungeon,GetTime()
    if not session or session.phase == "complete" then self.lastTick=nil; return end
    local delta = self.lastTick and now-self.lastTick or 0
    self.lastTick = now
    if delta >= 0 and delta <= 2 then
        session.elapsed=session.elapsed+delta
        local action = A.Navigation:Current()
        if session.phase=="preparing" and ((action and action.kind=="dungeonWait") or (A.plan and A.plan.waitingDungeon==session.id)) then
            session.waited=(session.waited or 0)+delta
        end
    end
    local d = A.Content.dungeons[session.id]
    local matching = d and D.InstanceMatches(d,A.state)
    if matching and not session.settled then
        self.runSample = self.runSample or {seconds=0,valid=false,initialCompleted={}}
        local sample = self.runSample
        if delta > 2 or A.state.dead or UnitIsAFK("player") or A.char.paused then sample.valid=false end
        if sample.valid then sample.seconds=sample.seconds+delta end
    elseif self.runSample then self.runSample.valid=false end
    local tick = math.floor(session.elapsed/30)
    if tick ~= self.budgetTick then self.budgetTick=tick; A:RequestRefresh() end
end
