local _,A=...
local UI=A.UI
local B=UI.Browser

local phases={
    open={kind="accept",label="接取",priority=1},active={kind="objective",icon="active",label="目标",priority=2},
    ready={kind="turnin",label="交付",priority=3},done={kind="done",label="已交付",priority=0},
}

local function mapName(map)
    local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or ("地图 #"..map)
end

local function regionLocations(entry,home,stats,filter)
    local data=A.Data
    local state=setmetatable({browseMap=home,objectiveTargets={}},{__index=A.state})
    local maps,locations,seen={[home]={}},{},{}
    local function add(q,key)
        if not q or seen[q.id] or (filter and filter~=key) or (key=="done" and not filter) then return end
        seen[q.id]=true
        local phase=phases[key]
        local notes={}
        locations[q.id]=notes
        local blocked
        if key=="open" then
            local ok,reason=A.Eligibility.Check(q,state,data)
            if not ok then
                blocked=reason or "暂不可接"
                if not filter then notes[1]=blocked;return end
            end
        end
        local function record(p,hint)
            local offers=p and p.entityId and (state.questOffers or {})[p.entityId]
            local offer=offers and offers[q.id]
            local surveyed=p and (not p.approximate or p.sourceKind=="patrol" or p.sourceKind=="observation" or type(offer)=="table" and offer.nativeOffer==p)
            if not (surveyed and p.map and p.x and p.y and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1 and not p.startItemId and not p.areaOnly) then
                notes[#notes+1]=hint or p and p.travelHint or (phase.label.."位置待确认")
                return
            end
            local goal=p.objectiveIndex and state.quests[q.id] and (state.quests[q.id].objectives or {})[p.objectiveIndex]
            local title=state.quests[q.id] and state.quests[q.id].title or q.title
            local goalName=goal and goal.text and goal.text:gsub("%s*%d+%s*/%s*%d+","")
            local name=p.siteName or p.entityName or goalName or phase.label.."地点"
            local location=string.format("%s  %.1f, %.1f",name,p.x*100,p.y*100)
            if p.approximate then location=location.." · "..(p.sourceKind=="patrol" and "巡逻" or "参考位置") end
            local label=phase.label.." · "..title
            if goalName then label=label.." · "..goalName end
            if blocked then label=label.." · "..blocked end
            maps[p.map]=maps[p.map] or {}
            table.insert(maps[p.map],{quest=q,point=p,key=key,blocked=blocked,title=title,label=label,location=location})
            notes[#notes+1]=(p.map~=home and (mapName(p.map).." · ") or "")..location..(blocked and (" · "..blocked) or "")
            return true
        end
        if key=="active" and data.ObjectiveTargets then
            local points=data:ObjectiveTargets(q,state)
            if #points>0 then
                local located=false
                for _,point in ipairs(points) do
                    if record(point) then located=true end
                end
                if located then return end
                -- The client may supply a waypoint even when every database match is area-only.
                wipe(notes)
            end
        end
        -- A completed quest is read at its recorded recipient, without changing the live log.
        local source=state
        if key=="done" then source=setmetatable({quests={[q.id]={ready=true}}},{__index=state}) end
        local point,unavailable,item=data:Target(q,source,home)
        if unavailable then notes[1]=blocked or (key=="open" and "当前不可接取" or "地点待确认");return end
        record(point,item and item.text)
    end
    if stats then
        for _,key in ipairs({"ready","active","open","done"}) do
            if (not filter and key~="done") or filter==key then
                for _,q in ipairs(stats[key]) do add(q,key) end
            end
        end
    end
    -- A visit can include a quest catalogued elsewhere but picked up or worked on here.
    local visit=entry.region
    if visit and not filter then
        for _,group in ipairs({visit.choices or {},visit.pickups or {},visit.handins or {}}) do
            for _,c in ipairs(group) do
                local id=c.questId
                local live=state.quests[id]
                if not seen[id] and not state.completed[id] then
                    add(data:GetQuest(id),live and (live.ready and "ready" or "active") or "open")
                end
            end
        end
    end
    return maps,locations
end

local function textureSize(n)
    local size=16
    while size<n do size=size*2 end
    return size
end

local function drawArt(canvas,map,width)
    if not C_Map then return 0 end
    local art=C_Map.GetMapArtID and C_Map.GetMapArtID(map)
    if canvas.map==map and canvas.art==art and canvas.widthUsed==width then return canvas:GetHeight() end
    for _,t in ipairs(canvas.tiles) do t:Hide() end
    local layers=C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(map)
    local layer=layers and layers[1]
    local files=layer and C_Map.GetMapArtLayerTextures(map,1)
    if not files or #files==0 then canvas.map=nil;return 0 end
    local w,h,tw,th=layer.layerWidth,layer.layerHeight,layer.tileWidth,layer.tileHeight
    local scale=width/w
    canvas:SetSize(width,h*scale)
    local used=0
    local function draw(files,x,y,span,height,overlay)
        local cols=math.ceil(span/tw)
        for i,file in ipairs(files) do
            local col,row=(i-1)%cols,math.floor((i-1)/cols)
            local px,py=x+col*tw,y+row*th
            local pw,ph=math.min(tw,span-col*tw),math.min(th,height-row*th)
            local left,top,right,bottom=math.max(0,px),math.max(0,py),math.min(w,px+pw),math.min(h,py+ph)
            if right>left and bottom>top then
                used=used+1
                local t=canvas.tiles[used] or canvas:CreateTexture(nil,"BACKGROUND")
                canvas.tiles[used]=t
                t:SetDrawLayer(overlay and "ARTWORK" or "BACKGROUND",overlay or 0)
                t:SetPoint("TOPLEFT",left*scale,-top*scale);t:SetSize((right-left)*scale,(bottom-top)*scale)
                local fw,fh=overlay and textureSize(pw) or tw,overlay and textureSize(ph) or th
                t:SetTexCoord((left-px)/fw,(right-px)/fw,(top-py)/fh,(bottom-py)/fh)
                t:SetTexture(file);t:Show()
            end
        end
    end
    draw(files,0,0,w,h)
    local explored=C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures(map)
    for _,area in ipairs(explored or {}) do
        if not area.isShownByMouseOver then
            draw(area.fileDataIDs,area.offsetX,area.offsetY,area.textureWidth,area.textureHeight,area.isDrawOnTopLayer and 1 or 0)
        end
    end
    canvas.map,canvas.art,canvas.widthUsed=map,art,width
    return h*scale
end

local function navigate(row)
    local q,p=row.quest,row.point
    if row.key=="done" or row.blocked then UI:QuestClick(q.id,"LeftButton");return end
    local kind=phases[row.key].kind
    local allowed=kind~="accept" or A.Eligibility.Check(q,A.state,A.Data)
    if allowed and A.Navigation:Navigate({kind=kind,questId=q.id,title=row.title,position=p,
        objectiveIndex=p.objectiveIndex,text=p.travelHint or (row.label.." · "..row.location)}) then
        UI.details:Hide()
    else B:Detail();A:Message("当前无法开始这项任务导航。") end
end

local function newPin(canvas)
    local pin=CreateFrame("Button",nil,canvas)
    local disc=pin:CreateTexture(nil,"BACKGROUND");disc:SetAllPoints()
    disc:SetTexture(UI.IconTexture("map-markers"))
    disc:SetTexCoord(0,.5,0,1);disc:SetVertexColor(.10,.12,.18)
    local icon=pin:CreateTexture(nil,"ARTWORK");icon:SetPoint("CENTER");icon:SetSize(16,16)
    pin.icon=icon
    pin:SetScript("OnEnter",function(b)
        GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
        GameTooltip:SetText("区域任务")
        for _,row in ipairs(b.rows) do
            GameTooltip:AddDoubleLine(row.label,row.location,1,.82,.35,.8,.87,1)
        end
        local first=b.rows[1]
        local action=#b.rows>1 and "点击选择任务" or (first.key=="done" or first.blocked) and "点击查看任务详情" or "点击开始导航"
        GameTooltip:AddLine(action)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    pin:SetScript("OnClick",function(b)
        if #b.rows==1 then navigate(b.rows[1]);return end
        MenuUtil.CreateContextMenu(b,function(_,menu)
            for _,row in ipairs(b.rows) do
                menu:CreateButton(row.label,function() navigate(row) end)
            end
        end)
    end)
    return pin
end

local function placePins(canvas,rows,width,height)
    local used,size=0,22*UI:FontScale()
    if canvas.rows==rows and canvas.pinWidth==width and canvas.pinHeight==height and canvas.pinSize==size then return end
    canvas.rows,canvas.pinWidth,canvas.pinHeight,canvas.pinSize=rows,width,height,size
    for _,r in ipairs(rows) do
        local x,y=r.point.x*width,r.point.y*height
        local pin
        for i=1,used do
            local b=canvas.pins[i]
            if math.abs(x-b.x)<size and math.abs(y-b.y)<size then pin=b;break end
        end
        if not pin then
            used=used+1
            pin=canvas.pins[used] or newPin(canvas);canvas.pins[used]=pin
            pin.x,pin.y,pin.rows,pin.primary=x,y,{},r
            pin:SetPoint("CENTER",canvas,"TOPLEFT",x,-y);pin:SetSize(size,size);pin:Show()
        elseif phases[r.key].priority>phases[pin.primary.key].priority or (pin.primary.blocked and not r.blocked) then
            pin.primary=r
        end
        table.insert(pin.rows,r)
    end
    for i=1,used do
        local pin=canvas.pins[i]
        local phase=phases[pin.primary.key]
        pin.icon:SetTexture(UI.IconTexture(phase.icon or phase.kind))
        pin.icon:SetDesaturated(pin.primary.blocked~=nil)
        UI:SetMapPinNumber(pin,#pin.rows>1 and #pin.rows,width)
    end
    for i=used+1,#canvas.pins do canvas.pins[i]:Hide() end
end

function B:OpenRegionMapMenu(owner)
    local view=self.regionMap
    UI:Menu(owner,function(_,menu)
        for _,map in ipairs(view.mapIDs) do
            menu:CreateButton(mapName(map).." · "..view.counts[map].." 项任务",function()
                view.shownMap=map;self.info:SetVerticalScroll(0);self:Detail()
            end)
        end
    end)
end

function B:RegionMapTitle(entry,stats,filter)
    local home=entry.map or entry.region.map
    local view=self.regionMap
    if not view then
        view=CreateFrame("Frame",nil,self.infoChild);self.regionMap=view
        view.canvas=CreateFrame("Frame",nil,view)
        view.canvas.pins,view.canvas.tiles={},{}
        view.note=UI:Text(view,"guideNote",UI.colors.muted)
        view:RegisterEvent("MAP_EXPLORATION_UPDATED")
        view:SetScript("OnEvent",function()
            view.canvas.map=nil
            if view:IsVisible() then self:Detail() end
        end)
    end
    if home~=view.home or view.filter~=filter then view.shownMap=home end
    if home~=view.home or view.zone~=entry.catalogZone or view.region~=entry.region or view.revision~=A.state.revision or view.filter~=filter then
        view.maps,view.locations=regionLocations(entry,home,stats,filter)
        view.filter=filter
        view.mapIDs,view.counts={},{}
        for map,rows in pairs(view.maps) do
            local counted,count={},0
            for _,row in ipairs(rows) do
                if not counted[row.quest.id] then counted[row.quest.id]=true;count=count+1 end
            end
            table.insert(view.mapIDs,map);view.counts[map]=count
        end
        table.sort(view.mapIDs,function(a,b)
            if a==home or b==home then return a==home and a~=b end
            return a<b
        end)
        view.home,view.zone,view.region,view.revision=home,entry.catalogZone,entry.region,A.state.revision
    end
    if not view.maps[view.shownMap] then view.shownMap=home end
    local map=view.shownMap
    local where=map==home and "本图" or mapName(map)
    local title=entry.title.."  |cff"..UI.hex.muted.."·  "..where.." "..view.counts[map].." 项|r"
    if #view.mapIDs>1 then return "|Hailregionmap:select|h"..title.."  ▼|h" end
    return title
end

function B:ShowRegionMap(top)
    local view=self.regionMap
    local map=view.shownMap
    local rows,width,gap=view.maps[map],self.info:GetWidth(),UI.metrics.gap*UI:FontScale()
    view:SetPoint("TOPLEFT",0,-top);view:SetWidth(width);view:Show()
    local y=0
    local canvas=view.canvas
    local height=drawArt(canvas,map,width)
    canvas:SetPoint("TOPLEFT",view,"TOPLEFT",0,-y);canvas:SetShown(height>0)
    if height>0 then placePins(canvas,rows,canvas:GetWidth(),height);y=height end
    local note=height==0 and "底图暂不可用，可在列表查看地点" or #rows==0 and "本图暂无符合条件的任务点"
    view.note:SetShown(not not note)
    if note then
        if height>0 then y=y+gap end
        view.note:SetPoint("TOPLEFT",0,-y);view.note:SetWidth(width);view.note:SetText(note)
        y=y+view.note:GetStringHeight()
    end
    view:SetHeight(y)
    return top+view:GetHeight()+gap,view.locations
end
