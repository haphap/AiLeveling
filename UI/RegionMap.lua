local _,A=...
local UI=A.UI
local B=UI.Browser

-- Only resolve starters for the selected region, when its pickup map is open.
local function pickupLocations(entry,home)
    local data,state=A.Data,A.state
    local maps,other,seen={[home]={}},{},{}
    local function add(q)
        if not q or seen[q.id] then return end
        seen[q.id]=true
        if state.quests[q.id] or state.completed[q.id] or not A.Eligibility.Check(q,state,data) then return end
        local p,unavailable,item=data:Target(q,state,home)
        if unavailable then return end
        local row={quest=q,point=p}
        local offers=p and p.entityId and (state.questOffers or {})[p.entityId]
        local offer=offers and offers[q.id]
        if p and p.map and p.x and p.y and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1 and
            not p.startItemId and not p.areaOnly and
            (not p.approximate or p.sourceKind=="patrol" or type(offer)=="table" and offer.nativeOffer==p) then
            local who=p.entityName or "任务发布者"
            row.location=string.format("%s  %.1f, %.1f",who,p.x*100,p.y*100)
            if p.approximate then row.location=row.location..(p.sourceKind=="patrol" and " · 巡逻" or " · 对话位置") end
            maps[p.map]=maps[p.map] or {}
            table.insert(maps[p.map],row)
        else
            row.location=item and item.text or p and p.travelHint or "接取位置待确认"
            other[#other+1]=row
        end
    end
    for _,q in ipairs(entry.catalogZone and entry.catalogZone.quests or {}) do add(q) end
    for _,c in ipairs(entry.region and entry.region.pickups or {}) do add(data:GetQuest(c.questId)) end
    return maps,other
end

local function mapName(map)
    local info=C_Map.GetMapInfo(map)
    return info and info.name or ("地图 #"..map)
end

local function textureSize(n)
    local size=16
    while size<n do size=size*2 end
    return size
end

local function drawArt(canvas,map,width)
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
    if not A.Eligibility.Check(q,A.state,A.Data) or A.state.completed[q.id] or A.state.quests[q.id] then
        B:Detail();A:Message("这项任务当前不可接取。");return
    end
    if A.Navigation:Pickup({kind="accept",questId=q.id,title=q.title,position=p,
        text=p.travelHint or ("前往"..(p.entityName or "任务发布者").."接取「"..q.title.."」。")}) then
        UI.details:Hide()
    else A:Message("当前无法开始这项接取导航。") end
end

local function newPin(canvas)
    local pin=CreateFrame("Button",nil,canvas)
    local disc=pin:CreateTexture(nil,"BACKGROUND");disc:SetAllPoints()
    disc:SetTexture(UI.IconTexture("map-markers"))
    disc:SetTexCoord(0,.5,0,1);disc:SetVertexColor(.10,.12,.18)
    local icon=pin:CreateTexture(nil,"ARTWORK");icon:SetPoint("CENTER");icon:SetSize(16,16)
    icon:SetTexture(UI.IconTexture("accept"))
    pin.count=UI:Text(pin,"guideLabel",UI.colors.white);pin.count:SetPoint("BOTTOMLEFT",pin,"TOPRIGHT",-6,-9)
    pin:SetScript("OnEnter",function(b)
        GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
        GameTooltip:SetText("可接任务")
        for _,row in ipairs(b.rows) do
            GameTooltip:AddDoubleLine(row.quest.title,row.location,1,.82,.35,.8,.87,1)
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    pin:SetScript("OnClick",function(b)
        if #b.rows==1 then navigate(b.rows[1]);return end
        MenuUtil.CreateContextMenu(b,function(_,menu)
            for _,row in ipairs(b.rows) do
                menu:CreateButton(row.quest.title,function() navigate(row) end)
            end
        end)
    end)
    return pin
end

local function placePins(canvas,rows,width,height)
    local used,size=0,22*UI:FontScale()
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
            pin.x,pin.y,pin.rows=x,y,{}
            pin:SetPoint("CENTER",canvas,"TOPLEFT",x,-y);pin:SetSize(size,size);pin:Show()
        end
        table.insert(pin.rows,r)
        pin.count:SetText(#pin.rows>1 and #pin.rows or "")
    end
    for i=used+1,#canvas.pins do canvas.pins[i]:Hide() end
end

function B:ShowRegionMap(entry,top,questLink)
    local home=entry.map or entry.region.map
    local view=self.regionMap
    if not view then
        view=CreateFrame("Frame",nil,self.infoChild);self.regionMap=view
        view.canvas=CreateFrame("Frame",nil,view)
        view.canvas.pins,view.canvas.tiles={},{}
        view.selector=UI:ListButton(view,"",180,function(b)
            MenuUtil.CreateContextMenu(b,function(_,menu)
                for _,map in ipairs(view.mapIDs) do
                    menu:CreateButton(mapName(map).." · "..#view.maps[map].." 项",function()
                        view.shownMap=map;self.info:SetVerticalScroll(0);self:Detail()
                    end)
                end
            end)
        end,"guideBody")
        view.selector:SetPoint("TOPLEFT")
        view.note=UI:Text(view,"guideNote",UI.colors.muted)
        view:RegisterEvent("MAP_EXPLORATION_UPDATED")
        view:SetScript("OnEvent",function()
            view.canvas.map=nil
            if view:IsVisible() then self:Detail() end
        end)
    end
    if home~=view.home then view.shownMap=home end
    if home~=view.home or view.zone~=entry.catalogZone or view.region~=entry.region or view.revision~=A.state.revision then
        view.maps,view.other=pickupLocations(entry,home)
        view.mapIDs={}
        for map in pairs(view.maps) do table.insert(view.mapIDs,map) end
        table.sort(view.mapIDs,function(a,b)
            if a==home or b==home then return a==home and a~=b end
            return a<b
        end)
        view.home,view.zone,view.region,view.revision=home,entry.catalogZone,entry.region,A.state.revision
    end
    local map=view.maps[view.shownMap] and view.shownMap or home
    local rows,width,gap=view.maps[map],self.info:GetWidth(),UI.metrics.gap*UI:FontScale()
    view:SetPoint("TOPLEFT",0,-top);view:SetWidth(width);view:Show()
    local multiple=#view.mapIDs>1
    view.selector.text:SetText(mapName(map).." · "..#rows.." 项"..(multiple and "  ▾" or ""))
    view.selector:SetEnabled(multiple)
    view.selector:SetSize(math.min(width,view.selector.text:GetStringWidth()+24),UI.metrics.button*UI:FontScale())
    local y=view.selector:GetHeight()+gap
    local canvas=view.canvas
    local height=drawArt(canvas,map,width)
    canvas:SetPoint("TOPLEFT",0,-y);canvas:SetShown(height>0)
    if height>0 then placePins(canvas,rows,width,height);y=y+height+gap end
    local note=#rows>0 and (height>0 and "点击接取标记可导航" or "地图底图暂不可用，请查看下方坐标") or "本图暂无可标出的接取点"
    if multiple then note=note.." · 可切换接取地图" end
    view.note:SetPoint("TOPLEFT",0,-y);view.note:SetWidth(width);view.note:SetText(note)
    view:SetHeight(y+view.note:GetStringHeight()+gap)
    local groups={}
    local function list(label,entries)
        if #entries==0 then return end
        local items={}
        for _,r in ipairs(entries) do
            items[#items+1]=questLink(r.quest.id,r.quest.title).."\n|cff"..UI.hex.muted..r.location.."|r"
        end
        groups[#groups+1]={label=label,tint=UI.hex.gold,items=items}
    end
    list("接取地点",rows)
    list("其他接取方式与待确认地点",view.other)
    return self:LayoutRegionLists(groups,top+view:GetHeight()+gap)
end
