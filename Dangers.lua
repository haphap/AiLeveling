local _,A=...
A.Dangers={pins={},lines={},glows={}}
local D=A.Dangers

local function accessible(value)
    return not (issecretvalue and issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value))
end
local function read(fn,...)
    if not fn then return end
    local ok,value=pcall(fn,...)
    if ok and accessible(value) then return value end
end

function D:HideMap()
    if self.overlay then self.overlay:Hide() end
    if self.mapKey and A.Navigation.hbdPins then A.Navigation.hbdPins:RemoveAllWorldMapIcons(self) end
    for _,pin in ipairs(self.pins) do pin:Hide() end
    self.mapKey=nil
end

function D:MapRows(map)
    local zones=A.DangerData[A.state.faction] or {}
    local rows={}
    for _,row in ipairs(zones[map] or {}) do
        if row.maxLevel>=(A.state.level or 1)-(row.classification=="Normal" and 1 or 3) then rows[#rows+1]=row end
    end
    return rows
end

function D:MapPin(index,row,map,x,y,patrol)
    local pin=self.pins[index]
    if not pin then
        pin=CreateFrame("Frame",nil,UIParent);self.pins[index]=pin
        pin:SetSize(18,18);pin:EnableMouse(true)
        pin.texture=pin:CreateTexture(nil,"OVERLAY");pin.texture:SetAllPoints()
        pin.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
        pin:SetScript("OnEnter",function(f)
            local entry=f.row
            GameTooltip:SetOwner(f,"ANCHOR_RIGHT")
            GameTooltip:SetText(A.Data.dangerNames and A.Data.dangerNames[entry.name] or entry.name,1,0.4,0.3)
            local classification=({Normal="普通",Elite="精英",Rare="稀有",["Rare Elite"]="稀有精英"})[entry.classification] or entry.classification
            local movement=({Idle="定点",["Slow Patrol"]="缓慢巡逻",["Fast Patrol"]="快速巡逻",["Patrols slightly"]="小范围巡逻"})[entry.movement]
            GameTooltip:AddLine(entry.minLevel.."—"..entry.maxLevel.." 级 · "..classification..
                (movement and (" · "..movement) or f.patrol and " · 巡逻" or ""),1,1,1)
            if entry.note~="" then GameTooltip:AddLine(entry.note,1,0.85,0.7,true) end
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    pin.row,pin.patrol=row,patrol
    A.Navigation.hbdPins:AddWorldMapIconMap(self,pin,map,x,y)
end

function D:UpdateMap()
    if not A.settings.dangerMap or A.char.paused or not WorldMapFrame or not WorldMapFrame:IsShown() or not A.Navigation.hbdPins then
        self:HideMap();return
    end
    local map,canvas=WorldMapFrame:GetMapID(),WorldMapFrame:GetCanvas()
    if not map or not canvas then self:HideMap();return end
    local width,height=canvas:GetSize()
    if width<=0 or height<=0 then self:HideMap();return end
    if self.canvas~=canvas then
        self:HideMap();self.canvas=canvas;self.lines={}
        self.overlay=CreateFrame("Frame",nil,canvas);self.overlay:SetAllPoints(canvas)
    end
    local key=table.concat({map,A.state.faction or "",A.state.level or 1,width,height},":")
    if self.mapKey~=key then
        self:HideMap();self.mapKey=key;self.segments={};self.cursor=1
        for _,line in ipairs(self.lines) do line:Hide() end
        local count=0
        for _,row in ipairs(self:MapRows(map)) do
            for i=1,#row.points,2 do count=count+1;self:MapPin(count,row,map,row.points[i],row.points[i+1]) end
            for _,path in ipairs(row.paths) do
                count=count+1;self:MapPin(count,row,map,path[1],path[2],true)
                for i=3,#path,2 do
                    self.segments[#self.segments+1]={path[i-2],path[i-1],path[i],path[i+1]}
                end
            end
        end
    end
    local finish=math.min(#self.segments,self.cursor+63)
    for i=self.cursor,finish do
        local segment,line=self.segments[i],self.lines[i]
        if not line then line=self.overlay:CreateLine(nil,"OVERLAY");self.lines[i]=line end
        line:ClearAllPoints();line:SetStartPoint("TOPLEFT",self.overlay,segment[1]*width,-segment[2]*height)
        line:SetEndPoint("TOPLEFT",self.overlay,segment[3]*width,-segment[4]*height)
        line:SetThickness(1.5);line:SetColorTexture(1,0.3,0.2,0.65);line:Show()
    end
    self.cursor=finish+1;self.overlay:Show()
end

function D:Glow(button)
    if not button or not button:IsShown() or button.IsForbidden and button:IsForbidden() then return end
    local texture=self.glows[button]
    if not texture then
        texture=button:CreateTexture(nil,"OVERLAY");texture:SetAllPoints()
        texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");texture:SetBlendMode("ADD")
        texture:SetVertexColor(1,0.3,0.1);self.glows[button]=texture
    end
    texture:SetAlpha(0.65+0.35*math.abs(math.sin(GetTime()*4)));texture:Show()
end

function D:EmergencyGlows()
    local data=A.DangerData
    for _,bar in ipairs({"Action","MultiBarBottomLeft","MultiBarBottomRight","MultiBarLeft","MultiBarRight","MultiBar5","MultiBar6","MultiBar7"}) do
        for i=1,12 do
            local button=_G[bar.."Button"..i]
            if button and not (button.IsForbidden and button:IsForbidden()) then
                local slot=read(button.GetPagedID,button)
                if slot then
                    local ok,kind,id=pcall(GetActionInfo,slot)
                    if ok and accessible(kind) and accessible(id) then
                        if kind=="macro" then kind,id="spell",read(C_ActionBar and C_ActionBar.GetSpell,slot) end
                        if kind=="spell" and data.spells[id] or kind=="item" and data.items[id] and (A.state.bags[id] or 0)>0 then self:Glow(button) end
                    end
                end
            end
        end
    end
    A.QuestAssist:EachBagButton(function(button,bag,slot)
        local id=read(C_Container.GetContainerItemID,bag,slot)
        if id and data.items[id] then self:Glow(button) end
    end)
end

function D:Emergency()
    for _,texture in pairs(self.glows) do texture:Hide() end
    local reason
    if A.settings.emergency and not A.char.paused and read(UnitIsDeadOrGhost,"player")~=true then
        local health,maximum=read(UnitHealth,"player"),read(UnitHealthMax,"player")
        if type(health)=="number" and type(maximum)=="number" and maximum>0 and health>0 and health/maximum<0.2 then
            reason="生命危急";self:EmergencyGlows()
        end
        for i=1,3 do
            local kind,_,maxValue,rate,paused=GetMirrorTimerInfo(i)
            if accessible(kind) and kind=="BREATH" and accessible(rate) and rate<0 and accessible(paused) and (paused==0 or paused==false) then
                local remaining=read(GetMirrorTimerProgress,"BREATH")
                if accessible(maxValue) and type(maxValue)=="number" and maxValue>0 and type(remaining)=="number" and remaining/maxValue<0.2 then
                    reason="呼吸将尽 · 尽快上浮"
                end
            end
        end
    end
    if reason and not self.warning then
        local f=CreateFrame("Frame",nil,UIParent);self.warning=f
        f:SetAllPoints();f:EnableMouse(false);f:SetFrameStrata("HIGH")
        for _,side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
            local edge=f:CreateTexture(nil,"OVERLAY");edge:SetColorTexture(1,0.1,0.05,0.2)
            if side=="TOP" or side=="BOTTOM" then edge:SetPoint(side.."LEFT");edge:SetPoint(side.."RIGHT");edge:SetHeight(12)
            else edge:SetPoint("TOP"..side);edge:SetPoint("BOTTOM"..side);edge:SetWidth(12) end
        end
        f.text=A.UI:Text(f,18,{1,0.35,0.2});f.text:SetPoint("TOP",0,-135)
    end
    if self.warning then
        self.warning:SetShown(reason~=nil)
        if reason then self.warning.text:SetText(reason) end
    end
    if reason and reason~=self.lastWarning then
        if A.settings.sound and PlaySound then PlaySound(SOUNDKIT.RAID_WARNING,"Master") end
        if FlashClientIcon then FlashClientIcon() end
    end
    self.lastWarning=reason
end

function D:Update()
    self:UpdateMap()
    local now=GetTime()
    if now<(self.nextEmergency or 0) then return end
    self.nextEmergency=now+0.5;self:Emergency()
end
