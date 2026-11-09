return function(test,eq,F)
test("小队同步任务进度、原生共享与通知，并在退出后清除队友状态",function()
    local names={"IsInGroup","IsInRaid","UnitName","UnitGUID","GetNormalizedRealmName","UnitIsConnected","C_ChatInfo","C_QuestLog",
        "QuestLogPushQuest","GetTime","InCombatLockdown","IsShiftKeyDown","LE_PARTY_CATEGORY_INSTANCE"}
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local grouped,raid,combat,shift,restricted,now=true,false,false,false,false,10
    LE_PARTY_CATEGORY_INSTANCE=nil
    IsInGroup=function() return grouped end;IsInRaid=function() return raid end
    UnitName=function(unit) if unit=="party1" then return "队友","家园" end end
    UnitGUID=function(unit) return unit=="party1" and "Player-2" or "Player-1" end
    GetNormalizedRealmName=function() return "家园" end;UnitIsConnected=function() return true end
    GetTime=function() return now end;InCombatLockdown=function() return combat end;IsShiftKeyDown=function() return shift end
    local sent,chat,shared,notices={},{},{},{}
    C_ChatInfo={RegisterAddonMessagePrefix=function(prefix) eq(prefix,"AiLeveling1") end,
        InChatMessagingLockdown=function() return restricted end,
        SendAddonMessage=function(prefix,message,channel) eq(prefix,"AiLeveling1");eq(channel,"PARTY");sent[#sent+1]=message end,
        SendChatMessage=function(message,channel) eq(channel,"PARTY");chat[#chat+1]=message end}
    C_QuestLog={GetLogIndexForQuestID=function(id) return id==1 and 3 end,IsPushableQuest=function(id) return id==1 end}
    QuestLogPushQuest=function(index) shared[#shared+1]=index end
    local B={version="0.1.129-dev",state=F.State(),char={},settings={partySync=true,autoShareQuests=false,partyAnnouncements=false},
        Transport={},UI={Settings={}},Navigation={},Data={GetQuest=function(_,id) return {title="任务"..id} end}}
    B.state.quests[1]={title="同一任务",ready=false,objectives={{numFulfilled=1,numRequired=3,finished=false}}}
    B.Navigation.Current=function() return {questId=1,kind="objective"} end
    B.Message=function(_,message) notices[#notices+1]=message end
    assert(loadfile("Party.lua"))("AiLeveling",B)
    local P=B.Party;P:Initialize();P:Update();eq(#sent,1)
    P:Receive("AiLeveling1",sent[1],"PARTY","陌生人");eq(next(P.peers),nil)
    P:Receive("AiLeveling1",sent[1],"PARTY","队友");eq(P.peers["队友-家园"].progress[1],"1/3")
    P:Receive("AiLeveling1","1|bad|20|x|objective|0","PARTY","队友");eq(P.peers["队友-家园"].progress[1],"1/3")
    eq(#chat,0);P:Event("QUEST_ACCEPTED",1);eq(next(P.pending),nil)
    B.settings.autoShareQuests=true;P:Event("QUEST_ACCEPTED",1);now=12;P:Update();eq(shared[1],3)
    P:Receive("AiLeveling1","1|0.1.130-dev|21|1|turnin|1|3:3:1","PARTY","队友-家园")
    eq(#notices,1);assert(table.concat(P:Lines(),"\n"):find("版本不同",1,true));eq(B.state.quests[1].ready,false)
    P:Receive("AiLeveling1","1|0.1.130-dev|21|1|turnin|1|3:3:1","PARTY","队友-家园");eq(#notices,1)
    B.settings.partyAnnouncements=true;B.state.quests[1].ready=true;now=14;P:Update();eq(chat[1],"任务完成：同一任务")
    P:Event("PLAYER_LEVEL_UP",21);eq(chat[2],"我升到了 21 级。")
    B.Transport.flight={name="目的地",duration=125};now=16;P:Update();eq(chat[3],"正在飞往：目的地 · 预计 3 分钟")
    combat=true;eq(P:ShareQuest(1),false);combat=false
    shift=true;P:Event("QUEST_ACCEPTED",1);eq(next(P.pending),nil);shift=false
    local before=#sent;restricted=true;B.char.paused=true;now=18;P:Update();eq(#sent,before)
    restricted=false;now=20;P:Update();assert(sent[#sent]:find("|0|paused|0",1,true));eq(#chat,3)
    B.settings.partySync=false;now=22;P:Update();eq(next(P.peers),nil)
    grouped=false;P:Event("GROUP_ROSTER_UPDATE");eq(next(P.members),nil);eq(next(P.pending),nil)
    for _,name in ipairs(names) do _G[name]=saved[name] end
end)
end
