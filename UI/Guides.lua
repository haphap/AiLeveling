local _,A=...
A.UI.Guides={}
local U=A.UI.Guides
function U:Refresh()
    local rows=A.Guides:List()
    local index=1
    for i,row in ipairs(rows) do if row.key==self.key then index=i;break end end
    self.preview=rows[index];self.key=self.preview and self.preview.key
    local guide=self.preview
    self.name:SetText(guide and string.format("%s · %d/%d",guide.name,index,#rows) or "尚未导入指南")
    self.previous:SetEnabled(#rows>1);self.next:SetEnabled(#rows>1)
    for _,button in ipairs({self.choose,self.reset,self.remove,self.export}) do button:SetEnabled(guide~=nil) end
    local current=A.state.guide
    self.status:SetText(self.message or (current and current.name and (current.name.." · "..
        (current.finished and "已完成" or string.format("步骤%d/%d",current.step,current.total))) or "当前使用自动规划"))
end
function U:Move(delta)
    local rows=A.Guides:List();local index=1
    for i,row in ipairs(rows) do if row.key==self.key then index=i;break end end
    if #rows>0 then self.key=rows[(index-1+delta)%#rows+1].key end
    self.message=nil;self.removeKey=nil;self:Refresh()
end
function U:Open()
    if not self.frame then
        local ui=A.UI
        local f=ui:Panel("AiLevelingGuides",UIParent,620,550);self.frame=f
        local p=A.settings.guidePosition
        if p then f:SetPoint(p[1],UIParent,p[2],p[3],p[4]) else f:SetPoint("CENTER") end
        f:SetFrameStrata("DIALOG");ui:Movable(f,"guidePosition")
        local title=ui:Text(f,20);title:SetPoint("TOPLEFT",18,-18);title:SetText("指南")
        local close=ui:Button(f,"关闭",54,function() f:Hide() end);close:SetPoint("TOPRIGHT",-16,-16)
        self.previous=ui:Button(f,"上一份",76,function() self:Move(-1) end);self.previous:SetPoint("TOPLEFT",18,-58)
        self.name=ui:Text(f,15,"accent");self.name:SetPoint("TOPLEFT",108,-63);self.name:SetWidth(400);self.name:SetMaxLines(1)
        self.next=ui:Button(f,"下一份",76,function() self:Move(1) end);self.next:SetPoint("TOPRIGHT",-18,-58)
        local function button(label,x,callback)
            local b=ui:Button(f,label,108,callback);b:SetPoint("TOPLEFT",x,-98);return b
        end
        self.choose=button("使用／续接",18,function()
            local ok,why=A.Guides:Select(self.key);self.message=ok and "已选择指南" or why;self:Refresh()
        end)
        self.reset=button("从头开始",136,function()
            local ok,why=A.Guides:Select(self.key,true);self.message=ok and "已重置指南进度" or why;self:Refresh()
        end)
        self.export=button("导出文字",254,function()
            local _,record=A.Guides:Get(self.key)
            if record then self.editor:SetText(record.source);self.editor:SetFocus();self.editor:HighlightText() end
        end)
        self.remove=button("删除指南",372,function()
            if self.removeKey==self.key then A.Guides:Remove(self.key);self.removeKey=nil;self.message="已删除指南"
            else self.removeKey=self.key;self.message="再次点击删除，确认移除此指南及当前角色的进度" end
            self:Refresh()
        end)
        local automatic=ui:Button(f,"自动规划",98,function() A.Guides:Select(nil);self.message=nil;self:Refresh() end)
        automatic:SetPoint("TOPLEFT",490,-98)
        self.status=ui:Text(f,13);self.status:SetPoint("TOPLEFT",18,-140);self.status:SetWidth(580);self.status:SetMaxLines(3)
        local label=ui:Text(f,14);label:SetPoint("TOPLEFT",18,-190);label:SetText("粘贴指南文字，或编辑后重新导入")
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",20,-220);scroll:SetSize(552,224)
        self.editor=CreateFrame("EditBox",nil,scroll);self.editor:SetMultiLine(true);self.editor:SetAutoFocus(false)
        self.editor:SetSize(548,224);self.editor:SetMaxLetters(65536);self.editor:SetFontObject(GameFontHighlight)
        ui:RegisterFont(self.editor,14);scroll:SetScrollChild(self.editor)
        local measure=ui:Text(f,14);measure:SetWidth(548);measure:Hide()
        self.editor:SetScript("OnTextChanged",function(box)
            measure:SetText(box:GetText());box:SetHeight(math.max(224,measure:GetStringHeight()+20))
        end)
        self.editor:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
        local import=ui:Button(f,"导入文字",116,function()
            local key,why=A.Guides:Import(self.editor:GetText())
            self.key=key or self.key;self.message=key and "已导入，可选择使用；同名内容更新后进度将重新计算" or why;self:Refresh()
        end)
        import:SetPoint("BOTTOMLEFT",18,64);self.import=import
        local skip=ui:Button(f,"暂缓当前步骤",140,function() A.Guides:Skip();self.message=nil;self:Refresh() end)
        skip:SetPoint("BOTTOMLEFT",146,64)
        local help=ui:Text(f,12);help:SetPoint("BOTTOMLEFT",18,16);help:SetWidth(580)
        help:SetText("#name 标题 · step 分步 · .accept 接任务 · .complete 目标 · .turnin 交任务\n.collect 物品,数量 · .xp 等级 · >> 说明 · /ail guides 打开此窗口")
    end
    self.frame:SetScale(A.settings.scale);self.frame:SetAlpha(A.settings.alpha)
    self:Refresh();self.frame:Show()
end
