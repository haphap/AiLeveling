local _,A=...
A.Party={members={},peers={},pending={}}
local P=A.Party
local prefix="AiLeveling1"
local kinds={none="暂无当前任务",paused="已暂停",accept="接取",objective="进行",turnin="交付",manual="手动导航",
    move="前往",approach="前往",service="补给／服务",transit="乘坐交通",flight="飞行中",hearthCast="炉石返回",
    dungeonEnter="进入副本",dungeonRun="副本进行中",dungeonLeave="离开副本",dungeonWait="等待队伍",dungeonEnd="结束本轮"}

function P:Channel()
    if not IsInGroup() or IsInRaid() then return end
    return LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
end

function P:Roster()
    local members={}
    if self:Channel() then
        for i=1,4 do
            local unit="party"..i
            local name,realm=UnitName(unit)
            if name then
                realm=realm and realm~="" and realm or GetNormalizedRealmName()
                members[name.."-"..realm]={unit=unit,name=name,realm=realm,guid=UnitGUID(unit)}
            end
        end
    end
    for name,peer in pairs(self.peers) do if not members[name] or members[name].guid~=peer.guid then self.peers[name]=nil end end
    self.members=members;self.lastPayload=nil
    if not next(members) then self.pending={};self.readyQuests=nil end
end

function P:Initialize()
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    self:Roster()
end

function P:Title(id)
    local quest=A.state.quests[id] or A.Data:GetQuest(id)
    return quest and quest.title or ("任务 #"..id)
end

