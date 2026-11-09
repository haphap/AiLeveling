local _,A=...
A.Guides={cache={}}
local G=A.Guides
local function trim(s) return s:match("^%s*(.-)%s*$") end
local function integer(n,max) return type(n)=="number" and n>=1 and n%1==0 and n<=(max or 2147483647) end
local kinds={accept="accept",complete="objective",turnin="turnin",collect="collect",xp="level"}
local tokens={Alliance=true,Horde=true,Human=true,Orc=true,Dwarf=true,NightElf=true,Scourge=true,Undead=true,Tauren=true,Gnome=true,Troll=true,
    WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true}
local function conditionValid(value)
    if value=="" or value:find("[^%w! /]") then return false end
    for branch in (value.."/"):gmatch("(.-)/") do
        if trim(branch)=="" then return false end
        for word in branch:gmatch("%S+") do
            word=word:gsub("^!","")
            if not tokens[word] and not tokens[word:upper()] and not integer(tonumber(word),60) then return false end
        end
    end
    return true
end
function G.Applies(value,state)
    if not value then return true end
    for branch in (value.."/"):gmatch("(.-)/") do
        local matches=true
        for word in branch:gmatch("%S+") do
            local inverse=word:sub(1,1)=="!";word=word:gsub("^!","")
            if word=="Undead" then word="Scourge" end
            local yes=word==state.faction or word==state.race or word:upper()==state.class or
                tonumber(word) and state.level>=tonumber(word)
            if (yes and true or false)==inverse then matches=false end
        end
        if matches then return true end
    end
    return false
