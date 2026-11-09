return function(test,eq,F,A,plan)
local names={"UnitGUID","UnitName","GetTime","GetBindLocation","C_Trainer","Enum","GetNumTrainerServices","GetTrainerServiceInfo","GetTrainerServiceCost","canaccessvalue",
    "BuyTrainerService","SetTrainerServiceTypeFilter","ExpandTrainerSkillLine","ConfirmBinder",
    "GetTrainerServiceSkillReq","GetTrainerServiceNumAbilityReq","GetTrainerServiceAbilityReq","C_TooltipInfo","C_SpellBook",
    "InCombatLockdown","IsShiftKeyDown","C_PlayerInteractionManager","C_GossipInfo","HOME"}
local function setup()
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local B={};for k,v in pairs(A) do B[k]=v end
    B.char={locked=42,samples={}};B.state=F.State();B.state.position={map=1,x=0.5,y=0.5};B.state.money=20
    B.ready=true;B.indexReady=true;B.jobs={};B.TaskGuide=nil
    B.settings={autoTrain=false,autoBind=false}
    B.Queue=function(_,key,callback) B.jobs[key]=callback end
    B.RequestRefresh=function() B.refreshRequests=(B.refreshRequests or 0)+1 end
    B.State={Position=function() end,Refresh=function() B.Services:Snapshot(B.state);B.state.revision=B.state.revision+1 end}
    B.Transport={InFlight=function() return B.flying end}
    B.Navigation={Distance=function(_,a,b) return a.map==b.map and math.abs(a.x-b.x)*1000 or nil end}
    B.Navigation.Near=function(self,a,b,radius) local d=self:Distance(a,b);return d and d<=radius end
    assert(loadfile("Services.lua"))("AiLeveling",B);assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    local e={npc=78,now=1,binding="旧旅店",kind=0,rows={{name="训练项目",status="available",sub="等级 1",cost=30},{name="下一等级",status="unavailable",cost=90}}}
    UnitGUID=function() return "Creature-0-1-2-3-"..e.npc.."-0001" end;UnitName=function() return "训练师" end
    GetTime=function() return e.now end;GetBindLocation=function() return e.binding end
    InCombatLockdown=function() return e.combat end;IsShiftKeyDown=function() return e.shift end
    C_PlayerInteractionManager=nil
    Enum={TrainerType={General=0,Tradeskills=2,Pet=3}};C_Trainer={GetTrainerType=function() return e.kind end}
    GetNumTrainerServices=function() return #e.rows end
    GetTrainerServiceInfo=function(i) local r=e.rows[i];return r.name,r.status,1,r.level or 10,r.sub end
    GetTrainerServiceCost=function(i) return e.rows[i].cost end
    GetTrainerServiceSkillReq=function(i) local r=e.rows[i];return r.skill,r.rank,r.skillMet end
    GetTrainerServiceNumAbilityReq=function(i) local r=e.rows[i];return r.abilityCount or #(r.abilities or {}) end
    GetTrainerServiceAbilityReq=function(i,j) local r=e.rows[i].abilities[j];return r.name,r.met end
    canaccessvalue=nil
    for _,key in ipairs({"BuyTrainerService","SetTrainerServiceTypeFilter","ExpandTrainerSkillLine","ConfirmBinder"}) do
        _G[key]=function() error("训练绑定和窗口筛选必须由玩家操作") end
    end
    return B,e,function() for _,name in ipairs(names) do _G[name]=saved[name] end end
end
local function chooseTraining(B)
    B.Services:Event("TRAINER_SHOW");B.Services:Snapshot(B.state)
    local rows=B.Services:Choices("learn");assert(B.Services:Pick(rows[1],B.state.revision));return B.char.serviceStop
