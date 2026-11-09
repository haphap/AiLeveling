local _, A = ...
A.Travel = {}
local T = A.Travel

function T.Walk(from,to,state,navigation)
    if not from or not to or not state then return end
    if from.map and from.map==to.map and type(from.x)=="number" and type(from.y)=="number" and
        from.x==to.x and from.y==to.y then return 0 end
    navigation=navigation or A.Navigation
    local distance=navigation and navigation.Distance and navigation:Distance(from,to)
    local speed=state.runSpeed
    if distance and distance>=0 and distance<math.huge and speed and speed>0 and speed<math.huge then
        return distance/speed,distance
    end
end

function T.FlightKey(id,version)
    return "flight:"..tostring(version or "unversioned")..":"..tostring(id)
end

function T.Transit(option, departure, context)
    if not option.verified or not option.seconds or option.seconds < 0 then return nil end
    if option.unlock and not (context.unlocked and context.unlocked[option.unlock]) then return nil end
    if context.transportKnown and option.kind=="flight" then
        if not option.fromTaxi or not option.toTaxi or not context.unlocked["taxi:"..option.fromTaxi] or not context.unlocked["taxi:"..option.toTaxi] then return nil end
        if context.taxiAvailability and context.taxiAvailability[option.fromTaxi..":"..option.toTaxi]==false then return nil end
    end
    local wait = 0
    if option.kind == "hearth" then
        if context.transportKnown and (not context.hearthNode or option.to~=context.hearthNode) then return nil end
        if not context.hearthReady or not option.cooldown then return nil end
        wait = math.max(0, context.hearthReady - departure)
    end
    if option.period then
        if option.period <= 0 then return nil end
        wait = ((option.offset or 0) - departure) % option.period
    end
    local seconds=option.seconds
    if option.kind=="flight" and context.samples and context.flightSampleKey then
        seconds=A.State.Estimate(seconds,context.samples[context.flightSampleKey])
    end
    return wait + seconds
end

-- Keep a slower arrival only when it preserves an earlier hearth cooldown.
function T.Dominates(a,b,now)
    local hearth=a.hearthReady==b.hearthReady or (a.hearthReady~=nil and b.hearthReady~=nil and
        a.hearthReady<=math.max(b.hearthReady,(now or 0)+b.seconds))
    return a.seconds<=b.seconds and hearth
end

