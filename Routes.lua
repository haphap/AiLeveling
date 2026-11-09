local _, A = ...
A.Routes={lines={}}
local R=A.Routes

function R.Project(p,map,hbd,overview)
    if p.map==map then return p.x,p.y end
    if not overview or not hbd then return end
    local x,y,instance=hbd:GetWorldCoordinatesFromZone(p.x,p.y,p.map)
    if not x then return end
    return hbd:GetZoneCoordinatesFromWorldInstance(x,y,instance,map)
end

function R.Segments(actions,index,map,project,origin)
    local result,seen,missing={},{},0
    local previous=origin
    for i=index,#actions do
        local action=actions[i]
        local target=action.kind=="transit" and action.departure or action.position
        local from=previous or action.fromPosition
        if from and target then
            local x,y=project(from,map)
            local tx,ty=project(target,map)
            if x and tx and x>=0 and x<=1 and y>=0 and y<=1 and tx>=0 and tx<=1 and ty>=0 and ty<=1 and (x~=tx or y~=ty) then
                local a,b=x..":"..y,tx..":"..ty
                local key=a<b and (a..">"..b) or (b..">"..a)
                if not seen[key] then
                    seen[key]=true;result[#result+1]={x=x,y=y,tx=tx,ty=ty,current=i==index}
                end
            end
        elseif not target then missing=missing+1 end
        previous=action.position
    end
    return result,missing
end

function R:Hide()
    if self.overlay then self.overlay:Hide() end
    if self.legend then self.legend:Hide() end
end

function R:Update(force)
    local nav=A.Navigation
    if not A.settings.routes or A.char.paused or nav.manual or (A.Transport and A.Transport:InFlight()) or
        not WorldMapFrame or not WorldMapFrame:IsShown() then self:Hide();return end
    local canvas,map=WorldMapFrame:GetCanvas(),WorldMapFrame:GetMapID()
    if not canvas or not map then self:Hide();return end
    local width,height=canvas:GetSize()
    if not width or width<=0 or height<=0 then self:Hide();return end
    if self.canvas~=canvas then
        self:Hide();self.canvas=canvas;self.lines={}
        self.overlay=CreateFrame("Frame",nil,canvas);self.overlay:SetAllPoints(canvas)
        self.legend=CreateFrame("Frame",nil,WorldMapFrame);self.legend:SetSize(440,64);self.legend:SetPoint("TOPLEFT",18,-44)
        self.legend.text=A.UI:Text(self.legend,12,"accent");self.legend.text:SetAllPoints();self.key=nil
    end
    local key=table.concat({tostring(nav.actions),nav.index or 1,map,width,height,A.settings.accent or "teal",
        A.state.position and string.format("%s:%.4f:%.4f",A.state.position.map,A.state.position.x,A.state.position.y) or ""},":")
    if force or key~=self.key then
        for _,line in ipairs(self.lines) do line:Hide() end
        local info=C_Map.GetMapInfo(map)
        local kinds=Enum and Enum.UIMapType
        local overview=kinds and info and (info.mapType==kinds.World or info.mapType==kinds.Continent)
        self.segments,self.missing=R.Segments(nav.actions or {},nav.index or 1,map,function(p,view)
            return R.Project(p,view,nav.hbd,overview)
        end,A.state.position)
        self.key,self.cursor=key,1
    end
    local r,g,b=A.UI:Accent()
    local finish=math.min(#self.segments,(self.cursor or 1)+63)
    for i=self.cursor or 1,finish do
        local segment=self.segments[i]
        local line=self.lines[i]
        if not line then line=self.overlay:CreateLine(nil,"OVERLAY");self.lines[i]=line end
        line:ClearAllPoints()
        line:SetStartPoint("TOPLEFT",self.overlay,segment.x*width,-segment.y*height)
        line:SetEndPoint("TOPLEFT",self.overlay,segment.tx*width,-segment.ty*height)
        line:SetThickness(segment.current and 2.5 or 1.5)
        line:SetColorTexture(r,g,b,segment.current and 1 or 0.3);line:Show()
    end
    self.cursor=finish+1
    local label=#self.segments>0 and "AiLeveling · 目的地直线参考，当前目标亮显" or "AiLeveling · 当前地图暂无目的地连线"
    if self.missing>0 then label=label.."\n"..self.missing.." 项目标尚无坐标" end
    if self.cursor<=#self.segments then label=label..string.format("\n正在绘制 %d/%d 段",finish,#self.segments) end
    self.legend.text:SetText(label);self.overlay:Show();self.legend:Show()
end
