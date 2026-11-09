local _,A=...
A.WorldInteract={plates={}}
local W=A.WorldInteract
local unit="softinteract"
local colors={quest={1,0.78,0.25},herb={0.35,0.9,0.5},ore={1,0.5,0.18},loot={0.35,0.7,1}}
local cursors={Quest="quest",QuestInteract="quest",QuestTurnIn="quest",QuestRepeatable="quest",
    Mine="ore",GatherHerbs="herb",Pickup="loot",LootAll="loot",PickLock="loot"}
local profile={SoftTargetInteract="3",SoftTargetNameplateInteract="1",SoftTargetIconGameObject="1",
    SoftTargetInteractRange="15",SoftTargetInteractOnlyInRange="0",nameplateGameObjectMaxDistance="60"}

local function read(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function get(name) return read(C_CVar and C_CVar.GetCVar or GetCVar,name) end
local function same(a,b)
    return a==b or tonumber(a)~=nil and tonumber(a)==tonumber(b)
end
local function set(name,value)
    local fn=C_CVar and C_CVar.SetCVar or SetCVar
    if type(fn)~="function" then return false end
    local ok=pcall(fn,name,value)
    return ok and same(get(name),value)
end

function W:Restore()
    if InCombatLockdown() then return end
    if type(A.char.interactCVars)~="table" then A.char.interactCVars=nil;return end
    for name,saved in pairs(A.char.interactCVars or {}) do
        if profile[name] and type(saved)=="table" and type(saved.before)=="string" then
            local current=get(name)
            -- Leave subsequent changes by the player or another addon in place.
            if current and (not same(current,saved.applied) or set(name,saved.before)) then A.char.interactCVars[name]=nil end
        else A.char.interactCVars[name]=nil end
    end
    if not next(A.char.interactCVars or {}) then A.char.interactCVars=nil end
end

function W:Refresh()
    if not self.events or not A.settings or not A.char then return end
    local other=read(C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded,"Lueur")
    local enabled=not self.leaving and A.settings.worldHighlight and not A.char.paused and not other
    if not enabled then
        self.enabled=false;self.glow:Hide();self:Restore();return
    end
    if InCombatLockdown() then self.glow:Hide();return end
    if not self.enabled then
        self:Restore()
        A.char.interactCVars=A.char.interactCVars or {}
        for name,value in pairs(profile) do
            local before=get(name)
            if type(before)=="string" and not same(before,value) and not A.char.interactCVars[name] then
                A.char.interactCVars[name]={before=before,applied=value}
                set(name,value)
            end
        end
        self.enabled=true
    end
    self:Update()
end

function W:Category()
    self.probe:SetTexture(nil)
    local hasCursor=read(SetUnitCursorTexture,self.probe,unit,nil,true)
    local texture=read(self.probe.GetTexture,self.probe)
    local info=texture and self.cursorIDs[texture]
    local category,blocked=info and info.kind,info and info.blocked
    if not info and type(texture)=="string" then
        local name=texture:match("([^\\/]+)$") or texture
        name=name:gsub("%.%w+$","")
        blocked=name:find("Unable",1,true)~=nil
        category=cursors[(name:gsub("Unable", ""))]
    end
    if read(C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest,unit)==true then category="quest" end
    if not hasCursor and not category then return end
    return category,blocked
end

function W:Update()
    local glow=self.glow
    if not glow then return end
    if not self.enabled or self.leaving or InCombatLockdown() or A.char.paused or
        read(UnitIsGameObject,unit)~=true then glow:Hide();return end
    local plate=read(C_NamePlate.GetNamePlateForUnit,unit)
    if not plate then
        local guid=read(UnitGUID,unit)
        for token in pairs(self.plates) do
            if read(UnitIsUnit,token,unit)==true or guid and read(UnitGUID,token)==guid then
                plate=read(C_NamePlate.GetNamePlateForUnit,token);if plate then break end
            end
        end
    end
    local category,blocked=self:Category()
    if not plate or not category or not colors[category] then glow:Hide();return end
    if read(plate.IsForbidden,plate)==true or read(plate.IsShown,plate)==false then glow:Hide();return end
    local range=read(UnitIsInInteractRange,unit)
    local status=range==false and "far" or blocked and "blocked" or range==true and "ready" or "unknown"
    local color=status=="blocked" and {0.5,0.5,0.5} or colors[category]
    glow:ClearAllPoints();glow:SetPoint("CENTER",plate,"CENTER",0,0)
    glow.ring:SetVertexColor(unpack(color))
    glow.ring:SetAlpha(status=="ready" and (0.7+0.2*math.sin(GetTime()*4)) or status=="far" and 0.3 or 0.5)
    local name=read(UnitName,unit) or ({quest="任务物件",herb="草药",ore="矿点",loot="可拾取物件"})[category]
    local key=status=="ready" and read(GetBindingKey,"INTERACTTARGET")
    glow.label:SetText(name..(key and ("  ["..key.."]") or ""))
    glow.label:SetTextColor(unpack(color));glow:Show()
end

function W:Initialize()
    if self.events or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit or
        not UnitIsGameObject or not SetUnitCursorTexture then return end
    local f=CreateFrame("Frame")
    self.events=f
    local glow=CreateFrame("Frame",nil,UIParent)
    glow:SetSize(64,64);glow:EnableMouse(false);glow:SetFrameStrata("BACKGROUND")
    glow.ring=glow:CreateTexture(nil,"OVERLAY");glow.ring:SetAllPoints()
    glow.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");glow.ring:SetBlendMode("ADD")
    glow.label=glow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    glow.label:SetPoint("TOP",glow,"BOTTOM",0,2);glow.label:SetWidth(240)
    glow.label:SetShadowColor(0,0,0,1);glow.label:SetShadowOffset(1,-1)
    glow:Hide();self.glow=glow
    self.probe=f:CreateTexture();self.probe:Hide();self.cursorIDs={}
    for name,kind in pairs(cursors) do
        for _,suffix in ipairs({"","Unable"}) do
            self.probe:SetTexture("Interface\\Cursor\\"..name..suffix)
            local id=read(self.probe.GetTexture,self.probe)
            if type(id)=="number" then self.cursorIDs[id]={kind=kind,blocked=suffix~=""} end
        end
    end
    for _,event in ipairs({"PLAYER_SOFT_INTERACT_CHANGED","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED",
        "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","ADDON_LOADED"}) do
        pcall(f.RegisterEvent,f,event)
    end
    f:SetScript("OnEvent",function(_,event,token)
        if event=="PLAYER_LOGOUT" then self.leaving=true;self:Refresh()
        elseif event=="PLAYER_REGEN_DISABLED" then glow:Hide()
        elseif event=="NAME_PLATE_UNIT_ADDED" then self.plates[token]=true;self:Update()
        elseif event=="NAME_PLATE_UNIT_REMOVED" then self.plates[token]=nil;glow:Hide()
        elseif event=="PLAYER_ENTERING_WORLD" then self.plates={};self:Refresh()
        elseif event=="PLAYER_SOFT_INTERACT_CHANGED" then self:Update()
        else self:Refresh() end
    end)
    local elapsed=0
    f:SetScript("OnUpdate",function(_,delta)
        elapsed=elapsed+delta
        if elapsed>=0.1 then elapsed=0;self:Update() end
    end)
    self:Refresh()
end
