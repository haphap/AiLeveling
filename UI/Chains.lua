local _, A = ...
A.UI.Chains = {}
local UI=A.UI.Chains
local status={active="进行中",ready="可交付",turnedIn="已交付",notStarted="未开始",unknown="状态加载中",missing="资料缺失"}
local function clamp(value,maximum) return math.max(0,math.min(value,math.max(0,maximum))) end

function UI:CurrentId()
    local action=A.Navigation:Current()
    if action and action.questId then return action.questId end
    if A.char.locked then return A.char.locked end
    if A.plan and A.plan.best and A.plan.best.questId then return A.plan.best.questId end
    local ids={}
    for id in pairs(A.state.quests) do ids[#ids+1]=id end
    table.sort(ids)
    return ids[1]
end

function UI:Focus(id,back)
    if type(id)~="number" or id<=0 or id>=2147483648 or id%1~=0 then
        self.message="请输入有效任务 ID";A.UI:SelectTab(2);return
    end
    if self.focus and self.focus~=id and not back then
        self.history[#self.history+1]=self.focus
        if #self.history>40 then table.remove(self.history,1) end
    end
    self.focus,self.preview,self.graphKey,self.message=id,nil,nil,nil
    self.drawnFocus=nil
    self.input:SetText(tostring(id));self.input:ClearFocus()
    self.relatedIndex=1
    self.infoScroll:SetVerticalScroll(0)
    A.UI:SelectTab(2)
end

function UI:Create(parent)
    self.frame=CreateFrame("Frame",nil,parent)
    self.frame:SetPoint("TOPLEFT",18,-94);self.frame:SetPoint("BOTTOMRIGHT",-18,18)
    self.history,self.cards,self.lines={},{},{}
    local box=A.UI:Panel(nil,self.frame,64,26);box:SetPoint("TOPLEFT")
    self.input=CreateFrame("EditBox",nil,box)
    self.input:SetPoint("TOPLEFT",4,-4);self.input:SetPoint("BOTTOMRIGHT",-4,4)
    self.input:SetAutoFocus(false);self.input:SetFontObject(GameFontHighlight);self.input:SetMaxLetters(10)
    if A.UI.RegisterFont then A.UI:RegisterFont(self.input,"caption") end
    self.input:SetScript("OnEnterPressed",function() self:Focus(tonumber(self.input:GetText())) end)
    self.input:SetScript("OnEscapePressed",function(f) f:ClearFocus() end)
    local open=A.UI:Button(self.frame,"查看 ID",72,function() self:Focus(tonumber(self.input:GetText())) end)
    open:SetPoint("TOPLEFT",72,0)
    local current=A.UI:Button(self.frame,"当前任务",80,function() self:Focus(self:CurrentId()) end)
    current:SetPoint("TOPLEFT",152,0)
    self.back=A.UI:Button(self.frame,"返回",62,function()
        local id=table.remove(self.history)
        if id then self:Focus(id,true) end
    end)
    self.back:SetPoint("TOPLEFT",240,0)
    self.lock=A.UI:Button(self.frame,"锁定任务",82,function()
        local ok,why=A.Selection:LockQuest(self.focus)
        self.message=ok and "已锁定此任务目标。" or why;A.UI:SelectTab(2)
    end)
    self.lock:SetPoint("TOPLEFT",310,0)
    self.defer=A.UI:Button(self.frame,"暂缓整链",86,function()
        if self.preview then
            local ok,why=A.Chains:Defer(self.preview)
            self.message=ok and "已暂缓预览中的整链任务，可随时恢复此起点。" or why
            self.preview=nil
        else
            self.preview,self.message=A.Chains.Preview(self.focus,A.Data,A.state)
            self.page=1
        end
        self.infoScroll:SetVerticalScroll(0)
        A.UI:SelectTab(2)
    end)
    self.defer:SetPoint("TOPLEFT",400,0)
    self.restore=A.UI:Button(self.frame,"恢复链",76,function()
        local ok,why=A.Chains:Restore(self.focus)
        self.message=ok and "已恢复此起点的整链偏好，其他暂缓记录保留。" or why
        self.preview=nil;A.UI:SelectTab(2)
    end)
    self.restore:SetPoint("TOPLEFT",494,0)
    self.header=A.UI:Text(self.frame,"body")
    self.header:SetPoint("TOPLEFT",0,-34);self.header:SetWidth(560);self.header:SetHeight(36);self.header:SetMaxLines(2)
    self.viewport=CreateFrame("ScrollFrame",nil,self.frame,"UIPanelScrollFrameTemplate")
    self.viewport:SetPoint("TOPLEFT",0,-72);self.viewport:SetSize(536,190)
    self.canvas=CreateFrame("Frame",nil,self.viewport);self.canvas:SetSize(536,190);self.viewport:SetScrollChild(self.canvas)
    self.left=A.UI:Button(self.frame,"<",44,function() self:Pan(-1) end);self.left:SetPoint("TOPLEFT",0,-270)
    self.right=A.UI:Button(self.frame,">",44,function() self:Pan(1) end);self.right:SetPoint("TOPLEFT",50,-270)
    self.related=A.UI:Button(self.frame,"关联任务",380,function()
        local entries=self.graph and self.graph.related or {}
        if #entries>0 then self.relatedIndex=(self.relatedIndex or 1)%#entries+1;self:Refresh() end
    end)
    self.related:SetPoint("TOPLEFT",102,-270);self.related.text:SetWidth(368);self.related.text:SetMaxLines(1)
    self.visit=A.UI:Button(self.frame,"查看",80,function()
        local entry=self.graph and self.graph.related[self.relatedIndex or 1]
        if entry then self:Focus(entry.id) end
    end)
    self.visit:SetPoint("TOPLEFT",490,-270)
    self.infoScroll=CreateFrame("ScrollFrame",nil,self.frame,"UIPanelScrollFrameTemplate")
    self.infoScroll:SetPoint("TOPLEFT",0,-306);self.infoScroll:SetPoint("BOTTOMRIGHT",-30,0)
    self.infoChild=CreateFrame("Frame",nil,self.infoScroll);self.infoChild:SetSize(530,80);self.infoScroll:SetScrollChild(self.infoChild)
    self.info=A.UI:Text(self.infoChild,"caption");self.info:SetPoint("TOPLEFT");self.info:SetWidth(524)
    self.frame:Hide()
end

function UI:Pan(direction)
    if self.preview then
        local pages=math.max(1,math.ceil(#self.preview.ids/12))
        self.page=((self.page or 1)-1+direction)%pages+1
        self:Refresh();self.infoScroll:SetVerticalScroll(0)
        return
    end
    self.offset=clamp((self.offset or 0)+direction*204,(self.graph and self.graph.width or 536)-536)
    self.viewport:SetHorizontalScroll(self.offset)
    self:Refresh()
end

function UI:Draw(graph)
    self.canvas:SetSize(graph.width,graph.height)
    for _,card in ipairs(self.cards) do card:Hide() end
    for _,line in ipairs(self.lines) do
        for _,part in ipairs(line.parts) do part:Hide() end
        line.label:Hide();line.arrow:Hide()
    end
    for i,node in ipairs(graph.nodes) do
        local card=self.cards[i]
        if not card then
            card=A.UI:Button(self.canvas,"",164,function() self:Focus(self.cards[i].questId) end)
            card:SetSize(164,64)
            card.text:ClearAllPoints();card.text:SetPoint("TOPLEFT",6,-6);card.text:SetWidth(152);card.text:SetMaxLines(1)
            card.title=A.UI:Text(card,"caption");card.title:SetPoint("TOPLEFT",6,-25);card.title:SetWidth(152);card.title:SetMaxLines(2)
            card:SetScript("OnEnter",function(f)
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(f.node.title)
                GameTooltip:AddLine(status[f.node.status] or f.node.status,1,1,1)
                GameTooltip:AddLine(f.node.eligible and "当前资格已满足" or (f.node.reason or "查看任务条件"),1,1,1,true)
                GameTooltip:Show()
            end)
            card:SetScript("OnLeave",function() GameTooltip:Hide() end)
            self.cards[i]=card
        end
        card.questId,card.node=node.id,node
        card:ClearAllPoints();card:SetPoint("TOPLEFT",self.canvas,"TOPLEFT",node.x,-node.y)
        card.text:SetText("#"..node.id.." · "..(node.deferredRoot and "整链暂缓" or node.skipped and "已暂缓" or status[node.status]))
        card.title:SetText(node.title)
        card.baseColor=node.id==self.focus and A.UI.colors.selected or A.UI.colors.button
        card:SetBackdropColor(unpack(card.baseColor))
        local tone=(node.deferredRoot or node.skipped) and A.UI.colors.muted or
            node.status=="ready" and A.UI.colors.turnin or node.status=="active" and A.UI.colors.objective or
            node.status=="notStarted" and A.UI.colors.accept or A.UI.colors.muted
        card.text:SetTextColor(unpack(tone))
        card:Show()
    end
    for i,edge in ipairs(graph.edges) do
        local line=self.lines[i]
        if not line then
            line={parts={},label=A.UI:Text(self.canvas,"caption"),arrow=A.UI:Text(self.canvas,"caption")}
            for j=1,3 do line.parts[j]=self.canvas:CreateTexture(nil,"ARTWORK") end
            self.lines[i]=line
        end
        local from,to=graph.byId[edge.from],graph.byId[edge.to]
        local right=to.x>from.x
        local sx,tx=from.x+(right and 164 or 0),to.x+(right and 0 or 164)
        local mx=(sx+tx)/2
        if from.x==to.x then sx,tx=from.x+164,to.x+164;mx=sx+18 end
        local sy,ty=from.y+32,to.y+32
        local segments={{sx,sy,mx,sy},{mx,sy,mx,ty},{mx,ty,tx,ty}}
        for j,s in ipairs(segments) do
            local part=line.parts[j]
            part:ClearAllPoints();part:SetPoint("TOPLEFT",self.canvas,"TOPLEFT",math.min(s[1],s[3]),-math.min(s[2],s[4]))
            part:SetSize(math.max(2,math.abs(s[1]-s[3])),math.max(2,math.abs(s[2]-s[4])))
            part:SetColorTexture(unpack(edge.kind=="exclusive" and A.UI.colors.purple or A.UI.colors.muted));part:Show()
        end
        line.label:ClearAllPoints();line.label:SetPoint("TOPLEFT",self.canvas,"TOPLEFT",mx+3,-(sy+ty)/2)
        line.label:SetText(A.Chains.Label(edge));line.label:Show()
        line.arrow:ClearAllPoints();line.arrow:SetPoint("TOPLEFT",self.canvas,"TOPLEFT",tx+(right and -9 or 1),-ty+6)
        line.arrow:SetText(right and ">" or "<");line.arrow:Show()
    end
    local focus=graph.byId[self.focus]
    local recenter=self.drawnFocus~=self.focus or self.drawnIndex~=A.Data.chainIndex
    self.offset=clamp(recenter and (focus and focus.x-180 or 0) or (self.offset or 0),graph.width-536)
    self.viewport:SetHorizontalScroll(self.offset)
    self.viewport:SetVerticalScroll(clamp(recenter and (focus and focus.y-50 or 0) or self.viewport:GetVerticalScroll(),graph.height-190))
    self.drawnFocus,self.drawnIndex=self.focus,A.Data.chainIndex
end

function UI:Details()
    local lines={}
    if self.message then lines[#lines+1]=self.message end
    if self.preview then
        local p=self.preview;local pages=math.max(1,math.ceil(#p.ids/12))
        lines[#lines+1]=string.format("暂缓范围：%d 个任务，第 %d/%d 页。用 < > 查看全部名单，点击“应用暂缓”保存；点击节点或当前任务可取消预览。",#p.ids,self.page or 1,pages)
        lines[#lines+1]="范围包含后续分支汇合任务；保留原生任务记录，单任务暂缓独立保存。"
        for i=((self.page or 1)-1)*12+1,math.min((self.page or 1)*12,#p.ids) do
            local id=p.ids[i];local q=A.Data:GetQuest(id)
            lines[#lines+1]="#"..id.." "..(q and q.title or "资料缺失").." ["..(status[A.State.Status(A.state,id)] or "未知").."]"
        end
        return lines
    end
    local node=self.graph and self.graph.byId[self.focus]
    if not node then lines[#lines+1]="输入任务 ID，或返回当前任务后浏览关联。";return lines end
    lines[#lines+1]=node.title.." ["..(status[node.status] or node.status).."]"
    lines[#lines+1]=node.eligible and "当前资格已满足" or (node.reason or "查看任务条件")
    lines[#lines+1]="全部：完成所有前置任务；任一：完成其中一个前置任务。"
    if self.graph.truncated or self.graph.edgesTruncated then lines[#lines+1]="当前视图已限量；点击节点重新聚焦，或通过关联选择器逐项查看未画出的关系。" end
    if self.graph.cycle then lines[#lines+1]="任务关系存在循环。" end
    local roots={}
    for root in pairs(A.char.deferredChains or {}) do roots[#roots+1]=root end
    table.sort(roots)
    for _,root in ipairs(roots) do
        if A.Data.chainIndex and A.Chains.Descendants(root,A.Data.chainIndex).members[self.focus] then
            lines[#lines+1]="受整链起点 #"..root.." 暂缓影响；查看该 ID 可恢复。"
        end
    end
    for _,entry in ipairs(self.graph.related) do
        lines[#lines+1]="#"..entry.edge.from.." → #"..entry.edge.to.."："..A.Chains.Label(entry.edge)
    end
    return lines
end

function UI:Refresh()
    if not self.focus then
        self.focus=self:CurrentId()
        if self.focus then self.input:SetText(tostring(self.focus)) end
    end
    if self.preview and (self.preview.revision~=A.state.revision or self.preview.index~=A.Data.chainIndex) then
        self.preview=nil;self.message="任务状态已变化，请重新查看暂缓范围。"
    end
    local key=tostring(self.focus)..":"..tostring(A.state.revision)..":"..tostring(A.Data.chainIndex)
    if A.ready and self.focus and key~=self.graphKey then
        self.graph=A.Chains.Graph(self.focus,A.Data,A.state)
        self.graphKey=key;self:Draw(self.graph)
    end
    local node=self.graph and self.graph.byId[self.focus]
    self.header:SetText(node and ("#"..node.id.." · "..node.title.."\n"..(status[node.status] or node.status).."；单击节点聚焦，滚轮上下浏览") or "选择任务后查看前置、后续与互斥关系")
    self.back:SetEnabled(#self.history>0)
    local q=self.focus and A.ready and A.Data:GetQuest(self.focus) or nil
    self.lock:SetEnabled(q~=nil and not (node and (node.skipped or node.deferredRoot)) and not (q and not q.repeatable and node and node.status=="turnedIn"))
    self.defer:SetEnabled(A.ready==true and A.Data.chainIndex~=nil and A.Data.chainIndex.nodes[self.focus]==true and node~=nil and not (A.char.deferredChains and A.char.deferredChains[self.focus]))
    self.defer.text:SetText(self.preview and "应用暂缓" or "暂缓整链")
    self.restore:SetEnabled(A.char.deferredChains~=nil and A.char.deferredChains[self.focus]==true)
    local entries=self.graph and self.graph.related or {}
    self.relatedIndex=math.max(1,math.min(self.relatedIndex or 1,#entries))
    local entry=entries[self.relatedIndex]
    self.related.text:SetText(entry and string.format("关联 %d/%d：#%d · %s（点击切换）",self.relatedIndex,#entries,entry.id,A.Chains.Label(entry.edge)) or "当前没有已知关联")
    self.related:SetEnabled(#entries>0);self.visit:SetEnabled(entry~=nil)
    self.left:SetEnabled(self.preview~=nil or (self.offset or 0)>0)
    self.right:SetEnabled(self.preview~=nil or (self.offset or 0)<((self.graph and self.graph.width or 536)-536))
    self.info:SetText(table.concat(self:Details(),"\n\n"))
    self.infoChild:SetHeight(math.max(80,self.info:GetStringHeight()+16))
end
