local _,A=...
A.Talents={}
local T=A.Talents

function T:Plans()
    if type(A.char.talentPlans)~="table" then A.char.talentPlans={plans={}} end
    local saved=A.char.talentPlans
    if type(saved.plans)~="table" then saved.plans={} end
    return saved
end

function T:Selected()
    local saved=self:Plans()
    return saved.plans[saved.selected]
end

function T:Save(name)
    name=(name or ""):match("^%s*(.-)%s*$")
    if name=="" then return false,"填写方案名称" end
    local frame=PlayerSpellsFrame.TalentsFrame
    if frame:IsInspecting() or not frame:GetConfigID() then return false,"先返回自己的天赋树，再保存加点" end
    local value=frame:GetLoadoutExportString()
    if not value or value=="" then return false,"天赋尚未解锁" end
    local saved=self:Plans()
    saved.plans[name]={text=value,level=UnitLevel("player")};saved.selected=name
    return true,"已保存「"..name.."」"
end

function T:Preview()
    local plan=self:Selected()
    if not plan then return false,"先选择一个方案" end
    PlayerSpellsFrame:SetInspectString(plan.text,plan.level)
    if not PlayerSpellsFrame:IsInspecting() then return false,"方案与当前天赋版本不匹配，请重新保存" end
    return true,"正在预览「"..self:Plans().selected.."」"
end

function T:Entries(frame,plan)
    local stream=ExportUtil.MakeImportDataStream(plan.text)
    local valid,version,spec,hash=frame:ReadLoadoutHeader(stream)
    if not valid or version~=C_Traits.GetLoadoutSerializationVersion() or spec~=PlayerUtil.GetCurrentSpecID() then
        return nil,"该方案与当前天赋版本或职业不匹配，请重新保存"
    end
    local tree=frame:GetTalentTreeID()
    if not tree or not frame:HashEquals(hash,C_Traits.GetTreeHash(tree)) then
        return nil,"天赋树已更新，请重新保存方案"
    end
    local content=frame:ReadLoadoutContent(stream,tree)
    return frame:ConvertToImportLoadoutEntryInfo(frame:GetConfigID(),tree,content)
end

function T:Stage()
    if InCombatLockdown() then return false,"战斗结束后再调整天赋" end
    local plan=self:Selected()
    if not plan then return false,"先选择一个方案" end
    local canEdit,reason=C_ClassTalents.CanEditTalents()
    if not canEdit then return false,reason~="" and reason or "当前无法调整天赋" end
    PlayerSpellsFrame:ClearInspectUnit()
    local frame=PlayerSpellsFrame.TalentsFrame
    if frame:IsCommitInProgress() then return false,"天赋正在应用" end
    frame:SetTab(frame:GetActiveTab())
    local entries,why=self:Entries(frame,plan)
    if not entries then return false,why end
    local config,tree=frame:GetConfigID(),frame:GetTalentTreeID()
    if not C_Traits.ResetTree(config,tree) then return false,"当前无法重置天赋预览" end
    -- Native purchases enforce level, currency, prerequisites and selection rules.
    -- Retry deferred nodes after their prerequisites have been staged.
    local changed
    repeat
        changed=false
        for _,entry in ipairs(entries) do
            local node=C_Traits.GetNodeInfo(config,entry.nodeID)
            if node and node.ranksPurchased<entry.ranksPurchased then
                if #node.entryIDs>1 and (not node.activeEntry or node.activeEntry.entryID~=entry.selectionEntryID) then
                    C_Traits.SetSelection(config,entry.nodeID,entry.selectionEntryID)
                    node=C_Traits.GetNodeInfo(config,entry.nodeID)
                end
                if node.canPurchaseRank and C_Traits.PurchaseRank(config,entry.nodeID) then changed=true end
            end
        end
    until not changed
    for _,entry in ipairs(entries) do
        local node=C_Traits.GetNodeInfo(config,entry.nodeID)
        if not node or node.ranksPurchased~=entry.ranksPurchased or entry.ranksPurchased>0 and
            (not node.activeEntry or node.activeEntry.entryID~=entry.selectionEntryID) then
            C_Traits.RollbackConfig(config);frame:UpdateConfigButtonsState()
            return false,"当前点数或前置天赋无法完成该方案，已恢复原加点"
        end
    end
    frame:UpdateConfigButtonsState()
    return true,"方案已载入，点击原生「应用」确认"
end

