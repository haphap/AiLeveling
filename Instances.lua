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
    state.instanceEntryError=self.entryError
    local keys={tostring(state.instanceLocksKnown),tostring(state.instanceEntryError)}
    for _,lock in ipairs(state.instanceLockouts) do keys[#keys+1]=lock.name..":"..tostring(lock.difficulty)..":"..lock.resetAt end
    table.sort(keys)
    return table.concat(keys,"|")
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
