local _,A=...
A.Services={}
local S=A.Services
local function accessible(value) return not canaccessvalue or canaccessvalue(value) end
local function text(value) return accessible(value) and type(value)=="string" and value or nil end
local function number(value,min,max) return accessible(value) and type(value)=="number" and value>=min and value<=max and value%1==0 end
local function spellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok,known=pcall(C_SpellBook.IsSpellKnown,id)
        if ok and accessible(known) and known==false then return false end
        if ok and accessible(known) and known==true and C_SpellBook.IsSpellInSpellBook then
            local listed,inBook=pcall(C_SpellBook.IsSpellInSpellBook,id,nil,false)
            if listed and accessible(inBook) and inBook==true then return true end
        end
    end
end
local function position(p)
    return type(p)=="table" and number(p.map,1,2147483647) and type(p.x)=="number" and p.x>=0 and p.x<=1 and
        type(p.y)=="number" and p.y>=0 and p.y<=1
end
local function copy(p) return {map=p.map,x=p.x,y=p.y} end
local function requirements(row)
    row.requirements={}
    local function add(name,rank,met)
        name=text(name)
        if not name or name=="" then row.requirementsPending=true;return end
        if not accessible(met) or type(met)~="boolean" then met=nil;row.requirementsPending=true end
        row.requirements[#row.requirements+1]={name=name,rank=rank,met=met}
        if met==false then row.requirementsBlocked=true end
    end
    if GetTrainerServiceSkillReq then
        local skill,rank,met=GetTrainerServiceSkillReq(row.index)
        if not accessible(skill) then row.requirementsPending=true
        elseif skill~=nil then
            if not number(rank,0,10000) then rank=nil;row.requirementsPending=true end
            add(skill,rank,met)
        end
    else row.requirementsPending=true end
    local count=GetTrainerServiceNumAbilityReq and GetTrainerServiceNumAbilityReq(row.index)
    if not number(count,0,64) or count>0 and not GetTrainerServiceAbilityReq then row.requirementsPending=true
    else
        for i=1,count do
            local ability,met=GetTrainerServiceAbilityReq(row.index,i)
            add(ability,nil,met)
        end
    end
end
function S.TrainingNeeds(offer,state)
    local needs={}
    if offer.level and state.level and state.level<offer.level then needs[#needs+1]="等级 "..offer.level end
    for _,req in ipairs(offer.requirements or {}) do
        if req.met==false then needs[#needs+1]=req.name..(req.rank and (" "..req.rank) or "") end
    end
    return table.concat(needs,"、")
end
local function trainingRank(offer)
    if offer.status=="used" then return 4 end
    if offer.status=="unavailable" then return 3 end
    if not offer.playerTraining or offer.ambiguous or offer.requirementsBlocked then return 2 end
    return offer.affordable and 0 or 1
end
local function taskStep(step)
    return type(step)=="table" and number(step.questId,1,2147483647) and type(step.title)=="string" and #step.title<=512 and
        (step.kind=="turnin" or step.kind=="objective" and number(step.objectiveIndex,1,1000))
end
function S.ValidStop(stop)
    return type(stop)=="table" and ((stop.kind=="train" or stop.kind=="bind") and number(stop.npcId,1,2147483647) or
        stop.kind=="unlockFlight" and number(stop.taxiId,1,2147483647)) and
        type(stop.title)=="string" and #stop.title>0 and #stop.title<=512 and position(stop.position) and
        (stop.afterTask==nil or stop.kind=="unlockFlight" and taskStep(stop.afterTask) and number(stop.afterTask.turnIns,0,2147483647)) and
        (stop.learnKey==nil or stop.kind=="train" and type(stop.learnKey)=="string" and #stop.learnKey<=1024 and stop.learnKey:match("^[^\031]+")~=nil) and
        (stop.learnSpellId==nil or stop.kind=="train" and stop.learnKey~=nil and number(stop.learnSpellId,1,2147483647))
end

function S:Event(event,...)
    if event=="TRAINER_SHOW" then self.trainerOpen=true
    elseif event=="TRAINER_CLOSED" then self.trainerOpen=false
    elseif event=="PLAYER_ENTERING_WORLD" then self.trainerOpen=false;self.binding=nil
    elseif event=="CONFIRM_BINDER" then
        self.binding=nil
        local stop=A.char.serviceStop or S.CurrentAutomatic()
        local id=UnitGUID and A.Merchant.NpcId(UnitGUID("npc"))
        A.State:Position()
        if stop and stop.kind=="bind" and id==stop.npcId and A.Navigation:Near(A.state.position,stop.position,25) then
            local area=text((...))
            if area and area~="" then self.binding={stop=stop,area=area,time=GetTime(),automatic=A.char.serviceStop==nil} end
        end
    elseif event=="HEARTHSTONE_BOUND" then
        local seen=self.binding;self.binding=nil
        A.State:Position()
        if seen and (seen.stop==A.char.serviceStop or seen.automatic and not A.char.serviceStop) and GetTime()>=seen.time and GetTime()-seen.time<=60 and
            A.Navigation:Near(A.state.position,seen.stop.position,25) and text(GetBindLocation and GetBindLocation())==seen.area then
            if A.Hearth then A.Hearth:ConfirmBinding(A.state,seen.area) end
            A.char.serviceStop=nil;self.message="炉石绑定已确认，继续原任务。"
        end
    end
end

function S:Snapshot(state)
    state.trainer=nil
    local selected=A.char.serviceStop
    if selected and selected.learnSpellId and spellKnown(selected.learnSpellId)==true then
        A.char.serviceStop=nil;self.message="所选训练已确认完成，继续原任务。"
    end
    local key={"services"}
    local tasks={}
    for id in pairs(state.quests or {}) do tasks[#tasks+1]=id end
    table.sort(tasks)
    for i,id in ipairs(tasks) do tasks[i]=id..":"..((A.char.turnIns or {})[id] or 0) end
    state.bindingTaskKey=table.concat(tasks,",")
    state.declinedBinding=A.char.declinedBinding
    key[#key+1]=state.bindingTaskKey;key[#key+1]=state.declinedBinding or ""
    if self.trainerOpen then
        local id=UnitGUID and A.Merchant.NpcId(UnitGUID("npc"))
        if id then
            local trainer={npcId=id,name=text(UnitName and UnitName("npc")),rows={},pending=false}
            state.trainer=trainer;key[#key+1]=id
            local kind=C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType()
            local types=Enum and Enum.TrainerType
            local copper=types and accessible(kind) and (kind==types.General or kind==types.Tradeskills)
            trainer.copper=copper==true
            local count=GetNumTrainerServices and GetNumTrainerServices()
            if not number(count,0,10000) or not GetTrainerServiceInfo then trainer.pending=true
            else
                local keys={}
                for index=1,count do
                    local name,status,_,level,sub,category=GetTrainerServiceInfo(index)
                    name,status,sub=text(name),text(status),text(sub)
                    if name and (status=="available" or status=="unavailable" or status=="used") then
                        local row={index=index,name=name,status=status,level=number(level,0,1000) and level or nil,sub=sub,playerTraining=trainer.copper}
                        row.key=table.concat({name,sub or "",text(category) or ""},"\031")
                        local cost=GetTrainerServiceCost and GetTrainerServiceCost(index)
                        if trainer.copper and number(cost,0,2147483647) then row.cost=cost end
                        row.affordable=row.cost~=nil and (row.cost==0 or state.money~=nil and state.money>=row.cost)
                        requirements(row)
                        if row.level and state.level and state.level<row.level then row.requirementsBlocked=true end
                        keys[row.key]=(keys[row.key] or 0)+1
                        trainer.rows[#trainer.rows+1]=row
                        key[#key+1]=table.concat({row.key,status,tostring(row.cost),tostring(row.level),tostring(row.affordable),
                            tostring(row.playerTraining),tostring(row.requirementsPending)},":")
                        for _,req in ipairs(row.requirements) do
                            key[#key+1]=table.concat({req.name,tostring(req.rank),tostring(req.met)},":")
                        end
                    else trainer.pending=true end
                end
                for _,row in ipairs(trainer.rows) do
                    row.ambiguous=keys[row.key]>1
                    local stop=A.char.serviceStop
                    if stop and stop.kind=="train" and stop.npcId==id and stop.learnKey==row.key and row.status=="used" and not row.ambiguous then
                        A.char.serviceStop=nil;self.message="所选训练已确认完成，继续原任务。"
                    end
                end
            end
            key[#key+1]=tostring(trainer.pending)
        end
    end
    local stop=A.char.serviceStop
    if stop and stop.kind=="unlockFlight" and (state.unlocked or {})["taxi:"..stop.taxiId]==true then
        A.char.serviceStop=nil;stop=nil;self.message="飞行点已开通，继续原任务。"
    end
    if stop then
        state.serviceStop={kind=stop.kind,npcId=stop.npcId,taxiId=stop.taxiId,title=stop.title,position=copy(stop.position),learnKey=stop.learnKey,learnSpellId=stop.learnSpellId}
        key[#key+1]=table.concat({stop.kind,stop.npcId or stop.taxiId,stop.position.map,stop.position.x,stop.position.y,stop.learnKey or "",stop.learnSpellId or ""},":")
        if stop.afterTask then
            local step=stop.afterTask
            state.serviceStop.afterTask={kind=step.kind,questId=step.questId,objectiveIndex=step.objectiveIndex,title=step.title,
                turnedIn=((A.char.turnIns or {})[step.questId] or 0)>step.turnIns}
            key[#key+1]=table.concat({step.kind,step.questId,step.objectiveIndex or 0,tostring(state.serviceStop.afterTask.turnedIn)},":")
        end
    else state.serviceStop=nil end
    return table.concat(key,"|")
end

function S.TaskDestination(plan)
    if not plan or plan.sessionActive or plan.maintenance then return end
    local function task(action)
        return action and action.questId and position(action.position) and
            (action.kind=="accept" or action.kind=="objective" or action.kind=="turnin")
    end
    local action=plan.serviceResume or plan.fallback
    if task(action) then return action end
    for _,candidate in ipairs(plan.best and plan.best.actions or {}) do
        if task(candidate) then return candidate end
    end
end

function S.BindingKey(row)
    local p=row.position
    return string.format("%d:%d:%.9f:%.9f",row.npcId,p.map,p.x,p.y)
end

function S.TrainerData(state)
    local data=A.Trainers
    if data and state.clientVersion==data.version and tostring(state.clientBuild)==data.build and state.interface==data.interface then return data end
end

function S.TrainerFit(state,id)
    local data=S.TrainerData(state)
    local profile=data and data.npcs[id]
    if not profile then return 1 end
    if profile.classMask and state.classMask and state.classMask>0 then
        if state.classMask==profile.classMask then return 0,"包含本职业的训练项目。" end
        return 3,"已知项目属于其他职业，优先查看本职业训练师。"
    end
    if profile.skill then
        local rank=(state.skills or {})[profile.skill]
        local name=data.skills[profile.skill]
        if rank and rank>0 then return 0,"已学习"..name.."，可到场查看后续训练。" end
        if rank==0 then return 2,"尚未学习"..name.."；需要学习这项技能时再前往。" end
    end
    return 1
end

function S.ServiceMaps(plan,state)
    local maps={}
    if not plan or plan.sessionActive or plan.maintenance or state.inInstance then return maps end
    local function add(action)
        if action and position(action.position) then maps[action.position.map]=true end
    end
    add(S.TaskDestination(plan))
    for _,choice in ipairs(plan.taskOrder or {}) do
        if state.quests[choice.questId] and not choice.lowValue and not choice.entryBlocked and not choice.requireCheck and not choice.acceptBlocked then
            for _,stage in ipairs(choice.stages or {}) do add(stage) end
        end
    end
    return maps
end

local function taskStages(plan,state)
    if plan.best or plan.sessionActive or plan.maintenance or state.dead or state.onTaxi or state.inInstance then return end
    local stages={}
    local function add(choice,stage)
        if choice.lowValue or choice.entryBlocked or choice.requireCheck or choice.acceptBlocked or not choice.stagesComplete then return false end
        for _,action in ipairs(stage and {stage} or choice.stages or {}) do
            if not position(action.position) then return false end
            stages[#stages+1]=action
        end
        return true
    end
    if plan.taskQueue then
        if (plan.taskQueue.remaining or 0)>0 then return end
        for _,step in ipairs(plan.taskQueue.steps) do if not add(step.choice,step.stage) then return end end
    else
        local choice
        for _,row in ipairs(plan.taskOrder or {}) do
            if state.quests[row.questId] and not row.lowValue then
                if choice then return end
                choice=row
            end
        end
        if not choice or not add(choice) then return end
    end
    if #stages==0 then return end
    return stages
end

local function betterHub(a,b)
    if a.deliveryCount~=b.deliveryCount then return a.deliveryCount>b.deliveryCount end
    if a.acceptCount~=b.acceptCount then return a.acceptCount>b.acceptCount end
    return a.deliveryDistance<b.deliveryDistance
end

function S.PlanBindings(plan,state,data)
    if state.serviceStop or plan.sessionActive or plan.maintenance or state.inInstance or not data.AmenityPoints then return end
    local result={}
    for _,row in ipairs(data:AmenityPoints(state,"bind",S.ServiceMaps(plan,state))) do
        local hub={deliveryCount=0,acceptCount=0,pendingCount=0,deliveryDistance=0,
            stop={kind="bind",npcId=row.npcId,title=row.title,position=copy(row.position)}}
        local seen={}
        for _,choice in ipairs(plan.taskChoices or plan.taskOrder or {}) do
            if not seen[choice.questId] and not choice.lowValue and not choice.entryBlocked and not choice.requireCheck and not choice.acceptBlocked then
                seen[choice.questId]=true
                local active=(state.quests or {})[choice.questId]
                local stages=choice.stages or {}
                local step=active and stages[#stages] or choice.actions and choice.actions[1]
                if step and (active and step.kind=="turnin" or not active and step.kind=="accept") and position(step.position) then
                    local distance=A.Navigation:Distance(row.position,step.position)
                    if distance and distance<=200 then
                        if active then
                            hub.deliveryCount=hub.deliveryCount+1;hub.deliveryDistance=hub.deliveryDistance+distance
                            if not active.ready then hub.pendingCount=hub.pendingCount+1 end
                        else hub.acceptCount=hub.acceptCount+1 end
                    end
                end
            end
        end
        result[S.BindingKey(row)]=hub
    end
    return result
end

function S.AutomaticBinding(plan,state)
    if state.locked or state.itinerary or state.gearTarget or state.taskBatch or state.serviceStop or state.dead or state.onTaxi or state.inInstance or
        plan.best or plan.sessionActive or plan.maintenance or not state.bindingTaskKey or state.bindingTaskKey=="" or
        state.declinedBinding==state.bindingTaskKey or (state.bags or {})[6948]==nil or state.bags[6948]<=0 then return end
    local current=S.TaskDestination(plan)
    if current and current.kind=="turnin" then return end
    local best,bestKey
    for key,hub in pairs(plan.bindingChoices or {}) do
        if hub.pendingCount>0 and (not best or betterHub(hub,best) or not betterHub(best,hub) and key<bestKey) then best,bestKey=hub,key end
    end
    if best and A.Navigation:Near(state.position,best.stop.position,100) and
        not (state.hearthPoint and A.Navigation:Near(state.hearthPoint,best.stop.position,200)) then
        local stop=best.stop
        return {kind="bind",npcId=stop.npcId,title=stop.title,position=copy(stop.position)}
    end
end

function S.CurrentAutomatic()
    local plan=A.plan
    if plan and plan.revision==A.state.revision and not A.char.serviceStop and not A.refreshAt and not (A.jobs and A.jobs.plan) then
        return plan.automaticService
    end
end

function S.PlanFlightUnlocks(plan,state)
    if state.serviceStop or not A.Flights or not A.Flights.Matches(state) then return end
    local stages=taskStages(plan,state);if not stages then return end
    local rows=A.Flights.UnlockCandidates(state,S.ServiceMaps(plan,state),A.Navigation)
    if #rows==0 then return end
    local baseline=A.Flights.Itinerary(state.position,stages,state,A.Navigation)
    if not baseline then return end
    local result={}
    for _,row in ipairs(rows) do
        local preview=A.Flights.PreviewUnlock(state,row,A.Navigation)
        if preview then
            local best,afterStage
            for insertion=0,#stages-1 do
                if insertion==0 or taskStep(stages[insertion]) then
                    local before,after={},{}
                    for index,stage in ipairs(stages) do
                        local list=index<=insertion and before or after;list[#list+1]=stage
                    end
                    before[#before+1]=row
                    for _,path in ipairs(A.Flights.Itinerary(state.position,before,state,A.Navigation) or {}) do
                        preview.money=path.money;preview.now=(state.now or 0)+path.seconds;preview.hearthReady=path.hearthReady
                        preview.maxSeconds=state.maxSeconds and math.max(0,state.maxSeconds-path.seconds)
                        local routes=A.Flights.Itinerary(row.position,after,preview,A.Navigation)
                        local seconds=routes and path.seconds+routes[1].seconds
                        if seconds and (not best or seconds<best-0.001) then best,afterStage=seconds,insertion end
                    end
                end
                local thread,main=coroutine.running();if thread and not main then coroutine.yield() end
            end
            if best then result[row.taxiId]={saving=baseline[1].seconds-best,afterStage=afterStage,
                afterTask=afterStage>0 and stages[afterStage] or nil,resumeTitle=stages[afterStage+1].title} end
        end
    end
    return result
end

function S:Choices(kind)
    local state=A.state
    local current=A.plan and A.plan.revision==state.revision and not A.refreshAt and not (A.jobs and A.jobs.plan) and A.plan
    local rows={}
    if kind=="learn" then
        local trainer=state.trainer
        if trainer and position(state.position) then
            for _,offer in ipairs(trainer.rows) do
                rows[#rows+1]={kind="train",npcId=trainer.npcId,title=trainer.name or ("NPC #"..trainer.npcId),
                    position=copy(state.position),learnKey=offer.key,offer=offer}
            end
        end
    elseif kind=="unlockFlight" then
        local maps=S.ServiceMaps(current,state);if state.position then maps[state.position.map]=true end
        if A.Flights then rows=A.Flights.UnlockCandidates(state,maps,A.Navigation) end
    elseif A.Data.AmenityPoints then rows=A.Data:AmenityPoints(state,kind,S.ServiceMaps(current,state)) end
    local resume=kind~="learn" and current and S.TaskDestination(current)
    local bindings=kind=="bind" and current and current.bindingChoices
    for _,row in ipairs(rows) do
        row.trainingRank,row.trainingText=nil,nil
        if kind=="train" then row.trainingRank,row.trainingText=S.TrainerFit(state,row.npcId) end
        row.distance=A.Navigation:Distance(state.position,row.position)
        row.journeyDistance,row.resumeTitle=nil,nil
        local binding=bindings and bindings[S.BindingKey(row)]
        local unlock=kind=="unlockFlight" and current and current.flightUnlockChoices and current.flightUnlockChoices[row.taxiId]
        row.unlockSaving=unlock and unlock.saving or nil;row.unlockAfterTask=unlock and unlock.afterTask or nil
        row.bindingHub=binding
        if resume then
            local onward=A.Navigation:Distance(row.position,resume.position)
            row.journeyDistance=row.distance and onward and row.distance+onward
            row.resumeTitle=unlock and unlock.resumeTitle or row.journeyDistance and resume.title
        end
    end
    table.sort(rows,function(a,b)
        if kind=="learn" and trainingRank(a.offer)~=trainingRank(b.offer) then return trainingRank(a.offer)<trainingRank(b.offer) end
        if kind=="train" and a.trainingRank~=b.trainingRank then return a.trainingRank<b.trainingRank end
        if a.bindingHub and b.bindingHub then
            if betterHub(a.bindingHub,b.bindingHub) then return true end
            if betterHub(b.bindingHub,a.bindingHub) then return false end
        end
        local as,bs=a.unlockSaving or 0,b.unlockSaving or 0
        if (as>1 or bs>1) and as~=bs then return as>bs end
        if resume and a.journeyDistance~=b.journeyDistance then
            return (a.journeyDistance or math.huge)<(b.journeyDistance or math.huge)
        end
        local da,db=a.distance,b.distance
        if da~=db then return (da or math.huge)<(db or math.huge) end
        if (a.npcId or a.taxiId)~=(b.npcId or b.taxiId) then return (a.npcId or a.taxiId)<(b.npcId or b.taxiId) end
        if a.offer and b.offer then return a.offer.index<b.offer.index end
        if a.position.map~=b.position.map then return a.position.map<b.position.map end
        if a.position.x~=b.position.x then return a.position.x<b.position.x end
        return a.position.y<b.position.y
    end)
    self.choices,self.revision=rows,state.revision
    return rows
end

function S:CanPick(row,revision)
    if not A.ready or not A.indexReady then return false,"任务数据尚未就绪" end
    if A.refreshAt or A.jobs and A.jobs.plan or revision~=A.state.revision or revision~=self.revision then return false,"状态正在更新，请稍后重选" end
    if A.char.dungeon or A.state.inInstance then return false,"请先结束副本行程并离开副本" end
    if A.state.dead or A.Transport:InFlight() then return false,"请在存活且落地后安排服务" end
    local found=false;for _,candidate in ipairs(self.choices or {}) do if candidate==row then found=true;break end end
    if not found or not S.ValidStop(row) then return false,"请重新选择当前服务点" end
    if row.kind=="unlockFlight" and (not A.Flights.Matches(A.state) or (A.state.unlocked or {})["taxi:"..row.taxiId]~=false) then return false,"飞行点状态已变化，请重新选择" end
    if row.offer and (row.offer.status~="available" or row.offer.ambiguous or not row.offer.playerTraining or row.offer.requirementsBlocked) then return false,"请选择当前可学且可明确识别的角色训练项目" end
    return true
end

function S:Pick(row,revision)
    local ok,why=self:CanPick(row,revision);if not ok then return false,why end
    A.char.serviceStop={kind=row.kind,npcId=row.npcId,taxiId=row.taxiId,title=row.title,position=copy(row.position),learnKey=row.learnKey}
    if row.offer and self.trainerOpen and C_TooltipInfo and C_TooltipInfo.GetTrainerService and
        Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell~=nil and GetTrainerServiceInfo and
        UnitGUID and A.Merchant.NpcId(UnitGUID("npc"))==row.npcId then
        local name,_,_,_,sub,category=GetTrainerServiceInfo(row.offer.index)
        local currentKey=table.concat({text(name) or "",text(sub) or "",text(category) or ""},"\031")
        if currentKey==row.learnKey then
            local ok,tip=pcall(C_TooltipInfo.GetTrainerService,row.offer.index)
            if ok and accessible(tip) and type(tip)=="table" and accessible(tip.type) and
                tip.type==Enum.TooltipDataType.Spell and number(tip.id,1,2147483647) and spellKnown(tip.id)==false then
                A.char.serviceStop.learnSpellId=tip.id
            end
        end
    end
    local step=row.unlockSaving and row.unlockSaving>1 and row.unlockAfterTask
    if step then
        A.char.serviceStop.afterTask={kind=step.kind,questId=step.questId,objectiveIndex=step.objectiveIndex,title=step.title,
            turnIns=((A.char.turnIns or {})[step.questId] or 0)}
    end
    self.binding,self.message=nil,nil
    A.char.paused=false;A.Navigation.manual=nil
    A.Observations:Reset();A.State:Refresh(true)
    return true
end
function S:Cancel()
    local stop=A.char.serviceStop or S.CurrentAutomatic()
    if stop and stop.kind=="bind" then A.char.declinedBinding=A.state.bindingTaskKey end
    A.char.serviceStop=nil;self.binding=nil;self.message="已取消服务安排，继续原任务。"
    A.State:Refresh(true)
end

function S.Build(state,plan,automatic)
    local stop=state.serviceStop or automatic
    if not stop then return end
    if plan then plan.serviceDeferred=nil end
    if stop.kind=="unlockFlight" and (not A.Flights or not A.Flights.Matches(state) or not A.FlightData.nodes[stop.taxiId]) then
        return {fallback={kind="selectionBlocked",title="飞行点资料与当前客户端不匹配",text="可取消此服务安排，继续原任务。"}}
    end
    if stop.afterTask then
        local step=stop.afterTask
        local active=(state.quests or {})[step.questId]
        local objective=active and (active.objectives or {})[step.objectiveIndex]
        local done=step.turnedIn or step.kind=="objective" and active and
            (active.ready or objective and objective.finished)
        if not done then
            if plan then plan.serviceDeferred="等待「"..step.title.."」" end
            return
        end
    end
    local instruction=stop.kind=="bind" and "与旅店老板交谈，设置炉石。" or
        stop.kind=="unlockFlight" and "与飞行管理员交谈，开通此飞行点。" or
        stop.learnKey and ("向训练师学习「"..stop.learnKey:match("^[^\031]+").."」；学会后继续原任务。") or
        "与训练师交谈，在服务页选择要学习的项目。"
    if automatic then instruction="建议把炉石设在这里，做完任务后回来集中交付。" end
    local trainingCost
    if stop.kind=="train" and stop.learnKey and state.trainer and state.trainer.npcId==stop.npcId then
        for _,offer in ipairs(state.trainer.rows) do
            if offer.key==stop.learnKey and not offer.ambiguous and offer.status~="used" then
                if offer.playerTraining and offer.status=="available" and not offer.requirementsBlocked then trainingCost=offer.cost end
                local needs=S.TrainingNeeds(offer,state)
                if needs~="" then instruction="学习「"..offer.name.."」还需："..needs.."。可取消服务安排，继续任务。"
                elseif offer.cost and state.money and state.money<offer.cost then
                    instruction="学习「"..offer.name.."」还差 "..(offer.cost-state.money).." 铜。可取消服务安排，继续任务。"
                elseif offer.status=="unavailable" then instruction="「"..offer.name.."」当前无法学习，请查看训练窗口中的条件。" end
                break
            end
        end
    end
    local action={kind="service",serviceKind=stop.kind,npcId=stop.npcId,taxiId=stop.taxiId,title=stop.title,position=copy(stop.position),text=instruction}
    if automatic then return {fallback=action,travelActions={action}} end
    local stages=stop.kind~="bind" and A.Flights and plan and taskStages(plan,state)
    local route={action}
    if stages then
        route[1]={kind=stop.kind,title=stop.title,position=action.position,moneyCost=trainingCost}
        for _,stage in ipairs(stages) do route[#route+1]=stage end
    end
    local routes=A.Flights and A.Flights.Itinerary(state.position,route,state,A.Navigation)
    local journey=routes and routes[1]
    local trainLater=stages and stop.kind=="train" and not stop.learnKey and not A.Navigation:Near(state.position,stop.position,25)
    if trainLater then
        for _,stage in ipairs(stages) do
            if not state.quests[stage.questId] then trainLater=false;break end
        end
    end
    if trainLater then
        local best,after=journey and journey.seconds or math.huge,nil
        for insertion=1,#stages do
            if taskStep(stages[insertion]) then
                local sequence={}
                for i=1,insertion do sequence[#sequence+1]=stages[i] end
                sequence[#sequence+1]=route[1]
                for i=insertion+1,#stages do sequence[#sequence+1]=stages[i] end
                local paths=A.Flights.Itinerary(state.position,sequence,state,A.Navigation)
                if paths and paths[1].seconds<best-1 then best,after=paths[1].seconds,stages[insertion] end
            end
            local thread,main=coroutine.running();if thread and not main then coroutine.yield() end
        end
        if after then
            plan.serviceDeferred=(after.kind=="turnin" and "先交付「" or "先完成「")..after.title.."」，再前往"..stop.title.."训练"
            return
        end
    end
    if journey then return {fallback=action,travelActions=A.Flights.Actions(journey.firstRoute,action,A.Navigation),referenceJourney=journey} end
    if stages then
        return {fallback={kind="selectionBlocked",title="服务后的任务行程暂不可衔接",
            text="当前交通、金币或行程时间不足以接续剩余任务。可取消服务安排，继续原任务。"}}
    end
    local flight=A.Flights and A.Flights.Guide(action,state,A.Navigation)
    return {fallback=action,travelActions=flight and flight.actions or {action},referenceFlight=flight}
end