end
test("原生服务窗口与菜单匹配实际NPC、可用选项和当前安排",function()
    local B,e,finish=setup();local S=B.Services
    S:Event("TRAINER_SHOW");local first=S:Snapshot(B.state);local t=B.state.trainer
    eq(t.npcId,78);eq(t.rows[1].status,"available");eq(t.rows[1].cost,nil)
    e.rows[1].status="used";assert(S:Snapshot(B.state)~=first);eq(B.state.trainer.rows[1].status,"used");e.rows[1].status="available"
    e.kind=3;S:Snapshot(B.state);eq(B.state.trainer.rows[1].cost,nil)
    local rows=S:Choices("learn");eq(S:CanPick(rows[1],B.state.revision),false)
    canaccessvalue=function(value) return type(value)~="string" end;S:Snapshot(B.state);eq(B.state.trainer,nil)
    canaccessvalue=nil;S:Event("TRAINER_CLOSED");S:Snapshot(B.state);eq(B.state.trainer,nil)
    B.settings.autoTrain=true;B.settings.autoBind=true;B.settings.autoTaxi=true
    B.char.serviceStop={kind="train",npcId=78,title="训练师",position=B.state.position}
    Enum.GossipOptionStatus={Available=0}
    local options={{icon=132060,name="训练",status=0,gossipOptionID=8,orderIndex=1},
        {icon=132058,name="服务",overrideIconID=132060,status=0,gossipOptionID=42,orderIndex=9}}
    local byID,byIndex=function() end,function() end
    C_GossipInfo={GetOptions=function() return options end,SelectOption=byID,SelectOptionByIndex=byIndex}
    S:Event("GOSSIP_SHOW");local selected=S:GossipOption();eq(selected.value,42);eq(selected.select,byID)
    local row=options[2];row.status=1;eq(S:GossipOption(),nil);row.status=0
    options[3]={icon=132058,status=0,gossipOptionID=43,orderIndex=10};eq(S:GossipOption(),nil);options[3]=nil
    row.gossipOptionID=nil;row.orderIndex=0;selected=S:GossipOption();eq(selected.value,0);eq(selected.select,byIndex)
    row.orderIndex=nil;eq(S:GossipOption(),nil);row.orderIndex=9;row.gossipOptionID=42
    e.npc=79;eq(S:GossipOption(),nil);e.npc=78
    e.shift=true;S:Event("GOSSIP_SHOW");e.shift=false;eq(S:GossipOption(),nil);S:Event("GOSSIP_SHOW")
    for _,mode in ipairs({"shift","combat","paused","manual","disabled","far","flying"}) do
        if mode=="shift" then e.shift=true elseif mode=="combat" then e.combat=true
        elseif mode=="paused" then B.char.paused=true elseif mode=="manual" then B.Navigation.manual={}
        elseif mode=="disabled" then B.settings.autoTrain=false elseif mode=="flying" then B.flying=true
        else B.state.position={map=1,x=0.9,y=0.5} end
        eq(S:GossipOption(),nil)
        e.shift,e.combat,B.char.paused,B.Navigation.manual,B.flying=nil,nil,nil,nil,nil
        B.settings.autoTrain=true;B.state.position={map=1,x=0.5,y=0.5}
    end
    B.refreshAt=1;S:Event("GOSSIP_SHOW");eq(S:GossipOption(),nil)
    S:Event("GOSSIP_CLOSED");eq(S:GossipOption(),nil);B.refreshAt=nil
    B.plan={revision=B.state.revision,automaticService={kind="bind",npcId=78,title="旅店",position=B.state.position}}
    B.char.serviceStop=nil;row.icon=132052;S:Event("GOSSIP_SHOW");eq(S:GossipOption().value,42)
    local secret={};row.icon=secret;canaccessvalue=function(v) return v~=secret end;eq(S:GossipOption(),nil)
    canaccessvalue=nil;row.icon=136458;HOME="家";row.name="设为新的家";eq(S:GossipOption().value,42)
    row.name="传送到战场";eq(S:GossipOption(),nil)
    B.plan=nil;row.icon=132057
    local transport=B.Transport;assert(loadfile("Transport.lua"))("AiLeveling",B)
    transport.PlannedFlight=B.Transport.PlannedFlight;B.Transport=transport
    B.Navigation.actions={{kind="move",position=B.state.position},{kind="transit",mode="flight",
        fromTaxi=1,toTaxi=2,departure=B.state.position,departureRadius=12}}
    B.Navigation.index=1;eq(S:GossipOption().value,42);eq(B.Navigation.index,1)
    table.insert(B.Navigation.actions,1,{kind="objective",questId=1});eq(S:GossipOption(),nil)
    B.Navigation.actions={};B.char.serviceStop={kind="unlockFlight",taxiId=1,title="飞行点",position=B.state.position}
    eq(S:GossipOption().value,42);eq((B.state.unlocked or {})["taxi:1"],nil)
    S:Event("GOSSIP_CLOSED");eq(S:GossipOption(),nil)
    finish()
end)
test("训练专业与前置技能条件影响状态指纹并区分未满足和未知",function()
    local B,e,finish=setup();local S=B.Services;local r=e.rows[1]
    r.skill,r.rank,r.skillMet="炼金术",75,false;r.abilities={{name="初级炼金术",met=true}}
    S:Event("TRAINER_SHOW");local before=S:Snapshot(B.state);local offer=B.state.trainer.rows[1]
    eq(offer.requirementsBlocked,true);eq(offer.requirementsPending,nil);eq(#offer.requirements,2)
    eq(S.TrainingNeeds(offer,B.state),"炼金术 75")
    local choices=S:Choices("learn");eq(S:CanPick(choices[1],B.state.revision),false)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B);B.UI.Services.preview=choices[1]
    local lines=table.concat(B.UI.Services:Lines(),"\n")
    assert(lines:find("炼金术 75 · 未满足",1,true));assert(lines:find("初级炼金术 · 已满足",1,true))
    r.skillMet=true;assert(S:Snapshot(B.state)~=before);eq(B.state.trainer.rows[1].requirementsBlocked,nil)
    r.level=30;S:Snapshot(B.state);choices=S:Choices("learn");eq(S:CanPick(choices[1],B.state.revision),false);r.level=10
    r.skillMet={};canaccessvalue=function(v) return type(v)~="table" end
    S:Snapshot(B.state);offer=B.state.trainer.rows[1]
    eq(offer.requirements[1].met,nil);eq(offer.requirementsPending,true);eq(offer.requirementsBlocked,nil)
    canaccessvalue=nil;r.abilityCount=65;GetTrainerServiceSkillReq=nil
    S:Snapshot(B.state);eq(B.state.trainer.rows[1].requirementsPending,true)
    eq(#B.state.trainer.rows[1].requirements,0)
    finish()
end)
test("当前训练项目优先可学，学习条件变化更新排序",function()
    local B,e,finish=setup();local S=B.Services
    e.rows={{name="已学",status="used",cost=0},{name="条件不足",status="unavailable",cost=0},
        {name="昂贵",status="available",cost=30},{name="可学",status="available",cost=10}}
    S:Event("TRAINER_SHOW");local before=S:Snapshot(B.state)
    local rows=S:Choices("learn");eq(rows[1].offer.name,"昂贵");eq(rows[2].offer.name,"可学")
    eq(rows[3].offer.name,"条件不足");eq(rows[4].offer.name,"已学")
    e.rows[3].skill,e.rows[3].rank,e.rows[3].skillMet="炼金术",75,false
    S:Snapshot(B.state);rows=S:Choices("learn");eq(rows[1].offer.name,"可学");eq(S:CanPick(rows[2],B.state.revision),false)
    finish()
end)
test("已安排训练按真实条件执行已选项目，重复事件不重学且原生确认后接续",function()
    local B,e,finish=setup();local stop=chooseTraining(B);local S=B.Services
    local action=S.Build(B.state).fallback;assert(action.text:find("向训练师学习",1,true))
    e.rows[1].skill,e.rows[1].rank,e.rows[1].skillMet="炼金术",75,false
    e.rows[1].abilities={{name="初级炼金术",met=false}};e.rows[1].level=30
    S:Snapshot(B.state);action=S.Build(B.state).fallback
    assert(action.text:find("等级 30、炼金术 75、初级炼金术",1,true));eq(B.char.serviceStop,stop)
    e.rows[1].skillMet=true;e.rows[1].abilities[1].met=true;e.rows[1].level=10;B.state.money=40
    S:Snapshot(B.state);action=S.Build(B.state).fallback;assert(action.text:find("向训练师学习",1,true))
    e.rows[1].status="used";S:Snapshot(B.state);eq(B.char.serviceStop,nil)
    finish();B,e,finish=setup();S=B.Services
    local bought={};BuyTrainerService=function(index) bought[#bought+1]=index end
    local loaded=false;Enum.TooltipDataType={Spell=1}
    C_TooltipInfo={GetTrainerService=function() if loaded then return {type=1,id=101} end end}
    C_SpellBook={IsSpellKnown=function() return false end}
    B.settings.autoTrain=true;stop=chooseTraining(B)
    eq(#bought,0);eq(B.char.serviceStop,stop)
    loaded=true;S:Event("TOOLTIP_DATA_UPDATE",999);eq(B.refreshRequests,1)
    S:Snapshot(B.state);eq(stop.learnSpellId,101)
    eq(#bought,1);eq(bought[1],1);eq(B.char.serviceStop,stop)
    S:Snapshot(B.state);S:Event("TRAINER_SHOW");S:Snapshot(B.state);eq(#bought,1)
    S:Event("TOOLTIP_DATA_UPDATE",999);eq(B.refreshRequests,1)
    local function window()
        S:Event("TRAINER_CLOSED");S:Event("TRAINER_SHOW");S:Snapshot(B.state)
    end
    e.npc=79;window();eq(#bought,1);e.npc=78
    e.shift=true;window();eq(#bought,1);e.shift=false
    e.combat=true;window();eq(#bought,1);e.combat=false
    B.char.paused=true;window();eq(#bought,1);B.char.paused=false
    B.Navigation.manual={};window();eq(#bought,1);B.Navigation.manual=nil
    B.settings.autoTrain=false;window();eq(#bought,1);B.settings.autoTrain=true
    B.flying=true;window();eq(#bought,1);B.flying=false
    e.rows[1].status="unavailable";window();eq(#bought,1);e.rows[1].status="available"
    e.rows[2]={name=e.rows[1].name,status="available",sub=e.rows[1].sub};window();eq(#bought,1)
    e.rows[2]=nil;e.kind=3;window();eq(#bought,1);e.kind=0
    Enum.TooltipDataType={Spell=1};stop.learnSpellId=101
    C_TooltipInfo={GetTrainerService=function() return {type=1,id=102} end}
    window();eq(#bought,1)
    C_TooltipInfo.GetTrainerService=function() return {type=1,id=101} end
    window();eq(#bought,2);eq(B.char.serviceStop,stop)
    e.rows[1].status="used";S:Snapshot(B.state);eq(B.char.serviceStop,nil);eq(B.char.locked,42)
    finish()
end)
test("所选技能确实学会后即使训练列表隐藏或关闭也恢复原任务",function()
    local B,e,finish=setup();local known,inBook=false,false
    Enum.TooltipDataType={Spell=1,Item=0}
    C_TooltipInfo={GetTrainerService=function(index) return {type=1,id=100+index} end}
    C_SpellBook={IsSpellKnown=function(id) return id==101 and known end,
        IsSpellInSpellBook=function(id,bank,overrides) eq(overrides,false);return id==101 and inBook end}
    local stop=chooseTraining(B);eq(stop.learnSpellId,101);assert(B.Services.ValidStop(stop))
    e.rows={};B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    B.Services:Event("TRAINER_CLOSED");B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    known=true;B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    inBook=true;B.Services:Snapshot(B.state);eq(B.char.serviceStop,nil);eq(B.state.serviceStop,nil)
    eq(B.char.locked,42)
    e.rows={{name="训练项目",status="available",sub="等级 1",cost=10}}
    stop=chooseTraining(B);eq(stop.learnSpellId,nil)
    B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    stop.learnSpellId=0;eq(B.Services.ValidStop(stop),false)
    stop.learnSpellId=nil;B.Services:Cancel();known=false
    C_TooltipInfo.GetTrainerService=function() return {type=0,id=101} end
    stop=chooseTraining(B);eq(stop.learnSpellId,nil)
    local bought=0;BuyTrainerService=function(index) eq(index,1);bought=bought+1 end
    B.settings.autoTrain=true;C_TooltipInfo.GetTrainerService=function() return {type=1,id=101} end
    B.Services:Snapshot(B.state);eq(stop.learnSpellId,101);eq(B.state.serviceStop.learnSpellId,101);eq(bought,1)
    e.rows={};known=true;inBook=true;B.Services:Snapshot(B.state);eq(B.char.serviceStop,nil)
    finish()
end)
test("训练完成只认同NPC同项目已学会且筛选消失和同名歧义保持安排",function()
    local B,e,finish=setup();local stop=chooseTraining(B);eq(B.char.locked,42)
    e.rows={};B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    e.rows={{name="训练项目",status="used",sub="等级 1",cost=0}};e.npc=79;B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    e.npc=78;e.rows[2]={name="训练项目",status="available",sub="等级 1",cost=30}
    B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    local rows=B.Services:Choices("learn");eq(B.Services:CanPick(rows[2],B.state.revision),false)
    e.rows[2]=nil;B.Services:Snapshot(B.state);eq(B.char.serviceStop,nil);eq(B.char.locked,42)
    finish()
end)
test("服务选择拒绝过期对象飞行死亡副本和不可学项目且持久意图独立复制",function()
    local B,e,finish=setup();B.Services:Event("TRAINER_SHOW");B.Services:Snapshot(B.state)
    local rows=B.Services:Choices("learn");eq(B.Services:CanPick(rows[2],B.state.revision),false)
    B.refreshAt=1;eq(B.Services:Pick(rows[1],B.state.revision),false);B.refreshAt=nil
    B.flying=true;eq(B.Services:Pick(rows[1],B.state.revision),false);B.flying=false
    B.char.dungeon={};eq(B.Services:Pick(rows[1],B.state.revision),false);B.char.dungeon=nil
    B.state.dead=true;eq(B.Services:Pick(rows[1],B.state.revision),false);B.state.dead=false
    B.Services:Choices("learn");eq(B.Services:Pick(rows[1],B.state.revision),false)
    rows=B.Services:Choices("learn");assert(B.Services:Pick(rows[1],B.state.revision));local p=B.char.serviceStop.position
    rows[1].position.x=0;eq(p.x,0.5);B.state.serviceStop.position.x=0;eq(p.x,0.5)
    assert(B.Services.ValidStop(B.char.serviceStop));B.char.serviceStop.learnKey="\031";eq(B.Services.ValidStop(B.char.serviceStop),false)
    B.char.serviceStop.learnKey=nil;B.char.serviceStop.position.x=0/0;eq(B.Services.ValidStop(B.char.serviceStop),false)
    finish()
end)
test("炉石安排须关联所选旅店确认和真实绑定事件且取消重载超时不误完成",function()
    local B,e,finish=setup();local S=B.Services
    local function reset()
        B.char.serviceStop={kind="bind",npcId=78,title="旅店",position={map=1,x=0.5,y=0.5}}
        e.npc=78;e.now=1;e.binding="旧旅店";B.state.position.x=0.5
    end
    reset();S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    e.npc=79;S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";e.now=62;S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");S:Event("PLAYER_ENTERING_WORLD");e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";B.state.position.x=0.9;S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(B.char.serviceStop,nil);eq(B.char.locked,42)
    reset();S:Cancel();e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(B.char.serviceStop,nil)
    local confirmed,cleared,valid=0,0,true
    B.settings.autoBind=true;Enum.PlayerInteractionType={Binder=77}
    C_PlayerInteractionManager={IsValidNPCInteraction=function(kind) eq(kind,77);return valid end,
        ConfirmationInteraction=function(kind) eq(kind,77);confirmed=confirmed+1 end,
        ClearInteraction=function(kind) eq(kind,77);cleared=cleared+1;valid=false end}
    local function flush()
        local job=B.jobs["service:bind"];B.jobs["service:bind"]=nil;if job then job() end
    end
    reset();valid=true;S:Event("CONFIRM_BINDER","新旅店");eq(confirmed,0)
    S:Event("CONFIRM_BINDER","新旅店");flush();eq(confirmed,1);eq(cleared,1);assert(B.char.serviceStop)
    S:Event("CONFIRM_BINDER","新旅店");flush();eq(confirmed,1)
    e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(B.char.serviceStop,nil);eq(B.char.locked,42)
    for _,mode in ipairs({"shift","combat","paused","manual","disabled","cancel","npc","far","closed","expired"}) do
        reset();valid=true
        if mode=="shift" then e.shift=true elseif mode=="combat" then e.combat=true
        elseif mode=="paused" then B.char.paused=true elseif mode=="manual" then B.Navigation.manual={}
        elseif mode=="disabled" then B.settings.autoBind=false end
        S:Event("CONFIRM_BINDER","新旅店")
        if mode=="cancel" then S:Cancel() elseif mode=="npc" then e.npc=79
        elseif mode=="far" then B.state.position.x=0.9 elseif mode=="closed" then valid=false
        elseif mode=="expired" then e.now=62 end
        flush();eq(confirmed,1)
        e.shift,e.combat,B.char.paused,B.Navigation.manual=nil,nil,nil,nil;B.settings.autoBind=true
    end
    reset();valid=true
    B.plan={revision=B.state.revision,automaticService=B.char.serviceStop};B.char.serviceStop=nil
    S:Event("CONFIRM_BINDER","新旅店");flush();eq(confirmed,2);eq(cleared,2)
    local bound=0;B.Hearth={ConfirmBinding=function(_,state,area) eq(state,B.state);eq(area,"新旅店");bound=bound+1 end}
    e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(bound,1);eq(B.char.serviceStop,nil)
    finish()
end)
test("服务插入覆盖普通规划保留锁定且必要维修优先并在完成后恢复任务",function()
    local B,e,finish=setup();local stop=chooseTraining(B);local s=B.state
    s.locked=42;s.quests[42]={title="原任务",ready=true,objectives={}}
    local d=F.Data({});d.GetQuest=function(_,id) return id==42 and {id=42,title="原任务"} end
    d.Target=function() return {map=1,x=0.6,y=0.5} end
    local result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.serviceStop,true);eq(result.best,nil);eq(result.fallback.npcId,78);eq(result.fallback.serviceKind,"train")
    eq(result.serviceResume.questId,42);eq(result.serviceResume.kind,"turnin")
    eq(B.Supplies.Done(result.fallback,s),false);eq(s.locked,42)
    s.durability=0.1;s.merchant={npcId=9,name="铁匠",canRepair=true,items={}}
    result=plan(s,d,{minutes=60,dungeons=false},B);eq(result.maintenance,true);eq(result.fallback.serviceKind,"repair")
    s.durability=1;e.rows[1].status="used";B.Services:Snapshot(s)
    result=plan(s,d,{minutes=60,dungeons=false},B);eq(result.serviceStop,nil);eq(result.fallback.questId,42)
    finish()
end)
test("服务点比较接续任务的总直线距离且过期规划不参与",function()
    local B,e,finish=setup();B.plan=nil
    B.Data={AmenityPoints=function() return {
        {kind="bind",npcId=1,title="身后旅店",position={map=1,x=0.45,y=0.5}},
        {kind="bind",npcId=2,title="前方旅店",position={map=1,x=0.7,y=0.5}}} end}
    local target={kind="objective",questId=42,title="原任务",position={map=1,x=0.9,y=0.5}}
    local function check(id) local rows=B.Services:Choices("bind");eq(rows[1].npcId,id);return rows end
    check(1)
    B.plan={revision=B.state.revision,fallback=target}
    local rows=check(2);eq(rows[1].resumeTitle,"原任务");assert(rows[1].journeyDistance<rows[2].journeyDistance)
    B.plan.revision=B.state.revision-1;eq(check(1)[1].resumeTitle,nil)
    B.plan.revision=B.state.revision;B.jobs.plan={};check(1);B.jobs.plan=nil
    B.refreshAt=1;check(1);B.refreshAt=nil
    B.plan.maintenance=true;check(1);B.plan.maintenance=nil
    B.plan.sessionActive=true;check(1);B.plan.sessionActive=nil
    B.plan.fallback={kind="service",position={map=1,x=0.45,y=0.5}};B.plan.serviceResume=target;check(2)
    -- An unknown onward distance cannot beat a complete two-leg comparison.
    local distance=B.Navigation.Distance
    B.Navigation.Distance=function(self,a,b) if a.x==0.7 and b.x==0.9 then return end;return distance(self,a,b) end
    check(1)
    B.plan.serviceResume=nil;B.plan.best={actions={{kind="move",position=B.state.position},target}}
    eq(B.Services.TaskDestination(B.plan),target)
    target.kind="dungeonBlocked";eq(B.Services.TaskDestination(B.plan),nil)
    finish()
end)
local function bindingFixture()
    local B,e,finish=setup();local s=B.state
    B.FlightData=nil;B.PublicTransitData=nil;B.Travel=A.Travel;B.Estimates={hearthSeconds=10}
    assert(loadfile("Hearth.lua"))("AiLeveling",B);assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    B.Navigation.Distance=function(_,a,b) if a.map==b.map then return math.abs(a.x-b.x)*7000 end end
    s.position={map=1,x=0,y=0};s.now=0;s.runSpeed=7;s.quests={[42]={}}
    s.hearthPoint={map=1,x=0,y=0};s.hearthBindingKey="old";s.hearthReady=0;s.hearthCooldown=3600;s.bags={[6948]=1}
    local stages={{kind="objective",questId=42,title="原任务",position={map=1,x=1,y=0}},
        {kind="turnin",questId=42,title="交付",position={map=1,x=0.8,y=0}}}
    local choice={questId=42,stages=stages,stagesComplete=true}
    local p={revision=s.revision,taskOrder={choice},fallback=stages[1]}
    local inns={{kind="bind",npcId=1,title="近旅店",position={map=1,x=0.05,y=0}},
        {kind="bind",npcId=2,title="交付地旅店",position={map=1,x=0.8,y=0}}}
    B.Data={AmenityPoints=function() return inns end};B.plan=p
    return B,s,p,inns,finish,e
end
local function automaticFixture()
    local B,s,_,inns,finish,e=bindingFixture()
    B.char.locked=nil;s.position.x=0.79
    for _,file in ipairs({"Planner/TaskGuide.lua","Planner/TaskQueue.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local q={id=42,title="原任务",questLevel=20}
    local d=F.Data({[42]=q})
    local recipient=inns[2].position
    d.AmenityPoints=function() return inns end
    d.Target=function(_,quest,state) return {map=1,x=state.quests[42].ready and recipient.x or 1,y=0,objectiveIndex=1} end
    d.ObjectiveTargets=function() return {{map=1,x=1,y=0,objectiveIndex=1}} end
    B.Data=d;s.quests[42]={title="原任务",objectives={{text="目标",numRequired=1,numFulfilled=0,finished=false}}}
    local function rebuild()
        B.Services:Snapshot(s);B.plan=plan(s,d,{minutes=60,dungeons=false},B);return B.plan
    end
    return B,s,inns,finish,e,rebuild
end
test("自动旅店安排从完整任务规划进入行动并在原生绑定后继续任务",function()
    local B,s,inns,finish,e,rebuild=automaticFixture();local S=B.Services
    local p=rebuild();eq(p.automaticService.npcId,2);eq(p.fallback.serviceKind,"bind");eq(p.serviceResume.questId,42)
    eq(B.char.serviceStop,nil);eq(s.hearthPoint.x,0);eq(s.quests[42].objectives[1].finished,false)
    assert(p.fallback.text:find("做完任务后回来集中交付",1,true))
    s.position={map=1,x=0.8,y=0};e.npc=2;rebuild()
    S:Event("HEARTHSTONE_BOUND");eq(B.Hearth.landing,nil)
    S:Event("CONFIRM_BINDER","交付地旅店");assert(S.binding)
    e.binding="交付地旅店";s.bindName=e.binding
    B.Hearth:Event("HEARTHSTONE_BOUND");S:Event("HEARTHSTONE_BOUND");B.Hearth:Snapshot(s)
    eq(s.hearthPoint.x,0.8);eq(s.quests[42].objectives[1].finished,false)
    p=rebuild();eq(p.automaticService,nil);eq(p.serviceStop,nil);eq(p.fallback.questId,42);eq(p.fallback.kind,"objective")
    eq(B.char.serviceStop,nil);finish()
end)
test("自动换绑取消后同批任务不重复，进度走动重载保留且新任务重新评估",function()
    local B,s,inns,finish,e,rebuild=automaticFixture();local S=B.Services
    rebuild();S:Cancel();local declined=B.char.declinedBinding;eq(declined,"42:0")
    eq(rebuild().automaticService,nil);eq(B.plan.fallback.questId,42)
    s.position.x=0.01;s.quests[42].objectives[1].numFulfilled=1
    eq(rebuild().automaticService,nil);eq(B.char.declinedBinding,declined)
    assert(loadfile("Services.lua"))("AiLeveling",B);S=B.Services
    eq(rebuild().automaticService,nil)
    -- An explicit service choice is still allowed after declining automatic advice.
    local rows=S:Choices("bind");assert(S:Pick(rows[1],s.revision));eq(B.char.serviceStop.npcId,2)
    S:Cancel();B.char.turnIns={[42]=1};s.position.x=0.79
    assert(rebuild().automaticService);eq(s.bindingTaskKey,"42:1")
    S:Cancel();s.quests[43]={};S:Snapshot(s);assert(s.bindingTaskKey~=B.char.declinedBinding)
    finish()
end)
test("炉石只在交接据点附近建议绑定并保护当前任务和维护",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services;S:Snapshot(s)
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    eq(S.AutomaticBinding(p,s),nil)
    s.position={map=1,x=0.79,y=0};assert(S.AutomaticBinding(p,s))
    s.hearthReady=nil;assert(S.AutomaticBinding(p,s))
    s.hearthPoint={map=1,x=0.81,y=0};eq(S.AutomaticBinding(p,s),nil)
    s.hearthPoint=nil;assert(S.AutomaticBinding(p,s))
    s.bags={};eq(S.AutomaticBinding(p,s),nil);s.bags={[6948]=1}
    p.fallback=p.taskOrder[1].stages[2];eq(S.AutomaticBinding(p,s),nil);p.fallback=p.taskOrder[1].stages[1]
    for _,field in ipairs({"locked","gearTarget","taskBatch","serviceStop","dead","onTaxi","inInstance"}) do
        s[field]=true;eq(S.AutomaticBinding(p,s),nil);s[field]=nil
    end
    for _,field in ipairs({"best","sessionActive","maintenance"}) do
        p[field]=true;eq(S.AutomaticBinding(p,s),nil);p[field]=nil
    end
    finish()
end)
test("过期自动绑定建议和错误NPC不确认，取消或另选服务使待确认失效",function()
    local B,s,inns,finish,e,rebuild=automaticFixture();local S=B.Services
    s.position={map=1,x=0.8,y=0};rebuild();e.npc=2
    B.jobs.plan={};S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);B.jobs.plan=nil
    B.refreshAt=1;S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);B.refreshAt=nil
    B.plan.revision=s.revision-1;S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);rebuild()
    e.npc=3;S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);e.npc=2
    S:Event("CONFIRM_BINDER","新旅店");assert(S.binding);S:Cancel()
    e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(B.Hearth.landing,nil)
    B.char.declinedBinding=nil;rebuild();S:Event("CONFIRM_BINDER","新旅店");assert(S.binding)
    local rows=S:Choices("bind");assert(S:Pick(rows[1],s.revision));eq(S.binding,nil)
    S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop);eq(B.Hearth.landing,nil)
    finish()
end)
test("手选旅店直接到店不安排延后步骤且不预测新绑定",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    local rows=S:Choices("bind");eq(rows[1].npcId,2);assert(S:Pick(rows[1],s.revision))
    eq(s.serviceStop.afterTask,nil)
    local result=S.Build(s,p);eq(result.fallback.serviceKind,"bind")
    eq(s.hearthBindingKey,"old");eq(s.hearthPoint.x,0)
    for _,leg in ipairs(result.referenceJourney.legs) do
        if leg.kind=="hearth" then eq(leg.bindingKey,"old") end
    end
    S:Cancel();eq(s.serviceStop,nil);finish()
end)
local function flightServiceFixture()
    local B,s,p,inns,finish=bindingFixture()
    s.bags={};s.hearthPoint=nil;s.hearthBindingKey=nil;s.hearthReady=nil
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001;s.transportKnown=true;s.faction="Alliance";s.taxiSpeed=1
    B.FlightData={version="service-test",clientVersion="1.60.1",build=70862,interface=16001,
        nodes={[1]={name="出发",instance=0,world={0,0,0},factionMask=1},[2]={name="服务",instance=0,world={0.4,0,0},factionMask=1}},
        durations={Alliance={["1:2"]=20},Horde={}}}
    s.unlocked={["taxi:1"]=true,["taxi:2"]=true};s.taxiAvailability={["1:2"]=true}
    s.taxiDepartures={[1]={map=1,x=0,y=0}};s.taxiLandings={["1:2"]={map=1,x=0.4,y=0}}
    s.taxiHops={["1:2"]="1:2"};B.Estimates.flightBoardSeconds=3
    s.serviceStop={kind="train",npcId=78,title="训练师",position={map=1,x=0.4,y=0}}
    return B,s,p,finish
end
test("训练访问顺路安排在任务之后，完成后恢复服务且具体技能仍先学",function()
    local B,s,p,finish=flightServiceFixture();local S=B.Services
    s.transportKnown=false;s.position={map=1,x=0,y=0};s.serviceStop.position={map=1,x=0.9,y=0}
    local stages=p.taskOrder[1].stages
    stages[1].position={map=1,x=0.2,y=0};stages[2].position={map=1,x=0.8,y=0}
    local stop=s.serviceStop
    eq(S.Build(s,p),nil);assert(p.serviceDeferred and p.serviceDeferred:find("训练师",1,true))
    eq(s.serviceStop,stop);eq(s.completed[42],nil)
    s.quests={}
    local choice=p.taskOrder[1]
    p.taskQueue={remaining=0,steps={{choice=choice,stage=stages[1]},{choice=choice,stage=stages[2]}}}
    local result=S.Build(s,p);eq(result.fallback.serviceKind,"train");eq(p.serviceDeferred,nil)
    p.taskOrder={};p.taskQueue=nil
    result=S.Build(s,p);eq(result.fallback.serviceKind,"train");eq(s.serviceStop,stop)
    s.quests[42]={};p.taskOrder={{questId=42,stages=stages,stagesComplete=true}}
    s.serviceStop.learnKey="指定技能"
    result=S.Build(s,p);eq(result.fallback.serviceKind,"train")
    s.serviceStop.learnKey=nil;s.position={map=1,x=0.9,y=0}
    result=S.Build(s,p);eq(result.fallback.serviceKind,"train")
    s.position={map=1,x=0,y=0};p.taskOrder[1].stagesComplete=false
    result=S.Build(s,p);eq(result.fallback.serviceKind,"train")
    for _,file in ipairs({"Planner/TaskGuide.lua","Planner/TaskQueue.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local q=F.Quest(42);q.verified=false
    local data=F.Data({[42]=q})
    data.Target=function(_,_,state) return {map=1,x=state.quests[42].ready and 0.8 or 0.2,y=0,objectiveIndex=1} end
    data.ObjectiveTargets=function() return {{map=1,x=0.2,y=0,objectiveIndex=1}} end
    s.quests[42]={title="顺路任务",objectives={{text="目标",numRequired=1,numFulfilled=0}}}
    result=plan(s,data,{minutes=60,dungeons=false},B)
    eq(result.serviceStop,nil);eq(result.fallback.kind,"objective");assert(result.serviceDeferred)
    B.UI={};assert(loadfile("UI/Main.lua"))("AiLeveling",B);assert(loadfile("UI/Tracker.lua"))("AiLeveling",B)
    eq(B.UI.TrackerModel(s,result,result.fallback,false).hint,result.serviceDeferred)
    assert(loadfile("UI/Services.lua"))("AiLeveling",B)
    B.plan=result;B.UI.Services.preview=nil;B.UI.Services.kind="train"
    assert(table.concat(B.UI.Services:Lines(),"\n"):find(result.serviceDeferred,1,true))
    s.quests[42].ready=true
    result=plan(s,data,{minutes=60,dungeons=false},B);eq(result.fallback.kind,"turnin");assert(result.serviceDeferred)
    s.quests[42]=nil;s.completed[42]=true
    result=plan(s,data,{minutes=60,dungeons=false},B);eq(result.fallback.serviceKind,"train");eq(result.serviceDeferred,nil)
    finish()
end)
test("已知服务后段不可行时保持手选意图并拒绝单段贪心回退",function()
    local B,s,p,finish=flightServiceFixture();local S=B.Services
    local stop=s.serviceStop;p.taskOrder[1].stages[2].position={map=999,x=0,y=0}
    local distance=B.Navigation.Distance
    B.Navigation.Distance=function(self,a,b) if a.map==999 or b.map==999 then return nil end;return distance(self,a,b) end
    assert(S.Build(s).referenceJourney)
    local result=S.Build(s,p);eq(result.fallback.kind,"selectionBlocked");eq(result.travelActions,nil);eq(s.serviceStop,stop)
    p.taskOrder[1].stagesComplete=false
    result=S.Build(s,p);eq(result.fallback.kind,"service");eq(result.referenceJourney.firstRoute.flights,1)
    finish()
end)
local function unlockFixture()
    local B,s,p,_,finish=bindingFixture();local oldMap=C_Map
    C_Map={GetMapInfo=function(id) return {mapType=3,name="区域"} end}
    s.bags={};s.hearthPoint=nil;s.hearthBindingKey=nil;s.hearthReady=nil;s.hearthCooldown=nil
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001;s.transportKnown=true;s.faction="Alliance";s.taxiSpeed=1
    s.unlocked={["taxi:1"]=false,["taxi:2"]=true};s.taxiAvailability={};s.taxiDepartures={};s.taxiLandings={};s.taxiHops={}
    B.FlightData={version="test",clientVersion="1.60.1",build=70862,interface=16001,nodes={
        [1]={name="沿途飞行点",world={0,0.2,0},instance=0,factionMask=1,condition=0,visibility=0},
        [2]={name="交付地",world={0,1,0},instance=0,factionMask=1,condition=0,visibility=0}},
        paths={{1,2,10}},durations={Alliance={["1:2"]=100}}}
    B.Navigation.hbd={GetZoneCoordinatesFromWorldInstance=function(_,x,y,instance,map) if map==1 then return x,y end end}
    B.Estimates.flightBoardSeconds=3
    local stages=p.taskOrder[1].stages
    stages[1].title="沿途目标";stages[1].objectiveIndex=1;stages[1].position.x=0.1
    stages[2].position.x=1
    return B,s,p,function() C_Map=oldMap;finish() end
end
test("手选未发现飞行点使用实际交通，到达后等待原生开通再恢复任务",function()
    local B,s,p,finish=unlockFixture();local S=B.Services
    local rows=S:Choices("unlockFlight");eq(#rows,1);eq(rows[1].taxiId,1)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B)
    B.UI.Services.kind="unlockFlight";B.UI.Services.preview=rows[1]
    local lines=table.concat(B.UI.Services:Lines(),"\n");assert(lines:find("与飞行管理员交谈",1,true))
    assert(S:Pick(rows[1],s.revision));assert(S.ValidStop(B.char.serviceStop))
    local stop=S.Build(s,p);eq(stop.fallback.taxiId,1);eq(stop.referenceJourney.flights,0)
    eq(s.unlocked["taxi:1"],false);eq(next(s.taxiAvailability),nil)
    B.char.serviceStop.taxiId=0;eq(S.ValidStop(B.char.serviceStop),false);B.char.serviceStop.taxiId=1
    s.clientBuild="1";eq(S.Build(s,p).fallback.kind,"selectionBlocked");s.clientBuild="70862"
    s.position={map=1,x=0.2,y=0};S:Snapshot(s);assert(s.serviceStop)
    s.unlocked["taxi:2"]=true;S:Snapshot(s);assert(s.serviceStop)
    s.unlocked["taxi:1"]=true;S:Snapshot(s);eq(s.serviceStop,nil);eq(B.char.serviceStop,nil);eq(B.char.locked,42)
    finish()
end)
test("开点候选限当前构建原生明确未发现的友方室外飞行点",function()
    local B,s,p,finish=unlockFixture();local S=B.Services;local node=B.FlightData.nodes[1]
    s.unlocked["taxi:1"]=nil;eq(#S:Choices("unlockFlight"),0)
    s.unlocked["taxi:1"]=false;node.factionMask=2;eq(#S:Choices("unlockFlight"),0)
    node.factionMask=1;node.condition=8;eq(#S:Choices("unlockFlight"),0)
    node.condition=0;node.visibility=8;eq(#S:Choices("unlockFlight"),0);node.visibility=0
    s.clientBuild="1";eq(#S:Choices("unlockFlight"),0);s.clientBuild="70862"
    s.inInstance=true;eq(#S:Choices("unlockFlight"),0);s.inInstance=false
    local rows=S:Choices("unlockFlight");eq(#rows,1)
    s.unlocked["taxi:1"]=true;eq(S:CanPick(rows[1],s.revision),false)
    finish()
end)
test("原生明确未发现的飞行点进入状态指纹，未知标记不推定未开通",function()
    local oldTaxi,oldMap=C_TaxiMap,C_Map
    C_Map={GetMapInfo=function() return {mapType=3} end}
    C_TaxiMap={GetTaxiNodesForMap=function() return {
        {nodeID=1,faction=2,isUndiscovered=true},{nodeID=2,faction=2,isUndiscovered=false},
        {nodeID=3,faction=2,isUndiscovered=0},{nodeID=4,faction=1,isUndiscovered=true}} end}
    local B={Content={transit={}}};assert(loadfile("Transport.lua"))("AiLeveling",B)
    local s={unlocked={},now=0};local key=B.Transport.Key(s)
    B.Transport:RefreshKnown(1,"Alliance");s.unlocked=B.Transport.known
    eq(s.unlocked["taxi:1"],false);eq(s.unlocked["taxi:2"],true);eq(s.unlocked["taxi:3"],nil);eq(s.unlocked["taxi:4"],nil)
    assert(B.Transport.Key(s)~=key);s.unlocked["taxi:2"]=nil
    assert(B.Transport.Key(s)~=key);s.unlocked["taxi:1"]=true
    B.Transport:RefreshKnown(1,"Alliance");eq(s.unlocked["taxi:1"],true)
    C_TaxiMap,C_Map=oldTaxi,oldMap
end)
test("炉石旅店按集中交付与可接任务排序且不推演换绑行程",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    B.Flights.Itinerary=function() error("绑定建议不做整程搜索") end
    p.taskOrder[2]={questId=43,stages={{kind="turnin",position={map=1,x=0.81,y=0}}}};s.quests[43]={}
    p.taskOrder[3]=p.taskOrder[2]
    p.taskOrder[4]={questId=44,actions={{kind="accept",position={map=1,x=0.8,y=0}}}}
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    local hub=p.bindingChoices[S.BindingKey(inns[2])];eq(hub.deliveryCount,2);eq(hub.acceptCount,1)
    eq(p.bindingChoices[S.BindingKey(inns[1])].deliveryCount,0)
    local rows=S:Choices("bind");eq(rows[1].npcId,2)
    eq(s.hearthBindingKey,"old");eq(s.hearthPoint.x,0);eq(s.hearthReady,0)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B);B.UI.Services.preview=rows[1]
    local lines=table.concat(B.UI.Services:Lines(),"\n")
    assert(lines:find("2 个已接任务",1,true));assert(lines:find("1 个可接任务",1,true))
    assert(not lines:find("预计",1,true));finish()
end)
test("炉石交接点保留已知收件人并排除低价值受限及缺位置任务",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    p.taskQueue={remaining=1,steps={}};p.taskOrder[1].stagesComplete=false
    s.hearthPoint=nil;s.hearthReady=nil
    local function count() return S.PlanBindings(p,s,B.Data)[S.BindingKey(inns[2])].deliveryCount end
    eq(count(),1)
    for _,field in ipairs({"lowValue","entryBlocked","requireCheck","acceptBlocked"}) do
        p.taskOrder[1][field]=true;eq(count(),0);p.taskOrder[1][field]=nil
    end
    p.taskOrder[1].stages[2].position=nil;eq(count(),0)
    eq(s.hearthPoint,nil);eq(s.hearthReady,nil);finish()
end)
test("已确认所选旅店建立炉石参考点且再次绑定清除旧点",function()
    local B,e,finish=setup();assert(loadfile("Hearth.lua"))("AiLeveling",B)
    local s=B.state;s.hearthReady=1;s.bags={[6948]=1}
    B.char.serviceStop={kind="bind",npcId=78,title="旅店",position={map=1,x=0.5,y=0.5}}
    B.Services:Event("CONFIRM_BINDER","新旅店")
    e.binding="新旅店";s.bindName=e.binding
    B.Hearth:Event("HEARTHSTONE_BOUND");B.Services:Event("HEARTHSTONE_BOUND")
    eq(B.char.serviceStop,nil);assert(B.Hearth.landing.reference)
    B.Hearth:Snapshot(s);eq(s.hearthPoint.x,0.5);eq(s.hearthBindingKey,"1:新旅店")
    s.hearthPoint.x=0;eq(B.Hearth.landing.position.x,0.5);eq(next(B.char.samples),nil)
    B.Hearth:Event("HEARTHSTONE_BOUND");B.Services:Event("HEARTHSTONE_BOUND")
    B.Hearth:Snapshot(s);eq(s.hearthPoint,nil)
    finish()
end)
test("跨区旅店进入当前行程换绑比较且过期规划撤回扩展目录",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    local stages=p.taskOrder[1].stages
    stages[1].position={map=2,x=0.2,y=0};stages[2].position={map=2,x=0,y=0}
    inns[2].position={map=2,x=0,y=0}
    B.Navigation.Distance=function(_,a,b) return math.abs((a.map-1+a.x)-(b.map-1+b.x))*7000 end
    B.Data.AmenityPoints=function(_,state,kind,maps)
        if maps and maps[2] then return inns end
        return {inns[1]}
    end
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    eq(p.bindingChoices[S.BindingKey(inns[2])].deliveryCount,1)
    local choices=S:Choices("bind");eq(#choices,2);eq(choices[1].npcId,2);eq(choices[1].position.map,2)
    assert(S:Pick(choices[1],s.revision));eq(B.char.serviceStop.position.map,2)
    S:Cancel();p.revision=s.revision
    eq(#S:Choices("train"),2)
    p.revision=s.revision-1;eq(#S:Choices("bind"),1);p.revision=s.revision
    B.jobs.plan={};eq(#S:Choices("bind"),1);B.jobs.plan=nil
    p.taskOrder[2]={questId=43,stages={{position={map=3,x=0.5,y=0.5}}},lowValue={}}
    s.quests[43]={};eq(S.ServiceMaps(p,s)[3],nil)
    p.taskOrder[2].lowValue=nil;p.taskOrder[2].entryBlocked="受限";eq(S.ServiceMaps(p,s)[3],nil)
    B.Navigation.Distance=function(_,a,b) if a.map==b.map then return math.abs(a.x-b.x)*7000 end end
    eq(S.PlanBindings(p,s,B.Data)[S.BindingKey(inns[2])].deliveryCount,1)
    finish()
end)
test("训练师按本职业和已学专业优先，未知与未学专业保留手选",function()
    local B,e,finish=setup();local s=B.state
    assert(loadfile("Data/Trainers.lua"))("AiLeveling",B)
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001;s.classMask=16;s.skills={[165]=50,[202]=0}
    local ids={3047,3412,999999,3365,2123,2704}
    B.Data={AmenityPoints=function(_,state,kind)
        local rows={};for i,id in ipairs(ids) do rows[i]={kind=kind,npcId=id,title="训练师"..id,position={map=1,x=0.5+i/100,y=0.5}} end
        return rows
    end}
    local rows=B.Services:Choices("train")
    eq(rows[1].npcId,3365);eq(rows[2].npcId,2123);eq(rows[3].npcId,999999);eq(rows[4].npcId,2704)
    eq(rows[5].npcId,3412);eq(rows[6].npcId,3047);eq(#rows,6)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B);B.UI.Services.kind="train";B.UI.Services.preview=rows[1]
    assert(table.concat(B.UI.Services:Lines(),"\n"):find("已学习制皮",1,true))
    assert(B.Services:Pick(rows[5],s.revision));eq(B.char.serviceStop.npcId,3412)
    s.classMask=128;s.skills[165]=0;s.skills[202]=25
    rows=B.Services:Choices("train");eq(rows[1].npcId,3047);eq(rows[2].npcId,3412)
    s.classMask=nil;s.skills={};eq(B.Services.TrainerFit(s,3047),1);eq(B.Services.TrainerFit(s,3365),1)
    s.clientBuild="other";rows=B.Services:Choices("train");eq(rows[1].npcId,3047)
    for _,row in ipairs(rows) do eq(row.trainingRank,1);eq(row.trainingText,nil) end
    s.clientBuild="70862";rows=B.Services:Choices("bind");eq(rows[1].npcId,3047);eq(rows[1].trainingRank,nil)
    finish()
end)
test("训练专业按当前构建读取原生技能且缺接口保持未知",function()
    local B,e,finish=setup();local s=B.state
    assert(loadfile("Data/Trainers.lua"))("AiLeveling",B);assert(loadfile("State.lua"))("AiLeveling",B)
    B.ItemSets=nil;B.WeaponSkills=nil
    local old=C_SkillInfo;local calls={}
    C_SkillInfo={GetSkillLineInfoByID=function(id) calls[id]=true;if id==165 then return {rank=75} end end}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    B.State:Qualifications(s,{skills={[999]=true}});eq(s.skills[165],75);eq(s.skills[202],0);assert(calls[999])
    local count=0;for id in pairs(B.Trainers.skills) do assert(calls[id]);count=count+1 end;eq(count,7)
    C_SkillInfo=nil;B.State:Qualifications(s,{});eq(s.skills[165],nil);eq(B.Services.TrainerFit(s,3365),1)
    calls={};C_SkillInfo={GetSkillLineInfoByID=function(id) calls[id]=true end};s.clientBuild="other"
    B.State:Qualifications(s,{});eq(next(calls),nil)
    C_SkillInfo=old;finish()
end)

end