function T.Prune(routes,now)
    local result={}
    for _,candidate in ipairs(routes) do
        local dominated=false
        for _,old in ipairs(result) do if T.Dominates(old,candidate,now) then dominated=true;break end end
        if not dominated then
            for index=#result,1,-1 do if T.Dominates(candidate,result[index],now) then table.remove(result,index) end end
            result[#result+1]=candidate
        end
    end
    table.sort(result,function(a,b)
        if a.seconds~=b.seconds then return a.seconds<b.seconds end
        return (a.hearthReady or math.huge)<(b.hearthReady or math.huge)
    end)
    return result
end

function T.Routes(content,from,to,context)
    local function point(id)
        return type(id)=="table" and id or content.nodes[id] and content.nodes[id].position
    end
    if not from or not point(from) or not point(to) then return nil,"当前位置或目的地缺少坐标" end
    local function walk(a,b)
        local seconds=T.Walk(point(a),point(b),context)
        if seconds then return {seconds=seconds,from=a,to=b} end
    end
    local function steps(route)
        if route.seconds==0 then return {} end
        local node=content.nodes[route.to] or {}
        return {{kind="move",node=type(route.to)~="table" and route.to or nil,position=point(route.to),fromPosition=point(route.from),
            title=node.label or "前往下一目的地",arrival=node.arrival or 12,travelSeconds=route.seconds}}
    end
    local first={node=from,seconds=0,actions={},hearthReady=context.hearthReady}
    local labels,pending,results={[from]={first}},{first},{}
    local transitIds={}
    for id in pairs(content.transit or {}) do transitIds[#transitIds+1]=id end
    table.sort(transitIds,function(a,b) return tostring(a)<tostring(b) end)
    while #pending>0 do
        table.sort(pending,function(a,b) return a.seconds>b.seconds end)
        local label=table.remove(pending)
        if not label.discarded then
            local exit=walk(label.node,to)
            if exit then
                local candidate={seconds=label.seconds+exit.seconds,actions={},hearthReady=label.hearthReady}
                if not context.maxSeconds or candidate.seconds<=context.maxSeconds then
                    for _,action in ipairs(label.actions) do candidate.actions[#candidate.actions+1]=action end
                    for _,action in ipairs(steps(exit)) do candidate.actions[#candidate.actions+1]=action end
                    results[#results+1]=candidate
                end
            end
            for _,id in ipairs(transitIds) do
                local transit=content.transit[id]
                local source=transit.from or (transit.kind=="hearth" and label.node)
                local approach=walk(label.node,source)
                if approach and content.nodes[transit.to] then
                    local departure=(context.now or 0)+label.seconds+approach.seconds
                    local resources={}
                    for key,value in pairs(context) do resources[key]=value end
                    resources.hearthReady=label.hearthReady
                    resources.flightSampleKey=T.FlightKey(id,content.version)
                    local duration=T.Transit(transit,departure,resources)
                    if duration then
                        local ready=label.hearthReady
                        if transit.kind=="hearth" then ready=departure+duration+transit.cooldown end
                        local candidate={node=transit.to,seconds=label.seconds+approach.seconds+duration,
                            hearthReady=ready,actions={}}
                        local bucket,dominated=labels[transit.to] or {},false
                        for _,old in ipairs(bucket) do
                            if not old.discarded and T.Dominates(old,candidate,context.now) then dominated=true;break end
                        end
                        if not dominated and (not context.maxSeconds or candidate.seconds<=context.maxSeconds) then
                            for _,old in ipairs(bucket) do if T.Dominates(candidate,old,context.now) then old.discarded=true end end
                            for _,action in ipairs(label.actions) do candidate.actions[#candidate.actions+1]=action end
                            for _,action in ipairs(steps(approach)) do candidate.actions[#candidate.actions+1]=action end
                            candidate.actions[#candidate.actions+1]={kind="transit",transitId=id,node=transit.to,
                                title=transit.title or "使用交通前往下一段",text=transit.text,position=content.nodes[transit.to].position,
                                arrival=transit.arrival or 12,departure=point(source),mode=transit.kind,
                                departureRadius=(content.nodes[source] or {}).accessRadius or 12,referenceSeconds=transit.seconds,
                                fromTaxi=transit.fromTaxi,toTaxi=transit.toTaxi,
                                sampleKind=transit.kind=="flight" and resources.flightSampleKey or nil,travelSeconds=duration}
                            bucket[#bucket+1],pending[#pending+1]=candidate,candidate
                            labels[transit.to]=bucket
                        end
                    end
                end
            end
        end
    end
    results=T.Prune(results,context.now)
    if #results==0 then return nil,"缺少满足位置、交通、资源与时间条件的连接" end
    return results
end

function T.Route(content,from,to,context)
    local routes,reason=T.Routes(content,from,to,context)
    return routes and routes[1],reason
end

-- Preserve hearth cooldowns through the ordered itinerary.
function T.Itinerary(content,from,actions,state)
    local unlocked={}
    for key,value in pairs(state.unlocked or {}) do unlocked[key]=value end
    local paths={{node=from,seconds=0,actions={},hearthReady=state.hearthReady}}
    for _,source in ipairs(actions) do
        local action={}
        for key,value in pairs(source) do action[key]=value end
        if action.node and content.nodes[action.node] then action.position=action.position or content.nodes[action.node].position end
        local nextPaths,reason={},nil
        for _,path in ipairs(paths) do
            local context={}
            for key,value in pairs(state) do context[key]=value end
            context.now=(state.now or 0)+path.seconds
            context.hearthReady,context.unlocked=path.hearthReady,unlocked
            context.maxSeconds=state.maxSeconds and state.maxSeconds-path.seconds-(action.seconds or 0)
            local routes
            if action.node then routes,reason=T.Routes(content,path.node,action.node,context)
            else routes={{seconds=0,actions={},hearthReady=path.hearthReady}} end
            for _,route in ipairs(routes or {}) do
                local candidate={node=action.arriveNode or action.node or path.node,
                    seconds=path.seconds+route.seconds+(action.seconds or 0),actions={},hearthReady=route.hearthReady}
                if not state.maxSeconds or candidate.seconds<=state.maxSeconds then
                    for _,step in ipairs(path.actions) do candidate.actions[#candidate.actions+1]=step end
                    for _,source in ipairs(route.actions) do
                        local step={}
                        for key,value in pairs(source) do step[key]=value end
                        step.questId,step.dungeonId,step.stage=action.questId,action.dungeonId,action.stage
                        candidate.actions[#candidate.actions+1]=step
                    end
                    candidate.actions[#candidate.actions+1]=action
                    nextPaths[#nextPaths+1]=candidate
                end
            end
        end
        paths=T.Prune(nextPaths,state.now)
        if #paths==0 then return nil,reason or "超过游戏时间或交通资源不足" end
        if action.unlockAfter then unlocked[action.unlockAfter]=true end
        for _,key in ipairs(action.unlocksAfter or {}) do unlocked[key]=true end
    end
    for _,path in ipairs(paths) do
        path.lastNode=path.node
        path.resources={now=(state.now or 0)+path.seconds,hearthReady=path.hearthReady,unlocked=unlocked}
    end
    return paths
end
