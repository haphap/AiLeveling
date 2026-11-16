local _,A=...
A.Flights={}
local F=A.Flights

function F.Matches(state)
    local data=A.FlightData
    return data and state and state.clientVersion==data.clientVersion and state.interface==data.interface
end

function F.ReadSpeed(state)
    if not F.Matches(state) or not C_SpellBook or not C_SpellBook.IsSpellKnown then return end
    -- 70862 SpellEffect 1303665: taxi speed +20%; query learned spells, not staged talent ranks.
    local ok,known=pcall(C_SpellBook.IsSpellKnown,1225490)
    if ok and type(known)=="boolean" then return known and 1.2 or 1 end
end

function F.TimeKey(from,to,faction,hops,speed)
    return "flighttime:"..A.FlightData.version..":"..tostring(faction)..":"..from..":"..to..(hops and (":via:"..hops) or "")..
        ":speed:"..tostring(speed or "unknown")
end

function F.Seconds(from,to,state,hops)
    if not F.Matches(state) then return end
    hops=hops or (state.taxiHops or {})[from..":"..to]
    local sample=state.taxiSpeed and (state.samples or {})[F.TimeKey(from,to,state.faction,hops,state.taxiSpeed)]
    if sample and sample.unit=="seconds" and sample.n>=3 and sample.mean>=1 and sample.mean<=7200 then return sample.mean,"本地实测" end
    local observed=A.FlightData.observedDurations and A.FlightData.observedDurations[state.faction]
    local paths=A.FlightData.observedHops and A.FlightData.observedHops[state.faction]
    if observed and observed[from..":"..to] and (not hops or paths and paths[from..":"..to]==hops) then
        return observed[from..":"..to]/(state.taxiSpeed or 1),"当前构建飞行记录"
    end
    if hops and not hops:match("^%d+:%d+$") then
        local previous,total=nil,0
        for node in hops:gmatch("%d+") do
            node=tonumber(node)
            if previous then
                local seconds=F.Seconds(previous,node,state,previous..":"..node)
                if not seconds then return end
                total=total+seconds
            end
            previous=node
        end
        return total,"分段飞行参考"
    end
    local side=A.FlightData.durations[state.faction]
    local seconds=side and side[from..":"..to]
    if seconds then return seconds/(state.taxiSpeed or 1),"InFlight 参考" end
end

function F.Position(node,map,hbd)
    local x,y=hbd:GetZoneCoordinatesFromWorldInstance(node.world[2],node.world[1],node.instance,map)
    if x and y and x>=0 and x<=1 and y>=0 and y<=1 then return {map=map,x=x,y=y} end
end

