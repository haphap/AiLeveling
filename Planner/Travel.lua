local _, A = ...
A.Travel = {}
local T = A.Travel

-- Rut'theran (client area 702) is at sea level below Teldrassil. Its docks and
-- the upper island share a zone map, but only the portal connects them on foot.
local function land(point,navigation)
    local map,x,y=point.map,point.x,point.y
    if map==1457 then return "Teldrassil" end
    if map==1414 or map==947 then
        local hbd=navigation and navigation.hbd
        if not (hbd and hbd.TranslateZoneCoordinates and x and y) then return end
        x,y=hbd:TranslateZoneCoordinates(x,y,map,1438)
        if not x then return end
    elseif map~=1438 then return end
    if point.sourceAreaId==702 or x and y and x>=0.533 and x<=0.586 and y>=0.863 then return "Ruttheran" end
    return "Teldrassil"
end

function T.Separated(from,to,navigation)
    return from and to and land(from,navigation)~=land(to,navigation)
end

function T.Walk(from,to,state,navigation)
    if not from or not to or not state then return end
    if from.map and from.map==to.map and type(from.x)=="number" and type(from.y)=="number" and
        from.x==to.x and from.y==to.y then return 0,0 end
    navigation=navigation or A.Navigation
    if T.Separated(from,to,navigation) then return end
    local distance=navigation and navigation.Distance and navigation:Distance(from,to)
    local speed=state.runSpeed
    if distance and distance>=0 and distance<math.huge and speed and speed>0 and speed<math.huge then
        return distance/speed,distance
    end
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
