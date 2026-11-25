local _, A = ...
A.Transport = {known={},availability={},hops={},departures={},landings={},landingOrder={},dirty=true}
local T = A.Transport

local function clockText(seconds)
    seconds=math.max(0,math.floor(seconds))
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end

function T:IsFlying()
    if UnitOnTaxi then return UnitOnTaxi("player") == true end
end

function T:InFlight()
    return self:IsFlying() or self.flight ~= nil
end

local stormwind,ironforge=1453,1455

function T.IsTramStation(map)
    return map==stormwind or map==ironforge
end

local function tramAction(origin)
    for _,leg in ipairs(A.PublicTransitData.legs) do
        if leg.kind=="tram" and leg.from.map==origin then
            local city=leg.toName:gsub("地铁入口$","")
            return {kind="tram",title="矿道地铁 · 往"..city,toName=city,arrivalPoint=leg.to,text="到站后从出口进入"..city.."。"}
        end
    end
    return {kind="tram",title="矿道地铁",text="沿途可查看两端车站的交付任务。"}
end

function T:ObserveTram(instance,map)
    if instance==369 then
        if not self.tram then
            local origin=self.tramCity or A.char.tramOrigin
            self.tram=tramAction(origin)
            A.char.tramOrigin=origin
        end
    elseif instance~=nil then
        if map or self.tram then self.tramCity=self.IsTramStation(map) and map or nil end
        self.tram,self.tramY,A.char.tramOrigin=nil,nil,nil
    end
end

local function updateTramDirection(self)
    if not UnitPosition then return end
    local _,y,_,instance=UnitPosition("player")
    if instance~=369 or canaccessvalue and not canaccessvalue(y) or type(y)~="number" then return end
    -- Forever map 369 runs along world Y, from the Ironforge exit (10) to Stormwind (2491).
    -- Only measure in the tunnel, away from players walking around the platforms.
    if y<120 or y>2380 then self.tramY=nil;return end
    if not self.tramY then self.tramY=y;return end
    local delta=y-self.tramY
    if math.abs(delta)<75 then return end
    self.tramY=y
    local origin=delta<0 and stormwind or ironforge
    if origin~=A.char.tramOrigin then
        A.char.tramOrigin=origin
        self.tram=tramAction(origin)
        A.dirty=true
    end
end

function T:FlightGate()
    if not self:InFlight() then return end
    local flight,flying,now=self.flight,self:IsFlying(),GetTime()
    local message=A.char.paused and "任务安排已暂停。" or A.Navigation and A.Navigation.manual and "落地后继续手动导航。" or
        (flying and "落地后继续任务。" or "正在接续任务。")
    if flight and flight.observedStart and now>=flight.started then
        local elapsed=(flight.ended or now)-flight.started
        local timer=(flying and "已飞行 " or "飞行用时 ")..clockText(elapsed)
        if flying and flight.duration and elapsed<flight.duration then
            timer=timer.." · 预计剩余 "..clockText(math.ceil(flight.duration-elapsed))
        end
        message=timer.."\n"..message
    end
    return {kind="flight",title=flying and (flight and flight.name and ("飞行中 · "..flight.name) or "飞行中") or "已落地",
        toName=flight and flight.name,text=message}
end

function T:InvalidateSample()
    if self.flight then self.flight.valid=false end
end

function T:World()
    self:InvalidateSample()
    self.groundPosition,self.lastFlightTick=nil,nil
    self.taxiOrigin,self.taxiExpiry=nil,nil
    self:CloseTaxiMap()
    self.taxiChoices,self.taxiRequest=nil,nil
end

function T:CloseTaxiMap()
    self.taxiMapOpen,self.taxiSelected,self.autoTaxiLeg=nil,nil,nil
    if A.Navigation and A.Navigation.taxiMarker then A.Navigation.taxiMarker:Hide() end
end

function T:RestoreFlights(char)
    local routes=type(char.flightRoutes)=="table" and char.flightRoutes or {}
    for key,value in pairs(routes) do
        local from,to
        if type(key)=="string" then from,to=key:match("^(%d+):(%d+)$") end
        if value~=true or not (from and A.FlightData.nodes[tonumber(from)] and A.FlightData.nodes[tonumber(to)]) then
            routes[key]=nil
        else
            self.known["taxi:"..from],self.known["taxi:"..to]=true,true
        end
    end
    char.flightRoutes,self.availability=routes,routes
end