function T:SwitchSpec()
    if InCombatLockdown() then return false,"战斗结束后再切换天赋" end
    if GetNumSpecGroups()<2 then return false,"副天赋尚未解锁" end
    PlayerSpellsFrame:ClearInspectUnit()
    C_SpecializationInfo.SetActiveSpecGroup(C_SpecializationInfo.GetActiveSpecGroup()==1 and 2 or 1)
    return true,"正在切换天赋"
end

function T:Refresh(message)
    if not self.panel then return end
    local saved=self:Plans()
    self.choose.text:SetText(saved.selected or "选择已保存的方案")
    self.status:SetText(message or "在原生天赋树调整加点后保存。\n载入方案后，点击原生「应用」生效。")
    self.switch:SetEnabled(GetNumSpecGroups()>1 and not InCombatLockdown())
    self.switch.text:SetText(C_SpecializationInfo.GetActiveSpecGroup()==1 and "启用副天赋" or "启用主天赋")
end

function T:Create(frame)
    if self.panel then return end
    local toggle=A.UI:Button(frame,"AiLeveling · 天赋方案",200,function()
        self.panel:SetShown(not self.panel:IsShown());self:Refresh()
    end)
    toggle:SetPoint("BOTTOMLEFT",frame.LoadSystem,"BOTTOMLEFT",0,0)
    local panel=A.UI:Panel("AiLevelingTalents",frame,320,316);self.panel=panel
    panel:SetPoint("BOTTOMLEFT",toggle,"TOPLEFT",0,8);panel:SetFrameStrata("DIALOG")
    local title=A.UI:Text(panel,16,"accent");title:SetPoint("TOPLEFT",14,-12);title:SetText("天赋方案")
    local close=A.UI:Button(panel,"×",28,function() panel:Hide() end);close:SetPoint("TOPRIGHT",-8,-8)
    self.choose=A.UI:Button(panel,"选择已保存的方案",292,function()
        local saved=self:Plans();local names={}
        for name in pairs(saved.plans) do names[#names+1]=name end
        table.sort(names)
        local nextName=names[1]
        for i,name in ipairs(names) do if name==saved.selected then nextName=names[i%#names+1];break end end
        saved.selected=nextName
        if nextName then self.name:SetText(nextName) end
        self:Refresh()
    end)
    self.choose:SetPoint("TOPLEFT",14,-42);self.choose.text:SetWidth(280)
    self.name=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
    self.name:SetSize(280,28);self.name:SetPoint("TOPLEFT",20,-78);self.name:SetAutoFocus(false)
    self.name:SetMaxLetters(24);A.UI:RegisterFont(self.name,13);self.name:SetText("新方案")
    self.name:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
    local function result(_,message) self:Refresh(message) end
    local save=A.UI:Button(panel,"保存原生树中的加点",292,function()
        result(self:Save(self.name:GetText()));self.name:ClearFocus()
    end)
    save:SetPoint("TOPLEFT",14,-114)
    local preview=A.UI:Button(panel,"预览方案",140,function()
        local ok,message=self:Preview();result(ok,message);if ok then panel:Hide() end
    end)
    preview:SetPoint("TOPLEFT",14,-150)
    local load=A.UI:Button(panel,"载入待确认",140,function()
        PlayerSpellsFrame:CheckConfirmResetAction(function()
            local ok,message=self:Stage();result(ok,message);if ok then panel:Hide() end
        end)
    end)
    load:SetPoint("TOPLEFT",166,-150)
    local remove=A.UI:Button(panel,"删除方案",140,function()
        local saved=self:Plans()
        if saved.selected then saved.plans[saved.selected]=nil;saved.selected=nil end
        self:Refresh()
    end)
    remove:SetPoint("TOPLEFT",14,-186)
    local edit=A.UI:Button(panel,"返回自己的天赋",140,function() PlayerSpellsFrame:ClearInspectUnit();panel:Hide() end)
    edit:SetPoint("TOPLEFT",166,-186)
    self.switch=A.UI:Button(panel,"切换天赋",292,function() result(self:SwitchSpec()) end)
    self.switch:SetPoint("TOPLEFT",14,-222)
    self.status=A.UI:Text(panel,12);self.status:SetPoint("TOPLEFT",14,-262);self.status:SetWidth(292)
    panel:SetScript("OnShow",function() self:Refresh() end)
    self:Refresh()
end

function T:Show()
    if InCombatLockdown() then A:Message("战斗结束后打开天赋方案");return end
    PlayerSpellsUtil.OpenToClassTalentsTab()
    self:Create(PlayerSpellsFrame.TalentsFrame)
    self.panel:Show();self:Refresh()
end
