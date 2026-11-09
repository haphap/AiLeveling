return function(test,eq,F,A)
local function point(x,y,map) return {map=map or 1,x=x,y=y} end
local function engine()
    local B={Travel=A.Travel,settings={routes=true},char={},Navigation={index=1,actions={}},state={position=point(0,0)},
        Transport={InFlight=function() return false end},UI={}}
    assert(loadfile("Routes.lua"))("AiLeveling",B)
    return B
end
local function direct(p,map) if p.map==map then return p.x,p.y end end
test("目的地连线去重且不会把飞行航程画成地面连接",function()
    local B=engine();local a,b,c=point(0,0),point(1,1),point(1,1,2)
    local actions={{kind="transit",departure=b,position=c,mode="flight"},{kind="objective",position=point(0,0,2)}}
    local segments=B.Routes.Segments(actions,1,1,direct,a);eq(#segments,1);eq(segments[1].tx,1)
    eq(#B.Routes.Segments(actions,2,1,direct,c),0)
    actions={{kind="move",position=b},{kind="objective",position=a}}
    eq(#B.Routes.Segments(actions,1,1,direct,a),1)
end)
test("总览坐标转换须匹配世界实例且区域楼层只精确匹配",function()
    local B=engine()
    local hbd={GetWorldCoordinatesFromZone=function(_,x,y,map) return x*100,y*100,map==1 and 100 or 200 end,
        GetZoneCoordinatesFromWorldInstance=function(_,x,y,instance) if instance==100 then return x/100,y/100 end end}
    eq(B.Routes.Project(point(0.5,0.5),10,hbd,false),nil)
    eq(B.Routes.Project(point(0.5,0.5),10,hbd,true),0.5)
    eq(B.Routes.Project(point(0.5,0.5,2),10,hbd,true),nil)
end)
local function widget()
    local w={shown=true}
    w.SetSize=function(self,x,y) self.width,self.height=x,y end;w.GetSize=function(self) return self.width,self.height end
    w.SetAllPoints=function() end;w.SetPoint=function() end;w.ClearAllPoints=function() end
    w.SetText=function(self,value) self.value=value end
    w.Show=function(self) self.shown=true end;w.Hide=function(self) self.shown=false end;w.IsShown=function(self) return self.shown end
    w.SetStartPoint=function(self,anchor,parent,x,y) self.start={x,y} end
    w.SetEndPoint=function(self,anchor,parent,x,y) self.finish={x,y} end
    w.SetThickness=function(self,n) self.thickness=n end
    w.SetColorTexture=function(self,r,g,b,a) self.alpha=a end
    w.CreateLine=function() return widget() end
    return w
end
test("原生地图绘制目的地直线且关闭和换图清除旧连线",function()
    local saved={CreateFrame=CreateFrame,WorldMapFrame=WorldMapFrame,Enum=Enum,C_Map=C_Map}
    local B=engine();CreateFrame=function() return widget() end
    local canvas=widget();canvas:SetSize(1000,500)
    local map=1;WorldMapFrame=widget();WorldMapFrame.GetCanvas=function() return canvas end;WorldMapFrame.GetMapID=function() return map end
    Enum={UIMapType={World=1,Continent=2,Zone=3}};C_Map={GetMapInfo=function() return {mapType=3} end}
    B.UI.Text=function() return widget() end;B.UI.Accent=function() return 0.2,0.8,0.7 end
    B.Navigation.actions={{kind="objective",position=point(1,0)}}
    B.Routes:Update();eq(#B.Routes.lines,1)
    eq(B.Routes.lines[1].start[1],0);eq(B.Routes.lines[1].finish[1],1000)
    assert(B.Routes.legend.text.value:find("直线参考",1,true))
    B.settings.routes=false;B.Routes:Update();eq(B.Routes.overlay.shown,false)
    B.settings.routes=true;map=2;B.Routes:Update();eq(#B.Routes.segments,0);eq(B.Routes.lines[1].shown,false)
    for key,value in pairs(saved) do _G[key]=value end
    if saved.WorldMapFrame==nil then WorldMapFrame=nil end
    if saved.Enum==nil then Enum=nil end
end)
end
