local _, A = ...
A.UI.Settings = {}
local S=A.UI.Settings

function S:Create(parent)
    self.frame=CreateFrame("Frame",nil,parent)
    self.frame:SetPoint("TOPLEFT",18,-94);self.frame:SetPoint("BOTTOMRIGHT",-18,18)
    self.groups,self.controls={},{}
    for i,name in ipairs({"路线规划","显示与导航","任务辅助","数据与兼容"}) do
        local group=CreateFrame("Frame",nil,self.frame)
        group:SetPoint("TOPLEFT",0,-40);group:SetPoint("BOTTOMRIGHT")
        self.groups[i]=group
        local b=A.UI:Button(self.frame,name,132,function()
            for j,f in ipairs(self.groups) do f:SetShown(i==j) end
        end)
        b:SetPoint("TOPLEFT",(i-1)*143,0);group:SetShown(i==1)
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
    cycle(1,"mode","升级风格",{"relaxed","fast","story"},{"轻松单人","快速升级","剧情探索"},0)
    cycle(1,"minutes","游戏时间",{15,30,45,60,90,120,180,240},{"15 分钟","30 分钟","45 分钟","60 分钟","90 分钟","120 分钟","180 分钟","240 分钟"},1)
    cycle(1,"role","副本职责",{"DAMAGER","TANK","HEALER"},{"输出","坦克","治疗"},2)
    check(1,"dungeons","允许自动推荐副本",3)
    cycle(1,"waitMinutes","等队估计",{0,5,10,15,20,30,45,60},{"0 分钟","5 分钟","10 分钟","15 分钟","20 分钟","30 分钟","45 分钟","60 分钟"},4)
    cycle(1,"damageStyle","输出属性",{"auto","strength","agility","ranged","caster","hybrid"},{"按职业／混合","近战力量","近战敏捷","远程物理","施法输出","混合属性"},5)
    cycle(1,"gearPreference","装备偏好",{"nearby","xp"},{"接近经验率时比较装备","按经验率选择"},6)
    local auto=A.UI:Button(self.groups[1],"恢复自动选择",270,function()
        local ok,why=A.Selection:Automatic();if not ok then A:Message(why) end
    end)
    auto:SetPoint("TOPLEFT",position(7))
    local hint=A.UI:Text(self.groups[1],12)
    hint:SetPoint("TOPLEFT",286,0);hint:SetWidth(268)
    local guides=A.UI:Button(self.groups[1],"选择／导入指南",268,function() if A.UI.Guides then A.UI.Guides:Open() end end)
    guides:SetPoint("TOPLEFT",286,-150)
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
    check(3,"items","显示任务物品按钮",0)
    check(3,"highlight","高亮背包任务物品",1)
    check(3,"quantity","显示物品数量",2)
    check(3,"missingChecks","显示物品缺失提醒",3)
    check(3,"rewardAdvice","显示可选奖励建议",4)
    check(3,"sound","行动提示音（战斗外）",5)
    check(3,"worldHighlight","高亮附近可交互物件",6)
    check(3,"autoAccept","自动接取建议任务",7)
    check(3,"autoTurnIn","自动交付完成任务",8)
    check(3,"targets","显示当前任务目标按钮",9)
    local binding=A.UI:Text(self.groups[3],12)
    binding:SetPoint("TOPLEFT",286,-96);binding:SetWidth(268)
    binding:SetText("按住 Shift 可临时手动接交任务。多选奖励由你选择。\n\n在系统按键设置的 AiLeveling 分类中，设置任务物品、选中任务目标和标记目标快捷键。\n\n目标按钮：左键选中，右键给当前选中的目标加骷髅标记。已有标记保留。")
    check(4,"learn","记录本地耗时统计",0)
    local reset=A.UI:Button(self.groups[4],"重置本地统计",270,function()
        A.char.samples={};A.char.sampleContext=nil
        A.Observations:Reset();A.Dungeon.runSample=nil;A.Transport:InvalidateSample()
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
    self.summary=A.UI:Text(self.groups[4],12);self.summary:SetPoint("TOPLEFT",286,0);self.summary:SetWidth(268)
    self.frame:Hide()
end

function S:Refresh()
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
end
