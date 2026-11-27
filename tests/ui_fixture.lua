return function(eq,F,A)
local names={"DaylightUI","CreateFrame","UIParent","STANDARD_TEXT_FONT","GameFontHighlight","SlashCmdList","InCombatLockdown","GetTime","UnitClass","RAID_CLASS_COLORS",
    "geterrorhandler","C_Item","C_PlayerInfo","C_Container","GetQuestID","GetNumQuestChoices","GetQuestItemLink","GetQuestReward",
    "AcceptQuest","CompleteQuest","GetQuestMoneyToGet","IsQuestCompletable","IsShiftKeyDown","C_GossipInfo","UnitGUID","UnitLevel","UnitXP","UnitXPMax","UnitIsAFK",
    "PlaySound","SOUNDKIT","NUM_CONTAINER_FRAMES","ContainerFrameCombinedBags","AiLeveling",
    "debugprofilestop","C_PlayerInteractionManager","UnitClassification","UnitName","UnitCanAttack","UnitIsDeadOrGhost","UnitOnTaxi","C_NamePlate","UIErrorsFrame","issecretvalue","canaccessvalue","Enum",
    "IsInGroup","IsInRaid","UnitIsGroupLeader","UnitIsConnected","FollowUnit",
    "GetQuestLink","ChatFrameUtil","IsModifiedClick","QuestMapFrame_OpenToQuestDetails","GetRealmName","MenuUtil","GameTooltip","MinimapCluster","Minimap","ObjectiveTrackerFrame",
    "C_SpellBook","IsCharacterNewlyBoosted","SetItemRef",
    "WorldMapFrame","UnitHealth","UnitHealthMax","GetMirrorTimerInfo","GetMirrorTimerProgress","FlashClientIcon","GetActionInfo","ActionButton1",
    "PlayerSpellsFrame","PlayerSpellsUtil","PlayerUtil","ExportUtil","C_Traits","C_ClassTalents","C_SpecializationInfo","GetNumSpecGroups"}
