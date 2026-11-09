local _, A = ...
A.UI.Settings = {}
local S=A.UI.Settings

function S:Create(parent)
    self.frame=CreateFrame("Frame",nil,parent)
    self.frame:SetPoint("TOPLEFT",18,-94);self.frame:SetPoint("BOTTOMRIGHT",-18,18)
    self.groups,self.controls={},{}
    for i,name in ipairs({"路线规划","显示与导航","任务辅助","数据与兼容","背包整理","队伍协作"}) do
        local group=CreateFrame("Frame",nil,self.frame)
        group:SetPoint("TOPLEFT",0,-40);group:SetPoint("BOTTOMRIGHT")
        self.groups[i]=group
        local b=A.UI:Button(self.frame,name,90,function()
            for j,f in ipairs(self.groups) do f:SetShown(i==j) end
        end)
        b:SetPoint("TOPLEFT",(i-1)*96,0);group:SetShown(i==1)
    end
    local function position(row) return math.floor(row/8)*286,-(row%8)*40 end
    local function check(group,key,label,row)
        local b=CreateFrame("CheckButton",nil,self.groups[group],"UICheckButtonTemplate")
        b:SetPoint("TOPLEFT",position(row));b.Text:SetText(label);b.Text:SetWidth(238)
        A.UI:RegisterFont(b.Text,12)
        b:SetScript("OnClick",function() A:SetOption(key,b:GetChecked()==true) end)
        self.controls[#self.controls+1]={button=b,key=key}
    end
    local function cycle(group,key,label,values,names,row)
        local b=A.UI:Button(self.groups[group],label,270,function()
            local index=1
            for i,v in ipairs(values) do if A.settings[key]==v then index=i%#values+1;break end end
            A:SetOption(key,values[index]);self:Refresh()
        end)
        b:SetHeight(34);b.text:SetWidth(260);b.text:SetMaxLines(2)
        b:SetPoint("TOPLEFT",position(row))
        self.controls[#self.controls+1]={button=b,key=key,label=label,values=values,names=names}
    end
    cycle(1,"minutes","游戏时间",{15,30,45,60,90,120,180,240},{"15 分钟","30 分钟","45 分钟","60 分钟","90 分钟","120 分钟","180 分钟","240 分钟"},0)
    cycle(1,"role","副本职责",{"DAMAGER","TANK","HEALER"},{"输出","坦克","治疗"},1)
    check(1,"dungeons","允许自动推荐副本",2)
    cycle(1,"waitMinutes","等队估计",{0,5,10,15,20,30,45,60},{"0 分钟","5 分钟","10 分钟","15 分钟","20 分钟","30 分钟","45 分钟","60 分钟"},3)
    cycle(1,"damageStyle","输出属性",{"auto","strength","agility","ranged","caster","hybrid"},{"按职业／混合","近战力量","近战敏捷","远程物理","施法输出","混合属性"},4)
    cycle(1,"gearPreference","装备偏好",{"nearby","xp"},{"接近经验率时比较装备","按经验率选择"},5)
    local auto=A.UI:Button(self.groups[1],"恢复自动选择",270,function()
        local ok,why=A.Selection:Automatic();if not ok then A:Message(why) end
    end)
    auto:SetPoint("TOPLEFT",position(6))
    local hint=A.UI:Text(self.groups[1],12)
    hint:SetPoint("TOPLEFT",286,0);hint:SetWidth(268)
    hint:SetText("在行程页选择任务组合与顺序，在任务链页锁定目标或暂缓整链。\n\n在副本页结束当前行程后，恢复自动升级。")
    cycle(2,"fontScale","字号",{0.85,1,1.1,1.2},{"85%","100%","110%","120%"},0)
    cycle(2,"scale","界面缩放",{0.75,0.85,1,1.15,1.3,1.5},{"75%","85%","100%","115%","130%","150%"},1)
    cycle(2,"alpha","透明度",{0.2,0.5,0.75,0.85,0.94,1},{"20%","50%","75%","85%","94%","100%"},2)
    cycle(2,"density","卡片密度",{"compact","normal","expanded"},{"紧凑","标准","展开"},3)
    check(2,"lockWindow","锁定窗口位置",4)
    check(2,"routes","显示目的地连线",5)
    check(2,"arrow","显示方向箭头",6)
    check(2,"pins","显示世界地图点",7)
    check(2,"minimapPins","显示小地图点",8)
    cycle(2,"distanceUnits","距离单位",{"yards","meters"},{"码","米"},9)
    check(2,"transportHints","显示交通使用说明",10)
    check(2,"combatFold","战斗中收起解释区",11)
    check(2,"waypointUI","同步 Waypoint UI 目的地",12)
    check(2,"dangerMap","地图显示危险怪与巡逻位置",13)
    check(3,"items","显示任务物品按钮",0)
    check(3,"highlight","高亮背包任务物品",1)
    check(3,"quantity","显示物品数量",2)
    check(3,"missingChecks","显示物品缺失提醒",3)
    check(3,"rewardAdvice","显示可选奖励建议",4)
    check(3,"sound","提示音（战斗外）",5)
    check(3,"worldHighlight","高亮附近可交互物件",6)
    check(3,"autoAccept","自动接取建议任务",7)
    check(3,"autoTurnIn","自动交付完成任务",8)
    check(3,"targets","显示目标与队长按钮",9)
    check(3,"autoTaxi","自动乘坐计划航线",10)
    check(3,"scanRares","发现附近稀有怪",11)
    check(3,"autoTrain","自动学习已选训练项目",12)
    check(3,"autoBind","自动确认已安排的炉石绑定",13)
    check(3,"emergency","低血量急救高亮与溺水提醒",14)
    check(3,"autoGossip","自动继续当前任务的单选对话",15)
    local binding=A.UI:Text(self.groups[3],12)
    binding:SetPoint("TOPLEFT",0,-332);binding:SetWidth(554)
    binding:SetText("按住 Shift 临时手动操作，多选奖励由你选择。\n\n快捷键见系统按键设置的 AiLeveling。目标按钮左键选中、右键标记，战斗外滚轮／中键切换。")
    check(4,"learn","记录本地耗时统计",0)
    local reset=A.UI:Button(self.groups[4],"重置本地统计",270,function()
        A.char.samples={}
        A.Dungeon.runSample=nil;A.Transport:InvalidateSample()
        if A.Hearth then A.Hearth:InvalidateSample() end
        if A.ready then A.State:Refresh(true) end
    end)
    reset:SetPoint("TOPLEFT",position(1))
    local resume=A.UI:Button(self.groups[4],"清除暂缓与锁定",270,function()
        A.char.skipped,A.char.locked={},nil;A.char.deferredChains={};A.Selection:Clear()
        if A.ready then A.State:Refresh(true) end
    end)
    resume:SetPoint("TOPLEFT",position(2))
    local diagnostic=A.UI:Button(self.groups[4],"查看可复制诊断",270,function() A.UI:ShowText(A:Diagnostics()) end)
    diagnostic:SetPoint("TOPLEFT",position(3))
    local defaults=A.UI:Button(self.groups[4],"恢复设置与窗口位置",270,function() A:RestoreSettings() end)
    defaults:SetPoint("TOPLEFT",position(4))
    check(4,"levelingStats","记录练级时间与经验",5)
    local leveling=A.UI:Button(self.groups[4],"查看练级统计",270,function() A.UI:ShowText(A.LevelingTracker:Report()) end)
    leveling:SetPoint("TOPLEFT",position(6))
    local history=A.UI:Button(self.groups[4],"刷新并查看已完成任务",270,function() A.UI:ShowText(A:QuestHistory()) end)
    history:SetPoint("TOPLEFT",position(7))
    self.profile=A.UI:Button(self.groups[4],"配置",270,function()
        local names={};for name in pairs(A.db.profiles) do names[#names+1]=name end
        table.sort(names)
        for i,name in ipairs(names) do if name==A.char.profile then A:SelectProfile(names[i%#names+1]);break end end
    end)
    self.profile:SetPoint("TOPLEFT",position(8));self.profile.text:SetWidth(258)
    self.profileName=CreateFrame("EditBox",nil,self.groups[4],"InputBoxTemplate")
    self.profileName:SetSize(258,30);self.profileName:SetPoint("TOPLEFT",292,-40)
    self.profileName:SetAutoFocus(false);self.profileName:SetMaxLetters(32)
    A.UI:RegisterFont(self.profileName,13)
    self.profileName:SetText("新配置")
    self.profileName:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
    local function copyProfile()
        local ok,why=A:CopyProfile(self.profileName:GetText())
        if ok then self.profileName:ClearFocus() else A:Message(why) end
    end
    local copy=A.UI:Button(self.groups[4],"以此名称复制当前配置",270,copyProfile)
    copy:SetPoint("TOPLEFT",position(10))
    self.profileName:SetScript("OnEnterPressed",copyProfile)
    local useDefault=A.UI:Button(self.groups[4],"设为新角色默认配置",270,function()
        A.db.defaultProfile=A.char.profile;self:Refresh()
    end)
    useDefault:SetPoint("TOPLEFT",position(11))
    self.deleteProfile=A.UI:Button(self.groups[4],"删除当前配置",270,function()
        local ok,why=A:DeleteProfile(A.char.profile);if not ok then A:Message(why) end
    end)
    self.deleteProfile:SetPoint("TOPLEFT",position(12))
    self.profileHint=A.UI:Text(self.groups[4],12);self.profileHint:SetPoint("TOPLEFT",286,-200);self.profileHint:SetWidth(268)
    self.summary=A.UI:Text(self.groups[4],12);self.summary:SetPoint("TOPLEFT",286,-248);self.summary:SetWidth(268)
    check(5,"autoSellJunk","到店出售垃圾（灰色及手动标记）",0)
    cycle(5,"maxSoulShards","灵魂碎片保留",{0,5,10,15,20,30,40,100},{"0","5","10","15","20","30","40","100"},1)
    self.bagSummary=A.UI:Text(self.groups[5],14);self.bagSummary:SetPoint("TOPLEFT",286,-4);self.bagSummary:SetWidth(268)
    local instruction=A.UI:Text(self.groups[5],12);instruction:SetPoint("TOPLEFT",0,-96);instruction:SetWidth(554)
    instruction:SetText("拖入物品或输入物品 ID／链接，选择垃圾或保留。\n任务物品与炉石始终保留；灵魂袋内的碎片保留。")
    self.junkItem=CreateFrame("EditBox",nil,self.groups[5],"InputBoxTemplate")
    self.junkItem:SetSize(548,30);self.junkItem:SetPoint("TOPLEFT",6,-144)
    self.junkItem:SetAutoFocus(false);self.junkItem:SetMaxLetters(256);A.UI:RegisterFont(self.junkItem,13)
    self.junkItem:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
    self.junkItem:SetScript("OnTextChanged",function() self:RefreshBags() end)
    self.junkItem:SetScript("OnReceiveDrag",function(box)
        local kind,id=GetCursorInfo()
        if kind=="item" then box:SetText(tostring(id));ClearCursor();self:RefreshBags() end
    end)
    local function mark(value)
        local ok,why=A.Merchant:MarkJunk(self:JunkItemID(),value)
        self.bagMessage=not ok and why or nil;self.junkItem:ClearFocus();self:RefreshBags()
    end
    local junk=A.UI:Button(self.groups[5],"标为垃圾",174,function() mark(true) end);junk:SetPoint("TOPLEFT",0,-184)
    local keep=A.UI:Button(self.groups[5],"保留此物品",174,function() mark(false) end);keep:SetPoint("TOPLEFT",190,-184)
    local resetJunk=A.UI:Button(self.groups[5],"恢复此物品默认分类",174,function() mark(nil) end);resetJunk:SetPoint("TOPLEFT",380,-184)
    self.junkLabel=A.UI:Text(self.groups[5],13);self.junkLabel:SetPoint("TOPLEFT",0,-222);self.junkLabel:SetWidth(554)
    self.discard=A.UI:Button(self.groups[5],"丢弃价值最低的一组垃圾",554,function()
        local ok,why=A.Merchant:Discard(self.discardItem)
        self.bagMessage=not ok and why or nil;self:RefreshBags()
    end)
    self.discard:SetPoint("TOPLEFT",0,-264);self.discard:SetHeight(42);self.discard.text:SetWidth(534);self.discard.text:SetMaxLines(2)
    self.groups[5]:SetScript("OnShow",function() self:RefreshBags() end)
    for _,event in ipairs({"BAG_UPDATE_DELAYED","GET_ITEM_INFO_RECEIVED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do self.groups[5]:RegisterEvent(event) end
    self.groups[5]:SetScript("OnEvent",function() if self.frame:IsShown() and self.groups[5]:IsShown() then self:RefreshBags() end end)
    check(6,"partySync","与队友同步任务与进度",0)
    check(6,"autoShareQuests","接取后自动共享任务",1)
    check(6,"partyAnnouncements","队伍聊天：升级、完成及飞行",2)
    local share=A.UI:Button(self.groups[6],"共享当前任务",270,function()
        local action=A.Navigation:Current()
        local _,why=A.Party:ShareQuest(action and action.questId)
        A:Message(why)
    end);share:SetPoint("TOPLEFT",position(3))
    local hint=A.UI:Text(self.groups[6],12);hint:SetPoint("TOPLEFT",0,-176);hint:SetWidth(268)
    hint:SetText("任务与进度在同样安装 AiLeveling 的队友之间显示。\n\n原生任务共享会向队友发送接取请求。按住 Shift 接任务可临时跳过自动共享。")
    self.partyText=A.UI:Text(self.groups[6],13);self.partyText:SetPoint("TOPLEFT",286,0);self.partyText:SetWidth(268)
    self.groups[6]:SetScript("OnShow",function() if A.Party then A.Party:RefreshUI() end end)
    self.frame:Hide()
end

function S:ShowParty()
    A.UI.details:Show();A.UI:SelectTab(5)
    for i,group in ipairs(self.groups) do group:SetShown(i==6) end
    A.Party:RefreshUI()
end

function S:JunkItemID()
    local text=self.junkItem:GetText()
    return tonumber(text:match("item:(%d+)")) or tonumber(text)
end

function S:ShowBags()
    A.UI.details:Show();A.UI:SelectTab(5)
    for i,group in ipairs(self.groups) do group:SetShown(i==5) end
    self:RefreshBags()
end

function S:RefreshBags()
    if not A.Merchant or not A.ready then return end
    local id=self:JunkItemID()
    local name,_,quality
    if id and id>0 and id<2147483648 and id%1==0 then name,_,quality=C_Item.GetItemInfo(id) end
    self.junkLabel:SetText(self.bagMessage or (name and (name.." · "..(A.Merchant:IsJunk(id,quality) and "垃圾" or "保留")) or "请选择背包物品"))
    local free=0
    for bag=0,NUM_BAG_SLOTS or 4 do
        local count,family=C_Container.GetContainerNumFreeSlots(bag)
        if family==0 then free=free+(count or 0) end
    end
    self.bagSummary:SetText("通用背包空格："..free..(A.state.class=="WARLOCK" and ("\n灵魂碎片："..C_Item.GetItemCount(6265,false,false,false)) or ""))
    for _,control in ipairs(self.controls) do if control.key=="maxSoulShards" then control.button:SetShown(A.state.class=="WARLOCK") end end
    self.discardItem=A.Merchant:DiscardCandidate()
    local item=self.discardItem
    self.discard.text:SetText(item and ("丢弃："..(item.link or item.name).." ×"..item.count) or "暂无可丢弃的垃圾")
    self.discard:SetEnabled(item~=nil and not InCombatLockdown())
end

function S:Refresh()
    self.profile:SetEnabled(A.db~=nil)
    self.deleteProfile:SetEnabled(A.db~=nil and A.char.profile~=A.db.defaultProfile)
    self.profile.text:SetText("配置："..(A.char.profile or "默认").."  ›")
    self.profileHint:SetText("更改自动保存 · 点击配置名切换\n新角色默认："..(A.db and A.db.defaultProfile or "默认"))
    for _,c in ipairs(self.controls) do
        if c.values then
            local value=tostring(A.settings[c.key])
            for i,v in ipairs(c.values) do if A.settings[c.key]==v then value=c.names[i] end end
            c.button.text:SetText(c.label.."："..value)
        else c.button:SetChecked(A.settings[c.key]) end
    end
    local nodes=A.Data and A.Data.NodeCount and A.Data:NodeCount() or 0
    self.summary:SetText("版本："..A.version.."\n已索引任务："..(A.Data.count or 0).."\n自有目的地："..nodes..
        "\n任务／奖励／经验："..(A.TaskGuide and table.concat({A.TaskGuide.Counts()},"／") or "0／0／0")..
        "\n服务 NPC："..(A.Data.serviceCount or 0))
    if self.groups[5]:IsShown() then self:RefreshBags() end
    if A.Party then A.Party:RefreshUI() end
end
