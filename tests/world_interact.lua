return function(test,eq)
    local names={"CreateFrame","UIParent","C_NamePlate","C_CVar","C_AddOns","C_QuestLog",
        "UnitIsGameObject","SetUnitCursorTexture","UnitIsInInteractRange","UnitName","UnitGUID",
        "UnitIsUnit","GetBindingKey","InCombatLockdown","GetTime","issecretvalue"}
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local function fixture()
        local state={object=true,range=true,cursor="Mine",name="铜矿",key="F",vars={},plates={},guids={},secret={}}
        for _,name in ipairs({"SoftTargetInteract","SoftTargetNameplateInteract","SoftTargetIconGameObject",
            "SoftTargetInteractRange","SoftTargetInteractOnlyInRange","nameplateGameObjectMaxDistance"}) do state.vars[name]="0" end
        local ids,nextID={},100
        local function textureID(path)
            if type(path)~="string" then return path end
            if not ids[path] then nextID=nextID+1;ids[path]=nextID end
            return ids[path]
        end
        local function frame()
            local f={scripts={},shown=true}
            for _,method in ipairs({"SetSize","EnableMouse","SetFrameStrata","SetAllPoints","SetBlendMode",
                "SetWidth","SetShadowColor","SetShadowOffset","RegisterEvent","ClearAllPoints"}) do f[method]=function() end end
            function f:SetScript(k,v) self.scripts[k]=v end
            function f:SetPoint(...) self.point={...} end
            function f:SetTexture(path) self.texture=textureID(path) end
            function f:GetTexture() return self.texture end
            function f:SetAlpha(v) self.alpha=v end
            function f:SetVertexColor(...) self.color={...} end
            f.SetTextColor=f.SetVertexColor
            function f:SetText(v) self.text=v end
            function f:Show() self.shown=true end
            function f:Hide() self.shown=false end
            function f:IsShown() return self.shown end
            function f:IsForbidden() return self.forbidden end
            f.CreateTexture=frame;f.CreateFontString=frame
            return f
        end
        CreateFrame=frame;UIParent={}
        state.plate=frame();state.plates.softinteract=state.plate;state.guids.softinteract="Object-1"
        C_NamePlate={GetNamePlateForUnit=function(unit) return state.plates[unit] end}
        C_CVar={GetCVar=function(name) return state.vars[name] end,SetCVar=function(name,value)
            assert(not state.combat,"战斗中不改 CVar");state.vars[name]=value
        end}
        C_AddOns={IsAddOnLoaded=function(name) return name=="Lueur" and state.lueur end}
        C_QuestLog={UnitIsRelatedToActiveQuest=function() return state.quest end}
        UnitIsGameObject=function() return state.object end
        UnitIsInInteractRange=function() return state.range end
        UnitName=function() return state.name end
        UnitGUID=function(unit) return state.guids[unit] end
        UnitIsUnit=function(a,b) return state.sameToken==a and b=="softinteract" end
        GetBindingKey=function(binding) eq(binding,"INTERACTTARGET");return state.key end
        InCombatLockdown=function() return state.combat end
        GetTime=function() return 0 end
        issecretvalue=function(value) return value==state.secret end
        SetUnitCursorTexture=function(texture,unit)
            eq(unit,"softinteract")
            if state.secretCursor then texture.texture=state.secret;return state.secret end
            if state.cursor then texture:SetTexture("Interface\\Cursor\\"..state.cursor);return true end
        end
        local B={char={},settings={worldHighlight=true}}
        assert(loadfile("WorldInteract.lua"))("AiLeveling",B)
        return B,state
    end
    test("场景物件依原生光标分类，任务优先且仅就绪时显示按键",function()
        local B,s=fixture();local w=B.WorldInteract;w:Initialize()
        eq(w:Category(),"ore");eq(w.glow.shown,true);eq(w.glow.label.text,"铜矿  [F]")
        s.cursor="GatherHerbs";eq(w:Category(),"herb")
        s.cursor="Pickup";eq(w:Category(),"loot")
        s.quest=true;eq(w:Category(),"quest");s.quest=false
        s.cursor="Mine";s.range=false;w:Update();eq(w.glow.ring.alpha,0.3);eq(w.glow.label.text,"铜矿")
        s.range=nil;w:Update();eq(w.glow.label.text,"铜矿")
        s.range=true;s.cursor="MineUnable";w:Update();eq(w.glow.ring.color[1],0.5);eq(w.glow.label.text,"铜矿")
        s.cursor=nil;w:Update();eq(w.glow.shown,false)
        s.quest=true;w:Update();eq(w.glow.shown,true)
        s.object=false;w:Update();eq(w.glow.shown,false)
    end)
    test("场景名条回退只匹配相同物件，不误标其他物件",function()
        local B,s=fixture();local w=B.WorldInteract;w:Initialize()
        s.plates.softinteract=nil;s.plates.nameplate1=s.plate;s.guids.nameplate1="Object-2"
        w.events.scripts.OnEvent(nil,"NAME_PLATE_UNIT_ADDED","nameplate1");eq(w.glow.shown,false)
        s.guids.nameplate1="Object-1";w:Update();eq(w.glow.shown,true);eq(w.glow.point[2],s.plate)
        s.plate.forbidden=true;w:Update();eq(w.glow.shown,false)
        s.plate.forbidden=false;s.plate.shown=false;w:Update();eq(w.glow.shown,false)
        s.plate.shown=true;s.guids.softinteract=s.secret;s.guids.nameplate1=s.secret
        w:Update();eq(w.glow.shown,false)
        s.sameToken="nameplate1";w:Update();eq(w.glow.shown,true)
        s.secretCursor=true;w:Update();eq(w.glow.shown,false)
    end)
    test("场景高亮关闭恢复设置并保留外部改动，战斗结束再恢复",function()
        local B,s=fixture();local w=B.WorldInteract;w:Initialize()
        eq(s.vars.SoftTargetInteract,"3");eq(B.char.interactCVars.SoftTargetInteract.before,"0")
        s.vars.SoftTargetInteractRange="12";s.combat=true;B.settings.worldHighlight=false;w:Refresh()
        eq(w.glow.shown,false);eq(s.vars.SoftTargetInteract,"3")
        s.vars.nameplateGameObjectMaxDistance="60.000000"
        s.combat=false;w.events.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
        eq(s.vars.SoftTargetInteract,"0");eq(s.vars.nameplateGameObjectMaxDistance,"0")
        eq(s.vars.SoftTargetInteractRange,"12");eq(B.char.interactCVars,nil)
        B.settings.worldHighlight=true;w:Refresh();eq(w.glow.shown,true)
        B.char.paused=true;w:Refresh();eq(w.glow.shown,false);eq(s.vars.SoftTargetInteractRange,"12")
        B.char.paused=false;w:Refresh();s.combat=true
        w.events.scripts.OnEvent(nil,"PLAYER_REGEN_DISABLED");eq(w.glow.shown,false)
        w:Update();eq(w.glow.shown,false)
        s.combat=false;w.events.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED");eq(w.glow.shown,true)
    end)
    test("启用 Lueur 时让出场景高亮，缺少接口时安全停用",function()
        local B,s=fixture();s.lueur=true;local w=B.WorldInteract;w:Initialize()
        eq(w.glow.shown,false);eq(s.vars.SoftTargetInteract,"0")
        s.lueur=false;w:Refresh();eq(s.vars.SoftTargetInteract,"3")
        s.lueur=true;w.events.scripts.OnEvent(nil,"ADDON_LOADED","Lueur")
        eq(w.glow.shown,false);eq(s.vars.SoftTargetInteract,"0")
        B=fixture();C_NamePlate=nil;B.WorldInteract:Initialize();eq(B.WorldInteract.events,nil)
    end)
    test("战斗中退出保留恢复记录，下次加载可恢复原值",function()
        local B,s=fixture();local w=B.WorldInteract;w:Initialize();s.combat=true
        w.events.scripts.OnEvent(nil,"PLAYER_LOGOUT");assert(B.char.interactCVars);eq(w.glow.shown,false)
        s.combat=false;assert(loadfile("WorldInteract.lua"))("AiLeveling",B)
        B.WorldInteract:Initialize();eq(B.char.interactCVars.SoftTargetInteract.before,"0")
        B.WorldInteract.events.scripts.OnEvent(nil,"PLAYER_LOGOUT")
        eq(s.vars.SoftTargetInteract,"0");eq(B.char.interactCVars,nil)
        B.char.interactCVars="invalid";B.WorldInteract:Restore();eq(B.char.interactCVars,nil)
    end)
    for _,name in ipairs(names) do _G[name]=saved[name] end
end
