local _,A=...
A.Instances={known=false,lockouts={}}
local I=A.Instances

function I:Request()
    self.known=false
    if RequestRaidInfo then RequestRaidInfo() end
end

function I:Capture()
    if not GetNumSavedInstances or not GetSavedInstanceInfo then self.known=false;return end
    local now=GetTime()
    local locks={}
    for index=1,GetNumSavedInstances() do
        local name,_,reset,difficulty,locked,extended=GetSavedInstanceInfo(index)
        if name and reset and reset>0 and (locked or extended) then
            locks[#locks+1]={name=name,difficulty=difficulty,resetAt=now+reset}
        end
    end
    self.known,self.lockouts=true,locks
end

function I:Snapshot(state)
    state.instanceLocksKnown,state.instanceLockouts=self.known,{}
    state.locale=GetLocale and GetLocale() or state.locale
    self.nextReset=nil
    for _,lock in ipairs(self.lockouts) do
        if lock.resetAt>state.now then
            state.instanceLockouts[#state.instanceLockouts+1]={name=lock.name,difficulty=lock.difficulty,resetAt=lock.resetAt}
            self.nextReset=math.min(self.nextReset or math.huge,lock.resetAt)
        end
    end
    state.pendingResets={}
    for id,value in pairs(A.char.pendingResets or {}) do state.pendingResets[id]={name=value.name} end
    state.instanceEntryError=self.entryError
    local keys={tostring(state.instanceLocksKnown),tostring(state.instanceEntryError)}
    for _,lock in ipairs(state.instanceLockouts) do keys[#keys+1]=lock.name..":"..tostring(lock.difficulty)..":"..lock.resetAt end
    for id in pairs(state.pendingResets) do keys[#keys+1]="reset:"..id end
    table.sort(keys)
    return table.concat(keys,"|")
end

function I.Check(d,state)
    if not state.inInstance and state.instanceEntryError then return false,state.instanceEntryError end
    if state.inInstance then
        local matching,reason=A.Dungeon.InstanceMatches(d,state)
        if not matching then return false,reason end
    end
    local active=state.dungeon
    local continuing=active and active.id==d.id and active.entered and not active.settled
    if continuing then return true end
    if state.instanceLocksKnown~=true then return false,"副本锁定信息尚未就绪，请重新检查" end
    if state.pendingResets and state.pendingResets[d.instanceId] and not continuing then
        return false,"该实例已进入过；新一轮前请由队长重置，并确认已重置"
    end
    local locks=state.instanceLockouts or {}
    local name=(d.lockoutNames and d.lockoutNames[state.locale]) or d.lockoutName
    if #locks>0 and not name then return false,"副本锁定名称映射待补齐" end
    for _,lock in ipairs(locks) do
        if lock.name==name and (not d.difficultyId or lock.difficulty==d.difficultyId) and lock.resetAt>(state.now or 0) then
            return false,string.format("目标副本已有保存进度，约 %.1f 分钟后重置",(lock.resetAt-(state.now or 0))/60)
        end
    end
    return true
end

function I:Entered(state,d)
    A.char.pendingResets=A.char.pendingResets or {}
    A.char.pendingResets[d.instanceId]={name=state.instanceName or (d.lockoutNames and d.lockoutNames[state.locale]) or d.lockoutName}
    self.entryError=nil
end

function I:ConfirmReset(id)
    local d=A.Content.dungeons[id]
    if not d then return false,"副本资料不存在" end
    if A.state.inInstance then return false,"请先离开副本，再确认重置" end
    local session=A.char.dungeon
    if session and session.phase~="complete" and not session.settled then return false,"先结束当前轮次，再确认重置" end
    if self.entryError then return false,self.entryError.."；状态改变后点击重新检查" end
    A.char.pendingResets=A.char.pendingResets or {}
    if not A.char.pendingResets[d.instanceId] then return false,"该副本当前没有待确认的重置" end
    A.char.pendingResets[d.instanceId]=nil
    A.State:Refresh(true)
    return true
end

function I:SystemMessage(message)
    if type(message)~="string" or not INSTANCE_RESET_SUCCESS then return end
    for id,value in pairs(A.char.pendingResets or {}) do
        if value.name then
            local ok,text=pcall(string.format,INSTANCE_RESET_SUCCESS,value.name)
            if ok and text==message then
                A.char.pendingResets[id]=nil
                A:RequestRefresh()
            end
        end
    end
end

function I:Error(errorId,message)
    local name=GetGameMessageInfo and GetGameMessageInfo(errorId)
    if name=="TRANSFER_ABORT_TOO_MANY_INSTANCES" or
        (TRANSFER_ABORT_TOO_MANY_INSTANCES and message==TRANSFER_ABORT_TOO_MANY_INSTANCES) then
        self.entryError="客户端提示近期进入实例次数过多，待限制解除后重新检查"
        A:RequestRefresh()
    end
end

function I:Retry()
    if A.state.inInstance then return false,"离开副本后再重新检查" end
    self.entryError=nil
    self:Request()
    A.State:Refresh(true)
    return true
end

function I:Update()
    if self.nextReset and GetTime()>=self.nextReset then self.nextReset=nil;A:RequestRefresh() end
end
