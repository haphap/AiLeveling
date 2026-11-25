local _,A=...
local P={}
A.ShortestPath=P
local owner="AiLeveling"
local verbs={accept="接取",objective="完成",turnin="交付"}

local function destination(action)
    if not action then return end
    local goal=action.travelGoal or action.kind=="transit" and action.questAction or action
    local p=goal and goal.position
    if p and p.map and p.x and p.y and (verbs[goal.kind] or goal.kind=="manual" or goal.kind=="service" or goal.kind=="dungeonEnter") and
        A.Navigation.Target(goal) then return goal end
end

local function sameGoal(a,b)
    if not a or not b then return a==b end
    local p,q=a.position,b.position
    return a.kind==b.kind and a.questId==b.questId and a.objectiveIndex==b.objectiveIndex and
        p.map==q.map and p.x==q.x and p.y==q.y
end

function P:Read()
    local api=self.api
    self.journey,self.flight=nil,nil
    if self.owned and api.CurrentStop(owner) then
        local state=api.JourneyState()
        if state and state.failure and not (state.pending or state.settling or state.blocked) then
            self.owned=nil
            api.Cancel(owner)
            A.dirty=true
            return
        end
        local trip=api.Journey()
        if trip and trip.owner==owner then
            local steps={}
            for _,leg in ipairs(trip.legs) do
                steps[#steps+1]={kind=leg.mode,title=leg.text,seconds=leg.seconds}
                if self.flight==nil and leg.mode~="walk" then
                    self.flight=leg.mode=="flight" and leg or false
                end
            end
            if #steps>0 then
                local goal=self.goal
                if verbs[goal.kind] then
                    steps[#steps+1]={kind=goal.kind,title=verbs[goal.kind].." "..(goal.title or "任务"),action=goal,task=true}
                end
                self.journey={steps=steps,seconds=trip.secondsLeft,goal=goal,action=goal}
            end
        end
    else
        self.owned=nil
    end
    if A.Transport and A.Transport.taxiMapOpen then A.Navigation:RefreshTaxiMarker() end
    A.dirty=true
end

function P:Sync(action)
    local api=ShortestPathForever and ShortestPathForever.API
    if not (api and api.NavigateRoute and api.JourneyState and api.CurrentStop and api.Journey and api.Subscribe and api.Cancel) then return end
    if not self.api then
        self.api=api
        api.Subscribe(function(changes)
            if self.owned and (changes.leg or changes.replan or changes.ended or changes.stop or changes.changed or changes.active) then
                self:Read()
            elseif self.waiting and changes.ended then
                self.goal,self.waiting=nil,nil
            end
        end)
    end
    local state=A.state
    local goal=not (A.char.paused or state.dead or state.inInstance) and destination(action) or nil
    if sameGoal(self.goal,goal) then
        self.goal=goal
        if self.journey then
            self.journey.goal,self.journey.action=goal,goal
            local last=self.journey.steps[#self.journey.steps]
            if last.task then last.action=goal end
        end
        return
    end
    -- Wait for the next normal navigation update after loading or combat.
    if InCombatLockdown() or goal and not state.position then return end
    local status=api.JourneyState()
    if not status then return end
    local ours=status.owner==owner
    self.owned,self.journey,self.flight=nil,nil,nil
    self.goal=goal
    self.waiting=goal and status.busy and not ours
    if goal and not self.waiting then
        local p=goal.position
        self.owned=api.NavigateRoute(owner,{{map=p.map,x=p.x,y=p.y,title=goal.title,kind=goal.kind=="accept" and "pickup" or goal.kind=="dungeonEnter" and "dungeon" or goal.kind,hold=true}})
        if self.owned then self:Read()
        elseif ours then api.Cancel(owner) end
    elseif ours then
        api.Cancel(owner)
    end
end

function P:For(action)
    if self.owned and sameGoal(self.goal,destination(action)) then return self.goal end
end

-- Only the flight master's live offers may be highlighted or selected for boarding.
function P:TaxiLeg(choices)
    local flight,nav=self.flight,A.Navigation
    if not (flight and choices and flight.from and flight.to and A.FlightData and nav.hbd) then return end
    local function close(id,point)
        local node=A.FlightData.nodes[id]
        local position=node and A.Flights.Position(node,point.map,nav.hbd)
        local distance=position and nav:Distance(position,point)
        return distance and distance<=60
    end
    if not close(choices.from,flight.from) then return end
    local match
    for _,node in pairs(choices.slots) do
        if close(node.id,flight.to) then
            if match then return end
            match={kind="transit",mode="flight",fromTaxi=choices.from,toTaxi=node.id,position=flight.to,departure=flight.from}
        end
    end
    return match
end
