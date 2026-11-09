local _,A=...
A.RareScanner={seen={}}
local R=A.RareScanner

local function read(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and not (issecretvalue and issecretvalue(value)) and
        (not canaccessvalue or canaccessvalue(value)) then return value end
end

function R:Enabled()
    return A.ready and A.settings and A.settings.scanRares and A.char and not A.char.paused and
        read(UnitIsDeadOrGhost,"player")~=true and read(UnitOnTaxi,"player")~=true
end

function R:ReadUnit(unit)
    local classification=read(UnitClassification,unit)
    if classification~="rare" and classification~="rareelite" then return end
    if read(UnitIsDeadOrGhost,unit)==true or read(UnitCanAttack,"player",unit)~=true then return end
    local guid,name=read(UnitGUID,unit),read(UnitName,unit)
    if type(guid)~="string" or not (guid:match("^Creature%-") or guid:match("^Vehicle%-")) then return end
    -- The name enters a secure target macro, so discard command syntax.
    if type(name)~="string" or name=="" or #name>200 or name:find("[%c%[%];/\\|]") or
        name:match("^%s") or name:match("%s$") then return end
    local level=read(UnitLevel,unit)
    return {unit=unit,guid=guid,name=name,elite=classification=="rareelite",
        level=type(level)=="number" and level>0 and level or nil}
end

function R:Apply()
    if InCombatLockdown() then return end
    local row=self.pending
    if not self:Enabled() or not row or GetTime()>=row.expires or
        read(UnitGUID,row.unit)~=row.guid or not self:ReadUnit(row.unit) then
        self.pending=nil
        if self.button then self.button:SetAttribute("macrotext1",nil);self.button:Hide() end
        return
    end
    if not self.button then
        local f=CreateFrame("Button","AiLevelingRareAlert",UIParent,"SecureActionButtonTemplate,BackdropTemplate")
        self.button=f
        f:SetPoint("BOTTOMLEFT",A.UI.frame,"TOPLEFT",0,8)
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        f:SetBackdropColor(0.035,0.05,0.065,0.96)
        f:RegisterForClicks("AnyUp","AnyDown");f:SetAttribute("type1","macro")
        f.heading=A.UI:Text(f,13,{1,0.82,0.35});f.heading:SetPoint("TOPLEFT",12,-9)
        f.name=A.UI:Text(f,17);f.name:SetPoint("TOPLEFT",12,-28);f.name:SetWidth(296)
        f.hint=A.UI:Text(f,12);f.hint:SetPoint("BOTTOMLEFT",12,8)
        f.hint:SetText("左键选中 · 右键关闭")
        f:SetScript("PostClick",function(_,button,down)
            if button=="RightButton" and not down and not InCombatLockdown() then
                self.pending=nil;self:Apply()
            end
        end)
        f:SetScript("OnUpdate",function()
            if self.pending and GetTime()>=self.pending.expires then self:Apply() end
        end)
    end
    local f=self.button
    f.heading:SetText((row.elite and "发现稀有精英" or "发现稀有")..(row.level and (" · "..row.level.." 级") or ""))
    f.name:SetText(row.name)
    f:SetSize(320,math.max(82,54+f.name:GetStringHeight()))
    f:SetScale(A.settings.scale or 1);f:SetBackdropBorderColor(A.UI:Accent())
    f:SetAttribute("macrotext1","/targetexact "..row.name);f:Show()
end

function R:Check(unit)
    if not self:Enabled() then return end
    local row=self:ReadUnit(unit)
    if not row then return end
    if self.seen[row.guid] then
        if self.pending and self.pending.guid==row.guid then self.pending.unit=unit end
        return
    end
    self.seen[row.guid]=true;row.expires=GetTime()+10;self.pending=row
    local text=(row.elite and "发现稀有精英：" or "发现稀有：")..row.name..(row.level and ("（"..row.level.." 级）") or "")
    A:Message(text)
    if InCombatLockdown() then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(text,1,0.82,0.35) end
    elseif A.settings.sound and PlaySound then PlaySound(3175,"Master") end
    self:Apply()
end

function R:Refresh()
    if not self.events then return end
    if self:Enabled() then
        for _,plate in ipairs(read(C_NamePlate and C_NamePlate.GetNamePlates) or {}) do
            if plate.namePlateUnitToken then self:Check(plate.namePlateUnitToken) end
        end
        self:Check("mouseover");self:Check("target")
    end
    self:Apply()
end

function R:Initialize()
    if self.events then return end
    local f=CreateFrame("Frame");self.events=f
    for _,event in ipairs({"NAME_PLATE_UNIT_ADDED","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT",
        "UNIT_CLASSIFICATION_CHANGED","UNIT_NAME_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED"}) do
        f:RegisterEvent(event)
    end
    f:SetScript("OnEvent",function(_,event,unit)
        if event=="PLAYER_ENTERING_WORLD" then self.seen={};self.pending=nil;self:Refresh()
        elseif event=="PLAYER_REGEN_ENABLED" then self:Refresh()
        else
            if event=="PLAYER_TARGET_CHANGED" then unit="target"
            elseif event=="UPDATE_MOUSEOVER_UNIT" then unit="mouseover" end
            self:Check(unit);self:Apply()
        end
    end)
    self:Refresh()
end