local function widget()
    local w={scripts={},width=100,height=40,shown=true,attributeWrites=0}
    for _,key in ipairs({"SetResizable","SetClampedToScreen","SetHyperlinksEnabled","SetBackdrop","SetBackdropBorderColor","SetJustifyH","SetJustifyV","SetMovable","EnableMouse","EnableMouseWheel","RegisterForDrag",
        "RegisterForClicks","SetClampRectInsets","SetAllPoints","SetTexture","SetTexCoord","SetHorizTile","SetVertTile","SetBlendMode","SetMaxLines","SetNonSpaceWrap","SetSpacing","SetDrawLayer","SetFontObject","SetMultiLine",
        "SetMaxLetters","SetShadowColor","SetShadowOffset","SetAutoFocus","SetTextInsets","SetNumeric","ClearFocus","SetFocus","HighlightText","SetFrameStrata","SetCooldown","Clear"}) do w[key]=function() end end
    w.SetPoint=function(self,...) self.point={...} end
    w.GetPoint=function(self) return "CENTER",UIParent,"CENTER",25,-30 end
    w.ClearAllPoints=function(self) self.point=nil end
    w.SetSize=function(self,x,y) self.width,self.height=x,y end
    w.SetWidth=function(self,x) self.width=x end;w.SetHeight=function(self,y) self.height=y end
    w.GetSize=function(self) return self.width,self.height end
    w.GetEffectiveScale=function(self) return self.scale or 1 end
    w.GetFrameLevel=function(self) return self.frameLevel or 1 end;w.SetFrameLevel=function(self,v) self.frameLevel=v end
    w.GetCenter=function(self) return self.centerX or 300,self.centerY or 400 end
    w.SetParent=function(self,parent) self.parent=parent end
    w.GetParent=function(self) return self.parent end
    w.GetWidth=function(self) return self.width or 18 end;w.GetHeight=function(self) return self.height end
    w.SetText=function(self,v) self.value=v end;w.GetText=function(self) return self.value or "" end
    w.GetStringHeight=function(self) return self.measuredHeight or 30 end
    w.GetStringWidth=function(self) return #(self.value or "")/3*(self.fontSize or 12) end
    w.SetWordWrap=function(self,enabled) self.wordWrap=enabled end
    w.SetFont=function(self,face,size,flags)
        assert(self.kind~="EditBox" or type(flags)=="string","bad argument #3 to SetFont: EditBox requires flags")
        self.fontFace,self.fontSize,self.fontFlags=face,size,flags
        return true
    end
    w.GetFont=function(self) return self.fontFace,self.fontSize,self.fontFlags end
    w.SetMinMaxValues=function() end;w.SetStatusBarColor=function() end;w.SetValue=function() end
    w.SetShadowColor=function(self,...) self.shadowColor={...} end
    w.GetShadowColor=function(self) return unpack(self.shadowColor or {0,0,0,0}) end
    w.SetShadowOffset=function(self,...) self.shadowOffset={...} end
    w.GetShadowOffset=function(self) return unpack(self.shadowOffset or {0,0}) end
    w.SetAtlas=function(self,atlas) self.atlas=atlas end
    w.SetTexture=function(self,texture) self.texture=texture end
    w.SetHighlightTexture=function(self,texture) self.highlight=texture;texture:Hide() end
    w.SetTextColor=function(self,...) self.color={...} end;w.SetColorTexture=w.SetTextColor
    w.SetVertexColor=w.SetTextColor
    w.SetBackdropColor=w.SetTextColor
    w.SetScale=function(self,v) self.scale=v end;w.SetAlpha=function(self,v) self.alpha=v end
    w.SetScript=function(self,event,callback) self.scripts[event]=callback end
    w.HookScript=function(self,event,callback)
        local previous=self.scripts[event]
        self.scripts[event]=function(...) if previous then previous(...) end;callback(...) end
    end
    w.RegisterForClicks=function(self,...) self.clicks={...} end
    w.RegisterEvent=function(self,event) self.events=self.events or {};self.events[event]=true end
    w.SetResizeBounds=function(self,...) self.resizeBounds={...} end
    w.StartSizing=function(self,point) self.sizing=point end
    w.StartMoving=function(self) self.moving=true end;w.StopMovingOrSizing=function(self) self.moving=false;self.sizing=nil end
    w.Show=function(self) self.shown=true end;w.Hide=function(self) self.shown=false end
    w.SetShown=function(self,v) self.shown=v end;w.IsShown=function(self) return self.shown end
    w.SetEnabled=function(self,v) self.enabled=v end
    w.IsEnabled=function(self) return self.enabled~=false end
    w.Click=function(self) if self.enabled~=false and self.scripts.OnClick then self.scripts.OnClick(self,"LeftButton") end end
    w.GetChecked=function(self) return self.checked end;w.SetChecked=function(self,v) self.checked=v end
    w.SetAttribute=function(self,k,v) assert(not InCombatLockdown(),"战斗中修改了受保护按钮");self.attributeWrites=self.attributeWrites+1;self[k]=v end
    w.SetRotation=function(self,value) self.rotation=value end
    w.SetDesaturated=function(self,v) self.desaturated=v end
    w.IsDesaturated=function(self) return self.desaturated or false end
    w.SetScrollChild=function(self,child) self.child=child end
    w.SetVerticalScroll=function(self,v) self.offset=v end
    w.GetVerticalScroll=function(self) return self.offset or 0 end
    w.CreateTexture=function() return widget() end
    w.CreateFontString=function(self) local text=widget();text.parent=self;return text end
    w.CreateLine=function() local line=widget();line.SetThickness=function() end;line.SetStartPoint=function() end;line.SetEndPoint=function() end;return line end
    return w
