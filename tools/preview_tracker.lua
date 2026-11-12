-- Executes the actual tracker UI on a small native-widget mock. Example data, never game state.
local nodes={}
local box,boxes
local function clean(s) return (s or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|T.-|t","　"):gsub("|H.-|h(.-)|h","%1") end
local function width(s,size)
    size=math.floor(size*2+0.5)/2 -- Match the 2x preview font rasterization.
    local total=0
    for c in clean(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do total=total+(#c>1 and size or size*0.55) end
    return total
end
local function widget(kind,parent)
    local w={kind=kind,parent=parent,shown=true,points={},size=12,children={}}
    nodes[#nodes+1]=w;w.id=#nodes
    if parent then parent.children[#parent.children+1]=w end
    function w:SetSize(x,y) self.width,self.height=x,y end
    function w:SetWidth(x) self.width=x end;function w:SetHeight(y) self.height=y end
    function w:GetWidth() return self.width or math.ceil(width(self.value,self.size))+2 end
    function w:GetStringWidth() return width(self.value,self.size) end
    function w:GetHeight() return self.height or self:GetStringHeight() end
    function w:SetPoint(point,a,b,c,d)
        local relative,relativePoint,x,y
        if type(a)=="table" then relative,relativePoint,x,y=a,b,c,d
        else relative,relativePoint,x,y=self.parent,point,a,b end
        self.points[#self.points+1]={point=point,relative=relative,rpoint=relativePoint or point,x=x or 0,y=y or 0}
    end
    function w:ClearAllPoints() self.points={} end
    function w:SetAllPoints(other) self.all=other or self.parent end
    function w:SetText(value) self.value=tostring(value or "") end;function w:GetText() return self.value or "" end
    function w:SetFont(_,size,flags) self.size,self.fontFlags=size,flags end
    function w:SetSpacing(value) self.spacing=value end
    function w:GetEffectiveScale() return 1 end
    function w:GetCenter()
        boxes={};local r=box(self)
        return r.x+r.w/2,UIParent:GetHeight()-r.y-r.h/2
    end
    function w:GetStringHeight()
        local count=0
        for line in (clean(self.value).."\n"):gmatch("(.-)\n") do
            local used=0
            count=count+1
            for char in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                local length=width(char,self.size)
                if used>0 and used+length>(self.width or math.huge) then count=count+1;used=0 end
                used=used+length
            end
        end
        count=self.maxLines and self.maxLines>0 and math.min(count,self.maxLines) or count
        return count*(self.size+4)+math.max(0,count-1)*(self.spacing or 0)
    end
    function w:SetTextColor(...) self.color={...} end;w.SetColorTexture=w.SetTextColor
    w.SetVertexColor=w.SetTextColor
    function w:SetTexture(path) self.texture=path end
    function w:SetHorizTile(value) self.tileX=value end
    function w:SetVertTile(value) self.tileY=value end
    function w:SetHighlightTexture(texture) texture:Hide() end
    function w:SetTexCoord(...) self.uv={...} end
    function w:SetBackdropColor(...) self.background={...} end
    function w:SetBackdropBorderColor(...) self.border={...} end
    function w:SetJustifyH(value) self.justify=value end
    function w:SetShown(value) self.shown=value end;function w:IsShown() return self.shown end
    function w:Hide() self.shown=false end;function w:Show() self.shown=true end
    function w:IsEnabled() return self.enabled~=false end
    function w:Click() if self.enabled~=false and self.scripts and self.scripts.OnClick then self.scripts.OnClick(self,"LeftButton") end end
    function w:SetParent(parent)
        for i,child in ipairs(self.parent and self.parent.children or {}) do if child==self then table.remove(self.parent.children,i);break end end
        self.parent=parent;parent.children[#parent.children+1]=self
    end
    function w:SetMaxLines(value) self.maxLines=value end
    function w:SetNonSpaceWrap(value) self.nonSpaceWrap=value end
    function w:SetScript(event,fn) self.scripts=self.scripts or {};self.scripts[event]=fn end;function w:SetEnabled(value) self.enabled=value end
    function w:GetVerticalScroll() return 0 end
    function w:SetScrollChild(child) self.scrollChild=child;child:SetPoint("TOPLEFT",self,"TOPLEFT",0,0) end
    function w:CreateTexture(_,layer) local n=widget("Texture",self);n.layer=layer;return n end
    function w:CreateFontString(_,layer) local n=widget("Text",self);n.layer=layer;return n end
    function w:CreateLine(_,layer) local n=widget("Line",self);n.layer=layer;return n end
    function w:SetThickness(value) self.thickness=value end
    function w:SetStartPoint(point,relative,x,y) self.start={point=point,relative=relative,x=x,y=y} end
    function w:SetEndPoint(point,relative,x,y) self.finish={point=point,relative=relative,x=x,y=y} end
    for _,name in ipairs({"SetResizable","SetResizeBounds","SetClampedToScreen","SetJustifyV","SetBackdrop","SetShadowColor","SetShadowOffset","SetMovable","EnableMouse","EnableMouseWheel","RegisterForDrag","SetHyperlinksEnabled",
        "SetFrameStrata","SetAlpha","SetVerticalScroll","SetFontObject","SetMultiLine","SetAutoFocus","SetTextInsets","SetMaxLetters","ClearFocus","SetFocus","HighlightText","RegisterForClicks","SetAttribute","SetScale","SetDesaturated","SetCooldown","Clear"}) do w[name]=function() end end
    return w
end
local dungeonPreview=arg[1]=="dungeon"
local planPreview=arg[1]=="plan"
local canvasWidth=(dungeonPreview or planPreview) and 1080 or 560
local canvasHeight=(dungeonPreview or planPreview) and 700 or 1100
if (arg[1]=="gear" or arg[1]=="class") and arg[2]=="large" then canvasHeight=1450 end
UIParent=widget("Root");UIParent:SetSize(canvasWidth,canvasHeight)
CreateFrame=function(kind,_,parent) return widget(kind,parent) end
if not dungeonPreview and not planPreview then
    MinimapCluster=widget("Frame",UIParent);MinimapCluster:SetSize(280,160)
    MinimapCluster:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-100,-88)
    MinimapCluster:SetBackdropColor(0.1,0.18,0.18,0.6)
    local label=MinimapCluster:CreateFontString();label:SetFont("preview",14,"")
    label:SetPoint("CENTER");label:SetText("小地图 · 对齐示意")
end
STANDARD_TEXT_FONT="preview"
InCombatLockdown=function() return false end
GameFontHighlight={}
GameTooltip={Hide=function() end}
C_Map={GetMapInfo=function() return {name="艾尔文森林"} end}
RAID_CLASS_COLORS={PALADIN={r=0.96,g=0.55,b=0.73}}
local A={settings={fontScale=1,density="normal",arrow=true,distanceUnits="meters"},char={},indexReady=true,
    state={class="PALADIN",level=8,xp=3200,maxXP=5040,runSpeed=7,position={map=1429,x=0.46,y=0.42},quests={
        [7]={title="狗头人的威胁",level=8,objectives={{text="消灭狗头人歹徒",numFulfilled=6,numRequired=10},{text="消灭狗头人苦力",numFulfilled=4,numRequired=4,finished=true}}},
        [33]={title="林中的群狼",level=9,objectives={{type="item",text="收集狼肉",numFulfilled=3,numRequired=8}}},
        [18]={title="矿工归来",level=10,ready=true,objectives={}},
        [47]={title="把收集的金砂交给治安官",level=10,objectives={{type="item",text="收集金砂",numFulfilled=5,numRequired=10}}},
    }},Selection={CanChoose=function() return true end}}
if arg[2]=="large" then A.settings.fontScale=1.2 end
local action={kind="objective",questId=7,title="狗头人的威胁",text="清理矿洞外的狗头人，完成后返回北郡修道院。",position={map=1429,x=0.5,y=0.5,entityName="北郡矿洞"}}
assert(loadfile("Navigation.lua"))("AiLeveling",A)
A.Navigation.Current=function() return action end
A.Navigation.Distance=function(_,a,b)
    if a and b and a.map==b.map and a.x and b.x then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*4000 end
end
A.plan={revision=1,unverified=true,taskChoices={},taskOrder={}}
for _,id in ipairs({7,18,33,47}) do
    local q=A.state.quests[id]
    local c={questId=id,title=q.title,kind="task",actions={{kind=q.ready and "turnin" or "objective",title=q.title}}}
    c.remainingXP=({[7]=480,[18]=760,[33]=625,[47]=900})[id]
    c.timing={seconds=({[7]=135,[18]=48,[33]=265,[47]=380})[id]}
    if id==7 then c.orderBasis="movement-xp" end
    A.plan.taskChoices[#A.plan.taskChoices+1]=c;A.plan.taskOrder[#A.plan.taskOrder+1]=c
end
for _,choice in ipairs(A.plan.taskChoices) do
    choice.stages={{kind="turnin",position={map=1429,x=0.5,y=0.5,entityKind="npc",entityId=197,entityName="治安官玛克布莱德"}}}
end
assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",A)
A.plan.taskChoices[#A.plan.taskChoices+1]={lowValue={suggestion="建议跳过"},questId=62,title="西泉要塞的委托",kind="task",
    actions={{kind="accept",title="西泉要塞的委托"}}}
A.plan.taskQueue={stagePlan=true,steps={{choice=A.plan.taskChoices[1],stage=action}}}
for _,choice in ipairs(A.plan.taskOrder) do
    if choice.questId~=7 and not A.state.quests[choice.questId].ready then
        local stage=choice.actions[1];stage.questId=choice.questId
        stage.position={map=1429,x=0.4,y=0.4,entityName=choice.questId==33 and "北郡树林" or "金砂河岸"}
        A.plan.taskQueue.steps[#A.plan.taskQueue.steps+1]={choice=choice,stage=stage}
    end
end
for _,choice in ipairs(A.plan.taskOrder) do A.plan.taskQueue.steps[#A.plan.taskQueue.steps+1]={choice=choice,stage=choice.stages[1]} end
local pickup={questId=63,title="米莉的葡萄",level=9,kind="task",remainingXP=625,timing={seconds=65},
    actions={{kind="accept",questId=63,title="米莉的葡萄",position={map=1429,x=0.48,y=0.42,entityKind="npc",entityName="米莉·奥斯沃斯"}}}}
pickup.stages=pickup.actions
A.plan.taskChoices[#A.plan.taskChoices+1]=pickup
A.plan.taskOrder[#A.plan.taskOrder+1]=pickup
A.plan.taskQueue.steps[#A.plan.taskQueue.steps+1]={choice=pickup,stage=pickup.actions[1]}
assert(loadfile("UI/Main.lua"))("AiLeveling",A)
assert(loadfile("UI/Tracker.lua"))("AiLeveling",A)
local anchors={TOPLEFT={0,0},TOP={0.5,0},TOPRIGHT={1,0},LEFT={0,0.5},CENTER={0.5,0.5},RIGHT={1,0.5},BOTTOMLEFT={0,1},BOTTOM={0.5,1},BOTTOMRIGHT={1,1}}
boxes={}
box=function(w)
    if boxes[w] then return boxes[w] end
    if w==UIParent then return {x=0,y=0,w=canvasWidth,h=canvasHeight} end
    if w.all then local value=box(w.all);boxes[w]=value;return value end
    local ww,hh=w:GetWidth(),w:GetHeight()
    local x,y=0,0
    for i,p in ipairs(w.points) do
        local relative=box(p.relative or UIParent)
        local a,b=anchors[p.point],anchors[p.rpoint]
        local rx,ry=relative.x+relative.w*b[1]+p.x,relative.y+relative.h*b[2]-p.y
        if i==1 then x,y=rx-ww*a[1],ry-hh*a[2]
        else
            if a[1]==1 then ww=rx-x end
            if a[2]==1 then hh=ry-y end
        end
    end
    local value={x=x,y=y,w=ww,h=hh};boxes[w]=value;return value
end
if dungeonPreview then
    A.ready=true;A.Content={dungeons={}}
    if arg[2]=="entry-blocked" then A.state.instanceEntryError="客户端提示近期进入实例次数过多，待限制解除后重新检查" end
    A.state.clientVersion,A.state.clientBuild,A.state.faction="1.60.1","70862","Alliance"
    A.state.level=20;A.state.raceMask=1;A.state.classMask=1
    A.state.completed={};A.state.skipped={};A.state.quests={[167]={ready=true},[166]={}}
    local quests={
        [166]={id=166,title="迪菲亚兄弟会",questLevel=22},
        [167]={id=167,title="我的兄弟……",questLevel=20},
        [168]={id=168,title="收集记忆",questLevel=18},
        [214]={id=214,title="红色丝质面罩",questLevel=17,preQuestSingle={155}},
    }
    A.Content.gearSources={}
    A.state.equipment,A.state.bags,A.state.skills={},{},{}
    A.state.items={[100]={id=100,name="示例任务奖励",usable=true,equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=7}}}
    for _,quest in pairs(quests) do quest.taskFacts={level=quest.questLevel,xp={{1,1500}},rewards={}} end
    quests[166].taskFacts.rewards.choices={{id=100,count=1}}
    A.state.position={map=1453,x=0.5,y=0.5};A.state.runSpeed=7
    C_Map.GetMapInfo=function(id) return {name=({[1453]="暴风城",[1436]="西部荒野",[9999]="死亡矿井"})[id] or "任务区域",mapType=id==9999 and 4 or 3} end
    A.Navigation.Distance=function() return 1400 end
    A.Data={content=A.Content,maps={[40]=1436,[1581]=9999},GetQuest=function(_,id) return quests[id] end,
        Target=function(_,q,state)
            local active=state.quests[q.id]
            return {map=active and not active.ready and 9999 or 1453,x=0.6,y=0.5,entityKind="npc",entityId=q.id,
                entityName=active and (active.ready and "示例交付人" or "副本目标") or "示例接取人"}
        end}
    for _,file in ipairs({"State.lua","Data/Dungeons.lua","Planner/Eligibility.lua","Planner/Travel.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua","Planner/Gear.lua","Planner/TaskGuide.lua","UI/Dungeon.lua"}) do
        assert(loadfile(file))("AiLeveling",A)
    end
    if arg[2]=="journey" then
        A.state.revision=1
        A.Data.maps={[40]=1436}
        A.Navigation.Distance=function() return nil end
        A.state.quests[166].objectives={{text="击败范克里夫",numRequired=1,numFulfilled=0}}
        A.char.taskBatch={id="reference:36",baselines={[166]=0,[167]=0,[168]=0}}
        local choices={}
        for _,id in ipairs({166,167,168}) do
            local q=quests[id]
            local first={kind=id==167 and "turnin" or id==168 and "accept" or "objective",questId=id,title=q.title,
                text=id==166 and "击败范克里夫" or "按任务日志完成目标",position={map=1429,x=0.5,y=0.5}}
            local stages=A.TaskGuide.Stages(q,A.state,A.Data,first)
            for _,stage in ipairs(stages) do if stage.kind=="objective" then stage.position=nil;stage.areaId=1581 end end
            choices[#choices+1]={questId=id,stages=stages,actions={first}}
        end
        local d=A.Dungeon.Catalog(A.state,A.Content)["reference:36"]
        A.plan={revision=1,taskChoices=choices,taskBatch={id=d.id,journey=A.Dungeon.TaskJourney(d,choices,A.state,A.Data)}}
    end
    local selected="reference:36"
    if arg[2]=="loot" then
        selected="reference:389"
        A.state.items[272998]={id=272998,name="示例首领装备",usable=true,equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=8}}
    end
    A.previewTab=4;A.previewSelected=selected
elseif planPreview then
    assert(loadfile("UI/Plan.lua"))("AiLeveling",A)
    A.state.revision=1
    A.state.quests={
        [7]={title="西部荒野人民军",objectives={{text="迪菲亚抢劫者 8/15",numFulfilled=8,numRequired=15}}},
        [18]={title="迪菲亚兄弟会",ready=true,objectives={}},
        [33]={title="雷矛的包裹",ready=true,objectives={}}}
    A.plan.taskChoices={};A.plan.taskOrder={}
    for i,id in ipairs({7,18,33}) do
        local q=A.state.quests[id]
        local stage={kind=q.ready and "turnin" or "objective",questId=id,position={entityKind="npc",entityId=id==33 and 200 or 100,entityName=id==33 and "巡山人卡尔·雷矛" or "格里安·斯托曼"}}
        local c={id="task:"..id,questId=id,title=q.title,kind="task",actions={stage},stages={{kind="turnin",position=stage.position}},remainingXP=({975,1350,950})[i],timing={seconds=({85,52,174})[i]}}
        A.plan.taskChoices[i]=c;A.plan.taskOrder[i]=c
    end
    A.plan.best=A.plan.taskChoices[1]
    A.plan.taskQueue={taskCount=3,xpKnown=true,xp=3275,steps={}}
    for _,c in ipairs(A.plan.taskOrder) do A.plan.taskQueue.steps[#A.plan.taskQueue.steps+1]={choice=c,stage=c.actions[1]} end
    A.Data={GetQuest=function(_,id) return {id=id,title=(A.state.quests[id] or {}).title} end}
    A.previewTab=1

else
if arg[1]=="journey" then
    A.Data={GetQuest=function() return nil end}
    assert(loadfile("Planner/Travel.lua"))("AiLeveling",A)
    assert(loadfile("Planner/Flights.lua"))("AiLeveling",A)
    assert(loadfile("Data/PublicTransit.lua"))("AiLeveling",A)
    local tram
    for _,leg in ipairs(A.PublicTransitData.legs) do if leg.key=="public:tram:0" then tram=leg end end
    local goal={kind="accept",questId=63,title="肮脏的爪子",text="与巡山人卡尔·雷矛交谈，接取任务。",
        position={map=1432,x=0.248,y=0.184,entityKind="npc",entityName="巡山人卡尔·雷矛"}}
    local nextGoal={kind="objective",questId=63,title="肮脏的爪子",position={map=1432,x=0.356,y=0.246,entityName="银泉矿洞"}}
    local choice={questId=63,title=goal.title,kind="task",remainingXP=1350,actions={goal},stages={goal,nextGoal}}
    A.state.level=17;A.state.position={map=1453,x=0.6,y=0.5}
    local side={kind="accept",questId=64,title="保卫国王的领土",
        position={map=1432,x=0.258,y=0.184,entityKind="npc",entityName="拉格·加玛森"}}
    local sideChoice={questId=64,title=side.title,kind="task",remainingXP=900,actions={side},stages={side}}
    local later={kind="objective",questId=65,title="西部荒野人民军",objectiveIndex=1,
        position={map=1436,x=0.45,y=0.6,entityName="月溪镇"}}
    local delivery={kind="turnin",questId=66,title="迪菲亚兄弟会",
        position={map=1436,x=0.56,y=0.47,entityKind="npc",entityId=234,entityName="格里安·斯托曼"}}
    local laterChoice={questId=65,title=later.title,kind="task",remainingXP=975,actions={later},stages={later}}
    local deliveryChoice={questId=66,title=delivery.title,kind="task",remainingXP=1350,actions={delivery},stages={delivery}}
    A.state.quests={[65]={title=later.title,objectives={{text="消灭迪菲亚抢劫者",numFulfilled=8,numRequired=15}}},
        [66]={title=delivery.title,ready=true,objectives={}}};A.state.completed={}
    C_Map.GetMapInfo=function(id) return {name=({[1453]="暴风城",[1455]="铁炉堡",[1432]="洛克莫丹",[1436]="西部荒野"})[id]} end
    -- Example cross-zone distance; transit timing comes from the shipped table.
    A.Navigation.Distance=function(_,from,to)
        if from and to then return from.map==to.map and math.sqrt((from.x-to.x)^2+(from.y-to.y)^2)*4000 or 2850 end
    end
    local actions=A.Flights.Actions({legs={tram}},goal,A.Navigation)
    A.plan={taskChoices={choice,sideChoice,laterChoice,deliveryChoice},taskOrder={choice,sideChoice,laterChoice,deliveryChoice},
        travelActions=actions,taskQueue={steps={{choice=choice,stage=goal},{choice=sideChoice,stage=side},
            {choice=choice,stage=nextGoal},{choice=laterChoice,stage=later},{choice=deliveryChoice,stage=delivery}}}}
    A.Navigation.actions,A.Navigation.index,A.Navigation.plan=actions,1,A.plan
    action=actions[1]
end
if arg[1]=="gear" or arg[1]=="class" then
    assert(loadfile("Planner/Gear.lua"))("AiLeveling",A)
    local function item(id,name,strength)
        return {id=id,name=name,link="|cff1eff00|Hitem:"..id.."|h["..name.."]|h|r",usable=true,
            equipLoc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=strength}}
    end
    -- Example attributes exercise the real comparison and widgets, not a live reward table.
    local bag=item(100,"精制链甲",6)
    local reward=item(101,"卫兵胸甲",8)
    A.state.class,A.state.role,A.state.damageStyle="PALADIN","DAMAGER","auto"
    A.state.equipment={[5]=item(99,"旧链甲",4)};A.state.bagEquipment={};A.state.bags={}
    A.Gear:ScanBagOffers(A.state)
    A.state.bagEquipment={bag};A.state.bags[100]=1;A.Gear:ScanBagOffers(A.state)
    A.QuestAssist={Requirements=function() return {} end,LayoutTarget=function() end}
    A.plan.taskChoices[1].rewardPick={item=reward,upgrade=A.Gear.Upgrade(reward,A.state)}
    if arg[1]=="gear" then
        action.kind="accept";action.text="与治安官玛克布莱德交谈，接取任务。"
        action.position.entityName="治安官玛克布莱德";A.state.quests[7]=nil
    end
end
if arg[1]=="class" then
    A.state.level,A.state.revision=22,1
    A.Data={GetQuest=function() return nil end}
    A.state.trainableSpells={{id=101,level=22,name="圣光术 · 等级 4",link="|cff9acbff|Hspell:101|h[圣光术 · 等级 4]|h|r"},
        {id=102,level=22,name="奉献 · 等级 2",link="|cff9acbff|Hspell:102|h[奉献 · 等级 2]|h|r"}}
    A.plan.taskChoices[#A.plan.taskChoices+1]={questId=1641,title="圣洁之书",level=12,kind="task",actions={},
        unlock={kind="class",spell=7328,questId=1788}}
end
A.UI:CreateTracker();A.UI:RenderTracker();A.UI:SetTrackerNavigation(285,0.25,true)
if arg[1]=="class" then
    assert(A.UI.tracker.career:IsShown() and A.UI.tracker.career.text:GetText():find("圣洁之书",1,true))
end
if arg[1]=="gear" then
    local T=A.UI.tracker
    assert(T.gear:IsShown() and T.reward:IsShown() and T.objectiveFrame:IsShown())
    assert(T.gear.text:GetText():find("+50%%") and T.reward.text:GetText():find("大幅提升",1,true))
end
if arg[1]=="journey" then
    local T=A.UI.tracker
    assert(T.journey:IsShown() and T.alongLabel:IsShown() and T.thenText:IsShown() and T.queuePanel:IsShown())
    assert(T.model.rows[1].questId==64 and T.model.rows[1].along and T.model.rows[1].status=="未接取")
    assert(T.model.rows[2].questId==65 and T.model.rows[2].status=="已接取")
    assert(T.model.rows[3].questId==66 and T.model.rows[3].status=="可交付")
end
A.UI.navFrame:ClearAllPoints();A.UI.navFrame:SetPoint("TOP",A.UI.frame,"BOTTOM",0,-54)
if arg[1]=="assist" then
    A.UI.navFrame:Hide()
    InCombatLockdown=function() return false end
    action.objectiveIndex=1
    action.position.entityKind,action.position.entityId="npc",10
    A.state.quests[7].objectives[2]={text="消灭狗头人劳工",numFulfilled=2,numRequired=8}
    action.targetKind,action.targetId="npc",10
    table.insert(A.plan.taskChoices[1].stages,1,action)
    local shared=A.plan.taskChoices[3]
    A.state.quests[33].title="矿洞守卫"
    A.state.quests[33].objectives={{text="消灭狗头人歹徒",numFulfilled=3,numRequired=8}}
    local stage=shared.actions[1];stage.objectiveIndex=1;stage.targetKind="npc";stage.targetId=10;stage.position=action.position
    table.insert(shared.stages,1,stage)
    local names={[10]="狗头人歹徒",[20]="狗头人劳工"}
    A.Data={GetQuest=function() return {id=7} end,db={Npc={Get=function(id) return names[id] end}},
        ObjectiveTargets=function() return {{objectiveIndex=1,entityKind="npc",entityId=10},{objectiveIndex=2,entityKind="npc",entityId=20}} end}
    A.state.bags={}
    assert(loadfile("QuestAssist.lua"))("AiLeveling",A)
    A.QuestAssist:Create();A.QuestAssist:Update()
    A.UI:RenderTracker()
end
end
if A.previewTab then
    for _,file in ipairs({"Plan","Gear","Chains","Services","Browser"}) do assert(loadfile("UI/"..file..".lua"))("AiLeveling",A) end
    if not A.UI.Dungeon then
        A.UI.Dungeon={Create=function(self,parent) self.frame=CreateFrame("Frame",nil,parent);self.frame:Hide() end}
    end
    A.UI.Settings={Create=function(self,parent) self.frame=CreateFrame("Frame",nil,parent);self.frame:Hide() end}
    A.settings.scale,A.settings.alpha=1,1
    A.UI:Create();A.UI.frame:Hide();A.UI.details:Show();A.UI.details:ClearAllPoints();A.UI.details:SetPoint("TOPLEFT",40,-50)
    A.UI.Dungeon.selected=A.previewSelected
    A.UI:SelectTab(A.previewTab)
    if dungeonPreview then
        local browser=A.UI.Browser
        local view=browser.dungeonDetail
        assert(view:IsShown() and not browser.detail:IsShown())
        assert(#view.rows==#browser.selected.tasks)
        local tasks={};for _,task in ipairs(browser.selected.tasks) do tasks[task.id]=task end
        for _,row in ipairs(view.rows) do
            assert(tasks[row.questId] and row.text:GetText()==tasks[row.questId].title)
            assert(row.status:GetText()~="")
        end
        assert(view.tasks:GetText():find(tostring(browser.selected.rewards.count),1,true))
        if arg[2]~="loot" then
            local pickup
            for _,row in ipairs(view.rows) do if row.questId==168 then pickup=row end end
            assert(view.rows[1]==pickup)
            assert(pickup.route.text:GetText():find("接取：暴风城 · 示例接取人",1,true))
            local navigate=A.Dungeon.ContinueTask
            local chosen
            A.Dungeon.ContinueTask=function(_,d,id) chosen=id;return true end
            pickup.route:Click();assert(chosen==168)
            A.Dungeon.ContinueTask=navigate
        end
    end
end
local function json(value)
    if type(value)=="string" then return '"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',c:byte()) end)..'"' end
    if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
    if value==nil then return "null" end
    local parts={}
    if #value>0 then for i,v in ipairs(value) do parts[i]=json(v) end;return '['..table.concat(parts,',')..']' end
    for k,v in pairs(value) do parts[#parts+1]=json(k)..':'..json(v) end
    return '{'..table.concat(parts,',')..'}'
end
boxes={}
local records={}
local function visit(w,visible,clip)
    visible=visible and w.shown
    if not visible then return end
    local rect=box(w)
    local record={kind=w.kind,rect=rect,text=w.value,size=w.size,spacing=w.spacing,color=w.color,background=w.background,border=w.border,justify=w.justify,maxLines=w.maxLines,nonSpaceWrap=w.nonSpaceWrap,clip=clip,layer=w.layer,texture=w.texture,uv=w.uv,tileX=w.tileX,tileY=w.tileY}
    if w.kind=="Line" then
        local function point(p)
            local r=box(p.relative);local a=anchors[p.point]
            return {r.x+r.w*a[1]+p.x,r.y+r.h*a[2]-p.y}
        end
        record.start,record.finish,record.thickness=point(w.start),point(w.finish),w.thickness
    end
    records[#records+1]=record
    local children={};for _,child in ipairs(w.children) do children[#children+1]=child end
    table.sort(children,function(a,b)
        local order={BACKGROUND=0,ARTWORK=1,OVERLAY=3}
        local aa,bb=order[a.layer] or 2,order[b.layer] or 2
        return aa==bb and a.id<b.id or aa<bb
    end)
    for _,child in ipairs(children) do visit(child,visible,w.kind=="ScrollFrame" and rect or clip) end
end
visit(UIParent,true)
io.write(json(records))
