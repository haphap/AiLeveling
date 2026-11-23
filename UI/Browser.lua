local _,A=...
-- The main window: one list and one detail pane, backed by the existing task models.
A.UI.Browser={selection={}}
local B=A.UI.Browser
local gold,blue,green,muted=A.UI.hex.gold,A.UI.hex.blue,A.UI.hex.green,A.UI.hex.muted
local colors=A.UI.colors
local metrics=A.UI.metrics
local function color(c,s) return "|cff"..c..tostring(s).."|r" end
local function questLink(id,title) return color(blue,"|Hquest:"..id..":0|h["..title.."]|h") end
local function itemLink(item)
    return item.link or color(blue,"|Hitem:"..item.id.."|h["..(item.name or "物品 #"..item.id).."]|h")
end
local function time(seconds)
    return seconds and string.format("%d分%02d秒",math.floor(seconds/60),math.ceil(seconds)%60) or nil
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
        for _,item in ipairs(rewards[key] or {}) do
            local name=C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item.id)
            result[#result+1]=(key=="choices" and "可选奖励  " or "奖励  ")..itemLink({id=item.id,name=name}).." ×"..(item.count or 1)
        end
    end
    return result
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
        if self.mode then self.list:SetVerticalScroll(0);self:Refresh(self.mode,true) end
    end
    if A.UI.daylight then self.search:HookScript("OnTextChanged",onTextChanged)
    else self.search:SetScript("OnTextChanged",onTextChanged) end
    self.list=CreateFrame("ScrollFrame",nil,self.frame,"UIPanelScrollFrameTemplate")
    self.list:SetPoint("TOPLEFT",0,-70);self.list:SetSize(382,420)
    self.child=CreateFrame("Frame",nil,self.list);self.child:SetSize(382,460);self.list:SetScrollChild(self.child)
    self.list:HookScript("OnVerticalScroll",function(_,offset) self:DrawRows(offset) end)
    self.info=CreateFrame("ScrollFrame",nil,self.frame,"UIPanelScrollFrameTemplate")
    self.info:SetPoint("TOPLEFT",434,-14);self.info:SetSize(326,368)
    self.infoChild=CreateFrame("Frame",nil,self.info);self.infoChild:SetSize(330,382);self.info:SetScrollChild(self.infoChild)
    self.infoChild:SetHyperlinksEnabled(true)
    self.infoChild:SetScript("OnHyperlinkClick",function(_,link,text,button)
        local source=link:match("^ailquesturl:(%d+)$")
        if source then
            local locale=GetLocale()=="zhCN" and "cn" or "www"
            A.UI:ShowText("https://"..locale..".wowhead.com/forever/quest="..source)
            return
        end
        local id=tonumber(link:match("^quest:(%d+)"))
        if id then A.UI:QuestClick(id,button) elseif SetItemRef then SetItemRef(link,text,button) end
    end)
    self.infoChild:SetScript("OnHyperlinkEnter",function(f,link)
        if link:match("^ailquesturl:") then return end
        GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetHyperlink(link);GameTooltip:Show()
    end)
    self.infoChild:SetScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
    self.title=A.UI:Text(self.infoChild,"title",colors.white);self.title:SetPoint("TOPLEFT");self.title:SetWidth(326)
    self.detail=A.UI:Text(self.infoChild,"body",colors.white);self.detail:SetWidth(326)
    self.goals=CreateFrame("Frame",nil,self.infoChild)
    self.goalHeading=A.UI:Text(self.infoChild,"caption",colors.muted);self.goalHeading:SetText("任务目标")
    self.buttons={}
    for i=1,4 do
        local create=i==1 and A.UI.Button or A.UI.ListButton
        local b=create(A.UI,self.infoChild,"",330,function() local f=self.buttons[i].run;if f then f() end end,"body")
        self.buttons[i]=b
    end
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
        A.char.taskBatch and "整组指引" or "推荐先做"
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
        if skipped then allowed,why,pre=false,"已暂缓",nil
        elseif not allowed and status=="未接取" then status=why end
        local c=status=="可交付" and green or state.quests[id] and gold or allowed and blue or muted
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
            icon=A.UI.QuestIcon(status=="可交付" and "turnin" or state.quests[id] and "objective" or "accept",
                id==currentId and action or choice.executionAction,state.quests[id] and state.quests[id].objectives),tone=c,
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
    for id,d in pairs(entries) do
        local tasks=A.Dungeon.Tasks(d,A.state,A.Data,targets)
        local rewards=A.Dungeon.TaskRewards(tasks)
        local range=A.DungeonCatalog.recommendedLevels and A.DungeonCatalog.recommendedLevels[d.instanceId]
        local low,high=range and range[1],range and range[2]
        local levels=low and string.format("推荐 %d—%d级",low,high) or "查看任务"
        local sub=levels.." · "..color(gold,rewards.count.."项任务")
        rows[#rows+1]={key=id,title=d.title,sub=sub,icon="entry",dungeon=d,tasks=tasks,rewards=rewards,levels=levels,low=low or math.huge}
    end
    table.sort(rows,function(a,b)
        local av,bv=a.rewards.count>0,b.rewards.count>0
        if av~=bv then return av end
        if a.low~=b.low then return a.low<b.low end
        return a.title<b.title
    end)
    return rows
end

local slots={"头部","颈部","肩部","衬衣","胸部","腰部","腿部","脚部","手腕","手部","戒指","戒指","饰品","饰品","背部","主手","副手","远程","战袍"}
function B:GearRows()
    local rows={}
    for _,item in ipairs(A.state.bagEquipment or {}) do
        local c=A.Gear.Upgrade(item,A.state)
        if c and not c.provisional and (c.delta>0 or #(c.notes or {})>0) then
            rows[#rows+1]={key="bag:"..(item.instanceKey or item.id),title=item.name or "物品 #"..item.id,
                sub=color(green,"背包可替换")..string.format(" · 评分 %+.1f",c.delta),icon="turnin",item=item,comparison=c}
        end
    end
    for _,id in ipairs(A.UI.Gear:Ids()) do
        local source=A.Gear.GetSource(id)
        local value=source and A.Gear.Source(source,A.state,A.Data)
        if value then rows[#rows+1]={key="source:"..id,title=value.item.name or source.title,sub=(source.kind=="quest" and "任务奖励" or "副本掉落")..(value.upgrade.provisional and " · 属性加载中" or string.format(" · 评分 %+.1f",value.upgrade.delta)),
            icon="turnin",item=value.item,comparison=value.upgrade,source=source,sourceId=id} end
    end
    for slot=1,19 do
        local item=(A.state.equipment or {})[slot]
        if item then
            local reference,skill=A.Gear.WeaponSkill(item,A.state)
            local detail=reference and skill and string.format("%s熟练度 %d/%d（有效 %d）",reference.name,skill.rank,skill.maxRank,skill.rank+skill.modifier+skill.tempPoints)
            rows[#rows+1]={key="slot:"..slot,title=item.name or "物品 #"..item.id,sub=color(muted,"已装备 · "..slots[slot]),icon="objective",item=item,slot=slot,skill=detail}
        end
    end
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

function B:Refresh(mode,reuse)
    gold,blue,green,muted=A.UI.hex.gold,A.UI.hex.blue,A.UI.hex.green,A.UI.hex.muted
    reuse=reuse and self.mode==mode and self.entriesRevision==A.state.revision and self.entriesPlan==A.plan
    if self.mode~=mode then
        self.message=nil
        local tasks=mode==1 or mode==9
        local listWidth=tasks and 320 or 382
        local split=listWidth+28
        self.frame:ClearAllPoints();self.frame:SetPoint("TOPLEFT",194,tasks and -22 or -88)
        self.frame:SetHeight(tasks and 552 or 490)
        self.summary:ClearAllPoints();self.summary:SetPoint("TOPLEFT",tasks and 106 or 0,tasks and -5 or 0)
        self.summary:SetWidth(listWidth-(tasks and 96 or 0));self.summary:SetJustifyH(tasks and "RIGHT" or "LEFT")
        self.search:SetWidth(listWidth+10)
        self.list:SetSize(listWidth,tasks and 482 or 420);self.child:SetWidth(listWidth)
        self.divider:ClearAllPoints();self.divider:SetPoint("TOPLEFT",split,0);self.divider:SetPoint("BOTTOMLEFT",split,0)
        self.info:ClearAllPoints();self.info:SetPoint("TOPLEFT",split+24,tasks and 0 or -14)
        local right=tasks and 378 or 326
        self.info:SetWidth(right);self.infoChild:SetWidth(right)
        self.title:SetWidth(right);self.detail:SetWidth(right)
        self.list:SetVerticalScroll(0);self.info:SetVerticalScroll(0)
    end
    self.mode=mode
    local rows
    if reuse then rows=self.entries
    elseif mode==4 then rows=self:DungeonRows()
    elseif mode==3 then rows=self:GearRows()
    elseif mode==10 then
        rows={}
        for _,region in ipairs(A.plan and A.plan.regions or A.Planner.TaskRegions(A.state,A.plan,A.Data)) do
            rows[#rows+1]={key="map:"..region.map,title=region.title,icon="entry",region=region,
                sub=string.format("%d项适级任务 · %s",#region.choices,color(gold,region.xp..(region.unknownXP>0 and "+经验" or "经验")))..(region.current and " · 当前区域" or "")..(#(region.revisit or {})>0 and (" · 回访"..#region.revisit.."项") or "")}
        end
    else
        if mode==11 then self:IndexMounts() end
        rows=self:TaskRows(mode)
    end
    self.entries=rows
    self.entriesRevision,self.entriesPlan=A.state.revision,A.plan
    if self.query and self.query~="" then
        local filtered={}
        for _,row in ipairs(rows) do
            if row.title:lower():find(self.query,1,true) or tostring(row.questId or ""):find(self.query,1,true) then filtered[#filtered+1]=row end
        end
        rows=filtered
    end
    local key=self.selection[mode]
    if mode==1 then
        key=A.UI.Plan.key
        if not key then for _,row in ipairs(rows) do if row.current then key=row.key;break end end end
    end
    if mode==4 and A.UI.Dungeon.selected then key=A.UI.Dungeon.selected end
    local selected
    for _,row in ipairs(rows) do if row.key==key then selected=row;break end end
    self.selected=selected or rows[1]
    self.selection[mode]=self.selected and self.selected.key
    if mode==1 then A.UI.Plan.preview=self.selected and self.selected.choice end
    local summary=#rows..(mode==10 and " 个练级区域" or mode==4 and " 个地下城" or mode==3 and " 件装备" or " 项任务")
    if mode==1 then
        local status=A.char.paused and "引导已暂停" or A.char.locked and "单任务锁定" or
            A.Navigation.manual and "手动导航" or A.char.taskBatch and "副本任务安排" or
            A.char.gearTarget and "装备目标" or "自动安排"
        summary=status.." · "..#rows.." 项可查看"
    end
    if #rows==0 and self.query and self.query~="" then
        summary="没有匹配的"..(({[3]="装备",[4]="地下城",[10]="练级区域"})[mode] or "任务")
    end
    self.summary:SetText(summary)
    self.filtered=rows
    local scale=A.UI:FontScale()
    self.rowPitch=math.ceil(40*scale)+2*metrics.gap+metrics.tight
    local height=math.max(1,#rows*self.rowPitch)
    self.child:SetHeight(height)
    local offset=math.min(self.list:GetVerticalScroll(),math.max(0,height-self.list:GetHeight()))
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
            row.icon=A.UI:Text(row,"body");row.icon:SetPoint("TOPLEFT",metrics.gap,-metrics.gap)
            row.sub=A.UI:Text(row,"caption",colors.muted);row.sub:SetMaxLines(1)
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
                if self.mode==4 then A.UI.Dungeon.selected=f.entry.key end
                for _,r in ipairs(self.rows) do
                    if r.entry==previous or r==f then markRow(r,r==f) end
                end
                self:Detail()
            end)
            row:HookScript("OnEnter",function(f)
                f:SetBackdropColor(unpack(colors.rowHover))
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(f.entry.title)
                GameTooltip:AddLine(f.entry.sub or "",0.85,0.9,1,true);GameTooltip:Show()
            end)
            row:HookScript("OnLeave",function(f) f:SetBackdropColor(unpack(f.baseColor));GameTooltip:Hide() end)
            self.rows[i]=row
        end
        if row.entry~=entry or row.pitch~=pitch or row.index~=index then
            row.entry,row.pitch,row.index=entry,pitch,index
            row.questId,row.candidate,row.revision=entry.questId,entry.choice,A.plan and A.plan.revision
            row.deferred=entry.questId and ((A.state.skipped or {})[entry.questId] or (A.state.chainDeferred or {})[entry.questId])
            local inset=metrics.gap+(metrics.icon+metrics.gap)*scale
            row.text:ClearAllPoints();row.text:SetPoint("TOPLEFT",inset,-metrics.gap);row.text:SetWidth(width-inset-metrics.gap)
            row.text:SetText(entry.title);row.text:SetTextColor(unpack(colors.white))
            row.icon:SetText(A.UI:Icon(entry.icon,metrics.icon));row.sub:SetText(entry.sub or "")
            row.sub:ClearAllPoints();row.sub:SetPoint("TOPLEFT",inset,-metrics.gap-23*scale);row.sub:SetWidth(width-inset-metrics.gap)
            row.line:ClearAllPoints();row.line:SetPoint("BOTTOMLEFT",inset,0);row.line:SetPoint("BOTTOMRIGHT",-metrics.gap,0)
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-(index-1)*pitch);row:SetSize(width,pitch-metrics.tight)
            row.marker:SetColorTexture(unpack(colors.accent))
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
    b.baseColor=index==1 and colors.selected or colors.button;b:SetBackdropColor(unpack(b.baseColor))
    b.text:SetTextColor(unpack(enabled==false and colors.muted or index==1 and colors.gold or colors.white))
end

function B:PlaceActions(y)
    local x,bottom=0,y
    for i,button in ipairs(self.buttons) do
        if button:IsShown() then
            local w=math.min(self.info:GetWidth(),math.ceil(button.text:GetStringWidth())+24)
            if x>0 and x+w>self.info:GetWidth() then x=0;y=bottom end
            button:ClearAllPoints();button:SetPoint("TOPLEFT",x,-y);button:SetWidth(w)
            if i>1 then
                button.baseColor=colors.panel;button:SetBackdropColor(unpack(colors.panel))
                button.text:SetTextColor(unpack(button:IsEnabled() and colors.blue or colors.muted))
            end
            x=x+w+metrics.gap;bottom=y+button:GetHeight()+metrics.gap
        end
    end
    return bottom
end

function B:Detail()
    for _,button in ipairs(self.buttons) do button:Hide() end
    self.info:SetHeight(self.frame:GetHeight()-18);self.detail:Show()
    if self.dungeonDetail then self.dungeonDetail:Hide() end
    self.goals:Hide();self.goalHeading:Hide();if self.meta then self.meta:Hide() end
    local e=self.selected
    self.title:SetText(e and e.title or "暂无项目")
    local lines={}
    local detailTop=self.title:GetStringHeight()+18
    if not e then lines[1]=self.query and self.query~="" and "清空搜索或换一个关键词。" or "角色状态更新后，相关内容会显示在这里。"
    elseif e.dungeonCandidate then
        local c=e.dungeonCandidate
        lines[#lines+1]=e.sub
        if c.remainingXP or c.xp then lines[#lines+1]=color(gold,"当前可做任务："..(c.remainingXP or c.xp).." 经验") end
        local can,why=A.Selection.CanChoose(c,A.plan.revision)
        if why then lines[#lines+1]=why end
        self:Action(1,c.requiresAcceptance and "安排副本行程" or "继续当前行程",function()
            local ok,reason=A.UI.Plan:Choose(c,A.plan.revision);self.message=not ok and reason or nil;self:Refresh(self.mode)
        end,can)
        self:Action(2,"查看地下城",function() A.UI.Dungeon.selected=c.dungeonId;A.UI:SelectTab(4) end)
    elseif e.choice then
        local q=e.q or A.Data:GetQuest(e.questId,A.state)
        self.title:SetText("|Hquest:"..e.questId..":0|h"..e.title.."|h")
        local timing=e.choice.executionTiming or e.choice.timing
        local status=e.sub
        if e.current then status=status:gsub("^.- · ","",1) end
        local meta=status..(timing and timing.seconds and (" · 路程 "..time(timing.seconds)) or "")
        if not self.meta then self.meta=A.UI:Text(self.infoChild,"caption",colors.muted) end
        self.meta:ClearAllPoints();self.meta:SetPoint("TOPLEFT",0,-detailTop);self.meta:SetWidth(self.info:GetWidth())
        self.meta:SetText(meta);self.meta:Show()
        detailTop=detailTop+self.meta:GetStringHeight()+metrics.section
        local active=(A.state.quests or {})[e.questId]
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
                if recipient and recipient.entityName then lines[#lines+1]=A.UI:Icon("turnin",16).." 交付给 "..color(blue,recipient.entityName) end
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
                local item=A.Data.db and A.Data.db.Item.Get(stage.targetId,"name") or stage.text or "任务物品"
                lines[#lines+1]=color(gold,(item or "任务物品").." · "..A.UI.PurchaseText(stage.purchase))
            end
            local where=stage.recipient or stage.position
            if stage.kind~="objective" and where and where.entityName then
                lines[#lines+1]=A.UI:Icon(stage.kind,16).." "..(stage.kind=="turnin" and "交付给 " or "接取于 ")..color(blue,where.entityName)
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
        local label,change=A.UI.QuestDeferral(e.questId)
        if label then self:Action(2,label,function()
            if self.mode==1 then A.UI.Plan.key=e.key end
            change(A.Selection,e.questId);self:Refresh(self.mode)
        end) end
        self:Action(4,"查看任务链",function() A.UI.Chains:Focus(e.questId) end)
        if A.char.locked or A.char.itinerary or A.char.taskBatch or A.char.gearTarget or A.Navigation.manual or A.char.serviceStop or A.char.paused then
            self:Action(3,"恢复练级导航",function() A.Selection:Automatic();self:Refresh(self.mode) end)
        end
    elseif e.dungeon then
        A.UI.Dungeon.selected=e.key
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
        self:DungeonDetail(e)
        return
    elseif e.region then
        local r=e.region
        local visit=A.plan and A.plan.regionPlan
        local nextStop=visit and visit.destination==r
        lines[#lines+1]=color(gold,string.format("本轮 %d项 · %s",#r.choices,r.xp..(r.unknownXP>0 and "+经验" or "经验")))
        local function tasks(label,choices,kind)
            if #choices==0 then return end
            lines[#lines+1]=color(kind=="turnin" and green or kind=="accept" and blue or muted,label)
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
            lines[#lines+1]=table.concat(items,"\n")
        end
        if nextStop then tasks("出发前交付",visit.handins,"turnin") end
        if r.seconds then lines[#lines+1]="前往首个任务  "..time(r.seconds) end
        tasks("到达后接取",r.pickups,"accept")
        local active={}
        for _,c in ipairs(r.choices) do if c.status=="objective" then active[#active+1]=c end end
        tasks("本轮继续完成",active,"objective")
        tasks("本轮集中交付",r.handins,"turnin")
        tasks("留待回访",r.revisit,"revisit")
        if nextStop and visit.current~=r then tasks("离开本区后留待回访",visit.revisit,"revisit") end
        self:Action(1,r.current and "指引本轮任务" or "前往首个任务",function()
            local ok,why=A.Selection:LockQuest(r.first.questId);self.message=not ok and why or nil;self:Refresh(self.mode)
        end,r.first~=nil)
    elseif e.item then
        lines[#lines+1]=itemLink(e.item);lines[#lines+1]=e.sub
        if e.skill then lines[#lines+1]=e.skill end
        if e.source then lines[#lines+1]="来源  "..e.source.title end
        if e.comparison then
            local c=e.comparison
            lines[#lines+1]=c.provisional and "属性加载中" or color(c.delta>0 and green or muted,string.format("属性评分 %+.1f",c.delta))
            local stats={}
            local order={};for slot in pairs(c.replacements or {}) do order[#order+1]=slot end;table.sort(order)
            for _,slot in ipairs(order) do
                local replacement=c.replacements[slot]
                local old=(A.state.equipment or {})[slot]
                lines[#lines+1]=(slots[slot] or "槽位 "..slot).."  "..(old and itemLink(old) or "空").." → "..(replacement and itemLink(replacement) or "空")
                for key,n in pairs(old and old.stats or {}) do stats[key]=(stats[key] or 0)-n end
                for key,n in pairs(replacement and replacement.stats or {}) do stats[key]=(stats[key] or 0)+n end
            end
            local keys={};for key,n in pairs(stats) do if n~=0 then keys[#keys+1]=key end end;table.sort(keys)
            for _,key in ipairs(keys) do lines[#lines+1]=color(stats[key]>0 and green or A.UI.hex.red,(_G[key] or key)..string.format(" %+.1f",stats[key])) end
            for _,note in ipairs(c.notes or {}) do lines[#lines+1]=note end
        end
        if e.sourceId then self:Action(1,"安排获取此装备",function() local ok,why=A.Gear:SetTarget(e.sourceId);self.message=not ok and why or nil;self:Refresh(3) end) end
        if A.char.gearTarget then self:Action(2,"恢复升级目标",function()
            A.char.gearTarget,A.char.gearBaseline=nil,nil
            if A.ready then A.State:Refresh(true) end
            self:Refresh(3)
        end) end
    end
    if self.message then lines[#lines+1]=color(gold,self.message) end
    self.detail:ClearAllPoints();self.detail:SetPoint("TOPLEFT",0,-detailTop)
    self.detail:SetText(table.concat(lines,"\n\n"))
    local height=detailTop+(#lines>0 and self.detail:GetStringHeight()+12 or 0)
    height=self:PlaceActions(height)
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
            button=A.UI:ListButton(view,"",326,function()
                view.boss=view.boss==i and 0 or i
                self:DungeonDetail(self.selected)
            end,"body")
            button.text:ClearAllPoints();button.text:SetPoint("LEFT",6,0)
            view.bosses[i]=button
        end
        local expanded=view.boss==i
        local name=group.npc and db and db.Npc.Get(group.npc,"name") or group.name
        button.text:SetText((expanded and "−  " or "+  ")..name..
            (group.wing and " · "..group.wing or "")..color(muted,"  "..#group.items.." 件"))
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
            self.detail:SetPoint("TOPLEFT",view,"TOPLEFT",10,-y);self.detail:SetWidth(316);self.detail:Show()
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

function B:DungeonDetail(e)
    local view=self.dungeonDetail
    if not view then
        view=CreateFrame("Frame",nil,self.infoChild);view:SetWidth(326)
        self.dungeonDetail=view;view.rows={};view.bosses={}
        view.levels=A.UI:Text(view,"caption",colors.muted);view.levels:SetPoint("TOPLEFT");view.levels:SetWidth(326)
        view.tasks=A.UI:Text(view,"title");view.tasks:SetWidth(154)
        view.xp=A.UI:Text(view,"title",colors.gold);view.xp:SetWidth(162)
        view.tasksLabel=A.UI:Text(view,"caption",colors.muted);view.tasksLabel:SetWidth(154)
        view.xpLabel=A.UI:Text(view,"caption",colors.muted);view.xpLabel:SetWidth(162);view.xpLabel:SetText("任务经验")
        view.hint=A.UI:Text(view,"body");view.hint:SetWidth(326);view.hint:SetMaxLines(2)
        view.note=CreateFrame("Frame",nil,view);view.note:SetAllPoints(view.hint);view.note:EnableMouse(true)
        view.note:SetScript("OnEnter",function(f)
            GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText("当前安排")
            for _,line in ipairs(view.tip) do GameTooltip:AddLine(line,0.9,0.85,0.8,true) end
            GameTooltip:Show()
        end)
        view.note:SetScript("OnLeave",function() GameTooltip:Hide() end)
        view.questTab=A.UI:ListButton(view,"关联任务",158,function()
            view.showLoot=false;self:DungeonDetail(self.selected)
        end)
        view.loot=A.UI:ListButton(view,"装备掉落",158,function()
            view.showLoot=true;self:DungeonDetail(self.selected)
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
    local top=self.title:GetStringHeight()+10
    view:SetPoint("TOPLEFT",0,-top)
    local d=A.UI.Dungeon
    local batch=A.char.taskBatch
    local current=batch and batch.id==e.key
    local plan=current and A.plan
    local choices=plan and plan.revision==A.state.revision and plan.taskBatch and plan.taskBatch.id==e.key and plan.taskChoices
    local rewards=A.Dungeon.TaskRewards(e.tasks,current and batch.baselines or nil,choices)
    local minimum=A.DungeonCatalog and A.DungeonCatalog.entryLevels and A.DungeonCatalog.entryLevels[e.dungeon.instanceId]
    view.levels:SetText(e.levels..(minimum and "  ·  "..minimum.."级可进入" or ""))
    local y=view.levels:GetStringHeight()+16
    view.tasks:ClearAllPoints();view.tasks:SetPoint("TOPLEFT",0,-y)
    view.tasks:SetText(rewards.count.." 项")
    view.xp:ClearAllPoints();view.xp:SetPoint("TOPLEFT",164,-y)
    view.xp:SetText(rewards.unknownXP==0 and rewards.xp or rewards.xp>0 and rewards.xp.."+" or "—")
    y=y+math.max(view.tasks:GetStringHeight(),view.xp:GetStringHeight())+3
    view.tasksLabel:ClearAllPoints();view.tasksLabel:SetPoint("TOPLEFT",0,-y);view.tasksLabel:SetText(current and "已安排任务" or "可安排任务")
    view.xpLabel:ClearAllPoints();view.xpLabel:SetPoint("TOPLEFT",164,-y)
    y=y+view.tasksLabel:GetStringHeight()+16
    local hint=not A.state.inInstance and A.state.instanceEntryError or current and
        (batch.returning and "任务已交齐，离开副本后继续练级。" or batch.waiting and "等队时做附近任务；集合后点击「出发去副本」。")
    local journey=choices and plan.taskBatch.journey
    local nextStep=choices and plan.fallback and {action=plan.fallback} or
        journey and (journey.before[1] or journey.inside[1] or journey.after[1])
    if (not hint or hint=="") and nextStep then
        local action=nextStep.action
        local verb=({accept="接取 ",turnin="交付 ",objective="完成 "})[action.kind]
        hint=verb and (verb..action.title) or A.UI.ActionText(action,A.settings)
    end
    if not hint or hint=="" or hint=="选择并准备关联任务。" then
        hint=rewards.count==0 and "暂无可安排任务" or rewards.ready==rewards.count and "任务已完成，可安排交付" or
            rewards.active+rewards.ready<rewards.count and "先接取关联任务，再完成副本目标" or "完成副本目标后集中交付"
    end
    view.hint:ClearAllPoints();view.hint:SetPoint("TOPLEFT",0,-y)
    view.hint:SetText(A.UI:Icon("entry",14).." "..(self.message or hint))
    y=self:PlaceActions(top+y+view.hint:GetStringHeight()+metrics.gap)-top+metrics.gap
    if view.instance~=e.dungeon.instanceId then
        view.instance=e.dungeon.instanceId;view.boss=1
    end
    view.pending=nil
    for _,button in ipairs(view.bosses) do button:Hide() end
    view.questTab:ClearAllPoints();view.questTab:SetPoint("TOPLEFT",0,-y)
    view.loot:ClearAllPoints();view.loot:SetPoint("TOPLEFT",164,-y)
    for _,tab in ipairs({view.questTab,view.loot}) do
        local active=(tab==view.loot)==(view.showLoot==true)
        tab.baseColor=active and colors.selected or colors.panel;tab:SetBackdropColor(unpack(tab.baseColor))
        tab.text:SetTextColor(unpack(active and colors.gold or colors.white))
    end
    y=y+view.loot:GetHeight()+metrics.gap
    local _,group=A.Dungeon.GroupStatus(e.dungeon,A.state)
    view.tip={self.message or hint,group}
    for _,line in pairs({A.Dungeon.EncounterProgress(e.dungeon,A.state),A.Dungeon:TaskActivityText(e.key)}) do
        view.tip[#view.tip+1]=line
    end
    if view.showLoot then
        for _,row in ipairs(view.rows) do row:Hide() end
        y=self:DungeonLoot(view,A.DungeonCatalog.dropsByInstance[view.instance] or {},y)
        view:SetHeight(y);self.infoChild:SetHeight(top+y+8)
        return
    end
    local tones={colors.turnin,colors.objective,colors.accept,colors.muted,colors.muted}
    local tasks,prep,inside,other={},{},{},{}
    for _,task in ipairs(e.tasks) do
        local group=other
        if task.group==3 then
            local instance=A.Dungeon.TaskInstance and A.Dungeon.TaskInstance(task.position,A.state,A.Data,task.areaId)
            group=instance and inside or tasks
        elseif task.preparation then group=prep end
        group[#group+1]=task
    end
    local insideFirst=#tasks+#prep+1
    for _,group in ipairs({prep,inside,other}) do
        for _,task in ipairs(group) do tasks[#tasks+1]=task end
    end
    for i,task in ipairs(tasks) do
        local row=view.rows[i]
        if not row then
            row=A.UI:Button(view,"",326,function() end,"body")
            row.baseColor=colors.panel;row:SetBackdropColor(0,0,0,0)
            row.text:ClearAllPoints();row.text:SetPoint("TOPLEFT",metrics.indent,-metrics.gap);row.text:SetMaxLines(2)
            row.icon=A.UI:Text(row,"body");row.icon:SetPoint("TOPLEFT",0,-metrics.gap)
            row.status=A.UI:Text(row,"caption");row.status:SetPoint("TOPRIGHT",0,-metrics.gap);row.status:SetJustifyH("RIGHT")
            row.meta=A.UI:Text(row,"caption",colors.muted);row.meta:SetWidth(302)
            row.line=row:CreateTexture(nil,"ARTWORK");row.line:SetPoint("TOPLEFT");row.line:SetPoint("TOPRIGHT");row.line:SetHeight(1)
            row.line:SetColorTexture(unpack(colors.line))
            row:RegisterForClicks("LeftButtonUp","RightButtonUp")
            row:SetScript("OnClick",function(f,button)
                if button=="RightButton" then A.UI:TrackerMenu(f)
                else A.UI:QuestClick(f.questId,button) end
            end)
            row:HookScript("OnLeave",function(f) f:SetBackdropColor(0,0,0,0);GameTooltip:Hide() end)
            row:HookScript("OnEnter",function(f)
                f:SetBackdropColor(unpack(colors.rowHover))
                local task=f.task
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(task.title)
                GameTooltip:AddLine(task.status,unpack(tones[task.group]))
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
            row.route=A.UI:Button(row,"",302,function()
                GameTooltip:Hide()
                local ok,why=A.Dungeon:ContinueTask(self.selected.dungeon,row.questId)
                self.message=not ok and why or nil;self:Refresh(self.mode)
            end,"caption")
            row.route.baseColor=colors.panel;row.route:SetBackdropColor(0,0,0,0)
            row.route.text:ClearAllPoints();row.route.text:SetPoint("TOPLEFT");row.route.text:SetWidth(302)
            row.route.text:SetMaxLines(2);row.route.text:SetJustifyH("LEFT");row.route.text:SetTextColor(unpack(colors.blue))
            row.route:SetScript("OnEnter",function(f)
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(row.direction or "任务指引")
                GameTooltip:AddLine("点击单独导航；接取后继续引导任务目标。",0.9,0.85,0.8,true);GameTooltip:Show()
            end)
            row.route:SetScript("OnLeave",function() GameTooltip:Hide() end)
        end
        row.deferred=(A.state.skipped or {})[task.id] or (A.state.chainDeferred or {})[task.id]
        row.revision=A.plan and A.plan.revision
        row.text:SetWidth(292-64*(A.settings.fontScale or 1));row.text:SetText(task.title);row.text:SetTextColor(unpack(colors.blue))
        local active=(A.state.quests or {})[task.id]
        local icon=A.UI.QuestIcon(task.group==1 and "turnin" or task.group==2 and "objective" or "accept",nil,active and active.objectives)
        row.icon:SetText(A.UI:Icon(icon,14))
        row.status:SetWidth(64*(A.settings.fontScale or 1));row.status:SetText(i>=insideFirst and i<insideFirst+#inside and "副本内接" or task.group==4 and (task.preparation and "需前置" or "未解锁") or task.status)
        row.status:SetTextColor(unpack(tones[task.group]))
        local direction,seconds=d:TaskDirection(task)
        row.direction=direction
        local meta={}
        if task.xp then meta[#meta+1]=color(gold,task.xp.." 经验") end
        if seconds then meta[#meta+1]="路程 "..time(seconds) end
        if task.gear then meta[#meta+1]="装备提升" end
        if task.lowValue then meta[#meta+1]=task.lowValue.suggestion end
        row.meta:SetText(table.concat(meta," · "))
        local h=math.max(row.text:GetStringHeight(),row.status:GetStringHeight())+metrics.gap+metrics.tight
        row.meta:ClearAllPoints();row.meta:SetPoint("TOPLEFT",24,-h)
        h=h+(#meta>0 and row.meta:GetStringHeight() or 0)+4
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
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y);row:SetSize(326,h);row:Show();y=y+h
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