end
local function setup(fullUI,daylight,nameplates)
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    DaylightUI=daylight and {API=daylight}
    local clock,combat=10,false
    UIParent=widget();UIParent:SetSize(1920,1080);STANDARD_TEXT_FONT="font";GameFontHighlight={};SlashCmdList={};NUM_CONTAINER_FRAMES=0;ContainerFrameCombinedBags=nil
    MinimapCluster=widget();MinimapCluster:SetSize(280,280);ObjectiveTrackerFrame=widget()
    CreateFrame=function(kind,_,parent,template)
        local w=widget();w.kind,w.template,w.parent=kind,template,parent
        if kind=="Slider" then
            for _,method in ipairs({"SetOrientation","SetValueStep","SetObeyStepOnDrag","SetThumbTexture"}) do w[method]=function() end end
            w.SetValue=function(self,value)
                if self.value==value then return end
                self.value=value
                if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end
            end
        end
        if kind=="CheckButton" then w.Text=widget() end
        if kind=="PlayerModel" then
            w.ClearModel=function(self) self.creature=nil end
            w.SetCreature=function(self,id) self.creature=id end
            w.SetPortraitZoom=function(self,zoom) self.zoom=zoom end
        end
        return w
    end
    C_NamePlate=nameplates
    InCombatLockdown=function() return combat end;GetTime=function() return clock end
    debugprofilestop=function() return 0 end
    local B={}
    GameTooltip={Hide=function() end}
    MenuUtil={CreateContextMenu=function(owner,generate)
        B.menu={}
        generate(owner,{CreateButton=function(_,label,callback)
            local entry={callback=callback,enabled=true}
            entry.SetEnabled=function(self,value) self.enabled=value end
            B.menu[label]=entry;return entry
        end})
    end}
    assert(loadfile("Core.lua"))("AiLeveling",B)
    B.settings={};for k,v in pairs(B.defaults) do B.settings[k]=v end
    B.char={samples={},skipped={},deferredChains={},turnIns={}}
    B.state=F.State();B.state.bags[500]=2;B.state.quests[1]={objectives={}}
    local q=F.Quest(1);q.itemRules={[500]={kind="use",count=5,recovery="找 NPC 补领"}}
    B.Data=F.Data({[1]=q});B.Data.count=1
    B.action={kind="objective",questId=1,objectiveIndex=1}
    local nav={};assert(loadfile("Navigation.lua"))("AiLeveling",nav)
    B.Navigation={Current=function() return B.action end,RefreshPins=function() end,Target=nav.Navigation.Target,StaleAction=nav.Navigation.StaleAction}
    B.Dungeon={};assert(loadfile("Planner/DungeonTasks.lua"))("AiLeveling",B);B.Transport={InvalidateSample=function() end,InFlight=function() return false end}
    B.State={Refresh=function() B.refreshes=(B.refreshes or 0)+1;B.state.revision=B.state.revision+1 end}
    B.Gear=A.Gear;B.ready=true
    assert(loadfile("LevelingTracker.lua"))("AiLeveling",B)
    B.Selection={CanChoose=function() return false,"没有候选行程" end}
    local items={[500]={name="道具",loc="",stats=nil},[100]={name="奖励甲",loc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=1}},
        [101]={name="奖励乙",loc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=10}},[102]={name="药水",loc="",stats=nil}}
    local function idOf(value) return type(value)=="number" and value or tonumber(value:match("item:(%d+)")) end
    B.requests=0
    C_Item={GetItemNameByID=function(id) return items[id] and items[id].name end,GetItemIconByID=function() return 1 end,
        RequestLoadItemDataByID=function() B.requests=B.requests+1 end,
        GetItemInfo=function(value)
            local id=idOf(value);local item=items[id];if not item or item.pending then return end
            return item.name,"item:"..id,2,20,1,"","",1,item.loc,1,0,4,0
        end,GetItemStats=function(value) return items[idOf(value)].stats end,
        GetItemInfoInstant=function(id) return id,"","",items[id] and items[id].loc,1,4,0 end}
    C_PlayerInfo={CanUseItem=function() return true end}
    C_Container={GetItemCooldown=function() return 0,0 end}
    GetQuestID=function() return 1 end
    B.choices={100,101};B.linkReads=0
    GetNumQuestChoices=function() return #B.choices end
    GetQuestItemLink=function(kind,index) eq(kind,"choice");B.linkReads=B.linkReads+1;return "item:"..B.choices[index] end
    GetQuestReward=function() error("插件不能替玩家领取奖励") end
    B.sounds=0;SOUNDKIT={IG_QUEST_LIST_SELECT=123};PlaySound=function(id) eq(id,123);B.sounds=B.sounds+1 end
    assert(loadfile("Items.lua"))("AiLeveling",B)
    assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(loadfile("UI/Tracker.lua"))("AiLeveling",B)
    assert(loadfile("UI/Settings.lua"))("AiLeveling",B)
    local U=B.UI
    if fullUI then
        for _,name in ipairs({"Dungeon","Gear","Plan","Chains","Services","Browser"}) do
            assert(loadfile("UI/"..name..".lua"))("AiLeveling",B)
        end
        U:Create()
    else U:CreateTracker();U.details=widget() end
    U.title.measuredHeight=40;U.body.measuredHeight=300
    if not fullUI then U.Settings:Create(U.details) end;U.Settings:Refresh()
    assert(loadfile("QuestAssist.lua"))("AiLeveling",B)
    B.QuestAssist:Create();B.QuestAssist:Update()
    B.items=items
    B.combat=function(value) combat=value end;B.time=function(value) clock=value end
    B.finish=function() for _,name in ipairs(names) do _G[name]=saved[name] end end
    return B
end
local function setupMap()
    local B=setup();B.Transport.FlightGate=function() end
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    local adds={world=0,mini=0}
    B.Navigation.hbdPins={IsMinimapIconOnEdge=function(_,pin) return pin.onEdge end,RemoveAllWorldMapIcons=function() end,RemoveAllMinimapIcons=function() end,
        AddWorldMapIconMap=function(_,owner,pin) adds.world=adds.world+1;pin:Show() end,
        AddMinimapIconMap=function(_,owner,pin,map,x,y,parent,floatOnEdge) adds.mini=adds.mini+1;pin.floats=floatOnEdge;pin:Show() end}
    return B,adds
end
return setup,widget,setupMap
end
