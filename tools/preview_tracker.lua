-- Executes the actual tracker UI on a small native-widget mock. Example data, never game state.
local nodes={}
local function clean(s) return (s or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|T.-|t","　") end
local function width(s,size)
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
    function w:SetFont(_,size) self.size=size end
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
        return count*(self.size+4)
    end
    function w:SetTextColor(...) self.color={...} end;w.SetColorTexture=w.SetTextColor
    w.SetVertexColor=w.SetTextColor
    function w:SetTexture(path) self.texture=path end
    function w:SetTexCoord(...) self.uv={...} end
    function w:SetBackdropColor(...) self.background={...} end
    function w:SetBackdropBorderColor(...) self.border={...} end
    function w:SetJustifyH(value) self.justify=value end
    function w:SetShown(value) self.shown=value end;function w:IsShown() return self.shown end
    function w:Hide() self.shown=false end;function w:Show() self.shown=true end
    function w:SetScript() end;function w:SetEnabled(value) self.enabled=value end
    function w:SetScrollChild(child) self.scrollChild=child;child:SetPoint("TOPLEFT",self,"TOPLEFT",0,0) end
    function w:CreateTexture(_,layer) local n=widget("Texture",self);n.layer=layer;return n end
    function w:CreateFontString(_,layer) local n=widget("Text",self);n.layer=layer;return n end
    function w:CreateLine(_,layer) local n=widget("Line",self);n.layer=layer;return n end
    function w:SetThickness(value) self.thickness=value end
    function w:SetStartPoint(point,relative,x,y) self.start={point=point,relative=relative,x=x,y=y} end
    function w:SetEndPoint(point,relative,x,y) self.finish={point=point,relative=relative,x=x,y=y} end
    for _,name in ipairs({"SetJustifyV","SetBackdrop","SetShadowColor","SetShadowOffset","SetMovable","EnableMouse","EnableMouseWheel","RegisterForDrag","SetMaxLines",
        "RegisterForClicks","SetAttribute","SetScale","SetDesaturated","SetCooldown","Clear"}) do w[name]=function() end end
    return w
end
local dungeonPreview=arg[1]=="dungeon"
local canvasWidth=dungeonPreview and 860 or 560
local canvasHeight=dungeonPreview and 700 or arg[1]=="assist" and 240 or 1100
UIParent=widget("Root");UIParent:SetSize(canvasWidth,canvasHeight)
CreateFrame=function(kind,_,parent) return widget(kind,parent) end
STANDARD_TEXT_FONT="preview"
C_Map={GetMapInfo=function() return {name="艾尔文森林"} end}
RAID_CLASS_COLORS={PALADIN={r=0.96,g=0.55,b=0.73}}
local A={settings={fontScale=1,density="normal",arrow=true,distanceUnits="meters"},char={},indexReady=true,
    state={class="PALADIN",level=8,xp=3200,maxXP=5040,position={map=1429},quests={
        [7]={title="狗头人的威胁",objectives={{text="消灭狗头人歹徒",numFulfilled=6,numRequired=10}}},
        [33]={title="林中的群狼",objectives={{text="收集狼肉",numFulfilled=3,numRequired=8}}},
        [18]={title="矿工归来",ready=true,objectives={}},
        [47]={title="把收集的金砂交给治安官",objectives={{numFulfilled=5,numRequired=10}}},
    }},Selection={CanChoose=function() return true end}}
if not dungeonPreview and arg[2]=="large" then A.settings.fontScale=1.2 end
local action={kind="objective",questId=7,title="狗头人的威胁",text="清理矿洞外的狗头人，完成后返回北郡修道院。",position={map=1429,x=0.5,y=0.5}}
assert(loadfile("Navigation.lua"))("AiLeveling",A)
A.Navigation.Current=function() return action end
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
A.plan.taskQueue={stagePlan=true}
assert(loadfile("UI/Main.lua"))("AiLeveling",A)
assert(loadfile("UI/Tracker.lua"))("AiLeveling",A)
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
    A.Data={content=A.Content,GetQuest=function(_,id) return quests[id] end,
        Target=function(_,q) return {map=1429,x=0.5,y=0.5,entityKind="npc",entityId=q.id,entityName="任务交付人"} end}
    for _,file in ipairs({"State.lua","Data/Dungeons.lua","Planner/Eligibility.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua","Planner/Gear.lua","Planner/TaskGuide.lua","UI/Dungeon.lua"}) do
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
    local panel=A.UI:Panel(nil,UIParent,780,560);panel:SetPoint("TOPLEFT",40,-88)
    local mark=panel:CreateTexture(nil,"ARTWORK");mark:SetTexture("Interface\\AddOns\\AiLeveling\\Media\\compass.tga")
    mark:SetSize(28,28);mark:SetPoint("TOPLEFT",18,-12);mark:SetVertexColor(A.UI:Accent())
    local title=A.UI:Text(panel,20);title:SetPoint("TOPLEFT",54,-16);title:SetText("AiLeveling · 副本任务")
    local close=A.UI:Button(panel,"关闭",50,function() end);close:SetPoint("TOPRIGHT",-12,-12)
    for i,label in ipairs({"行程","任务链","装备","副本","设置","数据","服务"}) do
        local tab=A.UI:Button(panel,label,72,function() end);tab:SetPoint("TOPLEFT",16+(i-1)*78,-52)
        if i==4 then local r,g,b=A.UI:Accent();tab:SetBackdropColor(r*0.24,g*0.24,b*0.24,1);tab.text:SetTextColor(r,g,b)
        else tab:SetBackdropColor(0,0,0,0);tab.text:SetTextColor(0.74,0.79,0.86) end
    end
    A.UI.Dungeon:Create(panel);A.UI.Dungeon.selected=selected;A.UI.Dungeon:Refresh();A.UI.Dungeon.frame:Show()
    local scroll=CreateFrame("ScrollFrame",nil,panel);scroll:SetPoint("TOPLEFT",18,-A.UI.Dungeon.bodyTop);scroll:SetSize(476,560-A.UI.Dungeon.bodyTop-18)
    local child=CreateFrame("Frame",nil,scroll);child:SetSize(474,500);scroll:SetScrollChild(child)
    local text=A.UI:Text(child,16,{0.97,0.98,1});text:SetPoint("TOPLEFT");text:SetWidth(466)
    text:SetText(table.concat(A.UI.Dungeon:Lines(),"\n\n"))
else
A.UI:CreateTracker();A.UI:RenderTracker();A.UI:SetTrackerNavigation(285,0.25,true)
A.UI.frame:ClearAllPoints();A.UI.frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",100,-88)
A.UI.navFrame:ClearAllPoints();A.UI.navFrame:SetPoint("TOP",A.UI.frame,"BOTTOM",0,-54)
if arg[1]=="assist" then
    A.UI.frame:Hide();A.UI.navFrame:Hide()
    InCombatLockdown=function() return false end
    action.objectiveIndex=1
    action.position.entityKind,action.position.entityId="npc",10
    A.state.quests[7].objectives[2]={text="消灭狗头人劳工",numFulfilled=2,numRequired=8}
    local names={[10]="狗头人歹徒",[20]="狗头人劳工"}
    A.Data={GetQuest=function() return {id=7} end,db={Npc={Get=function(id) return names[id] end}},
        ObjectiveTargets=function() return {{objectiveIndex=1,entityKind="npc",entityId=10},{objectiveIndex=2,entityKind="npc",entityId=20}} end}
    A.state.bags={}
    assert(loadfile("QuestAssist.lua"))("AiLeveling",A)
    A.QuestAssist:Create();A.QuestAssist:Update()
    A.QuestAssist.targetButton:ClearAllPoints();A.QuestAssist.targetButton:SetPoint("TOPLEFT",110,-100)
end
end
local anchors={TOPLEFT={0,0},TOP={0.5,0},TOPRIGHT={1,0},LEFT={0,0.5},CENTER={0.5,0.5},RIGHT={1,0.5},BOTTOMLEFT={0,1},BOTTOM={0.5,1},BOTTOMRIGHT={1,1}}
local boxes={}
local function box(w)
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
local function json(value)
    if type(value)=="string" then return '"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',c:byte()) end)..'"' end
    if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
    if value==nil then return "null" end
    local parts={}
    if #value>0 then for i,v in ipairs(value) do parts[i]=json(v) end;return '['..table.concat(parts,',')..']' end
    for k,v in pairs(value) do parts[#parts+1]=json(k)..':'..json(v) end
    return '{'..table.concat(parts,',')..'}'
end
local records={}
local function visit(w,visible,clip)
    visible=visible and w.shown
    if not visible then return end
    local rect=box(w)
    local record={kind=w.kind,rect=rect,text=w.value,size=w.size,color=w.color,background=w.background,border=w.border,justify=w.justify,clip=clip,layer=w.layer,texture=w.texture,uv=w.uv}
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
