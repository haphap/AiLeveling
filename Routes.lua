local _, A = ...
A.Routes={}
local R=A.Routes

function R.Project(p,map,hbd,overview)
    if p.map==map then return p.x,p.y end
    if not overview or not hbd then return end
    local x,y,instance=hbd:GetWorldCoordinatesFromZone(p.x,p.y,p.map)
    if not x then return end
    return hbd:GetZoneCoordinatesFromWorldInstance(x,y,instance,map)
end

function R.Endpoints(origin,target,map,hbd,overview)
    if not origin or not target then return end
    local x,y=R.Project(origin,map,hbd,overview)
    local tx,ty=R.Project(target,map,hbd,overview)
    if x and tx and x>=0 and x<=1 and y>=0 and y<=1 and tx>=0 and tx<=1 and ty>=0 and ty<=1 and
        (x~=tx or y~=ty) then return x,y,tx,ty end
end

function R:Hide()
    if self.line then self.line:Hide() end
end

function R:Update(force)
    local nav=A.Navigation
    if not A.settings.routes or A.char.paused or (A.Transport and A.Transport:InFlight()) or
        not WorldMapFrame or not WorldMapFrame:IsShown() then self:Hide();return end
    local canvas,map=WorldMapFrame:GetCanvas(),WorldMapFrame:GetMapID()
    if not canvas or not map then self:Hide();return end
    local width,height=canvas:GetSize()
    if not width or width<=0 or height<=0 then self:Hide();return end
    if map~=self.map or force then
        local info=C_Map.GetMapInfo(map)
        local kinds=Enum and Enum.UIMapType
        self.map=map
        self.overview=info and kinds and (info.mapType==kinds.World or info.mapType==kinds.Continent)
    end
    local x,y,tx,ty=R.Endpoints(A.state.position,nav.Target(nav:Current()),map,nav.hbd,self.overview)
    if not x then self:Hide();return end
    if self.canvas~=canvas then
        self:Hide();self.canvas=canvas
        local overlay=CreateFrame("Frame",nil,canvas);overlay:SetAllPoints(canvas)
        self.line=overlay:CreateLine(nil,"OVERLAY")
        self.line:SetTexture("Interface\\AddOns\\AiLeveling\\Media\\map-dash.tga","REPEAT","CLAMP")
        self.line:SetThickness(2)
        force=true
    end
    x,y,tx,ty=x*width,-y*height,tx*width,-ty*height
    if force or self.x~=x or self.y~=y or self.tx~=tx or self.ty~=ty then
        self.line:SetStartPoint("TOPLEFT",canvas,x,y)
        self.line:SetEndPoint("TOPLEFT",canvas,tx,ty)
        self.line:SetTexCoord(0,math.sqrt((tx-x)^2+(ty-y)^2)/8,0,1)
        self.line:SetVertexColor(A.UI:ClassColor())
        self.x,self.y,self.tx,self.ty=x,y,tx,ty
    end
    self.line:Show()
end
