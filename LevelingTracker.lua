local _,A=...
A.LevelingTracker={}
local T=A.LevelingTracker

local function number(value,max)
    return (not canaccessvalue or canaccessvalue(value)) and type(value)=="number" and value>=0 and value<=(max or 1e12)
end

function T.Normalize(char)
    local history=char.leveling
    if type(history)~="table" or history.version~=1 or type(history.levels)~="table" then
        history={version=1,levels={}};char.leveling=history
    end
    for level,row in pairs(history.levels) do
        local valid=number(level,60) and level>=1 and level%1==0 and type(row)=="table"
        if valid then
            for _,key in ipairs({"seconds","xp","quests","deaths"}) do
                if not number(row[key]) then valid=false;break end
            end
        end
        if not valid then history.levels[level]=nil
        else row.partial=row.partial==true;row.completed=row.completed==true end
    end
    return history
end

function T:Row(level,partial)
    local levels=T.Normalize(A.char).levels
    if not levels[level] then levels[level]={seconds=0,xp=0,quests=0,deaths=0,partial=partial==true} end
    return levels[level]
end

function T:Update(event)
    if not A.char or not A.settings or not UnitLevel or not UnitXP or not UnitXPMax then return end
    local now=GetTime()
    if not event and self.lastAt and now-self.lastAt<1 then return end
    local level,xp,maxXP=UnitLevel("player"),UnitXP("player"),UnitXPMax("player")
    if not number(level,60) or level<1 or level%1~=0 or not number(xp) or not number(maxXP) then return end
    local running=A.settings.levelingStats~=false and not A.char.paused and not (UnitIsAFK and UnitIsAFK("player"))
    local last=self.last
    local death=event=="PLAYER_DEAD" and not self.dead
    if event=="PLAYER_DEAD" then self.dead=true
    elseif event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST" then self.dead=false end
    if A.settings.levelingStats==false then
        self.last={level=level,xp=xp,maxXP=maxXP};self.lastAt=now;self.running=false;return
    end
    -- The level event can precede the new XP balance; settle it on XP update or the next tick.
    if event=="PLAYER_LEVEL_UP" and last then level,xp,maxXP=last.level,last.xp,last.maxXP end
    local row=self:Row(level,not last and (level>1 or xp>0))
    if last then
        local previous=self:Row(last.level)
        if self.running then
            local elapsed=math.max(0,now-self.lastAt)
            previous.seconds=previous.seconds+elapsed
            self.sessionSeconds=(self.sessionSeconds or 0)+elapsed
        end
        if level>last.level then
            previous.completed=true
            if level>last.level+1 or not self.running or not running then previous.partial=true;row.partial=true end
        end
        if self.running and running then
            local gain=0
            if level==last.level then gain=math.max(0,xp-last.xp);row.xp=row.xp+gain
            elseif level==last.level+1 and last.maxXP>0 then
                local remainder=math.max(0,last.maxXP-last.xp)
                previous.xp=previous.xp+remainder;row.xp=row.xp+xp;gain=remainder+xp
            elseif level~=last.level then row.partial=true end
            self.sessionXP=(self.sessionXP or 0)+gain
        end
    end
    -- XP can reset before the level event; keep the old balance for that rollover.
    if last and level==last.level and xp<last.xp then xp,maxXP=last.xp,last.maxXP end
    self.last={level=level,xp=xp,maxXP=maxXP};self.lastAt=now;self.running=running
    if death and running then row.deaths=row.deaths+1 end
end

function T:QuestTurnedIn()
    self:Update("quest")
    if self.running and self.last then local row=self:Row(self.last.level);row.quests=row.quests+1 end
end

local function duration(seconds)
    seconds=math.floor(seconds)
    return string.format("%d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end

function T:Report()
    self:Update("report")
    local levels=T.Normalize(A.char).levels
    local seconds,xp,quests,deaths=0,0,0,0
    local history={}
    for level=1,60 do
        local row=levels[level]
        if row then
            seconds=seconds+row.seconds;xp=xp+row.xp;quests=quests+row.quests;deaths=deaths+row.deaths
            history[#history+1]=string.format("%d 级%s · %s\n  活动 %s · 经验 %d · 交付 %d · 死亡 %d",level,
                row.partial and "（中途开始）" or "",row.completed and "已升级" or "记录中",duration(row.seconds),row.xp,row.quests,row.deaths)
        end
    end
    return string.format("练级统计%s\n\n累计活动 %s · 经验 %d\n经验／小时 %d · 交付 %d · 死亡 %d\n本次登录 活动 %s · 经验 %d\n\n%s\n\n活动时间排除离线、暂停和 AFK。",
        A.settings.levelingStats==false and "（已关闭）" or A.char.paused and "（已暂停）" or "",
        duration(seconds),xp,seconds>0 and xp*3600/seconds or 0,quests,deaths,
        duration(self.sessionSeconds or 0),self.sessionXP or 0,table.concat(history,"\n\n"))
end
