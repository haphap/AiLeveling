local _,A=...
A.Flights={}
local F=A.Flights

function F.Matches(state)
    local data=A.FlightData
    return data and state and state.clientVersion==data.clientVersion and tostring(state.clientBuild)==tostring(data.build) and state.interface==data.interface
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

local function referenceLanding(node,target,origin,hbd)
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

-- Compare available flights with straight-line walking.
function F.Routes(origin,target,state,navigation)
    if not origin or not target or not navigation or not A.Travel or
        state.dead or state.onTaxi or state.inInstance then return end
    local walks={}
    local function pointKey(p) return string.format("%d:%.9f:%.9f",p.map,p.x,p.y) end
    local function walk(from,to)
        local key=pointKey(from)..">"..pointKey(to)
        if walks[key]~=nil then return walks[key] or nil end
        local seconds=A.Travel.Walk(from,to,state,navigation)
        local result=seconds and {kind="walk",from=from,to=to,seconds=seconds,coarse=seconds>0}
        walks[key]=result or false;return result
    end
    local flights={}
    local mask=state.faction=="Alliance" and 1 or state.faction=="Horde" and 2
    if F.Matches(state) and mask and state.transportKnown then
        for key,available in pairs(state.taxiAvailability or {}) do
            local from,to=key:match("^(%d+):(%d+)$")
            from,to=tonumber(from),tonumber(to)
            local source,dest=A.FlightData.nodes[from],A.FlightData.nodes[to]
            local departure=(state.taxiDepartures or {})[from]
            local seconds,label
            if from and to then seconds,label=F.Seconds(from,to,state) end
            if source and dest and departure and seconds and seconds>0 and source.instance==dest.instance and
                math.floor(source.factionMask/mask)%2==1 and math.floor(dest.factionMask/mask)%2==1 and
                (state.unlocked or {})["taxi:"..from] and (state.unlocked or {})["taxi:"..to] and
                available==true then
                local observed=(state.taxiLandings or {})[key]
                local landing=observed or referenceLanding(dest,target,departure,navigation.hbd)
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
    if public and state.clientVersion==public.clientVersion and tostring(state.clientBuild)==tostring(public.build) and state.interface==public.interface then
        for _,leg in ipairs(public.legs) do
            if not leg.faction or leg.faction==state.faction then flights[#flights+1]=leg end
        end
    end
    table.sort(flights,function(a,b) return a.key<b.key end)
    local first={position=origin,seconds=0,low=0,high=0,legs={},flights=0,
        hearthReady=state.hearthReady,hearths=0,initial=false}
    local pending,labels,results={first},{origin={first}},{}
    local function offer(candidate,key)
        local bucket=labels[key] or {}
        for _,old in ipairs(bucket) do
            if not old.discarded and A.Travel.Dominates(old,candidate,state.now) then return end
        end
        if state.maxSeconds and candidate.seconds>state.maxSeconds then return end
        for _,old in ipairs(bucket) do if A.Travel.Dominates(candidate,old,state.now) then old.discarded=true end end
        bucket[#bucket+1]=candidate;pending[#pending+1]=candidate;labels[key]=bucket
    end
    local count=0
    while #pending>0 do
        table.sort(pending,function(a,b) return a.seconds>b.seconds end)
        local current=table.remove(pending)
        if not current.discarded then
            local finish=walk(current.position,target)
            if finish and (not state.maxSeconds or current.seconds+finish.seconds<=state.maxSeconds) then
                results[#results+1]={seconds=current.seconds+finish.seconds,low=current.low+finish.seconds,high=current.high+finish.seconds,
                    legs=append(current.legs,finish),flights=current.flights,initial=current.initial,
                    hearthReady=current.hearthReady,hearths=current.hearths,coarse=current.coarse or finish.coarse}
                results[#results].initial=current.initial or finish.coarse==true
            end
            for _,flight in ipairs(flights) do
                local approach=walk(current.position,flight.from)
                if approach then
                    local candidate={position=flight.to,seconds=current.seconds+approach.seconds+flight.seconds,
                        low=current.low+approach.seconds+flight.low,high=current.high+approach.seconds+flight.high,
                        legs=append(append(current.legs,approach),flight),flights=current.flights+(flight.kind=="flight" and 1 or 0),
                        hearthReady=current.hearthReady,hearths=current.hearths,initial=true,
                        coarse=current.coarse or approach.coarse}
                    offer(candidate,flight.key)
                end
                count=count+1;checkpoint(count)
            end
            if A.Hearth and state.hearthPoint and state.hearthBindingKey and (state.bags or {})[6948] and
                state.bags[6948]>0 and current.hearthReady and current.hearthReady<math.huge then
                local duration,low,high,initial=A.Hearth.Duration(state)
                if duration then
                    local wait=math.max(0,current.hearthReady-((state.now or 0)+current.seconds))
                    local leg={kind="hearth",from=current.position,to=state.hearthPoint,seconds=wait+duration,wait=wait,
                        name=state.bindName,bindingKey=state.hearthBindingKey}
                    local seconds=current.seconds+wait+duration
                    offer({position=state.hearthPoint,seconds=seconds,low=current.low+wait+low,high=current.high+wait+high,
                        legs=append(current.legs,leg),flights=current.flights,
                        hearthReady=(state.now or 0)+seconds+(state.hearthCooldown or math.huge),hearths=current.hearths+1,
                        initial=current.initial or initial,coarse=current.coarse},"hearth")
                end
                count=count+1;checkpoint(count)
            end
        end
    end
    results=A.Travel.Prune(results,state.now)
    return #results>0 and results or nil
end

function F.Itinerary(origin,stages,state,navigation)
    local paths={{position=origin,seconds=0,low=0,high=0,legs={},flights=0,
        hearthReady=state.hearthReady,hearths=0}}
    for index,stage in ipairs(stages) do
        if not stage.position then return end
        local nextPaths={}
        for _,path in ipairs(paths) do
            local context={};for key,value in pairs(state) do context[key]=value end
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
                position=leg.to,arrival=12,departure=leg.from,hearthBindingKey=leg.bindingKey,travelSeconds=leg.seconds,referenceHearth=true}
        elseif leg.kind=="boat" or leg.kind=="zeppelin" then
            local vehicle=leg.kind=="boat" and "船" or "飞艇"
            actions[#actions+1]={kind="transit",mode=leg.kind,questId=action.questId,title="乘"..vehicle.."前往"..leg.toName,
                text="前往"..leg.fromName..(leg.kind=="zeppelin" and "，登上塔台" or "").."，乘坐开往"..leg.toName.."的"..vehicle.."；到站后下"..vehicle.."继续任务。",
                departure=leg.from,departureRadius=40,position=leg.to,arrival=40,travelSeconds=leg.seconds,
                publicTransit=true,transitKey=leg.key}
        elseif leg.kind=="flight" then
            local node=A.FlightData.nodes[leg.toTaxi]
            local name=(A.state and A.state.taxiNames or {})[leg.toTaxi] or node.name
            actions[#actions+1]={kind="transit",mode="flight",questId=action.questId,title="飞往 "..name,
                text=string.format("与出发点飞行管理员交谈，飞往「%s」，落地后继续任务。",name),
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
