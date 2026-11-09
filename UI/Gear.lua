local _, A = ...
A.UI.Gear = {}
local UI=A.UI.Gear

function UI:Create(parent)
    local frame=CreateFrame("Frame",nil,parent)
    frame:SetPoint("TOPLEFT",18,-94);frame:SetSize(570,72)
    self.frame=frame
    self.selector=A.UI:Button(frame,"装备来源",560,function()
        local ids=self:Ids()
        for index,id in ipairs(ids) do if id==self.selected then self.selected=ids[index%#ids+1];break end end
        self.message=nil;A.UI:SelectTab(3)
    end)
    self.selector:SetPoint("TOPLEFT")
    self.choose=A.UI:Button(frame,"选择装备目标",170,function()
        local ok,reason=A.Gear:SetTarget(self.selected)
        self.message=not ok and reason or nil;A.UI:SelectTab(3)
    end)
    self.choose:SetPoint("TOPLEFT",0,-36)
    local clear=A.UI:Button(frame,"恢复升级目标",170,function()
        A.char.gearTarget,A.char.gearBaseline=nil,nil
        if A.ready then A.State:Refresh(true) end
        self.message=nil;A.UI:SelectTab(3)
    end)
    clear:SetPoint("TOPLEFT",180,-36)
    frame:Hide()
end

function UI:Ids()
    local ids,seen={},{}
    local function add(id) if not seen[id] then ids[#ids+1]=id;seen[id]=true end end
    for id in pairs(A.Content.gearSources) do add(id) end
    for _,choice in ipairs(A.plan and A.plan.taskChoices or {}) do
        for id in pairs(choice.gearSources or {}) do add(id) end
    end
    for id,source in pairs(A.Gear.DungeonSources(A.state)) do
        local value=A.Gear.Source(source,A.state,A.Content)
        if value and not value.owned and (value.upgrade.delta>0 or #(value.upgrade.notes or {})>0) then add(id) end
    end
    local target=A.char and A.char.gearTarget
    if target and A.Gear.GetSource(target) then add(target) end
    table.sort(ids,function(a,b) return tostring(a)<tostring(b) end)
    return ids
end

function UI:Lines()
    local lines={}
    local _,name=A.Gear.Model(A.state)
    lines[#lines+1]="装备比较："..(name or "选择职业与职责")
    local ids=self:Ids()
    local present=false;for _,id in ipairs(ids) do if id==self.selected then present=true;break end end
    if not present then self.selected=ids[1] end
    local source=self.selected and A.Gear.GetSource(self.selected)
    self.selector.text:SetText(source and ("当前来源："..(source.title or tostring(self.selected)).."（点击切换）") or "当前没有适用的装备来源")
    self.selector:SetEnabled(#ids>0)
    self.choose:SetEnabled(A.ready and source~=nil and (source.verified==true or source.reference==true))
    if source and A.ready then
        local value,reason=A.Gear.Source(source,A.state,A.Content)
        if value then
            local itemName=value.item.link or value.item.name or ("物品 #"..source.itemId)
            if source.reference and source.kind=="quest" then
                lines[#lines+1]=string.format("%s · 属性评分%s %+.1f",itemName,value.upgrade.delta>0 and "提升" or "变化",value.upgrade.delta)
                lines[#lines+1]=source.choice and "交付任务时选择此奖励。" or "交付任务后获得此奖励。"
            else
                lines[#lines+1]=string.format("%s\n属性评分变化 %+.1f；获得概率区间 %.0f%%—%.0f%%",itemName,
                    value.upgrade.delta,value.chanceLow*100,value.chanceHigh*100)
            end
            for _,note in ipairs(value.upgrade.notes) do lines[#lines+1]=note end
            if source.kind=="dungeon" and value.expectedAttemptsHigh then
                lines[#lines+1]=string.format("预计刷取：%.1f—%.1f 次",value.expectedAttemptsLow,value.expectedAttemptsHigh)
            end
            local route
            local fastest
            for _,candidate in ipairs(A.plan and A.plan.alternatives or {}) do
                if not candidate.requiresAcceptance and (not fastest or candidate.rate>fastest.rate) then fastest=candidate end
                if candidate.gearSources and candidate.gearSources[self.selected] and (not route or candidate.seconds<route.seconds) then route=candidate end
            end
            if source.reference and source.kind=="quest" then
                lines[#lines+1]="选择此装备目标后，继续对应任务及必要前置。"
            elseif source.reference and source.kind=="dungeon" then
                lines[#lines+1]="选择后前往"..source.title.."获取装备。"
            elseif route then
                lines[#lines+1]=string.format("来源行程 %.1f 分钟 · %.0f 经验／小时%s",route.seconds/60,route.rate*3600,
                    fastest and string.format("；较当前最高经验率方案多用 %+.1f 分钟",(route.seconds-fastest.seconds)/60) or "")
            else lines[#lines+1]="当前暂无可用的获取行程。" end
        else lines[#lines+1]=reason end
    end
    if self.message then lines[#lines+1]=self.message end
    lines[#lines+1]="背包中的属性提升与效果变化："
    local upgrades={}
    for _,item in ipairs(A.state.bagEquipment or {}) do
        local comparison=A.Gear.Upgrade(item,A.state)
        if comparison and (comparison.delta>0 or #(comparison.notes or {})>0) then upgrades[#upgrades+1]={item=item,comparison=comparison} end
    end
    table.sort(upgrades,function(a,b) return a.comparison.delta>b.comparison.delta end)
    for _,entry in ipairs(upgrades) do
        local c,item=entry.comparison,entry.item
        lines[#lines+1]=string.format("%s · 属性评分变化 %+.1f",item.link or item.name or ("#"..item.id),c.delta)
        for _,note in ipairs(c.notes) do lines[#lines+1]=note end
    end
    if #upgrades==0 then lines[#lines+1]="当前没有属性提升或效果变化的可用搭配。" end
    lines[#lines+1]="当前装备："
    for slot=1,19 do
        local item=A.state.equipment and A.state.equipment[slot]
        if item then
            local score=A.Gear.Score(item,A.state)
            lines[#lines+1]=(item.link or item.name or ("物品 #"..item.id))..(score and string.format(" · 评分 %.1f",score) or " · 属性加载中")
            local reference,skill=A.Gear.WeaponSkill(item,A.state)
            if reference and skill then
                lines[#lines+1]=string.format("  %s熟练度 %d/%d（有效 %d）",reference.name,skill.rank,skill.maxRank,
                    skill.rank+skill.modifier+skill.tempPoints)
            end
        end
    end
    return lines
end
