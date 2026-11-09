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
    return {kind="flight",title=flying and (flight and flight.name and ("飞行中 · "..flight.name) or "飞行中") or "已落地",text=message}
end

function T:InvalidateSample()
    if self.flight then self.flight.valid=false end
end

function T:World()
    self:InvalidateSample()
    self.groundPosition,self.lastFlightTick=nil,nil
    self.taxiOrigin,self.taxiExpiry=nil,nil
    self.taxiSelected=nil
    self.taxiChoices,self.taxiRequest=nil,nil
end

function T:RefreshKnown(map,faction)
    if not C_TaxiMap or not C_TaxiMap.GetTaxiNodesForMap then return end
    local maps,seen={},{}
    while map and map>0 and not seen[map] do
        seen[map]=true;maps[#maps+1]=map
        local info=C_Map.GetMapInfo(map)
        map=info and info.parentMapID
    end
    for _,option in pairs(A.Content.transit) do if option.taxiMap then maps[#maps+1]=option.taxiMap end end
    local side=faction=="Alliance" and 2 or faction=="Horde" and 1
    for _,id in ipairs(maps) do
        for _,node in ipairs(C_TaxiMap.GetTaxiNodesForMap(id) or {}) do
            if node.faction==0 or node.faction==side then
                if type(node.isUndiscovered)=="boolean" then
                    local key="taxi:"..node.nodeID
                    self.known[key]=self.known[key] or node.isUndiscovered==false
                end
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
    local nav=A.Navigation
    if not nav or nav.manual then return end
    for index=nav.index or 1,#(nav.actions or {}) do
        local action=nav.actions[index]
        if action.kind~="move" then
            if action.kind=="transit" and action.mode=="flight" then return action end
            return
        end
    end
end

function T:SelectTaxi(nodes,from)
    if not A.ready or not A.settings or not A.settings.autoTaxi or not A.char or A.char.paused or
        not A.state or A.state.dead or self.taxiSelected or self:InFlight() or type(TakeTaxiNode)~="function" or
        InCombatLockdown and InCombatLockdown() or IsShiftKeyDown and IsShiftKeyDown() then return end
    local action=self:PlannedFlight()
    if not action or action.fromTaxi~=from then return end
    for _,node in ipairs(nodes) do
        if node.nodeID==action.toTaxi and node.state==1 and not node.isMapLayerTransition and
            type(node.slotIndex)=="number" and node.slotIndex>0 and node.slotIndex%1==0 then
            self.taxiSelected=true
            self:RecordTaxi(node.slotIndex)
            local ok,result=pcall(TakeTaxiNode,node.slotIndex)
            if not ok then self.taxiRequest=nil end
            return ok,result
        end
    end
end

function T:RecordTaxi(slot)
    local choices=self.taxiChoices
    if self.flight or not choices or canaccessvalue and not canaccessvalue(slot) or type(slot)~="number" then return end
    self.taxiRequest=nil
    local node=choices.slots[slot]
    local now=GetTime()
    if node and now>=choices.at and now-choices.at<=120 then
        self.taxiRequest={from=choices.from,to=node.id,name=node.name,at=now}
    end
end

function T:CaptureTaxi()
    self:SyncFlightSpeed(A.state)
    self.dirty=true
    self.taxiOrigin,self.taxiExpiry=nil,nil
    self.taxiChoices=nil
    local map=GetTaxiMapID and GetTaxiMapID()
    if not map or map<=0 or not C_TaxiMap or not C_TaxiMap.GetAllTaxiNodes then self.taxiRequest=nil;return end
    local nodes=C_TaxiMap.GetAllTaxiNodes(map) or {}
    local from,slots=nil,{}
    for _,node in ipairs(nodes) do
        if not node.isMapLayerTransition then
            if type(node.slotIndex)=="number" and node.slotIndex>0 then slots[node.slotIndex]=node.nodeID end
            if node.state==0 then from=node.nodeID end
            if node.state==0 or node.state==1 then self.known["taxi:"..node.nodeID]=true end
        end
    end
    if from then
        self.taxiChoices={from=from,at=GetTime(),slots={}}
        if self.taxiRequest and self.taxiRequest.from~=from then self.taxiRequest=nil end
        for _,node in ipairs(nodes) do
            if node.state==1 and not node.isMapLayerTransition and type(node.slotIndex)=="number" and node.slotIndex>0 and node.slotIndex%1==0 then
                self.taxiChoices.slots[node.slotIndex]={id=node.nodeID,name=type(node.name)=="string" and node.name or nil}
            end
        end
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
            if type(node.name)=="string" then self.taxiNames[node.nodeID]=node.name end
            if node.nodeID~=from and not node.isMapLayerTransition then
                local key=prefix..node.nodeID
                if node.state==1 or node.state==2 then self.availability[key]=node.state==1 end
                if node.state==1 then self.hops[key]=taxiHops(from,node,slots,#nodes) end
            end
        end
        self:SelectTaxi(nodes,from)
    else self.taxiRequest=nil
    end
end

function T:InvalidateFlights()
    self.availability,self.hops,self.dirty={},{},true
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

function T:Bound()
    local name=GetBindLocation and GetBindLocation()
    local position=A.state.position
    A.char.hearthBinding=nil
    for id,node in pairs(A.Content.nodes) do
        if position and node.position.map==position.map and node.hearth and node.verified and node.bindName==name and node.accessRadius then
            local distance=A.Navigation:Distance(position,node.position)
            if distance and distance<=node.accessRadius then
                A.char.hearthBinding={name=name,node=id}
                break
            end
        end
    end
end

function T:Snapshot(state)
    self:SyncFlightSpeed(state)
    state.taxiSpeed=self.taxiSpeed
    state.onTaxi=self:IsFlying()
    state.hearthReady,state.hearthNode=nil,nil
    self.readyAt=nil
    local map=C_Map.GetBestMapForUnit("player")
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
    if not self.requiredUnlocks then
        self.requiredUnlocks={}
        local function add(option)
            local id=type(option.unlock)=="string" and option.unlock:match("^quest:(%d+)$")
            if id then self.requiredUnlocks[option.unlock]=tonumber(id) end
        end
        for _,option in pairs(A.Content.transit) do add(option) end
    end
    for key,id in pairs(self.requiredUnlocks) do state.unlocked[key]=state.completed[id]==true end
    state.bindName=GetBindLocation and GetBindLocation()
    local binding=A.char.hearthBinding
    local candidates={}
    for id,node in pairs(A.Content.nodes) do
        if node.hearth and node.verified and node.bindName==state.bindName then candidates[#candidates+1]=id end
    end
    if binding and type(binding)=="table" and binding.name==state.bindName then
        local node=A.Content.nodes[binding.node]
        if node and node.hearth and node.verified and node.bindName==state.bindName then state.hearthNode=binding.node end
    end
    if not state.hearthNode and #candidates==1 then state.hearthNode=candidates[1] end
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
    return table.concat(keys,",")..":"..hearth..":"..tostring(state.hearthNode)..":"..tostring(state.bindName)..":"..tostring(state.onTaxi)..
        ":origin:"..tostring(state.taxiOrigin and state.taxiOrigin.id)..":speed:"..tostring(state.taxiSpeed)
end

function T:Update()
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
        if observed and not A.char.paused and not A.Navigation.manual then
            action=A.Navigation:BeginFlight(self.groundPosition)
            if action and request and (action.fromTaxi~=request.from or action.toTaxi~=request.to) then action=nil end
        end
        self.flight={action=action,started=now,valid=action~=nil,observedStart=observed,name=request and request.name,displaySecond=0}
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
                    local reference=action.referenceSeconds
                    local ratio=reference and reference>0 and (flight.ended-flight.started)/reference
                    if ratio and type(action.sampleKind)=="string" and flight.ended-flight.started>=1 and ratio>=0.25 and ratio<=4 then
                        local key=action.sampleKind
                        local samples=A.char.samples
                        if samples[key] and samples[key].unit~="ratio" then samples[key]=nil end
                        A.State.Observe(samples,key,ratio)
                        if samples[key] then samples[key].unit="ratio" end
                    end
                end
                self.flight=nil
                A.Navigation.lastMap,A.Navigation.lastNode=A.state.position.map,A.state.position.node
                A.Navigation:RefreshPins()
                A.State:Refresh(true)
            end
        end
    end
    if not flying and not self.flight then self.groundPosition=A.state.position end
    self.wasFlying,self.lastFlightTick=flying,now
end
