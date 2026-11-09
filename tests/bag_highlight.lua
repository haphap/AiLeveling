return function(test,eq,actualBagsPath)
local names={"DaylightUIBag","ContainerFrameCombinedBags","NUM_CONTAINER_FRAMES","C_Container","C_Timer",
    "hooksecurefunc","InCombatLockdown","issecretvalue","CreateFrame","DaylightUI","Constants","NUM_BAG_SLOTS","KEYRING_CONTAINER"}
local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
local function fixture()
    local env={ids={["0:1"]=101,["0:2"]=102,["0:3"]=103},later={},hookCount=0,created=0}
    InCombatLockdown=function() return env.combat end
    issecretvalue=function() return false end
    local function frame(parent)
        local f={shown=true,parent=parent,hooks={}}
        function f:IsShown() return self.shown end
        function f:IsForbidden() return self.forbidden end
        function f:GetID() return self.id end
        function f:SetID(id) self.id=id end
        function f:GetParent() return self.parent end
        function f:GetBagID() return 0 end
        function f:Show() self.shown=true;if self.hooks.OnShow then self.hooks.OnShow() end end
        function f:Hide() self.shown=false;if self.hooks.OnHide then self.hooks.OnHide() end end
        function f:SetAllPoints() end
        function f:HookScript(event,fn) self.hooks[event]=fn;env.hookCount=env.hookCount+1 end
        function f:CreateTexture()
            assert(not env.combat);env.created=env.created+1
            local t={}
            for _,k in ipairs({"SetAllPoints","SetTexture","SetBlendMode","SetVertexColor"}) do t[k]=function() assert(not env.combat) end end
            function t:Show() assert(not env.combat);self.shown=true end
            function t:Hide() assert(not env.combat);self.shown=false end
            return t
        end
        return f
    end
    env.frame=frame
    C_Container={GetContainerItemID=function(bag,slot) return env.ids[bag..":"..slot] end,
        GetContainerNumSlots=function() return 3 end}
    C_Timer={After=function(_,fn) env.later[#env.later+1]=fn end}
    function env.flush() local list=env.later;env.later={};for _,fn in ipairs(list) do fn() end end
    hooksecurefunc=function(t,key,fn)
        env.hookCount=env.hookCount+1;local old=t[key]
        t[key]=function(...) old(...);fn(...) end
    end
    DaylightUIBag=frame();DaylightUIBag.kind="bag"
    local slots={};env.buttons={}
    for i=1,3 do local b=frame();b.id=i;env.buttons[i]=b;slots[i]={bag=0,button=b} end
    DaylightUIBag.set={Slots=function() return slots end,Sync=function() end}
    ContainerFrameCombinedBags=frame()
    ContainerFrameCombinedBags.EnumerateValidItems=function() return ipairs(env.buttons) end
    NUM_CONTAINER_FRAMES=0
    local B={settings={highlight=true},char={}}
    assert(loadfile("QuestAssist.lua"))("AiLeveling",B)
    B.QuestAssist.active={101};B.QuestAssist.requirements={{id=101},{id=102,kind="key"},{id=103,finished=true}}
    return B,env
end
test("原生及Daylight背包按真实槽位高亮全部所需物品且隐藏堆叠不重复",function()
    local B,e=fixture();local q=B.QuestAssist;q:Highlight()
    eq(#q.highlights,2);eq(e.created,2);assert(e.buttons[2].AiLevelingHighlight.shown)
    eq(e.buttons[3].AiLevelingHighlight,nil)
    ContainerFrameCombinedBags=nil;e.buttons[1]:Hide();q:Highlight();eq(#q.highlights,1)
    eq(e.buttons[1].AiLevelingHighlight.shown,false)
    DaylightUIBag.kind="viewer";q:Highlight();eq(#q.highlights,0)
end)
test("背包整理与开关延后合并刷新且复用光圈不改物品按钮",function()
    local B,e=fixture();ContainerFrameCombinedBags=nil;local q=B.QuestAssist;q:Highlight();eq(e.hookCount,3)
    e.ids["0:1"]=999;e.ids["0:3"]=101
    DaylightUIBag.set.Sync();DaylightUIBag.set.Sync();eq(#e.later,1)
    e.flush();eq(e.buttons[1].AiLevelingHighlight.shown,false);assert(e.buttons[3].AiLevelingHighlight.shown)
    eq(e.created,3);q:Highlight();eq(e.created,3);eq(e.hookCount,3)
    DaylightUIBag:Hide();e.flush();eq(#q.highlights,0)
    DaylightUIBag:Show();e.flush();eq(#q.highlights,2)
end)
test("背包晚创建战斗暂停和关闭高亮保持安全",function()
    local B,e=fixture();ContainerFrameCombinedBags=nil;local bag=DaylightUIBag;DaylightUIBag=nil
    local q=B.QuestAssist;q:Highlight();eq(#q.highlights,0)
    DaylightUIBag=bag;q:Highlight();eq(#q.highlights,2)
    e.combat=true;B.settings.highlight=false;q:ScheduleHighlight();e.flush();eq(#q.highlights,2)
    e.combat=false;q:Highlight();eq(#q.highlights,0)
    B.settings.highlight=true;B.char.paused=true;q:Highlight();eq(#q.highlights,0)
    B.char.paused=false;q.requirements=nil;q.wanted={101,102,103};q:Highlight();eq(#q.highlights,3)
end)
if actualBagsPath then
    test("已安装DaylightUI Bags真实槽位池接入",function()
        local B,e=fixture();ContainerFrameCombinedBags=nil
        DaylightUI={};Constants=nil;NUM_BAG_SLOTS=0;KEYRING_CONTAINER=nil
        CreateFrame=function(_,_,parent) return e.frame(parent) end
        local ns={Items={Dress=function() end,TEMPLATE="ContainerFrameItemButtonTemplate"},Saved={Is=function() return false end}}
        assert(loadfile(actualBagsPath))("DaylightUI_Bags",ns)
        DaylightUIBag.set=ns.Bags;ns.Bags.Sync(e.frame(DaylightUIBag))
        B.QuestAssist:Highlight();eq(#B.QuestAssist.highlights,2)
        e.ids["0:1"]=999;ns.Bags.Sync(e.frame());e.flush();eq(#B.QuestAssist.highlights,1)
    end)
end
for _,name in ipairs(names) do _G[name]=saved[name] end
end
