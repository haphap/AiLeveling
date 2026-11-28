local _,A=...
-- The main window: one list and one detail pane, backed by the existing task models.
A.UI.Browser={selection={}}
local B=A.UI.Browser
local gold,blue,green,muted=A.UI.hex.gold,A.UI.hex.blue,A.UI.hex.green,A.UI.hex.muted
local colors=A.UI.colors
local metrics=A.UI.metrics
local function color(c,s) return "|cff"..c..tostring(s).."|r" end
local function questLink(id,title,level,dimmed)
    local link="|Hquest:"..id..":0|h["..title.."]|h"
    if level then
        local r,g,b=A.UI.DungeonQuestColor(level,dimmed)
        return color(string.format("%02x%02x%02x",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5)),link)
    end
    return A.UI.QuestName(link,dimmed)
end
local function itemLink(item)
    if item.link then return item.link end
    local name=item.name
    if A.QuestItemZhCN then name=A.QuestItemZhCN(item.id,name) end
    return color(blue,"|Hitem:"..item.id.."|h["..(name or "物品 #"..item.id).."]|h")
end
local function skillName(id)
    return A.Trainers and A.Trainers.skills[id] or ({[164]="锻造",[171]="炼金",[182]="草药学",[186]="采矿",[356]="钓鱼",[762]="骑术"})[id] or "专业 #"..id
