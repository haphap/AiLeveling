local _,A=...
A.Hearth={epoch=0}
local H=A.Hearth
local function accessible(value) return not canaccessvalue or canaccessvalue(value) end
local function number(value) return accessible(value) and type(value)=="number" and value==value and value>=0 and value<math.huge end
local function text(value) return accessible(value) and type(value)=="string" and value~="" and value or nil end
local function copy(p) return p and {map=p.map,x=p.x,y=p.y} end
local function usable()
    return not A.char.paused and not A.Navigation.manual and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end
function H.Key(state) return "hearthtime:v1:"..tostring(state.clientBuild) end
function H:InTransit() return self.cast~=nil or self.pending~=nil end
function H:InvalidateSample()
    local window=self.cast or self.pending
    if window then window.learn=false end
end
function H:Gate()
    if self:InTransit() then return {kind="hearthCast",title="炉石返回中",text="返回绑定地点后继续任务。"} end
end

function H:Event(event,unit,guid,spell)
    if event=="HEARTHSTONE_BOUND" then
        self.epoch=self.epoch+1;self.landing,self.cast,self.pending,self.arrived=nil,nil,nil,nil
        return true
    end
    if event=="PLAYER_ENTERING_WORLD" then
        local window=self.pending or self.cast
        if window then window.loaded=true;return true end
        return
    end
    if not accessible(unit) or unit~="player" or not text(guid) or not number(spell) then return end
    local _,itemSpell
    if C_Item and C_Item.GetItemSpell then _,itemSpell=C_Item.GetItemSpell(6948) end
    if not number(itemSpell) or spell~=itemSpell then return end
    local now=GetTime()
    if event=="UNIT_SPELLCAST_START" then
        local name=text(GetBindLocation and GetBindLocation())
        if not name then return end
        local action=A.Navigation:Current()
        self.pending=nil
        self.retryAt=nil
        self.cast={guid=guid,spell=spell,started=now,name=name,epoch=self.epoch,learn=A.settings.learn and usable(),
            action=usable() and action and action.kind=="transit" and action.mode=="hearth" and action or nil}
        return true
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
        local cast=self.cast
        if cast and cast.guid==guid and now>=cast.started and now-cast.started<=60 and
            text(GetBindLocation and GetBindLocation())==cast.name and cast.epoch==self.epoch then
            cast.succeeded=now;self.pending=cast;self.cast=nil
            return true
        end
    elseif (event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_FAILED_QUIET" or event=="UNIT_SPELLCAST_INTERRUPTED") and
        (self.cast and self.cast.guid==guid or self.pending and self.pending.guid==guid) then
        self.cast,self.pending=nil,nil
        return true
    end
end

function H:Snapshot(state)
    local pending=self.pending
    if pending and pending.loaded and state.now>=pending.started and state.now-pending.started<=120 then
        local snapshot={};A.State:Position(snapshot)
        local p=snapshot.position
        if p and number(p.map) and p.map>0 and number(p.x) and p.x<=1 and number(p.y) and p.y<=1 and
            state.bindName==pending.name and pending.epoch==self.epoch and usable() then
            self.arrived={action=pending.action,position=copy(p)}
            if pending.learn and A.settings.learn then
                self.landing={position=copy(p),name=pending.name,epoch=pending.epoch,build=state.clientBuild,version=state.clientVersion}
                local elapsed=state.now-pending.started
                if elapsed>=1 and elapsed<=120 then
                    local key=H.Key(state);local samples=A.char.samples
                    if samples[key] and samples[key].unit~="seconds" then samples[key]=nil end
                    if not samples[key] then
                        local count,remove=0,nil
                        for kind in pairs(samples) do if kind:sub(1,11)=="hearthtime:" then count=count+1;remove=remove or kind end end
                        if count>=8 then samples[remove]=nil end
                    end
                    A.State.Observe(samples,key,elapsed)
                    if samples[key] then samples[key].unit="seconds" end
                end
                self.cooldown=nil
                if C_Container and C_Container.GetItemCooldown then
                    local start,duration,enabled=C_Container.GetItemCooldown(6948)
                    if number(start) and number(duration) and duration>0 and start>=pending.started-1 and start<=state.now and
                        (enabled==1 or enabled==true) then self.cooldown=duration end
                end
            end
            self.cast,self.pending=nil,nil
        end
    end
    local landing=self.landing
    if landing and (landing.name~=state.bindName or landing.epoch~=self.epoch or landing.build~=state.clientBuild or
        landing.version~=state.clientVersion) then self.landing=nil;landing=nil end
    state.hearthPoint,state.hearthBindingKey,state.hearthCooldown=nil,nil,nil
    if landing and (state.bags[6948] or 0)>0 and number(state.hearthReady) then
        state.hearthPoint=copy(landing.position)
        state.hearthBindingKey=tostring(landing.epoch)..":"..landing.name
        state.hearthCooldown=self.cooldown
    end
end

function H:Update()
    local window=self.cast or self.pending
    if window then
        if not usable() or not A.settings.learn then window.learn=false end
        if GetTime()<window.started or GetTime()-window.started>120 or window.loaded and not usable() then
            self.cast,self.pending=nil,nil;A:RequestRefresh()
        end
    end
    if self.pending and self.pending.loaded and (not self.retryAt or GetTime()>=self.retryAt) then
        self.retryAt=GetTime()+0.5;A:RequestRefresh()
    end
    local arrived=self.arrived;self.arrived=nil
    if arrived and arrived.action and usable() and A.Navigation.actions and
        A.Navigation.actions[A.Navigation.index]==arrived.action and
        A.Navigation:Near(arrived.position,arrived.action.position,arrived.action.arrival or 12) then
        A.Navigation:Advance()
    end
end

function H.Duration(state)
    local sample=(state.samples or {})[H.Key(state)]
    if sample and sample.unit=="seconds" and sample.n>=3 and number(sample.mean) and sample.mean>=1 and sample.mean<=120 then
        local spread=math.sqrt(sample.m2/(sample.n-1))
        return sample.mean,math.max(1,sample.mean-spread),sample.mean+spread,false
    end
    local seconds=A.Estimates and A.Estimates.hearthSeconds
    if seconds then return seconds,seconds*0.5,seconds*3,true end
end

-- A confirmed inn visit provides a reference point until an actual hearth landing replaces it.
function H:ConfirmBinding(state,name)
    local p=state.position
    if not p or not number(p.map) or p.map<=0 or not number(p.x) or p.x>1 or not number(p.y) or p.y>1 then return end
    self.landing={position=copy(p),name=name,epoch=self.epoch,build=state.clientBuild,version=state.clientVersion,reference=true}
end