local function append(list,value)
    local result={};for i,item in ipairs(list) do result[i]=item end
    result[#result+1]=value;return result
end

local function checkpoint(count)
    local thread,main=coroutine.running()
    if count%10==0 and thread and not main then coroutine.yield() end
end

local function referencePosition(node,target,origin,hbd)
    if not hbd or not C_Map or not C_Map.GetMapInfo then return end
    local seen={}
    for _,map in ipairs({target.map,origin.map}) do
        while map and map>0 and not seen[map] do
            seen[map]=true
            local info=C_Map.GetMapInfo(map)
            if not info then break end
            if info.mapType==2 or info.mapType==3 then
                local point=F.Position(node,map,hbd)
                if point then return point end
            end
            map=info.parentMapID
        end
    end
end

local function unlockNode(node,state)
    local mask=state.faction=="Alliance" and 1 or state.faction=="Horde" and 2
    return node and mask and math.floor(node.factionMask/mask)%2==1 and node.condition==0 and node.visibility==0
end

function F.UnlockCandidates(state,maps,navigation)
    local rows={}
    if not F.Matches(state) or not state.transportKnown or not navigation or not navigation.hbd or state.inInstance then return rows end
    local ordered={};for map in pairs(maps or {}) do ordered[#ordered+1]=map end;table.sort(ordered)
    for id,node in pairs(A.FlightData.nodes) do
        if (state.unlocked or {})["taxi:"..id]==false and unlockNode(node,state) then
            for _,map in ipairs(ordered) do
                local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
                local point=info and (info.mapType==2 or info.mapType==3) and F.Position(node,map,navigation.hbd)
                if point then
                    rows[#rows+1]={kind="unlockFlight",taxiId=id,title=(state.taxiNames or {})[id] or node.name,position=point}
                    break
                end
            end
        end
    end
    table.sort(rows,function(a,b) return a.taxiId<b.taxiId end)
    return rows
end

-- Walking and transport geometry do not change as the hearth cooldown advances.
local function routeWithoutHearth(origin,target,state,navigation)
    local cache=state.travelCache
    local walks=cache and cache.walks or {}
    local points=cache and cache.points or {}
    if cache then cache.points=points end
    local function pointKey(p)
        if not points[p] then points[p]=string.format("%d:%.9f:%.9f",p.map,p.x,p.y) end
        return points[p]
    end
    local routeKey=pointKey(origin)..">"..pointKey(target)
    local saved=cache and cache.routes[routeKey]
    if cache and saved~=nil then return saved or nil end
    local function walk(from,to)
        local key=pointKey(from)..">"..pointKey(to)
        if walks[key]~=nil then return walks[key] or nil end
        local seconds=A.Travel.Walk(from,to,state,navigation)
        local result=seconds and {kind="walk",from=from,to=to,seconds=seconds,coarse=seconds>0}
        walks[key]=result or false;return result
    end
    local mapKey=origin.map..":"..target.map
    local flights=cache and cache.flights[mapKey]
    if not flights then
        flights={}
        local mask=state.faction=="Alliance" and 1 or state.faction=="Horde" and 2
        if F.Matches(state) and mask and state.transportKnown then
            for key,available in pairs(state.taxiAvailability or {}) do
                local from,to=key:match("^(%d+):(%d+)$")
                from,to=tonumber(from),tonumber(to)
                local source,dest=A.FlightData.nodes[from],A.FlightData.nodes[to]
                local departure=(state.taxiDepartures or {})[from] or
                    source and referencePosition(source,origin,target,navigation.hbd)
                local seconds,label
                if from and to then seconds,label=F.Seconds(from,to,state) end
                if source and dest and departure and seconds and seconds>0 and source.instance==dest.instance and
                    math.floor(source.factionMask/mask)%2==1 and math.floor(dest.factionMask/mask)%2==1 and
                    (state.unlocked or {})["taxi:"..from] and (state.unlocked or {})["taxi:"..to] and
                    available==true then
                    local observed=(state.taxiLandings or {})[key]
                    local landing=observed or referencePosition(dest,target,departure,navigation.hbd)
                    local hops=(state.taxiHops or {})[key]
                    local sample=(state.samples or {})[F.TimeKey(from,to,state.faction,hops,state.taxiSpeed)]
                    local spread=label=="本地实测" and sample and sample.n>1 and math.sqrt(sample.m2/(sample.n-1)) or seconds*0.25
                    local boarding=A.Estimates and A.Estimates.flightBoardSeconds
                    if boarding and landing then
                        flights[#flights+1]={kind="flight",key=key,from=departure,to=landing,fromTaxi=from,toTaxi=to,
                            arrival=observed and 12 or 25,
                            flightSeconds=seconds,durationSource=label,seconds=seconds+boarding,faction=state.faction,hops=hops,taxiSpeed=state.taxiSpeed,
                            low=math.max(1,seconds-spread)+boarding*0.5,high=seconds+spread+boarding*3}
                    end
                end
            end
        end
        local public=A.PublicTransitData
        if public and state.clientVersion==public.clientVersion and state.interface==public.interface then
            for _,leg in ipairs(public.legs) do
                if not leg.faction or leg.faction==state.faction then flights[#flights+1]=leg end
            end
        end
        table.sort(flights,function(a,b) return a.key<b.key end)
        if cache then cache.flights[mapKey]=flights end
    end
    local direct=walk(origin,target)
    local best=direct and {seconds=direct.seconds,low=direct.seconds,high=direct.seconds,legs={direct},
        flights=0,hearths=0,initial=direct.coarse==true,coarse=direct.coarse}
    if not flights.minimum then
        flights.minimum=math.huge
        for _,flight in ipairs(flights) do flights.minimum=math.min(flights.minimum,flight.seconds) end
    end
    -- A trip shorter than every transport leg is already optimal by walking.
    if best and best.seconds<=flights.minimum then
        if cache then cache.routes[routeKey]=best end
        return best
    end
    flights.connections=flights.connections or {}
    local sourceKey=pointKey(origin)..">"..target.map
    local sources=cache and cache.sources or {}
    if cache then cache.sources=sources end
    local reached=sources[sourceKey]
    if not reached then
        reached={}
        local first={position=origin,seconds=0,low=0,high=0,legs={},flights=0,hearths=0,initial=false}
        local pending,labels={first},{[pointKey(origin)]=first}
        local count=0
        while #pending>0 do
            table.sort(pending,function(a,b) return a.seconds>b.seconds end)
            local current=table.remove(pending)
            if not current.discarded then
                reached[#reached+1]=current
                local positionKey=pointKey(current.position)
                local connections=flights.connections[positionKey]
                if not connections then
                    connections={}
                    for _,flight in ipairs(flights) do
                        local approach=walk(current.position,flight.from)
                        if approach then connections[#connections+1]={approach=approach,flight=flight,key=pointKey(flight.to)} end
                    end
                    flights.connections[positionKey]=connections
                end
                for _,connection in ipairs(connections) do
                    local flight,approach,key=connection.flight,connection.approach,connection.key
                    local seconds=current.seconds+approach.seconds+flight.seconds
                    local previous=labels[key]
                    if not previous or seconds<previous.seconds then
                        if previous then previous.discarded=true end
                        local candidate={position=flight.to,seconds=seconds,
                            low=current.low+approach.seconds+flight.low,high=current.high+approach.seconds+flight.high,
                            legs=append(append(current.legs,approach),flight),
                            flights=current.flights+(flight.kind=="flight" and 1 or 0),hearths=0,
                            initial=true,coarse=current.coarse or approach.coarse}
                        labels[key]=candidate;pending[#pending+1]=candidate
                    end
                    count=count+1;checkpoint(count)
                end
            end
        end
        sources[sourceKey]=reached
    end
    for _,current in ipairs(reached) do
        if best and current.seconds>=best.seconds then break end
        local finish=walk(current.position,target)
        local seconds=finish and current.seconds+finish.seconds
        if seconds and (not best or seconds<best.seconds) then
            best={seconds=seconds,low=current.low+finish.seconds,high=current.high+finish.seconds,
                legs=append(current.legs,finish),flights=current.flights,hearths=0,
                initial=current.initial or finish.coarse==true,coarse=current.coarse or finish.coarse}
        end
    end
    if cache then cache.routes[routeKey]=best or false end
    return best
end

function F.Routes(origin,target,state,navigation)
    if not origin or not target or not navigation or not A.Travel or
        state.dead or state.onTaxi or state.inInstance then return end
    local routes={}
    local direct=routeWithoutHearth(origin,target,state,navigation)
    if direct and (not state.maxSeconds or direct.seconds<=state.maxSeconds) then
        local route={};for key,value in pairs(direct) do route[key]=value end
        route.hearthReady=state.hearthReady
        routes[#routes+1]=route
    end
    if A.Hearth and state.hearthPoint and state.hearthBindingKey and (state.bags or {})[6948] and
        state.bags[6948]>0 and state.hearthReady and state.hearthReady<math.huge then
        local duration,low,high,initial=A.Hearth.Duration(state)
        local wait=math.max(0,state.hearthReady-(state.now or 0))
        local seconds=duration and wait+duration
        if seconds and (not direct or seconds<direct.seconds) and (not state.maxSeconds or seconds<=state.maxSeconds) then
            -- Moving before a hearth cast cannot improve arrival at its fixed destination.
            local onward=routeWithoutHearth(state.hearthPoint,target,state,navigation)
            if onward and (not state.maxSeconds or seconds+onward.seconds<=state.maxSeconds) then
                local legs={{kind="hearth",from=origin,to=state.hearthPoint,seconds=seconds,wait=wait,
                    name=state.bindName,bindingKey=state.hearthBindingKey}}
                for _,leg in ipairs(onward.legs) do legs[#legs+1]=leg end
                routes[#routes+1]={seconds=seconds+onward.seconds,low=wait+low+onward.low,high=wait+high+onward.high,
                    legs=legs,flights=onward.flights,initial=initial or onward.initial,coarse=onward.coarse,
                    hearthReady=(state.now or 0)+seconds+(state.hearthCooldown or math.huge),hearths=1}
            end
        end
    end
    routes=A.Travel.Prune(routes,state.now)
    return #routes>0 and routes or nil
end

function F.Itinerary(origin,stages,state,navigation)
    local paths={{position=origin,seconds=0,low=0,high=0,legs={},flights=0,
        hearthReady=state.hearthReady,hearths=0}}
    local context={};for key,value in pairs(state) do context[key]=value end
    for index,stage in ipairs(stages) do
        if not stage.position then return end
        local nextPaths={}
        for _,path in ipairs(paths) do
            context.now=(state.now or 0)+path.seconds
            context.hearthReady=path.hearthReady
            context.maxSeconds=state.maxSeconds and math.max(0,state.maxSeconds-path.seconds)
            for _,route in ipairs(F.Routes(path.position,stage.position,context,navigation) or {}) do
                local legs={};for _,leg in ipairs(path.legs) do legs[#legs+1]=leg end
                for _,leg in ipairs(route.legs) do legs[#legs+1]=leg end
                nextPaths[#nextPaths+1]={position=stage.position,seconds=path.seconds+route.seconds,
                    low=path.low+route.low,high=path.high+route.high,
                    legs=legs,flights=path.flights+route.flights,initial=path.initial or route.initial,
                    firstRoute=path.firstRoute or route,coarse=path.coarse or route.coarse}
                nextPaths[#nextPaths].hearthReady=route.hearthReady
                nextPaths[#nextPaths].hearths=path.hearths+route.hearths
            end
        end
        paths=A.Travel.Prune(nextPaths,state.now)
        if #paths==0 then return end
        checkpoint(index)
    end
    return paths
end

function F.Actions(route,action,navigation)
    local actions={}
    for _,leg in ipairs(route.legs or {}) do
        -- The task points to its goal; transit steps already point to their departure.
        if leg.kind=="hearth" then
            actions[#actions+1]={kind="transit",mode="hearth",questId=action.questId,title="炉石返回 "..(leg.name or "绑定地点"),
                text=(leg.wait>0 and string.format("等待炉石冷却约 %.1f 分钟后，",leg.wait/60) or "").."手动使用炉石返回实际绑定地点，落地后继续任务。",
                position=leg.to,arrival=12,departure=leg.from,hearthBindingKey=leg.bindingKey,travelSeconds=leg.seconds,travelWait=leg.wait,travelRide=leg.seconds-leg.wait,referenceHearth=true}
        elseif leg.kind=="boat" or leg.kind=="zeppelin" or leg.kind=="tram" then
            local vehicle=leg.kind=="boat" and "船" or leg.kind=="tram" and "地铁" or "飞艇"
            actions[#actions+1]={kind="transit",mode=leg.kind,questId=action.questId,title="乘"..vehicle.."前往"..leg.toName,
                text="前往"..leg.fromName..(leg.kind=="zeppelin" and "，登上塔台" or "").."，乘坐开往"..leg.toName.."的"..vehicle.."；到站后下"..vehicle.."继续任务。",
                departure=leg.from,departureRadius=40,position=leg.to,arrival=40,travelSeconds=leg.seconds,
                publicTransit=true,transitKey=leg.key,fromName=leg.fromName,toName=leg.toName,travelWait=leg.seconds-leg.low,travelRide=leg.low}
        elseif leg.kind=="flight" then
            local names=A.state and A.state.taxiNames or {}
            local name=names[leg.toTaxi] or A.FlightData.nodes[leg.toTaxi].name
            local from=names[leg.fromTaxi] or A.FlightData.nodes[leg.fromTaxi].name
            actions[#actions+1]={kind="transit",mode="flight",questId=action.questId,title="飞往 "..name,
                fromName=from.."飞行管理员",text=string.format("前往%s的飞行管理员，飞往「%s」，落地后继续任务。",from,name),
                departure=leg.from,departureRadius=12,position=leg.to,arrival=leg.arrival or 12,fromTaxi=leg.fromTaxi,toTaxi=leg.toTaxi,
                travelSeconds=leg.seconds,timeSampleKey=F.TimeKey(leg.fromTaxi,leg.toTaxi,leg.faction,leg.hops,leg.taxiSpeed),referenceFlight=true}
        end
    end
    actions[#actions+1]=action
    return actions
end

-- Direction-only fallback when the full journey cannot be timed.
function F.Guide(action,state,navigation)
    local anchor,target=state.taxiOrigin,action and action.position
    if not F.Matches(state) or not anchor or not target or not state.position or not navigation or not navigation.hbd or
        state.dead or state.onTaxi or state.inInstance or target.map==state.position.map or
        not state.now or state.now<anchor.at or state.now-anchor.at>120 then return end
    local map=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(target.map)
    if not map or (map.mapType~=2 and map.mapType~=3) then return end
    local distance=navigation:Distance(state.position,anchor.position)
    if distance==nil or distance>2 then return end
    local data=A.FlightData
    local source=data.nodes[anchor.id]
    local mask=state.faction=="Alliance" and 1 or state.faction=="Horde" and 2
    if not source or not mask or math.floor(source.factionMask/mask)%2~=1 or
        not (state.unlocked or {})["taxi:"..anchor.id] then return end
    local candidates={}
    local original=navigation:Distance(state.position,target)
    for id,node in pairs(data.nodes) do
        local key=anchor.id..":"..id
        if id~=anchor.id and node.instance==source.instance and math.floor(node.factionMask/mask)%2==1 and
            (state.unlocked or {})["taxi:"..id] and (state.taxiAvailability or {})[key]==true then
            local landing=F.Position(node,target.map,navigation.hbd)
            local remaining=landing and navigation:Distance(landing,target)
            if remaining and (not original or remaining+50<original) then
                candidates[#candidates+1]={id=id,node=node,landing=landing,distance=remaining}
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.id<b.id
    end)
    local best=candidates[1]
    if not best then return end
    local seconds,sourceLabel=F.Seconds(anchor.id,best.id,state)
    local name=(state.taxiNames or {})[best.id] or best.node.name
    local text="与当前飞行管理员交谈，飞往「"..name.."」，落地后继续任务。"
    local transit={kind="transit",mode="flight",questId=action.questId,title="飞往 "..name,text=text,
        departure=anchor.position,departureRadius=12,position=best.landing,arrival=25,
        fromTaxi=anchor.id,toTaxi=best.id,travelSeconds=seconds,
        timeSampleKey=F.TimeKey(anchor.id,best.id,state.faction,(state.taxiHops or {})[anchor.id..":"..best.id],state.taxiSpeed),referenceFlight=true}
    return {actions={transit,action},from=anchor.id,to=best.id,flightSeconds=seconds,
        durationSource=sourceLabel}
end