end
function G.Parse(source)
    if type(source)~="string" or #source>65536 or source:find("%z") then return nil,"指南文字无效或超过64KB" end
    local guide={steps={},group="自定义指南"}
    local step,lineNumber=nil,0
    for line in (source:gsub("\r\n","\n").."\n"):gmatch("(.-)\n") do
        lineNumber=lineNumber+1;line=trim(line)
        local errorText
        if line=="" or line:sub(1,2)=="--" then
        elseif line=="step" or line:match("^step%s+<<") then
            local condition=line:match("^step%s+<<%s*(.-)%s*$")
            if condition and not conditionValid(condition) then errorText="步骤条件尚不支持"
            else step={commands={},condition=condition};guide.steps[#guide.steps+1]=step end
        elseif line:sub(1,1)=="#" and not step then
            local key,value=line:match("^#(%a+)%s+(.+)$")
            if (key~="name" and key~="group" and key~="next") or #value>160 then errorText="指南标题字段无效"
            else guide[key]=value end
        elseif step and line:sub(1,2)==">>" then
            step.text=(step.text and (step.text.."\n") or "")..trim(line:sub(3))
        elseif step then
            local command,args=line:match("^%.(%a+)%s+(.+)$")
            local kind=kinds[command]
            if not kind then errorText="尚不支持此指南指令"
            else
                local raw=trim((args:gsub("%s*>>.*$","")))
                local id,amount=raw:match("^(%d+)%s*,%s*(%d+)$")
                id=tonumber(id or raw);amount=tonumber(amount)
                if not integer(id,kind=="level" and 60 or nil) or (amount and not integer(amount)) or
                    (kind=="collect" and not amount) or (kind~="collect" and kind~="objective" and amount) then errorText="指令参数无效"
                else step.commands[#step.commands+1]={kind=kind,id=id,index=kind=="objective" and amount or nil,count=kind=="collect" and amount or nil,text=args:match(">>%s*(.+)$")} end
            end
        else errorText="先填写指南标题和step" end
        if errorText then return nil,string.format("第%d行：%s · %s",lineNumber,errorText,line:sub(1,120)) end
        if #guide.steps>1000 then return nil,"指南超过1000步" end
    end
    if not guide.name or #guide.steps==0 then return nil,"指南需要#name和至少一个step" end
    for i,row in ipairs(guide.steps) do if #row.commands==0 and not row.text then return nil,"第"..i.."步没有内容" end end
    guide.key=guide.group.."\031"..guide.name
    return guide
end
function G:Get(key)
    local record=A.settings.guides and A.settings.guides[key]
    if type(record)~="table" or not integer(record.revision) then return end
    local cached=self.cache[key]
    if cached and cached.source==record.source then return cached.guide,record end
    local guide,why=G.Parse(record.source)
    if guide and guide.key==key then self.cache[key]={source=record.source,guide=guide};return guide,record end
    return nil,nil,why or "指南名称与记录不一致"
end
function G:Normalize()
    if type(A.settings.guides)~="table" then A.settings.guides={} end
    if type(A.char.guideProgress)~="table" then A.char.guideProgress={} end
    if type(A.char.activeGuide)~="string" then A.char.activeGuide=nil end
    local serial=integer(A.settings.guideSerial) and A.settings.guideSerial or 0
    for _,record in pairs(A.settings.guides) do
        if type(record)=="table" and integer(record.revision) then serial=math.max(serial,record.revision) end
    end
    A.settings.guideSerial=serial
end
function G:List()
    local rows={}
    for key in pairs(A.settings.guides or {}) do
        local guide=self:Get(key)
        if guide then rows[#rows+1]=guide end
    end
    table.sort(rows,function(a,b) return a.key<b.key end)
    return rows
end
function G:Import(source)
    local guide,why=G.Parse(source)
    if not guide then return nil,why end
    self:Normalize()
    local old=A.settings.guides[guide.key]
    local count=0;for _ in pairs(A.settings.guides) do count=count+1 end
    if not old and count>=16 then return nil,"最多保存16份指南，请先删除不用的指南" end
    if not old or old.source~=source then
        A.settings.guideSerial=A.settings.guideSerial+1
        A.settings.guides[guide.key]={source=source,revision=A.settings.guideSerial}
        A.char.guideProgress[guide.key]=nil
    end
    self.cache[guide.key]=nil
    if A.ready then A.State:Refresh(true) end
    return guide.key
end
function G:Select(key,reset)
    local guide=key and self:Get(key)
    if key and not guide then return false,"指南不存在或格式需要修正" end
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先结束当前副本行程" end
    self:Normalize()
    A.char.activeGuide=key
    if key then
        if reset then A.char.guideProgress[key]=nil end
        A.Selection:Clear();A.char.serviceStop=nil;A.char.gearTarget,A.char.gearBaseline=nil,nil
        A.Navigation.manual=nil;A.char.paused=false
    end
    if A.ready then A.State:Refresh(true) end
    return true
end
function G:Remove(key)
    if A.char.activeGuide==key then self:Select(nil) end
    A.settings.guides[key]=nil;A.char.guideProgress[key]=nil;self.cache[key]=nil
end
local function questDone(command,state,progress,data)
    local active=state.quests[command.id]
    local q=data:GetQuest(command.id)
    local turned=(state.turnIns[command.id] or 0)>(progress.baselines[command.id] or 0) or
        (state.completed[command.id] and q and not q.repeatable)
    if command.kind=="accept" then return active~=nil or turned end
    if command.kind=="turnin" then return turned end
    if turned or active and active.ready then return true end
    local objective=active and command.index and (active.objectives or {})[command.index]
    return objective and objective.finished==true
end
function G:Snapshot(state)
    state.guide=nil
    local key=A.char.activeGuide
    if not key then return "guide:none" end
    state.turnIns={};for id,n in pairs(A.char.turnIns or {}) do state.turnIns[id]=n end
    if not state.race and UnitRace then local _,race=UnitRace("player");state.race=race end
    local guide,record=self:Get(key)
    if not guide then state.guide={key=key,error="所选指南需要重新导入"};return "guide:missing:"..key end
    local progress=A.char.guideProgress[key]
    if type(progress)~="table" or progress.revision~=record.revision or not integer(progress.step,#guide.steps+1) or
        type(progress.baselines)~="table" or type(progress.skipped)~="table" then
        progress={revision=record.revision,step=1,skipped={},baselines={}}
        A.char.guideProgress[key]=progress
    end
    for _,step in ipairs(guide.steps) do for _,command in ipairs(step.commands) do
        if command.kind=="accept" or command.kind=="objective" or command.kind=="turnin" then
            local n=progress.baselines[command.id]
            if type(n)~="number" or n<0 or n%1~=0 or n>=math.huge then progress.baselines[command.id]=(state.turnIns or {})[command.id] or 0 end
        end
    end end
    while progress.step<=#guide.steps do
        local step=guide.steps[progress.step]
        local done=progress.skipped[progress.step]==true or not G.Applies(step.condition,state)
        if not done and #step.commands>0 then
            done=true
            for _,command in ipairs(step.commands) do
                local finished=command.kind=="level" and state.level>=command.id or
                    command.kind=="collect" and (state.bags[command.id] or 0)>=command.count or
                    (command.kind~="level" and command.kind~="collect" and questDone(command,state,progress,A.Data))
                if not finished then done=false;break end
            end
        end
        if not done then break end
        progress.step=progress.step+1
    end
    state.guide={key=key,name=guide.name,step=progress.step,total=#guide.steps,commands=guide.steps[progress.step] and guide.steps[progress.step].commands,
        baselines={},text=guide.steps[progress.step] and guide.steps[progress.step].text,finished=progress.step>#guide.steps,next=guide.next}
    for id,n in pairs(progress.baselines) do state.guide.baselines[id]=n end
    return table.concat({"guide",key,record.revision,progress.step},":")
end
function G:Skip()
    local key=A.char.activeGuide
    local progress=key and A.char.guideProgress[key]
    if not progress or not A.state.guide or A.state.guide.finished then return end
    progress.skipped[progress.step]=true
    A.State:Refresh(true)
end
function G.Apply(plan,state,data)
    local guide=state.guide
    if not guide or state.locked or state.itinerary or state.taskBatch or state.serviceStop or state.gearTarget or plan.sessionActive or plan.maintenance then return end
    local selectedChoice,commandText
    local action={kind="guide",title=guide.name or "所选指南",text=guide.error or guide.text or "按指南继续。"}
    if guide.finished then
        action.title="指南已完成";action.text=guide.next and ("下一份指南："..guide.next.."；在指南窗口中选择继续。") or "可选择另一份指南或恢复自动规划。"
    elseif not guide.error then
        for _,command in ipairs(guide.commands or {}) do
            commandText=command.text
            if command.kind=="level" and state.level<command.id then action.text="继续升级至"..command.id.."级。";break
            elseif command.kind=="collect" and (state.bags[command.id] or 0)<command.count then
                local name=data.db and data.db.Item and data.db.Item.Get(command.id,"name") or
                    state.itemMetadata and state.itemMetadata[command.id] and state.itemMetadata[command.id].name or ("物品 #"..command.id)
                action.text="收集"..name.."，还需"..(command.count-(state.bags[command.id] or 0)).."件。";break
            elseif command.kind=="accept" or command.kind=="objective" or command.kind=="turnin" then
                local progress={baselines=guide.baselines}
                if not questDone(command,state,progress,data) then
                    local context={};for k,v in pairs(state) do context[k]=v end;context.locked=command.id
                    local choices=A.Planner.TaskChoices(context,data,{command.id},true,A.settings)
                    local choice=choices[1];selectedChoice=choice
                    if choice and not choice.acceptBlocked and not choice.entryBlocked and not choice.requireCheck then
                        action=choice.actions[1]
                        if command.kind=="objective" and command.index and state.quests[command.id] then
                            local found
                            for _,candidate in ipairs(choice.stages or choice.actions) do
                                if candidate.kind=="objective" and candidate.objectiveIndex==command.index then found=candidate;break end
                            end
                            action=found or {kind="guide",title=choice.title,text="任务日志中尚无指南指定的目标"..command.index.."；可暂缓此步骤。"}
                        end
                    else action.title="指南任务 #"..command.id;action.text=choice and (choice.acceptBlocked or choice.entryBlocked or choice.checkText) or "查看任务前置条件，或暂缓此指南步骤。" end
                    break
                end
            end
        end
    end
    if action.kind=="turnin" and A.TaskGuide then
        local _,groups=A.TaskGuide.DeliveryGroups(plan.taskChoices,state,plan.taskOrder)
        local group=groups[action.questId]
        if group and not group.splitDelivery and group.ready<#group.choices then
            plan.guideDeferred="先完成同一NPC的剩余任务，再按指南一起交付"
            return
        end
    end
    if action.questId and A.Dungeon and A.Dungeon.TaskApproach then action=A.Dungeon.TaskApproach(action,state,data) or action end
    if commandText or guide.text then
        local copy={};for k,v in pairs(action) do copy[k]=v end;action=copy
        local lines={}
        if guide.text then lines[#lines+1]=guide.text end
        if commandText then lines[#lines+1]=commandText end
        if action.text and action.text~=guide.text then lines[#lines+1]=action.text end
        action.text=table.concat(lines,"\n")
    end
    plan.guideActive=true;plan.best=nil;plan.travelActions=nil;plan.referenceJourney=nil;plan.referenceFlight=nil
    plan.fallback=action;plan.unverified=true
    if selectedChoice then
        plan.taskChoices=plan.taskChoices or {}
        local found=false
        for _,choice in ipairs(plan.taskChoices) do if choice.questId==selectedChoice.questId then found=true;break end end
        if not found then table.insert(plan.taskChoices,1,selectedChoice) end
    end
    if action.position and A.Flights then
        local routes=A.Flights.Itinerary(state.position,{action},state,A.Navigation)
        if routes then plan.referenceJourney=routes[1];plan.travelActions=A.Flights.Actions(routes[1].firstRoute,action,A.Navigation) end
    end
end