function P:Payload()
    local action=A.Navigation:Current()
    local id=action and action.questId or 0
    local kind=action and action.kind or "none"
    if not kinds[kind] then kind="none" end
    if A.char.paused then id,kind=0,"paused" end
    local quest=A.state.quests[id]
    local fields={"1",A.version,tostring(A.state.level or 0),tostring(id),kind,quest and quest.ready and "1" or "0"}
    for _,objective in ipairs(quest and quest.objectives or {}) do
        local part=string.format("%d:%d:%d",objective.numFulfilled or 0,objective.numRequired or 0,objective.finished and 1 or 0)
        if #table.concat(fields,"|")+1+#part>255 then break end
        fields[#fields+1]=part
    end
    return table.concat(fields,"|")
end

function P:Receive(tag,message,channel,sender)
    if tag~=prefix or not A.settings.partySync or channel~=self:Channel() or type(message)~="string" or #message>255 then return end
    local full=sender
    if not self.members[full] and type(sender)=="string" and not sender:find("-",1,true) then full=sender.."-"..GetNormalizedRealmName() end
    local member=self.members[full]
    if not member then return end
    local fields={};for part in (message.."|"):gmatch("(.-)|") do fields[#fields+1]=part end
    local version,level,id,kind,ready=fields[2],tonumber(fields[3]),tonumber(fields[4]),fields[5],fields[6]
    if fields[1]~="1" or not version or #version>32 or not version:match("^[%w._%-]+$") or not level or level<1 or level>100 or level%1~=0 or
        not id or id<0 or id>=2147483648 or id%1~=0 or not kinds[kind] or ready~="0" and ready~="1" then return end
    local progress={}
    for i=7,#fields do
        local done,total,finished=fields[i]:match("^(%d+):(%d+):([01])$")
        done,total=tonumber(done),tonumber(total)
        if not done or done>1000000 or total>1000000 then return end
        progress[#progress+1]=total>0 and (done.."/"..total) or (finished=="1" and "已完成" or "进行中")
    end
    local previous=self.peers[full]
    self.peers[full]={guid=member.guid,version=version,level=level,id=id,kind=kind,ready=ready=="1",progress=progress,seen=GetTime()}
    if not previous then self.lastPayload=nil
    elseif previous.id==id and not previous.ready and ready=="1" and id>0 then
        A:Message(member.name.."已完成："..self:Title(id))
    end
    self:RefreshUI()
end

function P:ShareQuest(id)
    if not self:Channel() then return false,"先加入小队。" end
    if InCombatLockdown() then return false,"脱离战斗后共享。" end
    local index=id and C_QuestLog.GetLogIndexForQuestID(id)
    if not index or not C_QuestLog.IsPushableQuest(id) then return false,"当前任务无法共享。" end
    QuestLogPushQuest(index)
    return true,"已发送任务共享请求。"
end

function P:Announce(message)
    local channel=self:Channel()
    if not channel or not A.settings.partyAnnouncements or A.char.paused or
        C_ChatInfo.InChatMessagingLockdown() or #message>255 then return end
    C_ChatInfo.SendChatMessage(message,channel)
end

function P:Event(event,...)
    if event=="CHAT_MSG_ADDON" then self:Receive(...)
    elseif event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" then self:Roster();self:RefreshUI()
    elseif event=="QUEST_ACCEPTED" and A.settings.autoShareQuests and self:Channel() and not A.char.paused and not IsShiftKeyDown() then
        self.pending[(...)]=GetTime()+10
    elseif event=="PLAYER_LEVEL_UP" then self:Announce("我升到了 "..(...).." 级。") end
end

function P:Update()
    local now=GetTime()
    if now<(self.nextUpdate or 0) then return end
    self.nextUpdate=now+2
    local channel=self:Channel()
    if not channel then return end
    if A.settings.partySync then
        local payload=self:Payload()
        if not C_ChatInfo.InChatMessagingLockdown() and (payload~=self.lastPayload or now-(self.lastSent or 0)>=15) then
            C_ChatInfo.SendAddonMessage(prefix,payload,channel)
            self.lastPayload,self.lastSent=payload,now
        end
    else self.peers={};self.lastPayload=nil end
    if not A.settings.autoShareQuests or A.char.paused or IsShiftKeyDown() then self.pending={} end
    for id,expires in pairs(self.pending) do
        if expires<now then self.pending[id]=nil
        elseif A.state.quests[id] and not InCombatLockdown() then self:ShareQuest(id);self.pending[id]=nil;break end
    end
    local ready={}
    for id,quest in pairs(A.state.quests) do
        ready[id]=quest.ready==true
        if ready[id] and self.readyQuests and self.readyQuests[id]==false then self:Announce("任务完成："..quest.title) end
    end
    self.readyQuests=ready
    local flight=A.Transport.flight
    if flight and flight~=self.lastFlight and flight.name then
        self:Announce("正在飞往："..flight.name..(flight.duration and (" · 预计 "..math.ceil(flight.duration/60).." 分钟") or ""))
    end
    self.lastFlight=flight
    self:RefreshUI()
end

function P:Lines()
    if not self:Channel() then return {"加入小队后查看队友的任务与进度。"} end
    local names={};for name in pairs(self.members) do names[#names+1]=name end;table.sort(names)
    local lines={}
    for _,name in ipairs(names) do
        local member,peer=self.members[name],self.peers[name]
        if not UnitIsConnected(member.unit) then lines[#lines+1]=member.name.." · 离线"
        elseif not A.settings.partySync then lines[#lines+1]=member.name.." · 任务同步已关闭"
        elseif not peer or GetTime()-peer.seen>35 then lines[#lines+1]=member.name.." · 尚未收到任务"
        else
            lines[#lines+1]=member.name.." · "..peer.level.." 级 · "..peer.version..(peer.version~=A.version and "（版本不同）" or "")
            lines[#lines+1]=kinds[peer.kind]..(peer.id>0 and ("："..self:Title(peer.id)) or "")
            if peer.ready then lines[#lines+1]="可交付"
            elseif #peer.progress>0 then lines[#lines+1]=table.concat(peer.progress," · ") end
        end
        lines[#lines+1]=""
    end
    return lines
end

function P:RefreshUI()
    local settings=A.UI.Settings
    if settings.partyText and settings.frame:IsShown() and settings.groups[6]:IsShown() then settings.partyText:SetText(table.concat(self:Lines(),"\n")) end
end
