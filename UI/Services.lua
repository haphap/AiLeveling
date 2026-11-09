local _,A=...
A.UI.Services={kind="bind",index=1}
local U=A.UI.Services
local labels={bind="旅店／设置炉石",train="训练师位置",learn="当前训练项目",unlockFlight="开通飞行点"}
function U:Create(parent)
    self.frame=CreateFrame("Frame",nil,parent);self.frame:SetPoint("TOPLEFT",18,-94);self.frame:SetSize(570,72)
    self.mode=A.UI:Button(self.frame,"切换服务",150,function()
        self.kind=({bind="train",train="learn",learn="unlockFlight",unlockFlight="bind"})[self.kind];self.index=1;self.message=nil;A.UI:SelectTab(7)
    end);self.mode:SetPoint("TOPLEFT")
    self.previous=A.UI:Button(self.frame,"上一项",84,function() self:Move(-1) end);self.previous:SetPoint("TOPLEFT",160,0)
    self.label=A.UI:Text(self.frame,12);self.label:SetPoint("TOPLEFT",252,-6);self.label:SetWidth(214)
    self.next=A.UI:Button(self.frame,"下一项",84,function() self:Move(1) end);self.next:SetPoint("TOPLEFT",478,0)
    self.choose=A.UI:Button(self.frame,"安排此服务",268,function()
        local ok,why=A.Services:Pick(self.preview,self.revision)
        self.message=ok and "已安排服务。" or why;A.UI:SelectTab(7)
    end);self.choose:SetPoint("TOPLEFT",0,-36)
    self.cancel=A.UI:Button(self.frame,"取消服务，继续原任务",282,function() A.Services:Cancel();A.UI:SelectTab(7) end)
    self.cancel:SetPoint("TOPLEFT",280,-36);self.frame:Hide()
end
function U:Move(delta)
    local count=#(self.rows or {});if count>0 then self.index=(self.index-1+delta)%count+1 end
    self.message=nil;A.UI.scroll:SetVerticalScroll(0);A.UI:SelectTab(7)
end
function U:Refresh()
    self.rows=A.Services:Choices(self.kind);self.index=math.max(1,math.min(self.index,#self.rows))
    self.preview,self.revision=self.rows[self.index],A.state.revision
    self.mode.text:SetText(labels[self.kind]);self.label:SetText(string.format("%d / %d",#self.rows>0 and self.index or 0,#self.rows))
    self.previous:SetEnabled(#self.rows>1);self.next:SetEnabled(#self.rows>1)
    local ok,why=A.Services:CanPick(self.preview,self.revision);self.choose:SetEnabled(ok==true);self.blocked=not ok and why or nil
    self.choose.text:SetText(self.kind=="learn" and "安排学习此项后继续" or "安排此服务")
    self.cancel:SetEnabled(A.ready==true and (A.char.serviceStop~=nil or A.Services.CurrentAutomatic()~=nil))
end
function U:Lines()
    local s,row=A.state,self.preview
    local lines={"当前炉石绑定："..(s.bindName or "尚未读取")}
    if A.char.serviceStop then lines[#lines+1]="已安排："..A.char.serviceStop.title.." · "..labels[A.char.serviceStop.kind] end
    local automatic=A.Services.CurrentAutomatic()
    if automatic then lines[#lines+1]="当前建议："..automatic.title.." · 设置炉石" end
    local plan=A.plan
    if plan and plan.revision==s.revision and not A.refreshAt and not (A.jobs and A.jobs.plan) and plan.serviceDeferred then lines[#lines+1]=plan.serviceDeferred end
    if A.char.serviceStop and A.char.serviceStop.afterTask then lines[#lines+1]="完成「"..A.char.serviceStop.afterTask.title.."」后前往。" end
    if self.message or A.Services.message then lines[#lines+1]=self.message or A.Services.message end
    if self.blocked then lines[#lines+1]=self.blocked end
    if not row then
        lines[#lines+1]=self.kind=="learn" and "与训练师交谈，选择要学习的项目。" or "附近暂无此类服务点。"
        return lines
    end
    lines[#lines+1]=row.title..(row.description and (" · "..row.description) or "")
    if row.trainingText then lines[#lines+1]=row.trainingText end
    local p=row.position;local map=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(p.map)
    lines[#lines+1]=string.format("%s · %.1f, %.1f",map and map.name or ("地图 #"..p.map),p.x*100,p.y*100)
    if row.distance then lines[#lines+1]=string.format("当前位置距离约 %.0f 码",row.distance) end
    if row.resumeTitle then lines[#lines+1]="服务后继续："..row.resumeTitle end
    if row.bindingHub and row.bindingHub.deliveryCount>0 then
        lines[#lines+1]="有 "..row.bindingHub.deliveryCount.." 个已接任务完成后可在附近交付。"
        if row.bindingHub.acceptCount>0 then lines[#lines+1]="附近还有 "..row.bindingHub.acceptCount.." 个可接任务。" end
        lines[#lines+1]="经过这里时再设置炉石。"
    end
    if row.unlockSaving then
        if row.unlockSaving>1 then
            lines[#lines+1]=row.unlockAfterTask and ("可先完成「"..row.unlockAfterTask.title.."」，再来开通飞行点，方便后续任务。") or
                "可考虑先开通此飞行点，方便后续任务。"
        else lines[#lines+1]="当前任务行程无需专程绕路开通此点。" end
    end
    if row.offer then
        local offer=row.offer
        lines[#lines+1]=offer.name..(offer.sub and (" · "..offer.sub) or "").." · "..({available="可学习",unavailable="条件未满足",used="已学会"})[offer.status]
        if offer.level and offer.level>0 then lines[#lines+1]="要求等级："..offer.level end
        for _,req in ipairs(offer.requirements or {}) do
            local status=req.met==true and "已满足" or req.met==false and "未满足" or "待确认"
            lines[#lines+1]="需要："..req.name..(req.rank and (" "..req.rank) or "").." · "..status
        end
        if offer.requirementsPending then lines[#lines+1]="在训练窗口查看学习条件。" end
        if offer.ambiguous then lines[#lines+1]="在训练窗口选择具体项目。" end
        lines[#lines+1]="学习所选技能后继续任务。"
    elseif self.kind=="unlockFlight" then lines[#lines+1]="与飞行管理员交谈，开通此飞行点。"
    elseif self.kind=="train" then lines[#lines+1]="与训练师交谈，选择要学习的项目。"
    else lines[#lines+1]="与旅店老板交谈，设置炉石。" end
    return lines
end