function T:RefreshKnown(map,faction)
    if not C_TaxiMap or not C_TaxiMap.GetTaxiNodesForMap then return end
    local maps,seen={},{}
    while map and map>0 and not seen[map] do
        seen[map]=true;maps[#maps+1]=map
        local info=C_Map.GetMapInfo(map)
        map=info and info.parentMapID
    end
    local side=faction=="Alliance" and 2 or faction=="Horde" and 1
    self.taxiNames=self.taxiNames or {}
    local discovered={}
    for _,id in ipairs(maps) do
        for _,node in ipairs(C_TaxiMap.GetTaxiNodesForMap(id) or {}) do
            if node.faction==0 or node.faction==side then
                if type(node.name)=="string" then self.taxiNames[node.nodeID]=node.name end
                if type(node.isUndiscovered)=="boolean" and discovered[node.nodeID]==nil then
                    local key="taxi:"..node.nodeID
                    discovered[node.nodeID]=not node.isUndiscovered
                    self.known[key]=discovered[node.nodeID]
                end
            end
        end
    end
    for key,available in pairs(self.availability) do
        if available then
            local from,to=key:match("^(%d+):(%d+)$")
            if discovered[tonumber(from)]==false or discovered[tonumber(to)]==false then
                self.availability[key],self.hops[key]=nil,nil
            end
        end
    end
end

local function taxiHops(from,node,slots,total)
    if not GetNumRoutes or not TaxiGetNodeSlot or type(node.slotIndex)~="number" or node.slotIndex<1 then return end
    local count=GetNumRoutes(node.slotIndex)
    if type(count)~="number" or count<1 or count>=total or count%1~=0 then return end
    local path,seen={from},{[from]=true}
    for index=1,count do
        local source=slots[TaxiGetNodeSlot(node.slotIndex,index,true)]
        local dest=slots[TaxiGetNodeSlot(node.slotIndex,index,false)]
        if source~=path[#path] or not dest or seen[dest] then return end
        path[#path+1]=dest;seen[dest]=true
    end
    if path[#path]==node.nodeID then return table.concat(path,":") end
end

function T:PlannedFlight()
    if A.ShortestPath and A.ShortestPath.owned then return A.ShortestPath:TaxiLeg(self.taxiChoices) end
    local nav=A.Navigation
    if not nav or nav.manual and (type(nav.manual)~="table" or not nav.manual.actions) then return end
    if not nav.manual and nav.RouteStatus and nav:RouteStatus(nav.plan,A.state) then return end
    nav=nav.Sequence and nav:Sequence() or nav
    for index=nav.index or 1,#(nav.actions or {}) do
        local action=nav.actions[index]
        if action.kind~="move" then
            if action.kind=="transit" and action.mode=="flight" then return action end
            return
        end
    end
end

function T:TaxiDestination()
    local choices=self.taxiMapOpen and self.taxiChoices
    if not choices or not A.ready or not A.char or A.char.paused or not A.state or A.state.dead or self:InFlight() then return end
    local action=self:PlannedFlight()
    if not action or action.fromTaxi~=choices.from then return end
    for slot,node in pairs(choices.slots) do
        if node.id==action.toTaxi then return slot,node end
    end
end

function T:PreviewTaxi(slot,node,mark)
    local flight=self.autoTaxiLeg
    if not flight or self.taxiSelected or flight.fromTaxi~=self.taxiChoices.from or flight.toTaxi~=node.id then return end
    self.autoTaxiLeg=nil
    local preview={}
    self.taxiSelected=preview
    -- Give the highlighted station a moment on screen before optional automatic boarding.
    C_Timer.After(1,function()
        if self.taxiSelected~=preview then return end
        self.taxiSelected=nil
        local liveSlot,liveNode=self:TaxiDestination()
        if liveSlot~=slot or liveNode.id~=node.id or self.taxiChoices.from~=flight.fromTaxi or not mark:IsVisible() or
            not A.settings.autoTaxi or type(TakeTaxiNode)~="function" or InCombatLockdown and InCombatLockdown() or
            IsShiftKeyDown and IsShiftKeyDown() then return end
        if self.legacyTaxi and TaxiNodeGetType and TaxiNodeGetType(slot)~="REACHABLE" then return end
        self:RecordTaxi(slot)
        if not pcall(TakeTaxiNode,slot) then self.taxiRequest=nil end
    end)
end

function T:RecordTaxi(slot)
    local choices=self.taxiChoices
    if self.flight or not choices or canaccessvalue and not canaccessvalue(slot) or type(slot)~="number" then return end
    self.taxiRequest=nil
    if self.taxiMapOpen then self.autoTaxiLeg=nil;self.taxiSelected=true end
    local node=choices.slots[slot]
    local now=GetTime()
    if node and now>=choices.at and now-choices.at<=120 then
        self.taxiRequest={from=choices.from,to=node.id,name=node.name,at=now}
    end
end

-- TaxiFrame draws and selects numbered slots even when the map-ID API has no rows.
-- Use the exact name printed by the open menu; a slot number alone is not a node ID.
local function stationName(name)
    if type(name)=="string" and name~="" then return (name:gsub("，",","):gsub("%s*,%s*",",")) end
end

local function menuNodes(self)
    local map=GetTaxiMapID and GetTaxiMapID()
    if not self.legacyTaxi and (not map or map<=0) and FlightMapFrame and FlightMapFrame:IsShown() then
        map=FlightMapFrame:GetMapID()
    end
    local rows=map and map>0 and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_TaxiMap.GetAllTaxiNodes(map) or {}
    local count=self.legacyTaxi and NumTaxiNodes and NumTaxiNodes()
    if not count or not TaxiNodeName or not TaxiNodeGetType then return rows,count end
    local bySlot,byName={},{}
    local function remember(name,id)
        name=stationName(name)
        if name and id then
            if byName[name]==nil then byName[name]=id
            elseif byName[name]~=id then byName[name]=false end
        end
    end
    local faction=A.state and A.state.faction
    local side=faction=="Alliance" and 1 or faction=="Horde" and 2
    for id,station in pairs(A.FlightData and A.FlightData.nodes or {}) do
        if not side or math.floor(station.factionMask/side)%2==1 then
            remember(station.name,id)
            remember(station.zhCN,id)
            remember(self.taxiNames and self.taxiNames[id],id)
        end
    end
    for _,row in ipairs(rows) do
        if row.slotIndex then
            bySlot[row.slotIndex]=row
            if not row.isMapLayerTransition then remember(row.name,row.nodeID) end
        end
    end
    local nodes={}
    for slot=1,count do
        local kind=TaxiNodeGetType(slot)
        if kind and kind~="NONE" then
            local name=TaxiNodeName(slot)
            local row=bySlot[slot]
            local key=stationName(name)
            local id=key and (row and stationName(row.name)==key and row.nodeID or byName[key])
            if id and not (row and row.isMapLayerTransition) then
                nodes[#nodes+1]={nodeID=id,slotIndex=slot,name=name,state=kind=="CURRENT" and 0 or kind=="REACHABLE" and 1 or 2}
            end
        end
    end
    return nodes,count
end

function T:CaptureTaxi(refreshOnly,system)
    self.taxiMapOpen=true
    if not refreshOnly then
        self.legacyTaxi=system==nil and not (FlightMapFrame and FlightMapFrame:IsShown()) or
            system~=nil and Enum and Enum.UIMapSystem and system==Enum.UIMapSystem.Taxi
    end
    self:SyncFlightSpeed(A.state)
    self.dirty=true
    self.taxiOrigin,self.taxiExpiry=nil,nil
    self.taxiChoices=nil
    local nodes,count=menuNodes(self)
    local from,slots=nil,{}
    for _,node in ipairs(nodes) do
        if not node.isMapLayerTransition then
            if type(node.slotIndex)=="number" and node.slotIndex>0 then slots[node.slotIndex]=node.nodeID end
            if node.state==0 then from=node.nodeID end
        end
    end
    if from then
        self.known["taxi:"..from]=true
        self.taxiChoices={from=from,at=GetTime(),slots={}}
        if self.taxiRequest and self.taxiRequest.from~=from then self.taxiRequest=nil end
        if not self.taxiHooked and hooksecurefunc and type(TakeTaxiNode)=="function" then
            hooksecurefunc("TakeTaxiNode",function(slot) self:RecordTaxi(slot) end);self.taxiHooked=true
        end
        local snapshot={}
        if A.State and A.State.Position then A.State:Position(snapshot) end
        if snapshot.position then
            self.taxiOrigin={id=from,position=snapshot.position,at=GetTime()}
            self.taxiExpiry=GetTime()+120
            self.departures[from]={map=snapshot.position.map,x=snapshot.position.x,y=snapshot.position.y}
        end
        self.taxiNames=self.taxiNames or {}
        local prefix=from..":"
        for key in pairs(self.availability) do
            if key:sub(1,#prefix)==prefix then self.availability[key]=nil;self.hops[key]=nil end
        end
        for _,node in ipairs(nodes) do
            local slot=node.slotIndex
            if type(node.name)=="string" then self.taxiNames[node.nodeID]=node.name end
            if node.nodeID~=from and node.state==1 and not node.isMapLayerTransition and
                type(slot)=="number" and slot>0 and slot%1==0 and (not count or slot<=count) and
                (not self.legacyTaxi or not TaxiNodeGetType or TaxiNodeGetType(slot)=="REACHABLE") then
                local key=prefix..node.nodeID
                self.taxiChoices.slots[slot]={id=node.nodeID,name=self.taxiNames[node.nodeID]}
                self.known["taxi:"..node.nodeID]=true
                self.availability[key]=true
                self.hops[key]=taxiHops(from,node,slots,count or #nodes)
            end
        end
    else self.taxiRequest=nil
    end
    if not refreshOnly then
        self.autoTaxiLeg=A.settings and A.settings.autoTaxi and not (IsShiftKeyDown and IsShiftKeyDown()) and self:PlannedFlight() or nil
    end
end

function T:InvalidateFlights()
    self.hops,self.dirty={},true
    self.taxiOrigin,self.taxiExpiry=nil,nil
end

function T:SyncFlightSpeed(state)
    local speed=A.Flights and A.Flights.ReadSpeed(state)
    if speed~=self.taxiSpeed then
        self.taxiSpeed=speed
        self:InvalidateFlights()
        self:InvalidateSample()
        return true
    end
end

function T:Snapshot(state)
    self:SyncFlightSpeed(state)
    state.taxiSpeed=self.taxiSpeed
    state.onTaxi=self:IsFlying()
    state.hearthReady=nil
    self.readyAt=nil
    local map=C_Map.GetBestMapForUnit("player")
    self:ObserveTram(state.instanceId,map)
    if self.dirty or self.map~=map then self:RefreshKnown(map,state.faction);self.dirty=false;self.map=map end
    state.transportKnown,state.unlocked,state.taxiAvailability=true,{},{}
    for key,value in pairs(self.known) do state.unlocked[key]=value end
    for key,value in pairs(self.availability) do state.taxiAvailability[key]=value end
    state.taxiHops={};for key,value in pairs(self.hops) do state.taxiHops[key]=value end
    state.taxiNames={};for key,value in pairs(self.taxiNames or {}) do state.taxiNames[key]=value end
    for field,source in pairs({taxiDepartures=self.departures,taxiLandings=self.landings}) do
        state[field]={}
        for key,p in pairs(source) do state[field][key]={map=p.map,x=p.x,y=p.y} end
    end
    state.taxiOrigin=nil
    local origin=self.taxiOrigin
    if origin and state.now>=origin.at and state.now-origin.at<=120 then
        state.taxiOrigin={id=origin.id,at=origin.at,position={map=origin.position.map,x=origin.position.x,y=origin.position.y}}
    end
    state.bindName=GetBindLocation and GetBindLocation()
    if (state.bags[6948] or 0)>0 and C_Container.GetItemCooldown then
        local start,duration,enabled=C_Container.GetItemCooldown(6948)
        if start and duration and (enabled==1 or enabled==true) then
            state.hearthReady=math.max(state.now,start+duration)
            self.readyAt=state.hearthReady>state.now and state.hearthReady or nil
        end
    end
    if A.Hearth then A.Hearth:Snapshot(state) end
end

function T.Key(state)
    local keys={}
    local p=state.hearthPoint
    if p then keys[#keys+1]=string.format("hearth:%s:%d:%.8f:%.8f:%s",state.hearthBindingKey,p.map,p.x,p.y,tostring(state.hearthCooldown)) end
    for id,value in pairs(state.unlocked) do keys[#keys+1]=id.."="..tostring(value) end
    for id,value in pairs(state.taxiAvailability or {}) do keys[#keys+1]="flight:"..id.."="..tostring(value) end
    for id,value in pairs(state.taxiHops or {}) do keys[#keys+1]="hops:"..id.."="..value end
    for field,points in pairs({departures=state.taxiDepartures or {},landings=state.taxiLandings or {}}) do
        for key,p in pairs(points) do keys[#keys+1]=string.format("%s:%s:%d:%.8f:%.8f",field,tostring(key),p.map,p.x,p.y) end
    end
    table.sort(keys)
    local hearth=state.hearthReady and (state.hearthReady<=state.now and "ready" or tostring(state.hearthReady)) or "unknown"
    return table.concat(keys,",")..":"..hearth..":"..tostring(state.bindName)..":"..tostring(state.onTaxi)..
        ":origin:"..tostring(state.taxiOrigin and state.taxiOrigin.id)..":speed:"..tostring(state.taxiSpeed)
end

function T:Update()
    if self.tram then updateTramDirection(self) end
    if self:SyncFlightSpeed(A.state) then A:RequestRefresh() end
    if self.taxiExpiry and GetTime()>self.taxiExpiry then self.taxiOrigin,self.taxiExpiry=nil,nil;A:RequestRefresh() end
    if self.readyAt and GetTime()>=self.readyAt then self.readyAt=nil;A:RequestRefresh() end
    local flying,now=self:IsFlying(),GetTime()
    if flying==nil then return end
    if self.taxiRequest and (now<self.taxiRequest.at or now-self.taxiRequest.at>3) then self.taxiRequest=nil end
    if flying and self.wasFlying~=true then
        local observed=self.wasFlying==false and self.lastFlightTick and now>=self.lastFlightTick and now-self.lastFlightTick<=2
        local request=observed and self.taxiRequest or nil
        local action
        if observed and not A.char.paused and (not A.Navigation.manual or A.Navigation.manual.actions) then
            action=A.Navigation:BeginFlight(self.groundPosition)
            if action and request and (action.fromTaxi~=request.from or action.toTaxi~=request.to) then action=nil end
        end
        self.flight={action=action,started=now,valid=action~=nil,observedStart=observed,name=request and request.name,
            toTaxi=request and request.to or action and action.toTaxi,displaySecond=0}
        if request and A.Flights then
            local context={};for key,value in pairs(A.state) do context[key]=value end
            context.taxiSpeed,context.samples=self.taxiSpeed,A.char.samples
            self.flight.duration=A.Flights.Seconds(request.from,request.to,context,self.hops[request.from..":"..request.to])
        end
        self.taxiRequest,self.taxiChoices=nil,nil
        if action then
            self.flight.timeSampleKey=action.timeSampleKey
            if action.referenceFlight and A.Flights and action.fromTaxi and action.toTaxi then
                self.flight.timeSampleKey=A.Flights.TimeKey(action.fromTaxi,action.toTaxi,A.state.faction,
                    self.hops[action.fromTaxi..":"..action.toTaxi],self.taxiSpeed)
                if not self.taxiSpeed then self.flight.valid=false end
            end
        end
        self.groundPosition=nil
        A.jobs.plan=nil
        A.Navigation:RefreshPins()
        A.QuestAssist:Update()
        A:RequestRefresh()
        A.dirty=true
    end
    local flight=self.flight
    if flight then
        if flying and flight.observedStart and now>=flight.started and flight.displaySecond~=math.floor(now-flight.started) then
            flight.displaySecond=math.floor(now-flight.started);A.dirty=true
        end
        if not self.lastFlightTick or now-self.lastFlightTick>2 or now<self.lastFlightTick or
            not A.settings.learn or A.char.paused or A.Navigation.manual or
            (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then flight.valid=false end
        if not flying then
            flight.ended=flight.ended or now
            if A.state.position then
                local arrived=A.Navigation:LandFlight(flight,A.state.position)
                if arrived and flight.valid then
                    local action=flight.action
                    if action.fromTaxi and action.toTaxi then
                        local key=action.fromTaxi..":"..action.toTaxi
                        if not self.landings[key] then
                            self.landingOrder[#self.landingOrder+1]=key
                            if #self.landingOrder>128 then self.landings[table.remove(self.landingOrder,1)]=nil end
                        end
                        local p=A.state.position
                        self.landings[key]={map=p.map,x=p.x,y=p.y}
                    end
                    local elapsed=flight.ended-flight.started
                    if flight.timeSampleKey and elapsed>=1 and elapsed<=7200 then
                        local key=flight.timeSampleKey
                        local samples=A.char.samples
                        if samples[key] and samples[key].unit~="seconds" then samples[key]=nil end
                        if not samples[key] then
                            local count,remove=0,nil
                            for kind in pairs(samples) do
                                if kind:sub(1,11)=="flighttime:" then count=count+1;remove=remove or kind end
                            end
                            if count>=128 then samples[remove]=nil end
                        end
                        A.State.Observe(samples,key,elapsed)
                        if samples[key] then samples[key].unit="seconds" end
                    end
                end
                self.flight=nil
                A.Navigation:RefreshPins()
                A.State:Refresh(true,false)
            end
        end
    end
    if not flying and not self.flight then self.groundPosition=A.state.position end
    self.wasFlying,self.lastFlightTick=flying,now
end