end
local function rewardLines(q)
    local result,seen={},{}
    local rewards=q and q.taskFacts and q.taskFacts.rewards or {}
    local mount=q and q.taskFacts and q.taskFacts.mountReward
    if mount then
        seen[mount]=true
        local info=C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(mount)
        result[#result+1]=color(gold,"坐骑  |Hspell:"..mount.."|h["..(info and info.name or "坐骑技能 #"..mount).."]|h")
    end
    for _,key in ipairs({"spell","spellCast"}) do
        local id=rewards[key]
        if id and id>0 and not seen[id] then
            seen[id]=true
            local info=C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
            result[#result+1]=color(gold,(key=="spell" and "学习：" or "获得：").."|Hspell:"..id.."|h["..(info and info.name or "技能 #"..id).."]|h")
        end
    end
    for _,key in ipairs({"items","choices"}) do
        local links={}
        for _,item in ipairs(rewards[key] or {}) do
            local name=A.Items.DisplayName(item.id)
            links[#links+1]=itemLink({id=item.id,name=name})..((item.count or 1)>1 and " ×"..item.count or "")
        end
        if #links>0 then result[#result+1]=color(muted,key=="choices" and "可选奖励" or "奖励").."    "..table.concat(links,"  ") end
    end
    return result
end

local function enableDetailLinks(frame)
    frame:SetHyperlinksEnabled(true)
    frame:SetScript("OnHyperlinkClick",function(owner,link,text,button)
        if link=="ailregionmap:select" then B:OpenRegionMapMenu(owner);return end
        local chain=tonumber(link:match("^ailchain:(%d+)$"))
        if chain then A.UI.Chains:Focus(chain);return end
        local source=link:match("^ailquesturl:(%d+)$")
        if source then
            local locale=GetLocale()=="zhCN" and "cn" or "www"
            A.UI:ShowText("https://"..locale..".wowhead.com/forever/quest="..source,"Wowhead 任务链接")
            return
        end
        local id=tonumber(link:match("^quest:(%d+)"))
        if id then A.UI:QuestClick(id,button) elseif SetItemRef then SetItemRef(link,text,button) end
    end)
    frame:SetScript("OnHyperlinkEnter",function(f,link)
        if link:match("^ailquesturl:") or link:match("^ailchain:") then return end
        GameTooltip:SetOwner(f,"ANCHOR_RIGHT")
        if link=="ailregionmap:select" then GameTooltip:SetText("切换任务地图") else GameTooltip:SetHyperlink(link) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
end

function B:Create(parent)
    self.frame=CreateFrame("Frame",nil,parent);self.frame:SetPoint("TOPLEFT",194,-88);self.frame:SetSize(784,490)
    local divider=self.frame:CreateTexture(nil,"BACKGROUND")
    divider:SetPoint("TOPLEFT",410,0);divider:SetPoint("BOTTOMLEFT",410,0);divider:SetWidth(1)
    divider:SetColorTexture(unpack(colors.line));self.divider=divider
    self.summary=A.UI:Text(self.frame,"body",colors.muted);self.summary:SetPoint("TOPLEFT");self.summary:SetWidth(392)
    self.search=A.UI:Input(self.frame,{search=true})
    self.search:SetPoint("TOPLEFT",0,-32);self.search:SetSize(392,28);self.search:SetAutoFocus(false)
    A.UI:RegisterFont(self.search,"body")
    self.search:SetTextColor(unpack(colors.white))
    self.searchHint=A.UI:Text(self.frame,"caption",colors.muted);self.searchHint:SetPoint("TOPLEFT",A.UI.daylight and 26 or 10,-38);self.searchHint:SetText("搜索名称或任务编号")
    self.search:SetScript("OnEscapePressed",function(box) box:SetText("");box:ClearFocus() end)
    local onTextChanged=function(box)
        local query=box:GetText():lower()
        if self.query==query then return end
        self.query=query;self.searchHint:SetShown(query=="")
        self.selected=nil
        if self.mode then self.list:SetVerticalScroll(0);self:Refresh(self.mode,true) end
    end
    if A.UI.daylight then self.search:HookScript("OnTextChanged",onTextChanged)
    else self.search:SetScript("OnTextChanged",onTextChanged) end
    self.list=CreateFrame("ScrollFrame",nil,self.frame,"UIPanelScrollFrameTemplate")
    self.list:SetPoint("TOPLEFT",0,-70);self.list:SetSize(382,420)
    self.child=CreateFrame("Frame",nil,self.list);self.child:SetSize(382,460);self.list:SetScrollChild(self.child)
    self.list:HookScript("OnVerticalScroll",function(_,offset) self:DrawRows(offset) end)
    self.questHeader=CreateFrame("Frame",nil,self.frame)
    enableDetailLinks(self.questHeader)
    self.info=CreateFrame("ScrollFrame",nil,self.frame,"UIPanelScrollFrameTemplate")
    self.info:SetPoint("TOPLEFT",434,-14);self.info:SetSize(326,368)
    self.infoChild=CreateFrame("Frame",nil,self.info);self.infoChild:SetSize(330,382);self.info:SetScrollChild(self.infoChild)
    enableDetailLinks(self.infoChild)
    self.title=A.UI:Text(self.infoChild,"title",colors.white);self.title:SetPoint("TOPLEFT");self.title:SetWidth(326)
    self.detail=A.UI:Text(self.infoChild,"body",colors.white);self.detail:SetWidth(326)
    self.goals=CreateFrame("Frame",nil,self.infoChild)
    self.goalHeading=A.UI:Text(self.infoChild,"caption",colors.muted);self.goalHeading:SetText("任务目标")
    self.buttons={}
    for i=1,5 do
        local create=i==1 and A.UI.Button or A.UI.ListButton
        local b=create(A.UI,self.infoChild,"",330,function() local f=self.buttons[i].run;if f then f() end end,"body")
        b.text:SetWordWrap(true)
        self.buttons[i]=b
    end
    self.levelFilter=A.UI:ListButton(self.frame,"",190,function()
        self.levelOnly=not self.levelOnly;self.list:SetVerticalScroll(0);self:Refresh(4,true)
    end,"caption")
    self.levelFilter:SetPoint("TOPLEFT",0,-100);self.levelFilter:SetHeight(26);self.levelFilter:Hide()
    self.rows={};self.frame:Hide()
end

-- Membership comes from the database. Eligibility and progress are evaluated against the live character.
function B:CatalogQuests(mode,state)
    local ids=A.Data.ids
    local cache=self.catalog
    if not cache or cache.ids~=ids or cache.race~=state.raceMask or cache.class~=state.class or cache.mask~=state.classMask then
        cache={ids=ids,race=state.raceMask,class=state.class,mask=state.classMask}
        self.catalog=cache
    end
    if cache[mode] then return cache[mode] end
    local quests={}
    local enums=A.Data.db and A.Data.db.Enum or {}
    local professions={}
    for key in pairs(enums.professionKeys or {}) do
        local sort=(enums.sortKeys or {})[key]
        if sort then professions[sort]=true end
    end
    for _,id in ipairs(ids or {}) do
        if mode~=11 or self.mountQuests[id] then
            local q=A.Data:GetQuest(id)
            if q and A.Eligibility.InMask(q.requiredRaces,state.raceMask)==true and A.Eligibility.InMask(q.requiredClasses,state.classMask)==true then
                if mode==11 or mode==9 and A.TaskGuide.IsClassQuest(q,state,A.Data) or
                    mode==8 and (q.requiredSkill or q.requiredRanks or professions[q.zoneOrSort]) then
                    quests[#quests+1]=q
                end
            end
        end
    end
    cache[mode]=quests
    return quests
end

function B:IsCareerChoice(choice)
    return choice.unlock and choice.unlock.kind=="class" or
        (A.Data.db or A.indexReady) and A.TaskGuide and A.TaskGuide.IsClassQuest and A.TaskGuide.IsClassQuest(A.Data:GetQuest(choice.questId,A.state),A.state,A.Data)
end

function B:TaskRows(mode)
    local rows,seen={},{}
    local state=A.state
    local action=mode==1 and A.Navigation:Current()
    local currentId=action and action.questId
    local requested=mode==1 and tonumber((A.UI.Plan.key or ""):match("^q:(%d+)$"))
    local currentLabel=A.char.paused and "已暂停" or A.char.locked and "已锁定" or
        A.char.regionTarget and "区域规划" or A.char.taskBatch and "整组指引" or "推荐先做"
    local function add(choice,q)
        local id=choice.questId
        if seen[id] then return end
        local complete=(state.completed or {})[id] and not state.quests[id]
        if complete then q=q or A.Data:GetQuest(id,state);complete=not (q and q.repeatable) end
        local skipped=(A.char.skipped or {})[id]
        if id~=requested and not skipped and (complete or mode==1 and self:IsCareerChoice(choice)) then return end
        seen[id]=true
        local status=complete and "已交付" or A.UI.QuestStatus(state,id,A.plan)
        local allowed,why,pre=true
        if q then allowed,why,pre=A.Eligibility.Check(q,state,A.Data) end
        if complete then allowed,why,pre=false,nil,nil end
        if skipped then allowed,why,pre=false,skipped=="ignored" and "已忽略" or "已暂缓",nil
        elseif not allowed and status=="未接取" then status=why end
        local c=status=="可交付" and green or state.quests[id] and A.UI.hex.white or allowed and gold or muted
        local meta={color(c,status)}
        if skipped then table.insert(meta,1,color(muted,why))
        elseif id==currentId then table.insert(meta,1,color(gold,currentLabel)) end
        if choice.revisitLevel then meta[#meta+1]=color(muted,choice.revisitLevel.."级回访") end
        if choice.unlock then meta[#meta+1]=color(gold,A.TaskGuide.UnlockText(choice.unlock)) end
        if q and q.requiredLevel then meta[#meta+1]="接取 "..q.requiredLevel.."级" end
        if choice.remainingXP then meta[#meta+1]=color(gold,choice.remainingXP.." 经验") end
        if q and q.requiredSkill then
            meta[#meta+1]=skillName(q.requiredSkill[1]).." "..(state.skills[q.requiredSkill[1]] or 0).."/"..q.requiredSkill[2]
        end
        rows[#rows+1]={key="q:"..id,title=choice.title or q and q.title or "任务 #"..id,sub=table.concat(meta," · "),
            icon=complete and "done" or A.UI.QuestIcon(status=="可交付" and "turnin" or state.quests[id] and "objective" or "accept",
                id==currentId and action or choice.executionAction,state.quests[id] and state.quests[id].objectives),
            dimmed=skipped or complete or (not allowed and not state.quests[id]),
            choice=choice,q=q,allowed=allowed,reason=why,prerequisite=pre,questId=id,current=id==currentId and not skipped}
    end
    local choices={}
    for _,c in ipairs(A.plan and A.plan.taskChoices or {}) do choices[c.questId]=c end
    if mode==1 then
        if choices[currentId] then add(choices[currentId]) end
        for _,c in ipairs(A.UI.Plan.Rows(A.plan)) do
            if not c.questId then rows[#rows+1]={key=c.id,title=c.title,sub="地下城 · "..(c.recommendation or (c.requiresAcceptance and "可选建议" or "进行中")),icon="entry",dungeonCandidate=c} end
        end
        for _,c in ipairs(A.plan and A.plan.taskOrder or {}) do add(c) end
        for _,c in ipairs(A.plan and A.plan.taskChoices or {}) do add(c) end
        local ids={};for id in pairs(state.quests or {}) do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids) do add({id="task:"..id,questId=id,title=state.quests[id].title,kind="task",actions={}}) end
        local deferred={}
        for id in pairs(A.char.skipped or {}) do if not seen[id] then deferred[#deferred+1]=id end end
        table.sort(deferred)
        for _,id in ipairs(deferred) do add({id="task:"..id,questId=id,kind="task",actions={}},A.Data:GetQuest(id,state)) end
        if requested and not seen[requested] then
            local q=A.Data:GetQuest(requested,state)
            add({id="task:"..requested,questId=requested,kind="task",actions={}},q)
            if not q then rows[#rows].allowed=false;rows[#rows].reason="暂无这项任务的详细资料。" end
        end
    else
        -- An unlock chain may start with a shared, unrestricted prerequisite.
        if mode==9 then
            for _,c in ipairs(A.plan and A.plan.taskChoices or {}) do
                if c.unlock and c.unlock.kind=="class" then
                    local q=A.Data:GetQuest(c.questId)
                    if q then add(c,q) end
                end
            end
        end
        for _,q in ipairs(self:CatalogQuests(mode,state)) do
            add(choices[q.id] or {id="task:"..q.id,kind="task",questId=q.id,title=q.title,level=q.questLevel,actions={},
                remainingXP=A.TaskGuide.XP(q,state.level,state)},q)
        end
        table.sort(rows,function(a,b)
            if a.allowed~=b.allowed then return a.allowed end
            local heldA,heldB=state.quests[a.questId]~=nil,state.quests[b.questId]~=nil
            if heldA~=heldB then return heldA end
            if (a.choice.unlock~=nil)~=(b.choice.unlock~=nil) then return a.choice.unlock~=nil end
            local al,bl=a.q.requiredLevel or 0,b.q.requiredLevel or 0
            if al~=bl then return al<bl end
            return a.questId<b.questId
        end)
    end
    return rows
end

function B:DungeonRows()
    local rows,targets={},{}
    local entries=A.Dungeon.Catalog()
    local state,batch=A.state,A.char and A.char.taskBatch
    local ranks={}
    if A.plan and A.plan.revision==state.revision and A.settings.dungeons~=false then
        for rank,candidate in ipairs(A.plan.dungeonChoices or {}) do ranks[candidate.dungeonId]=rank end
    end
    for id,d in pairs(entries) do
        local tasks=A.Dungeon.Tasks(d,state,A.Data,targets)
        local rewards=A.Dungeon.TaskRewards(tasks)
        local range=A.DungeonCatalog.recommendedLevels and A.DungeonCatalog.recommendedLevels[d.instanceId]
        local low,high=range and range[1],range and range[2]
        local levels=low and string.format("推荐 %d—%d级",low,high) or "查看任务"
        local sub=levels.." · "..color(gold,rewards.count.."项任务")
        local here=state.inInstance and state.instanceId==d.instanceId
        local selected=batch and batch.id==id
        local priority=here and 1 or selected and 2 or ranks[id] and 3 or 5
        if here or selected then sub=color(green,here and "当前副本" or "整组指引中").." · "..sub
        elseif not ranks[id] then
            for _,task in ipairs(tasks) do
                if state.quests[task.id] then priority=4;break end
                for _,id in ipairs(task.preparation or {}) do
                    if state.quests[id] then priority=4;break end
                end
                if priority==4 then break end
            end
        end
        rows[#rows+1]={key=id,title=d.title,sub=sub,icon="entry",dungeon=d,tasks=tasks,rewards=rewards,levels=levels,low=low or math.huge,
            availableRewards=ranks[id] and A.plan.dungeonChoices[ranks[id]].availableRewards,
            priority=priority,rank=ranks[id],levelGap=low and math.max(0,low-state.level,state.level-high) or math.huge}
    end
    table.sort(rows,function(a,b)
        if a.priority~=b.priority then return a.priority<b.priority end
        if a.rank and b.rank and a.rank~=b.rank then return a.rank<b.rank end
        if a.levelGap~=b.levelGap then return a.levelGap<b.levelGap end
        local av,bv=a.rewards.count>0,b.rewards.count>0
        if av~=bv then return av end
        if a.low~=b.low then return a.low<b.low end
        return a.title<b.title
    end)
    return rows
end

-- Geographic quest-log categories are useful even when the route planner has no outdoor visit.
function B:RegionCatalog()
    local data,state=A.Data,A.state
    if not A.indexReady or not data.byArea then return {} end
    local cache=self.regionCatalog
    if cache and cache.index==data.byArea and cache.race==state.raceMask and cache.class==state.classMask then return cache.maps end
    local maps={}
    for area,ids in pairs(data.byArea) do
        local map=data.maps and data.maps[area]
        local info=map and map>0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        if info and info.name and info.mapType==3 and not A.Dungeon.TaskInstance(nil,state,data,area)
            and not A.Dungeon.TaskPvP(nil,state,data,area) then
            for _,id in ipairs(ids) do
                local q=data:GetQuest(id)
                if q and not (q.taskFacts and q.taskFacts.hidden) and A.Eligibility.InMask(q.requiredRaces,state.raceMask)
                    and A.Eligibility.InMask(q.requiredClasses,state.classMask) then
                    local zone=maps[map]
                    if not zone then zone={title=info.name,quests={}};maps[map]=zone end
                    zone.quests[#zone.quests+1]=q
                end
            end
        end
    end
    for _,zone in pairs(maps) do
        table.sort(zone.quests,function(a,b)
            local al,bl=a.questLevel or 0,b.questLevel or 0
            if al~=bl then return al<bl end
            return a.id<b.id
        end)
    end
    self.regionCatalog={index=data.byArea,race=state.raceMask,class=state.classMask,maps=maps}
    return maps
end

function B:RegionRows()
    local rows,seen={},{}
    local catalog=self:RegionCatalog()
    local here=A.state.position and A.state.position.map
    local regions=not A.state.inInstance and A.plan and A.plan.regions
    for _,r in ipairs(regions or {}) do
        local revisits=#(r.revisit or {})
        if #r.choices>0 or revisits>0 then
            seen[r.map]=true
            local sub=string.format("本轮 %d 项任务 · 经验 %s",#r.choices,color(gold,A.UI.DungeonXPText(r)))
            rows[#rows+1]={key="map:"..r.map,title=r.title,icon="location",region=r,catalogZone=catalog[r.map],
                sub=sub..(r.map==here and " · 当前区域" or "")..(revisits>0 and (" · 回访 "..revisits.." 项") or "")}
        end
    end
    local target=A.char.regionTarget
    if target and not catalog[target.map] and not seen[target.map] then
        rows[#rows+1]={key="map:"..target.map,map=target.map,title=target.title,icon="location",sub="区域规划中"}
    end
    local other={}
    for map,zone in pairs(catalog) do
        if not seen[map] then
            other[#other+1]={key="map:"..map,title=zone.title,icon="location",catalogZone=zone,map=map,
                sub=(target and target.map==map and "区域规划中 · " or map==here and "当前区域 · " or "").."收录 "..#zone.quests.." 项任务"}
        end
    end
    table.sort(other,function(a,b)
        if target and (a.map==target.map)~=(b.map==target.map) then return a.map==target.map end
        if (a.map==here)~=(b.map==here) then return a.map==here end
        if a.title~=b.title then return a.title<b.title end
        return a.map<b.map
    end)
    for _,row in ipairs(other) do rows[#rows+1]=row end
    return rows
end

function B:ClearSearch()
    if self.query and self.query~="" then
        self.query=""
        self.search:SetText("")
        self.searchHint:Show()
        self.list:SetVerticalScroll(0)
    end
end

function B:Refresh(mode,reuse,opening)
    gold,blue,green,muted=A.UI.hex.gold,A.UI.hex.blue,A.UI.hex.green,A.UI.hex.muted
    reuse=reuse and self.mode==mode and self.entriesRevision==A.state.revision and self.entriesPlan==A.plan
    if mode==10 and self.entriesIndexReady~=A.indexReady then reuse=false end
    local scale=A.UI:FontScale()
    local modeChanged=self.mode~=mode
    if modeChanged then self.message=nil end
    if modeChanged or self.layoutScale~=scale then
        self.layoutScale=scale
        local listWidth=mode==4 and 204 or 232
        local split=listWidth+24
        self.frame:ClearAllPoints();self.frame:SetPoint("TOPLEFT",metrics.detailInset,-metrics.guidePadding);self.frame:SetSize(1000-metrics.detailInset-metrics.guidePadding,600-2*metrics.guidePadding)
        local searchY=math.ceil(A.UI.detailHeading:GetStringHeight())+metrics.guidePadding
        local searchHeight=math.max(metrics.button,math.ceil(metrics.hit*scale))
        local summaryY=searchY+searchHeight+metrics.gap
        self.summary:ClearAllPoints();self.summary:SetPoint("TOPLEFT",0,-summaryY)
        self.summary:SetWidth(listWidth);self.summary:SetJustifyH("LEFT")
        self.search:ClearAllPoints();self.search:SetPoint("TOPLEFT",0,-searchY);self.search:SetSize(listWidth,searchHeight)
        self.searchHint:ClearAllPoints();self.searchHint:SetPoint("LEFT",self.search,"LEFT",A.UI.daylight and 26 or 10,0)
        self.searchHint:SetText(({[4]="搜索地下城名称",[10]="搜索区域名称"})[mode] or "搜索任务名称或编号")
        self.levelFilter:SetShown(mode==4)
        local listY=summaryY+math.ceil(metrics.hit*scale)
        if mode==4 then
            self.levelFilter:ClearAllPoints();self.levelFilter:SetPoint("TOPLEFT",0,-listY)
            self.levelFilter:SetHeight(searchHeight);listY=listY+searchHeight+metrics.tight
        end
        self.list:ClearAllPoints();self.list:SetPoint("TOPLEFT",0,-listY)
        self.list:SetSize(listWidth,self.frame:GetHeight()-listY);self.child:SetWidth(listWidth)
        self.divider:ClearAllPoints();self.divider:SetPoint("TOPLEFT",split,0);self.divider:SetPoint("BOTTOMLEFT",split,0)
        self.questHeader:ClearAllPoints();self.questHeader:SetPoint("TOPLEFT",split+metrics.guidePadding,0)
        local right=self.frame:GetWidth()-split-metrics.guidePadding-40
        self.questHeader:SetWidth(right);self.info:SetWidth(right);self.infoChild:SetWidth(right)
        self.title:SetWidth(right-28);self.detail:SetWidth(right)
        if modeChanged then self.list:SetVerticalScroll(0);self.info:SetVerticalScroll(0) end
    end
    self.mode=mode
    local requested=mode==4 and A.UI.Dungeon.selected
    if requested then
        A.UI.Dungeon.selected=nil
        self.levelOnly=false
        self.selection[4]=requested
        self:ClearSearch()
        if self.dungeonDetail then self.dungeonDetail.showLoot=false end
    end
    local rows
    if reuse then rows=self.entries
    elseif mode==4 then rows=self:DungeonRows()
    elseif mode==10 then rows=self:RegionRows()
    else
        if mode==11 then self:IndexMounts() end
        rows=self:TaskRows(mode)
    end
    self.entries=rows
    self.entriesIndexReady=A.indexReady
    self.entriesRevision,self.entriesPlan=A.state.revision,A.plan
    if self.query and self.query~="" then
        local filtered={}
        for _,row in ipairs(rows) do
            local id=row.questId
            if row.title:lower():find(self.query,1,true) or id and tostring(id):find(self.query,1,true) then filtered[#filtered+1]=row end
        end
        rows=filtered
    end
    if mode==4 then
        self.levelFilter.text:SetText(self.levelOnly and "适级副本  ·  查看全部 ›" or "全部副本  ·  只看适级 ›")
        if self.levelOnly then
            local matched={}
            for _,entry in ipairs(rows) do if entry.levelGap==0 then matched[#matched+1]=entry end end
            rows=matched
        end
    end
    local key=self.selection[mode]
    if mode==1 then
        key=A.UI.Plan.key
        if not key then for _,row in ipairs(rows) do if row.current then key=row.key;break end end end
    end
    local selectedIndex=1
    for i,row in ipairs(rows) do if row.key==key then selectedIndex=i;break end end
    local previousKey=self.selected and self.selected.key
    self.selected=rows[selectedIndex]
    if mode==1 then A.UI.Plan.preview=self.selected and self.selected.choice end
    local summary=#rows..(mode==10 and " 个练级区域" or mode==4 and " 个地下城" or " 项任务")
    if mode==1 then
        local status=A.char.paused and "引导已暂停" or A.char.locked and "单任务锁定" or
            A.Navigation.manual and "手动导航" or A.char.taskBatch and "副本任务安排" or
            A.char.regionTarget and ("区域规划 · "..A.char.regionTarget.title) or A.char.gearTarget and "装备目标" or "自动安排"
        summary=status.." · "..#rows.." 项可查看"
    end
    if mode==10 and #rows==0 and #self.entries==0 then
        summary=A.error and "区域资料不可用" or not A.indexReady and "正在载入区域目录…" or "暂无区域资料"
    elseif #rows==0 and self.query and self.query~="" then
        summary="没有匹配的"..(({[4]="地下城",[10]="练级区域"})[mode] or "任务")
    end
    self.summary:SetText(summary)
    self.filtered=rows
    self.rowPitch=math.ceil((metrics.hit+18+metrics.tight)*scale)
    local height=math.max(1,#rows*self.rowPitch)
    self.child:SetHeight(height)
    local offset=math.min(self.list:GetVerticalScroll(),math.max(0,height-self.list:GetHeight()))
    if self.selected and (opening or requested or previousKey~=self.selected.key) then
        offset=math.max(0,math.min(offset,(selectedIndex-1)*self.rowPitch))
        offset=math.max(offset,selectedIndex*self.rowPitch-self.list:GetHeight())
        self.info:SetVerticalScroll(0)
    end
    if offset~=self.list:GetVerticalScroll() then self.list:SetVerticalScroll(offset) end
    self:DrawRows(offset)
    self:Detail()
end

local function markRow(row,selected)
    row.baseColor=selected and colors.selected or colors.panel
    row:SetBackdropColor(unpack(row.baseColor))
    row.marker:SetShown(selected)
end

function B:DrawRows(offset)
    local rows,pitch=self.filtered,self.rowPitch
    if not rows or not pitch then return end
    local width=self.child:GetWidth()
    local first=math.max(1,math.floor(offset/pitch)+1)
    local last=math.min(#rows,math.ceil((offset+self.list:GetHeight())/pitch))
    local scale=A.UI:FontScale()
    for index=first,last do
        local i=index-first+1
        local entry,row=rows[index],self.rows[i]
        if not row then
            row=A.UI:ListButton(self.child,"",width,function() end,"task")
            row.text:SetMaxLines(1)
            row.icon=A.UI:Text(row,"body")
            row.sub=A.UI:Text(row,"guideNote",colors.muted);row.sub:SetMaxLines(1)
            row.line=row:CreateTexture(nil,"ARTWORK");row.line:SetPoint("BOTTOMLEFT",metrics.indent+metrics.gap,0);row.line:SetPoint("BOTTOMRIGHT",-8,0);row.line:SetHeight(1)
            row.line:SetColorTexture(unpack(colors.line))
            row.marker=row:CreateTexture(nil,"ARTWORK");row.marker:SetPoint("TOPLEFT");row.marker:SetPoint("BOTTOMLEFT");row.marker:SetWidth(2)
            row:RegisterForClicks("LeftButtonUp","RightButtonUp")
            row:SetScript("OnClick",function(f,button)
                if button=="RightButton" and f.entry.questId then A.UI:TrackerMenu(f);return end
                if f.entry.questId and IsModifiedClick and IsModifiedClick("CHATLINK") then A.UI:QuestClick(f.entry.questId,button);return end
                self.message=nil
                local previous=self.selected
                self.selected=f.entry;self.selection[self.mode]=f.entry.key;self.info:SetVerticalScroll(0)
                if self.mode==1 then
                    A.UI.Plan.key=f.entry.key
                    A.UI.Plan.preview=f.entry.choice
                end
                for _,r in ipairs(self.rows) do
                    if r.entry==previous or r==f then markRow(r,r==f) end
                end
                self:Detail()
            end)
            row:HookScript("OnEnter",function(f)
                f:SetBackdropColor(unpack(colors.rowHover))
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(f.entry.questId and A.UI.QuestName(f.entry.title,f.entry.dimmed) or f.entry.title)
                GameTooltip:AddLine(f.entry.sub or "",0.85,0.9,1,true);GameTooltip:Show()
            end)
            row:HookScript("OnLeave",function(f) f:SetBackdropColor(unpack(f.baseColor));GameTooltip:Hide() end)
            self.rows[i]=row
        end
        if row.entry~=entry or row.pitch~=pitch or row.index~=index then
            row.entry,row.pitch,row.index=entry,pitch,index
            row.questId,row.candidate,row.revision=entry.questId,entry.choice,A.plan and A.plan.revision
            row.deferred=entry.questId and ((A.state.skipped or {})[entry.questId] or (A.state.chainDeferred or {})[entry.questId])
            local pad=metrics.guidePadding*scale
            local inset=pad+metrics.guideIndent*scale
            local top=metrics.tight*scale
            row.icon:ClearAllPoints();row.icon:SetPoint("TOPLEFT",pad,-top)
            row.text:ClearAllPoints();row.text:SetPoint("TOPLEFT",inset,-top);row.text:SetWidth(width-inset-pad)
            row.text:SetText(entry.questId and A.UI.QuestName(entry.title,entry.dimmed) or entry.title)
            row.icon:SetText(A.UI:Icon(entry.icon,metrics.icon));row.sub:SetText(entry.sub or "")
            row.sub:ClearAllPoints();row.sub:SetPoint("TOPLEFT",row.text,"BOTTOMLEFT",0,-2*scale);row.sub:SetWidth(width-inset-pad)
            row.line:ClearAllPoints();row.line:SetPoint("BOTTOMLEFT",pad,0);row.line:SetPoint("BOTTOMRIGHT",-pad,0)
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-(index-1)*pitch);row:SetSize(width,pitch)
            row.marker:SetColorTexture(unpack(entry.questId and colors.focus or colors.accent))
            markRow(row,entry==self.selected)
        elseif row.marker:IsShown()~=(entry==self.selected) then
            markRow(row,entry==self.selected)
        end
        row:Show()
    end
    for i=math.max(1,last-first+2),#self.rows do self.rows[i]:Hide() end
end

function B:Action(index,label,run,enabled)
    local b=self.buttons[index];b.text:SetText(label);b.run=run;b:SetEnabled(enabled~=false);b:Show()
    b.baseColor=index==1 and enabled~=false and colors.primary or colors.button;b:SetBackdropColor(unpack(b.baseColor))
    b.text:SetTextColor(unpack(enabled==false and colors.muted or index==1 and colors.ink or colors.white))
end

function B:PlaceActions(y,rightAligned)
    local x,bottom=0,y
    for i,button in ipairs(self.buttons) do
        if button:IsShown() then
            button.text:SetWidth(0)
            local w=math.min(self.info:GetWidth(),math.ceil(button.text:GetStringWidth())+24)
            button.text:SetWidth(w-24)
            if x>0 and x+w>self.info:GetWidth() then x=0;y=bottom end
            button:ClearAllPoints()
            if rightAligned then button:SetPoint("TOPRIGHT",-x,-y) else button:SetPoint("TOPLEFT",x,-y) end
            button:SetSize(w,math.max(metrics.button,math.ceil(button.text:GetStringHeight())+8))
            if i>1 then
                button.baseColor=colors.panel;button:SetBackdropColor(unpack(colors.panel))
                button.text:SetTextColor(unpack(button:IsEnabled() and colors.blue or colors.muted))
            end
            x=x+w+metrics.gap;bottom=math.max(bottom,y+button:GetHeight()+metrics.gap)
        end
    end
    return bottom
end

local regionStates={
    {key="done",label="已交付",tint=colors.green},
    {key="ready",label="可交付",tint=colors.gold},
    {key="active",label="进行中",tint=colors.blue},
    {key="open",label="未接取",tint={0.54,0.60,0.70}},
}
local function regionProgress(zone,state)
    local stats={done={},ready={},active={},open={},closed={},xp=0,unknown=0}
    for _,q in ipairs(zone.quests) do
        local live=state.quests[q.id]
        local key
        if state.completed[q.id] then key="done" -- Count each quest once, including repeatables.
        elseif live then key=live.ready and "ready" or "active"
        elseif A.Eligibility.Closed(q,state) or ((q.requiredMaxLevel or 0)>0 and state.level>q.requiredMaxLevel) then key="closed"
        else key="open" end
        local group=stats[key];group[#group+1]=q
        if key~="done" and key~="closed" and state.level<60 then
            local xp=A.TaskGuide.XP(q,state.level,state)
            if xp~=nil then stats.xp=stats.xp+xp else stats.unknown=stats.unknown+1 end
            if key=="open" and q.exclusiveTo and #q.exclusiveTo>0 then stats.hasAlternatives=true end
        end
    end
    stats.total=#zone.quests-#stats.closed
    stats.remaining=stats.total-#stats.done
    return stats
end

function B:RegionChart(zone,top,stats,filter)
    local chart=self.regionChart
    if not chart then
        chart=CreateFrame("Frame",nil,self.infoChild);self.regionChart=chart
        chart.labels,chart.values,chart.segments,chart.legend={},{},{},{}
        for i,label in ipairs({"区域完成度","剩余任务","预计剩余经验"}) do
            chart.labels[i]=A.UI:Text(chart,"guideLabel",colors.muted);chart.labels[i]:SetText(label)
            chart.values[i]=A.UI:Text(chart,"guideMetric",i==3 and colors.gold or colors.white)
        end
        for i,status in ipairs(regionStates) do
            local key=status.key
            local segment=chart:CreateTexture(nil,"ARTWORK");segment:SetColorTexture(unpack(status.tint))
            local b=A.UI:ListButton(chart,"",100,function()
                chart.filter=chart.filter~=key and key or nil
                self.info:SetVerticalScroll(0);self:Detail()
            end,"guideLabel")
            b.dot=b:CreateTexture(nil,"ARTWORK");b.dot:SetColorTexture(unpack(status.tint))
            b.dot:SetPoint("LEFT",4,0);b.dot:SetSize(7,7)
            b.text:ClearAllPoints();b.text:SetPoint("LEFT",b.dot,"RIGHT",6,0)
            chart.segments[i],chart.legend[i]=segment,b
        end
        chart.note=A.UI:Text(chart,"guideNote",colors.muted)
        chart.line=chart:CreateTexture(nil,"ARTWORK");chart.line:SetColorTexture(unpack(colors.line))
        chart.line:SetHeight(1);chart.line:SetPoint("BOTTOMLEFT");chart.line:SetPoint("BOTTOMRIGHT")
    end
    chart.zone,chart.filter=zone,filter
    local width,scale=self.info:GetWidth(),A.UI:FontScale()
    local gap=metrics.gap*scale
    chart:SetPoint("TOPLEFT",0,-top);chart:SetWidth(width);chart:Show()
    local xp=BreakUpLargeNumbers and BreakUpLargeNumbers(stats.xp) or tostring(stats.xp)
    if stats.unknown>0 then xp=stats.unknown==stats.remaining and "待确认" or "≥ "..xp end
    local values={stats.total>0 and math.floor(#stats.done/stats.total*100).."%" or "—",stats.remaining.." 项",xp}
    local bottom=0
    for i,value in ipairs(values) do
        local label,number=chart.labels[i],chart.values[i]
        label:SetPoint("TOPLEFT",(i-1)*width/3,0)
        number:SetPoint("TOPLEFT",label,"BOTTOMLEFT",0,-metrics.tight*scale)
        number:SetWidth(width/3-gap);number:SetText(value)
        bottom=math.max(bottom,label:GetStringHeight()+metrics.tight*scale+number:GetStringHeight())
    end
    local barY=bottom+gap
    local barHeight=7*scale
    local offset=0
    for i,status in ipairs(regionStates) do
        local count=#stats[status.key]
        local segment,button=chart.segments[i],chart.legend[i]
        segment:SetShown(count>0)
        if count>0 then
            local span=width*count/stats.total
            segment:SetPoint("TOPLEFT",offset,-barY);segment:SetSize(span,barHeight);offset=offset+span
        end
        button:SetPoint("TOPLEFT",(i-1)*width/4,-barY-barHeight-metrics.tight*scale)
        button:SetSize(width/4,metrics.hit*scale);button.text:SetText(status.label.."  "..count)
        A.UI:MarkChoice(button,chart.filter==status.key)
    end
    local notes={"收录 "..#zone.quests.." 项",A.state.level>=60 and "已满级" or ("按 "..A.state.level.." 级逐项估算")}
    if stats.unknown>0 then notes[#notes+1]=stats.unknown.." 项经验待确认" end
    if #stats.closed>0 then notes[#notes+1]=#stats.closed.." 项已关闭，不计入进度" end
    if stats.hasAlternatives then notes[#notes+1]="含互斥备选奖励" end
    notes[#notes+1]=chart.filter and "再点选中状态可清除筛选" or "点上方状态可筛选任务"
    chart.note:SetText(table.concat(notes,"  ·  "));chart.note:SetWidth(width)
    local noteY=barY+barHeight+(metrics.tight+metrics.hit)*scale+gap
    chart.note:SetPoint("TOPLEFT",0,-noteY);chart:SetHeight(noteY+chart.note:GetStringHeight()+gap)
    return top+chart:GetHeight()+gap
end

-- Keep each quest link and its wrapped description together in one column.
function B:LayoutRegionLists(groups,top)
    self.regionSections=self.regionSections or {}
    local scale,width=A.UI:FontScale(),self.info:GetWidth()
    local gutter=metrics.section*scale
    local half=math.floor((width-gutter)/2)
    local wide=half>=180*scale
    local function draw(i,x,y,span,split)
        local group,section=groups[i],self.regionSections[i]
        if not section then
            section=CreateFrame("Frame",nil,self.infoChild);self.regionSections[i]=section
            enableDetailLinks(section)
            section.heading=A.UI:Text(section,"guideAction",colors.white)
            section.heading:SetPoint("TOPLEFT")
            section.columns={A.UI:Text(section,"guideBody",colors.white),A.UI:Text(section,"guideBody",colors.white)}
        end
        section:SetPoint("TOPLEFT",x,-y);section:SetWidth(span);section:Show()
        section.heading:SetWidth(span)
        local count=#group.items
        section.heading:SetText(color(group.tint,group.label).."   "..color(muted,count.." 项"))
        local bodyY=section.heading:GetStringHeight()+metrics.gap*scale
        local cut=split and math.ceil(count/2) or count
        local height=0
        for col,body in ipairs(section.columns) do
            local first,last=col==1 and 1 or cut+1,col==1 and cut or count
            body:SetShown(first<=last)
            if first<=last then
                body:SetPoint("TOPLEFT",col==1 and 0 or half+gutter,-bodyY)
                body:SetWidth(cut<count and half or span)
                body:SetSpacing(metrics.tight*scale);body:SetWordWrap(true)
                body:SetText(table.concat(group.items,"\n",first,last))
                height=math.max(height,body:GetStringHeight())
            end
        end
        section:SetHeight(bodyY+height)
        return bodyY+height
    end
    local i=1
    while i<=#groups do
        local a,b=groups[i],groups[i+1]
        local paired=wide and a.pair and b and b.pair and #a.items<=6 and #b.items<=6
        local height
        if paired then
            height=math.max(draw(i,0,top,half),draw(i+1,half+gutter,top,half))
            i=i+2
        else
            height=draw(i,0,top,width,wide)
            i=i+1
        end
        top=top+height+gutter
    end
    return top
end

function B:Detail()
    for _,button in ipairs(self.buttons) do button:Hide() end
    for _,section in ipairs(self.regionSections or {}) do section:Hide() end
    self.info:SetHeight(self.frame:GetHeight()-18);self.detail:Show()
    if self.dungeonDetail then self.dungeonDetail:Hide() end
    self.goals:Hide();self.goalHeading:Hide();if self.meta then self.meta:Hide() end
    local e=self.selected
    local quest=e and e.choice
    local parent=quest and self.questHeader or self.infoChild
    if self.title:GetParent()~=parent then
        self.title:SetParent(parent)
        for _,button in ipairs(self.buttons) do button:SetParent(parent) end
    end
    self.questHeader:SetShown(quest and true or false)
    self.info:ClearAllPoints();self.info:SetPoint("TOPLEFT",self.questHeader,quest and "BOTTOMLEFT" or "TOPLEFT")
    self.title:ClearAllPoints();self.title:SetPoint("TOPLEFT")
    self.title:SetWidth(self.info:GetWidth()-28)
    self.title:SetText(e and e.title or "暂无项目")
    self.detail:SetWidth(self.info:GetWidth())
    local lines={}
    local regionLists
    local detailTop=self.title:GetStringHeight()+18
    local regionPage=e and self.mode==10
    local stats,filter
    local showMap=regionPage and A.indexReady and A.state.completionKnown~=false
    if e and e.catalogZone and A.state.completionKnown~=false then
        stats=regionProgress(e.catalogZone,A.state)
        filter=self.regionChart and self.regionChart.zone==e.catalogZone and self.regionChart.filter or nil
    end
    local guiding=regionPage and A.char.regionTarget and A.char.regionTarget.map==(e.map or e.region and e.region.map)
    if regionPage then
        self:Action(1,guiding and "结束区域规划" or "开始区域规划",function()
            local ok,why
            if guiding then ok,why=A.Selection:Automatic() else ok,why=A.Selection:StartRegion(e) end
            if not ok then A:Message(why) end
            self:Refresh(10)
        end,(guiding or A.ready and A.indexReady and A.state.completionKnown~=false and not A.state.inInstance) and true or false)
        local actionsHeight=self:PlaceActions(0,true)
        self.title:SetWidth(math.max(1,self.info:GetWidth()-self.buttons[1]:GetWidth()-metrics.gap))
        if showMap then self.title:SetText(self:RegionMapTitle(e,stats,filter)) end
        detailTop=math.max(self.title:GetStringHeight()+18,actionsHeight+metrics.gap)
    end
    if stats then
        detailTop=self:RegionChart(e.catalogZone,detailTop,stats,filter)
    elseif self.regionChart then self.regionChart:Hide();self.regionChart.zone=nil end
    local locations
    if showMap then
        detailTop,locations=self:ShowRegionMap(detailTop)
    elseif self.regionMap then self.regionMap:Hide() end
    if guiding and not filter then
        local plan=A.plan
        if A.state.inInstance then lines[#lines+1]="出本后继续区域规划。"
        elseif plan and plan.regionTarget==A.char.regionTarget and plan.fallback then
            local steps={}
            local function step(action)
                if not action then return end
                local verb=({accept="接取",objective="完成",turnin="交付"})[action.kind]
                steps[#steps+1]=verb and action.questId and (verb.."  "..questLink(action.questId,action.title)) or action.title
            end
            step(plan.fallback)
            local queue=plan.taskQueue and plan.taskQueue.steps or {}
            local first=queue[1] and (queue[1].stage or queue[1].choice.actions[1])
            if first and plan.fallback.questId==first.questId and plan.fallback.kind==first.kind then
                for i=2,math.min(3,#queue) do step(queue[i].stage or queue[i].choice.actions[1]) end
            end
            lines[#lines+1]=color(blue,"区域行程").."\n"..table.concat(steps,"\n")
        elseif plan and plan.regionTarget==A.char.regionTarget and plan.maintenance then
            lines[#lines+1]="完成补给后继续区域规划。"
        else lines[#lines+1]="正在安排本区任务…" end
    end
    self.detail:SetSpacing(stats and 3*A.UI:FontScale() or 0)
    if not e and self.mode==10 and #self.entries==0 then
        self.title:SetText(self.summary:GetText())
        lines[1]=A.error or (not A.indexReady and "任务索引就绪后会自动显示区域。" or "任务库中没有可显示的区域。")
    elseif not e then lines[1]=self.query and self.query~="" and "清空搜索或换一个关键词。" or "角色状态更新后，相关内容会显示在这里。"
    elseif e.dungeonCandidate then
        local c=e.dungeonCandidate
        lines[#lines+1]=e.sub
        if c.availableRewards and c.availableRewards.count>0 then
            lines[#lines+1]=color(gold,"本次任务经验  "..A.UI.DungeonXPText(c.availableRewards))
        end
        local can,why=A.Selection.CanChoose(c,A.plan.revision)
        if why then lines[#lines+1]=why end
        self:Action(1,c.requiresAcceptance and "安排副本行程" or "继续当前行程",function()
            local ok,reason=A.UI.Plan:Choose(c,A.plan.revision);self.message=not ok and reason or nil;self:Refresh(self.mode)
        end,can)
        self:Action(2,"查看地下城",function() A.UI.Dungeon.selected=c.dungeonId;A.UI:SelectTab(4) end)
    elseif e.choice then
        local q=e.q or A.Data:GetQuest(e.questId,A.state)
        self.title:SetText(A.UI.QuestName("|Hquest:"..e.questId..":0|h"..e.title.."|h",e.dimmed))
        local timing=e.choice.executionTiming or e.choice.timing
        local status=e.sub
        if e.current then status=status:gsub("^.- · ","",1) end
        local meta=status..(timing and timing.seconds and (" · 路程 "..A.UI.ClockText(timing.seconds)) or "")
        if not self.meta then self.meta=A.UI:Text(self.questHeader,"caption",colors.muted) end
        self.meta:ClearAllPoints();self.meta:SetPoint("TOPLEFT",0,-detailTop);self.meta:SetWidth(self.info:GetWidth())
        local active=(A.state.quests or {})[e.questId]
        local nextAction=e.choice.executionAction or e.choice.actions and e.choice.actions[1]
        local instruction=nextAction and nextAction.text
        if nextAction then
            local point=nextAction.recipient or nextAction.position
            local verb=({accept="接取于 ",turnin="交付给 "})[nextAction.kind]
            if verb and point and point.entityName then instruction=verb..color(blue,point.entityName) end
        end
        if not instruction and active and not active.ready then
            for _,goal in ipairs(active.objectives or {}) do
                if not goal.finished and goal.text then instruction=goal.text;break end
            end
        end
        self.meta:SetText(meta..(instruction and ("\n"..instruction) or ""));self.meta:Show()
        local headerTop=detailTop+self.meta:GetStringHeight()+metrics.gap
        detailTop=0
        local db=A.Data.db and A.Data.db.Quest
        local description,objective
        if A.State and A.State.QuestText then description,objective=A.State:QuestText(e.questId) end
        if not objective and not active and db then
            objective=table.concat(db.Get(e.questId,"objectivesText") or {},"\n")
        end
        local sourceLink=color(blue,"|Hailquesturl:"..e.questId.."|h[复制 Wowhead 链接]|h")
        lines[#lines+1]=color(gold,"任务原文").."\n"..(description or color(muted,
            active and "请在任务日志中查看原文。" or "打开接任务对话后，可在这里回看原文。").." "..sourceLink)
        if objective and objective~="" then lines[#lines+1]=color(gold,"任务目标").."\n"..objective end
        if q and q.requiredSkill then lines[#lines+1]="需要 "..skillName(q.requiredSkill[1]).." "..q.requiredSkill[2] end
        if e.prerequisite then
            local pre=A.Data:GetQuest(e.prerequisite)
            lines[#lines+1]="前置  "..questLink(e.prerequisite,pre and pre.title or "任务 #"..e.prerequisite)
        end
        if not active and db then
            if q and #(e.choice.stages or {})==0 and A.Data.QuestContact then
                local giver=A.Data:QuestContact(q.id,"startedBy")
                local recipient=A.Data:QuestContact(q.id,"finishedBy")
                if giver and giver.entityName then lines[#lines+1]=A.UI:Icon("accept",16).." 接取于 "..color(blue,giver.entityName) end
                if recipient and recipient.entityName then lines[#lines+1]=A.UI:Icon("pending",16).." 交付给 "..color(blue,recipient.entityName) end
            end
        end
        if active and active.objectives and #active.objectives>0 then
            self.goalHeading:ClearAllPoints();self.goalHeading:SetPoint("TOPLEFT",0,-detailTop);self.goalHeading:Show()
            detailTop=detailTop+self.goalHeading:GetStringHeight()+metrics.gap
            self.goals:ClearAllPoints();self.goals:SetPoint("TOPLEFT",0,-detailTop);self.goals:SetWidth(self.info:GetWidth())
            local h=A.UI:DetailObjectives(self.goals,e.choice,active.objectives,self.info:GetWidth())
            self.goals:SetHeight(h);self.goals:Show();detailTop=detailTop+h+metrics.gap
        end
        for _,stage in ipairs(e.choice.stages or {}) do
            if not (active and active.objectives and active.objectives[stage.objectiveIndex or 0]) and stage.purchase and (not stage.need or stage.need<=0 or (stage.have or 0)<stage.need) then
                local item=A.Data.db and A.Data.db.Item.Get(stage.targetId,"name")
                if A.QuestItemZhCN then item=A.QuestItemZhCN(stage.targetId,item) end
                lines[#lines+1]=color(gold,(item or stage.text or "任务物品").." · "..A.UI.PurchaseText(stage.purchase))
            end
            local where=stage.recipient or stage.position
            if stage.kind~="objective" and where and where.entityName then
                lines[#lines+1]=A.UI:Icon(A.UI.QuestIcon(stage.kind,stage),16).." "..(stage.kind=="turnin" and "交付给 " or "接取于 ")..color(blue,where.entityName)
            elseif not active and stage.kind=="objective" and stage.text then lines[#lines+1]=A.UI:Icon(A.UI.QuestIcon(stage.kind,stage),14).." "..stage.text end
        end
        if e.choice.lowValue then lines[#lines+1]=color(gold,e.choice.lowValue.suggestion).." · "..e.choice.lowValue.reason end
        if e.choice.entryBlocked then lines[#lines+1]=e.choice.entryBlocked end
        if e.reason then lines[#lines+1]=e.reason end
        for _,line in ipairs(rewardLines(q)) do lines[#lines+1]=line end
        local planned=false
        for _,c in ipairs(A.plan and A.plan.taskChoices or {}) do if c==e.choice then planned=true;break end end
        local can=not planned or A.Selection.CanChoose(e.choice,A.plan.revision)
        self:Action(1,e.allowed==false and e.prerequisite and "查看前置任务" or self.mode==9 and "跟随这条职业任务线" or e.choice.unlock and "切换到解锁任务线" or "优先做此任务",function()
            if not e.allowed and e.prerequisite then A.UI.Chains:Focus(e.prerequisite);return end
            local ok,why
            if planned then ok,why=A.UI.Plan:Choose(e.choice,A.plan.revision)
            else ok,why=A.Selection:LockQuest(e.questId) end
            self.message=not ok and why or nil;self:Refresh(self.mode)
        end,(can and e.allowed) or e.prerequisite~=nil)
        local label,change,canIgnore=A.UI.QuestDeferral(e.questId)
        local function preference(method,ignore)
            if self.mode==1 then A.UI.Plan.key=e.key end
            method(A.Selection,e.questId,ignore);self:Refresh(self.mode)
        end
        if label then self:Action(2,label,function() preference(change) end) end
        if canIgnore then self:Action(5,"忽略此任务",function() preference(A.Selection.Skip,true) end) end
        self:Action(4,"查看任务链",function() A.UI.Chains:Focus(e.questId) end)
        if A.char.locked or A.char.regionTarget or A.char.itinerary or A.char.taskBatch or A.char.gearTarget or A.Navigation.manual or A.char.serviceStop or A.char.paused then
            self:Action(3,"恢复练级导航",function() A.Selection:Automatic();self:Refresh(self.mode) end)
        end
        local headerHeight=self:PlaceActions(headerTop)+metrics.gap
        self.questHeader:SetHeight(headerHeight)
        self.info:SetHeight(self.frame:GetHeight()-18-headerHeight)
    elseif e.dungeon then
        local batch=A.char.taskBatch
        local current=batch and batch.id==e.key
        local preparable=current or false
        for _,task in ipairs(e.tasks) do if A.Dungeon.CanContinueTask(task) then preparable=true;break end end
        self:Action(1,current and "返回正常练级" or "开始整组指引",function()
            local ok,why
            if current then ok,why=A.Selection:Automatic() else ok,why=A.Dungeon:StartTaskBatch(e.key) end
            self.message=not ok and why or nil;self:Refresh(self.mode)
        end,current or A.ready and not A.refreshAt and preparable)
        if current then
            self:Action(2,batch.waiting and "出发去副本" or "等队做任务",function()
                local ok,why=A.Dungeon:ToggleTaskBatchWait()
                self.message=not ok and why or nil;self:Refresh(self.mode)
            end,A.ready and not A.refreshAt and not A.state.inInstance)
        end
        if A.state.instanceEntryError then
            self:Action(3,"重新检查",function()
                local ok,why=A.Instances:Retry()
                self.message=not ok and why or nil;self:Refresh(self.mode)
            end,not A.state.inInstance)
        end
        if not A.state.inInstance and e.dungeon.areas and e.dungeon.areas[1] and e.dungeon.entrances and #e.dungeon.entrances>0 then
            self:Action(4,"导航至入口",function()
                local entry=A.Dungeon.TaskApproach({kind="dungeonEnter",title=e.title,areaId=e.dungeon.areas[1]},A.state,A.Data)
                if entry.position and A.Navigation:Navigate(entry) then A.UI.details:Hide();return end
                self.message="当前无法导航至该副本入口";self:Detail()
            end,not A.char.paused and not A.state.dead and not A.state.onTaxi and not A.state.instanceEntryError)
        end
        self:DungeonDetail(e)
        return
    elseif e.catalogZone and (filter or not e.region) then
        if stats then
            regionLists={}
            local function add(status,tint,dimmed,pair)
                local key,label=status.key,status.label
                if filter and filter~=key then return end
                local items={}
                for _,q in ipairs(stats[key]) do
                    local live=A.state.quests[q.id]
                    local level=(q.questLevel or 0)>0 and color(muted,"["..q.questLevel.."]").."  " or ""
                    local place=locations and locations[q.id]
                    items[#items+1]=level..questLink(q.id,live and live.title or q.title,nil,dimmed)..
                        (place and ("\n"..color(muted,table.concat(place,"\n"))) or "")
                end
                if #items>0 then regionLists[#regionLists+1]={label=label,tint=tint,items=items,pair=pair}
                elseif filter then lines[#lines+1]="本区没有"..label.."的任务。" end
            end
            add(regionStates[2],gold,false,true)
            add(regionStates[3],blue,false,true)
            add(regionStates[4],muted)
            add(regionStates[1],green,true)
            add({key="closed",label="已关闭"},muted,true)
        else lines[#lines+1]="正在同步角色的交付记录，稍后会显示区域进度。" end
    elseif e.region then
        local r=e.region
        regionLists={}
        if e.catalogZone and not stats then lines[#lines+1]="正在同步角色的交付记录…" end
        local visit=A.plan and A.plan.regionPlan
        local nextStop=visit and visit.destination==r
        lines[#lines+1]=color(gold,string.format("本轮 %d项 · %s",#r.choices,r.xp..(r.unknownXP>0 and "+经验" or "经验")))
        local function tasks(label,choices,kind)
            if #choices==0 then return end
            local items={}
            for _,entry in ipairs(choices) do
                local c=kind=="revisit" and entry.choice or entry
                local stage=kind=="turnin" and c.stages and c.stages[#c.stages] or c.actions and c.actions[1]
                local point=stage and (stage.recipient or stage.position)
                local status=A.state.quests[c.questId] and (A.state.quests[c.questId].ready and "可交付" or "已接取") or "未接取"
                local detail=kind=="revisit" and (entry.level.."级回访 · "..status) or
                    kind=="turnin" and (c.status=="turnin" and "现在交付" or "本轮完成后交付") or status
                items[#items+1]=questLink(c.questId,c.title).."\n"..color(muted,detail..(kind~="revisit" and point and point.entityName and (" · "..point.entityName) or ""))
            end
            regionLists[#regionLists+1]={label=label,tint=kind=="turnin" and green or kind=="accept" and blue or muted,items=items,pair=true}
        end
        if nextStop then tasks("出发前交付",visit.handins,"turnin") end
        if r.seconds then lines[#lines+1]="前往首个任务  "..A.UI.ClockText(r.seconds) end
        tasks("到达后接取",r.pickups,"accept")
        local active={}
        for _,c in ipairs(r.choices) do if c.status=="objective" then active[#active+1]=c end end
        tasks("本轮继续完成",active,"objective")
        tasks("本轮集中交付",r.handins,"turnin")
        tasks("留待回访",r.revisit,"revisit")
        if nextStop and visit.current~=r then tasks("离开本区后留待回访",visit.revisit,"revisit") end
    end
    if self.message then lines[#lines+1]=color(gold,self.message) end
    self.detail:ClearAllPoints();self.detail:SetPoint("TOPLEFT",0,-detailTop)
    self.detail:SetText(table.concat(lines,"\n\n"))
    local height=detailTop+(#lines>0 and self.detail:GetStringHeight()+12 or 0)
    if regionLists then height=self:LayoutRegionLists(regionLists,height) end
    if not quest and not regionPage then height=self:PlaceActions(height) end
    self.infoChild:SetHeight(math.max(1,height))
end

-- Only the expanded source asks the client for item links.
function B:DungeonLoot(view,groups,y)
    local db=A.Data.db
    local upgrades={}
    for _,benefit in ipairs(A.Gear.DungeonBenefits(self.selected.dungeon,A.state,A.Data)) do
        upgrades[benefit.item.id]=true
    end
    view.pending={}
    for i,group in ipairs(groups) do
        local button=view.bosses[i]
        if not button then
            button=A.UI:ListButton(view,"",view:GetWidth(),function()
                view.boss=view.boss==i and 0 or i
                self:DungeonDetail(self.selected)
            end,"body")
            button.text:ClearAllPoints();button.text:SetPoint("LEFT",6,0);button.text:SetWidth(view:GetWidth()-12);button.text:SetJustifyH("LEFT")
            view.bosses[i]=button
        end
        local expanded=view.boss==i
        local name=group.npc and db and db.Npc.Get(group.npc,"name") or group.name
        button.text:SetText((expanded and "−  " or "+  ")..name..
            (group.wing and " · "..group.wing or "")..color(muted,"  "..#group.items.." 件"))
        button:SetHeight(math.max(metrics.button,math.ceil(button.text:GetStringHeight())+8))
        button:ClearAllPoints();button:SetPoint("TOPLEFT",0,-y);button:Show()
        y=y+button:GetHeight()+metrics.gap
        if expanded then
            local lines={}
            for _,id in ipairs(group.items) do
                local itemName,link
                if C_Item and C_Item.GetItemInfo then itemName,link=C_Item.GetItemInfo(id) end
                local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
                if not link then
                    view.pending[id]=true
                    itemName=itemName or db and db.Item.Get(id,"name")
                end
                local source=group.observed and group.observed[id] and "实录" or
                    group.beta and group.beta[id] and "测试服" or "图鉴"
                local image=icon and ("|T"..icon..":15:15|t ") or ""
                lines[#lines+1]=image..itemLink({id=id,name=itemName,link=link})..
                    color(muted,"  "..source)..(upgrades[id] and color(green,"  提升") or "")
            end
            self.detail:SetText(table.concat(lines,"\n"));self.detail:ClearAllPoints()
            self.detail:SetPoint("TOPLEFT",view,"TOPLEFT",10,-y);self.detail:SetWidth(view:GetWidth()-10);self.detail:Show()
            y=y+self.detail:GetStringHeight()+metrics.gap
        end
    end
    if #groups==0 then
        self.detail:SetText("暂无收录的装备掉落");self.detail:ClearAllPoints()
        self.detail:SetPoint("TOPLEFT",view,"TOPLEFT",0,-y);self.detail:Show()
        y=y+self.detail:GetStringHeight()
    end
    return y
end

-- Only the open quest card reads contacts, objective text and reward links.
local function dungeonQuestText(task)
    local id=task.id
    local q=A.Data:GetQuest(id,A.state)
    local active=(A.state.quests or {})[id]
    local lines,goals={},{}
    for _,goal in ipairs(active and active.objectives or {}) do
        if goal.text then goals[#goals+1]=goal.text end
    end
    if #goals==0 then
        local _,objective
        if A.State and A.State.QuestText then _,objective=A.State:QuestText(id) end
        if objective and objective~="" then goals[1]=objective
        elseif A.Data.db and A.Data.db.Quest then goals=A.Data.db.Quest.Get(id,"objectivesText") or {} end
    end
    local function field(label,value)
        if value and value~="" then lines[#lines+1]=color(muted,label).."    "..value end
    end
    field("目标",table.concat(goals," / "))
    local function contact(group)
        local target=A.Data.db and A.Data.QuestContact and A.Data:QuestContact(id,group)
        return target and target.entityName
    end
    local point=task.group==3 and not task.pickupItem and task.position
    local giver=contact("startedBy") or point and not point.areaOnly and point.entityName
    local recipient=task.recipientName or contact("finishedBy")
    if giver and giver==recipient then field("接取与交付",giver)
    else field("接取",giver);field("交付",recipient) end
    local index=A.Data.chainIndex
    local hasChain=false
    if index and A.Chains then
        for _,related in ipairs(A.Chains.Related(id,index)) do
            local kind=related.edge.kind
            if kind=="all" or kind=="any" or kind=="next" then
                local other=A.Data:GetQuest(related.id,A.state)
                local label=related.incoming and (kind=="any" and "前置（任选）" or "前置") or "后续"
                local done=(A.state.completed or {})[related.id] and not (A.state.quests or {})[related.id]
                field(label,questLink(related.id,other and other.title or ("任务 #"..related.id),other and other.questLevel,done))
                hasChain=true
            end
        end
    end
    for _,reward in ipairs(rewardLines(q)) do lines[#lines+1]=reward end
    lines[#lines+1]=color(blue,"|Hquest:"..id..":0|h任务原文与详情 ›|h")..
        (hasChain and "    "..color(blue,"|Hailchain:"..id.."|h完整任务链 ›|h") or "")
    return table.concat(lines,"\n")
end

function B:DungeonDetail(e)
    local width=self.info:GetWidth()
    local view=self.dungeonDetail
    if not view then
        view=CreateFrame("Frame",nil,self.infoChild);view:SetWidth(width)
        self.dungeonDetail=view;view.rows={};view.bosses={}
        view.levels=A.UI:Text(view,"body",colors.muted)
        view.tasks=A.UI:Text(view,"caption",colors.white)
        view.xp=A.UI:Text(view,"caption",colors.gold)
        view.hint=A.UI:Text(view,"body")
        view.note=CreateFrame("Frame",nil,view);view.note:SetAllPoints(view.hint);view.note:EnableMouse(true)
        view.note:SetScript("OnEnter",function(f)
            GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText("当前安排")
            for _,line in ipairs(view.tip) do GameTooltip:AddLine(line,0.9,0.85,0.8,true) end
            GameTooltip:Show()
        end)
        view.note:SetScript("OnLeave",function() GameTooltip:Hide() end)
        view.questTab=A.UI:ListButton(view,"任务接取清单",158,function()
            view.showLoot=false;self:DungeonDetail(self.selected)
        end)
        view.pickups=A.UI:Text(view,"body",colors.white);view.pickups:SetWidth(width)
        view.loot=A.UI:ListButton(view,"装备掉落",158,function()
            view.showLoot=true;self:DungeonDetail(self.selected)
        end)
        view.map=A.UI:ListButton(view,"入口区域地图 ›",142,function()
            local open=OpenWorldMap or C_Map and C_Map.OpenWorldMap
            if view.mapId and open then A.UI.details:Hide();open(view.mapId) end
        end)
        view:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        view:SetScript("OnEvent",function(f,_,id,success)
            if success and f.pending and f.pending[id] and f:IsVisible() then
                f.pending[id]=nil
                f:SetScript("OnUpdate",function()
                    f:SetScript("OnUpdate",nil)
                    if f.showLoot and self.selected and self.selected.dungeon then self:DungeonDetail(self.selected) end
                end)
            end
        end)
    end
    self.detail:Hide();view:Show();view:ClearAllPoints()
    local top=self.title:GetStringHeight()+16
    view:SetPoint("TOPLEFT",0,-top)
    local d=A.UI.Dungeon
    local batch=A.char.taskBatch
    local current=batch and batch.id==e.key
    local plan=current and A.plan
    local choices=plan and plan.revision==A.state.revision and plan.taskBatch and plan.taskBatch.id==e.key and plan.taskChoices
    local rewards=A.Dungeon.TaskRewards(e.tasks,current and batch.baselines or nil,choices)
    local minimum=A.DungeonCatalog and A.DungeonCatalog.entryLevels and A.DungeonCatalog.entryLevels[e.dungeon.instanceId]
    local entry=e.dungeon.entrances and e.dungeon.entrances[1]
    local mapId=entry and A.Data.maps and A.Data.maps[entry[1]]
    local map=mapId and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    view.levels:SetText(e.levels..(minimum and "  ·  "..minimum.."级可进入" or "")..(map and map.name and "  ·  "..map.name or ""))
    view.levels:ClearAllPoints();view.levels:SetPoint("TOPLEFT");view.levels:SetWidth(width)
    local y=view.levels:GetStringHeight()+metrics.gap
    y=self:PlaceActions(top+y,true)-top+metrics.gap
    local available=not current and e.availableRewards
    local displayed=available or rewards
    view.tasks:ClearAllPoints();view.tasks:SetPoint("TOPLEFT",0,-y)
    view.tasks:SetText((available and "本次可做 " or current and "已安排 " or "可安排 ")..displayed.count.." 项")
    local split=math.ceil(view.tasks:GetStringWidth())+metrics.guidePadding
    view.xp:ClearAllPoints();view.xp:SetPoint("TOPLEFT",split,-y);view.xp:SetWidth(width-split)
    view.xp:SetText("任务经验  "..A.UI.DungeonXPText(displayed))
    y=y+math.max(view.tasks:GetStringHeight(),view.xp:GetStringHeight())+metrics.gap
    local hint=not A.state.inInstance and A.state.instanceEntryError or current and
        (batch.returning and "任务已交齐，离开副本后继续练级。" or batch.waiting and "等队时做附近任务；集合后点击「出发去副本」。")
    local journey=choices and plan.taskBatch.journey
    local nextStep=choices and plan.fallback and {action=plan.fallback} or
        journey and (journey.before[1] or journey.inside[1] or journey.after[1])
    if (not hint or hint=="") and nextStep then
        local action=nextStep.action
        local verb=({accept="接取 ",turnin="交付 ",objective="完成 "})[action.kind]
        hint=verb and (verb..A.UI.QuestName(action.title)) or A.UI.ActionText(action,A.settings)
    end
    if not hint or hint=="" or hint=="选择并准备关联任务。" then
        hint=rewards.count==0 and "暂无可安排任务" or rewards.ready==rewards.count and "任务已完成，可安排交付" or
            rewards.active+rewards.ready<rewards.count and "先接取关联任务，再完成副本目标" or "完成副本目标后集中交付"
    end
    view.hint:ClearAllPoints();view.hint:SetPoint("TOPLEFT",0,-y)
    view.hint:SetWidth(width);view.hint:SetText(A.UI:Icon("entry",14).." "..(self.message or hint))
    y=y+view.hint:GetStringHeight()+metrics.section
    if view.instance~=e.dungeon.instanceId then
        view.instance=e.dungeon.instanceId;view.boss=1;view.expanded=nil
    end
    view.pending=nil
    for _,button in ipairs(view.bosses) do button:Hide() end
    view.questTab.text:SetText("任务  "..#e.tasks)
    local groups=A.DungeonCatalog and A.DungeonCatalog.dropsByInstance and A.DungeonCatalog.dropsByInstance[view.instance] or {}
    view.loot.text:SetText("装备掉落  "..#groups.." 组")
    view.questTab:ClearAllPoints();view.questTab:SetPoint("TOPLEFT",0,-y)
    view.loot:ClearAllPoints();view.loot:SetPoint("TOPLEFT",164,-y)
    view.mapId=mapId
    view.map:ClearAllPoints();view.map:SetPoint("TOPLEFT",328,-y)
    view.map:SetShown(map~=nil and (OpenWorldMap or C_Map.OpenWorldMap)~=nil)
    for _,tab in ipairs({view.questTab,view.loot}) do
        local active=(tab==view.loot)==(view.showLoot==true)
        tab.baseColor=active and colors.selected or colors.panel;tab:SetBackdropColor(unpack(tab.baseColor))
        tab.text:SetTextColor(unpack(active and colors.gold or colors.white))
    end
    if not view.tabMark then view.tabMark=view:CreateTexture(nil,"ARTWORK");view.tabMark:SetColorTexture(unpack(colors.gold)) end
    local tab=view.showLoot and view.loot or view.questTab
    view.tabMark:ClearAllPoints();view.tabMark:SetPoint("BOTTOMLEFT",tab,"BOTTOMLEFT",0,0);view.tabMark:SetSize(tab:GetWidth(),2)
    y=y+view.loot:GetHeight()+metrics.gap
    local _,group=A.Dungeon.GroupStatus(e.dungeon,A.state)
    view.tip={self.message or hint,group}
    for _,line in pairs({A.Dungeon.EncounterProgress(e.dungeon,A.state),A.Dungeon:TaskActivityText(e.key)}) do
        view.tip[#view.tip+1]=line
    end
    view.pickups:SetShown(not view.showLoot)
    if view.showLoot then
        for _,row in ipairs(view.rows) do row:Hide() end
        y=self:DungeonLoot(view,groups,y)
        view:SetHeight(y);self.infoChild:SetHeight(top+y+8)
        return
    end
    local tones={colors.turnin,colors.purple,colors.accept,colors.muted,colors.muted}
    view.pickups:ClearAllPoints();view.pickups:SetPoint("TOPLEFT",0,-y)
    view.pickups:SetText(A.UI.DungeonPickupSummary(e.tasks,A.state))
    y=y+view.pickups:GetStringHeight()+metrics.gap
    local tasks,inside,other,preparation={},{},{},{}
    for _,task in ipairs(e.tasks) do
        local group=other
        if task.relation=="preparation" then group=preparation
        elseif A.UI.DungeonPickupStatus(task,A.state)=="未接取" then
            local instance=A.Dungeon.TaskInstance and A.Dungeon.TaskInstance(task.position,A.state,A.Data,task.areaId)
            group=instance and instance.instanceId==e.dungeon.instanceId and inside or tasks
        end
        group[#group+1]=task
    end
    local insideFirst=#tasks+1
    for _,group in ipairs({inside,other,preparation}) do
        for _,task in ipairs(group) do tasks[#tasks+1]=task end
    end
    if view.expanded~=false then
        local found=false
        for _,task in ipairs(tasks) do if task.id==view.expanded then found=true;break end end
        if not found then view.expanded=tasks[1] and tasks[1].id end
    end
    for i,task in ipairs(tasks) do
        local row=view.rows[i]
        if not row then
            row=A.UI:ListButton(view,"",width,function() end,"task")
            enableDetailLinks(row)
            row.baseColor=colors.panel;row:SetBackdropColor(0,0,0,0)
            row.text:ClearAllPoints();row.text:SetPoint("TOPLEFT",metrics.indent,-metrics.gap);row.text:SetWordWrap(true)
            row.icon=A.UI:Text(row,"body");row.icon:SetPoint("TOPLEFT",0,-metrics.gap)
            row.status=A.UI:Text(row,"caption");row.status:SetPoint("TOPRIGHT",0,-metrics.gap);row.status:SetJustifyH("RIGHT")
            row.meta=A.UI:Text(row,"caption",colors.muted);row.meta:SetWidth(width-32)
            row.line=row:CreateTexture(nil,"ARTWORK");row.line:SetPoint("TOPLEFT");row.line:SetPoint("TOPRIGHT");row.line:SetHeight(1)
            row.line:SetColorTexture(unpack(colors.line))
            row:RegisterForClicks("LeftButtonUp","RightButtonUp")
            row:SetScript("OnClick",function(f,button)
                if button=="RightButton" then A.UI:TrackerMenu(f)
                elseif IsModifiedClick and IsModifiedClick("CHATLINK") then A.UI:QuestClick(f.questId,button)
                else
                    if view.expanded==f.questId then view.expanded=false else view.expanded=f.questId end
                    self:DungeonDetail(self.selected)
                end
            end)
            row:HookScript("OnLeave",function(f) f:SetBackdropColor(unpack(f.baseColor));GameTooltip:Hide() end)
            row:HookScript("OnEnter",function(f)
                f:SetBackdropColor(unpack(colors.rowHover))
                local task=f.task
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(task.title,A.UI.DungeonQuestColor(task.questLevel,task.group==5 or f.deferred))
                GameTooltip:AddLine(A.UI.DungeonPickupStatus(task,A.state),unpack(tones[task.group]))
                if task.reason then GameTooltip:AddLine(task.reason,1,0.8,0.5,true) end
                if task.requireCheck then GameTooltip:AddLine("向任务发布者查看任务",0.8,0.8,0.8,true) end
                if task.relation=="preparation" then GameTooltip:AddLine("入本前准备",0.8,0.8,0.8,true) end
                if task.recipientName then GameTooltip:AddLine("交付给 "..task.recipientName,0.8,0.8,0.8,true) end
                local active=A.state.quests[task.id]
                for _,o in ipairs(active and active.objectives or {}) do if o.text then GameTooltip:AddLine(o.text,0.8,0.8,0.8,true) end end
                if task.gear then GameTooltip:AddLine("装备提升："..itemLink(task.gear.item),1,0.8,0.5,true) end
                if task.lowValue then GameTooltip:AddLine(task.lowValue.suggestion.." · "..task.lowValue.reason,0.8,0.8,0.8,true) end
                GameTooltip:Show()
            end)
            view.rows[i]=row
        end
        row.task,row.questId=task,task.id
        if not row.route then
            row.route=A.UI:ListButton(row,"",width-36,function()
                GameTooltip:Hide()
                local ok,why=A.Dungeon:ContinueTask(self.selected.dungeon,row.questId)
                self.message=not ok and why or nil;self:Refresh(self.mode)
            end,"caption")
            row.route.baseColor=colors.panel;row.route:SetBackdropColor(0,0,0,0)
            row.route.text:ClearAllPoints();row.route.text:SetPoint("TOPLEFT");row.route.text:SetWidth(width-36)
            row.route.text:SetWordWrap(true);row.route.text:SetJustifyH("LEFT");row.route.text:SetTextColor(unpack(colors.blue))
            row.route:SetScript("OnEnter",function(f)
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(row.direction or "任务指引")
                GameTooltip:AddLine("点击单独导航；接取后继续引导任务目标。",0.9,0.85,0.8,true);GameTooltip:Show()
            end)
            row.route:SetScript("OnLeave",function() GameTooltip:Hide() end)
        end
        row.deferred=(A.state.skipped or {})[task.id] or (A.state.chainDeferred or {})[task.id]
        row.revision=A.plan and A.plan.revision
        local expanded=view.expanded==task.id
        row.baseColor=expanded and colors.selected or colors.panel;row:SetBackdropColor(unpack(row.baseColor))
        local statusWidth=90*A.UI:FontScale()
        row.text:SetWidth(width-36-statusWidth);row.text:SetText(task.title);row.text:SetTextColor(A.UI.DungeonQuestColor(task.questLevel,task.group==5 or row.deferred))
        local active=(A.state.quests or {})[task.id]
        local icon=task.group==5 and "done" or A.UI.QuestIcon(task.group==1 and "turnin" or task.group==2 and "objective" or "accept",nil,active and active.objectives)
        row.icon:SetText(A.UI:Icon(icon,14))
        row.status:ClearAllPoints();row.status:SetPoint("TOPRIGHT",-8,-metrics.gap)
        row.status:SetWidth(statusWidth);row.status:SetText(i>=insideFirst and i<insideFirst+#inside and "副本内接" or A.UI.DungeonPickupStatus(task,A.state))
        row.status:SetTextColor(unpack(tones[task.group]))
        local direction,seconds=d:TaskDirection(task)
        row.direction=direction
        local meta={}
        if task.questLevel and task.questLevel>0 then meta[1]=task.questLevel.."级" end
        if task.relation=="preparation" then meta[#meta+1]="入本前准备" end
        if task.xp then meta[#meta+1]=color(gold,task.xp.." 经验") end
        if seconds then meta[#meta+1]="路程 "..A.UI.ClockText(seconds) end
        if task.gear then meta[#meta+1]="装备提升" end
        if task.lowValue then meta[#meta+1]=task.lowValue.suggestion end
        row.meta:SetText(table.concat(meta," · "))
        local h=math.max(row.text:GetStringHeight(),row.status:GetStringHeight())+metrics.gap+metrics.tight
        row.meta:ClearAllPoints();row.meta:SetPoint("TOPLEFT",24,-h)
        h=h+(#meta>0 and row.meta:GetStringHeight() or 0)+4
        if expanded then
            if not row.facts then row.facts=A.UI:Text(row,"body",colors.white) end
            row.facts:SetWidth(width-40);row.facts:ClearAllPoints();row.facts:SetPoint("TOPLEFT",24,-h)
            row.facts:SetText(dungeonQuestText(task));row.facts:Show()
            h=h+row.facts:GetStringHeight()+metrics.gap
        elseif row.facts then row.facts:Hide() end
        row.route:SetShown(direction~=nil)
        local canGuide=A.Dungeon.CanContinueTask(task) and not A.refreshAt
        row.route:SetEnabled(canGuide)
        row.route.text:SetTextColor(unpack(canGuide and colors.blue or colors.muted))
        if direction then
            row.route.text:SetText(A.UI:Icon("location",12).." "..direction..(canGuide and "  ›" or ""))
            row.route:ClearAllPoints();row.route:SetPoint("TOPLEFT",24,-h)
            row.route:SetHeight(row.route.text:GetStringHeight()+4);h=h+row.route:GetHeight()
        end
        h=h+8
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y);row:SetSize(width,h);row:Show();y=y+h+metrics.tight
    end
    for i=#e.tasks+1,#view.rows do view.rows[i]:Hide() end
    view:SetHeight(y);self.infoChild:SetHeight(top+y+8)

end

function B:IndexMounts()
    if self.mountQuests and self.mountIds==A.Data.ids then return end
    self.mountIds=A.Data.ids
    self.mountQuests={}
    local journal=C_MountJournal
    for _,id in ipairs(A.Data.ids or {}) do
        local q=A.Data:GetQuest(id)
        local r=q and q.taskFacts and q.taskFacts.rewards or {}
        if q and q.taskFacts and q.taskFacts.mountReward then self.mountQuests[id]=true end
        for _,key in ipairs({"spell","spellCast"}) do
            if r[key] and r[key]>0 and journal and journal.GetMountFromSpell and journal.GetMountFromSpell(r[key]) then self.mountQuests[id]=true end
        end
        for _,key in ipairs({"items","choices"}) do
            for _,item in ipairs(r[key] or {}) do
                if journal and journal.GetMountFromItem and journal.GetMountFromItem(item.id) then self.mountQuests[id]=true end
            end
        end
    end
    -- Include the prerequisite chain, so the first pickup is visible before the final reward.
    local function parents(id,seen)
        if seen[id] then return end;seen[id]=true
        local q=A.Data:GetQuest(id);if not q then return end
        self.mountQuests[id]=true
        for _,key in ipairs({"preQuestGroup","preQuestSingle"}) do for _,pre in ipairs(q[key] or {}) do parents(math.abs(pre),seen) end end
    end
    local rewards={};for id in pairs(self.mountQuests) do rewards[#rewards+1]=id end
    for _,id in ipairs(rewards) do parents(id,{}) end
end
