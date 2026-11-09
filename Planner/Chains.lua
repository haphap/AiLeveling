local _, A = ...
A.Chains = {}
local C=A.Chains
C.labels={all="全部",any="任一",alternative="可替代",next="后续关联",parent="父任务进行",opens="开始后开放",
    breadcrumb="指引",exclusive="互斥",closes="交付后关闭",disables="进行时禁接",unknown="其他关系"}
local forward={all=true,any=true,alternative=true,next=true,parent=true,opens=true,breadcrumb=true}
local function valid(id) return type(id)=="number" and id>0 and id<2147483648 and id%1==0 end

function C.NewIndex()
    return {outgoing={},incoming={},edges={},keys={},nodes={},descendants={}}
end

-- Return executable frontiers of viable prerequisite branches, without projecting completion.
function C.Preparation(id,data,state)
    local memo,visiting={},{}
    local visit
    local function merge(target,source) for key in pairs(source) do target[key]=true end end
    local function resolve(id,depth)
        local q=data:GetQuest(id)
        if not q or not A.Eligibility.Check(q,state,data,true) then return end
        if A.Eligibility.Check(q,state,data) then
            if data:Target(q,state) then return {[id]=true} end
            return
        end
        local result={}
        local function alternatives(ids)
            local leaves={}
            for _,candidate in ipairs(ids) do
                local branch=visit(candidate,depth+1)
                if branch then merge(leaves,branch) end
            end
            if not next(leaves) then return false end
            merge(result,leaves);return true
        end
        for _,required in ipairs(q.preQuestGroup or {}) do
            if not A.Eligibility.Prerequisite(required,state,data) then
                local choices={math.abs(required)}
                local parent=required>0 and data:GetQuest(required)
                for _,other in ipairs(parent and parent.exclusiveTo or {}) do choices[#choices+1]=other end
                if not alternatives(choices) then return end
            end
        end
        if q.preQuestSingle and #q.preQuestSingle>0 then
            local met=false
            for _,required in ipairs(q.preQuestSingle) do if state.completed[required] then met=true end end
            if not met and not alternatives(q.preQuestSingle) then return end
        end
        if (q.parentQuest or 0)>0 and not state.quests[q.parentQuest] and not alternatives({q.parentQuest}) then return end
        if (q.availableStartingWith or 0)>0 and not state.quests[q.availableStartingWith] and
            not state.completed[q.availableStartingWith] and not alternatives({q.availableStartingWith}) then return end
        if next(result) then return result end
    end
    visit=function(id,depth)
        if not valid(id) or depth>32 or visiting[id] then return end
        if memo[id]~=nil then return memo[id] or nil end
        visiting[id]=true
        local result=resolve(id,depth)
        visiting[id]=nil;memo[id]=result or false
        return result
    end
    local ids={}
    for candidate in pairs(visit(id,0) or {}) do ids[#ids+1]=candidate end
    table.sort(ids);return ids
end

function C.IndexQuest(index,q,data)
    if not q then return end
    index.nodes[q.id]=true
    local function add(from,to,kind,exact,group)
        if not valid(from) or not valid(to) then return end
        if kind=="exclusive" and from>to then from,to=to,from end
        local key=table.concat({from,to,kind,tostring(exact),group or ""},":")
        if index.keys[key] then return end
        local edge={from=from,to=to,kind=kind,exact=exact,group=group,key=key}
        index.keys[key]=true;index.edges[#index.edges+1]=edge
        index.nodes[from],index.nodes[to]=true,true
        index.outgoing[from]=index.outgoing[from] or {};index.incoming[to]=index.incoming[to] or {}
        index.outgoing[from][#index.outgoing[from]+1]=edge;index.incoming[to][#index.incoming[to]+1]=edge
    end
    for _,id in ipairs(q.preQuestGroup or {}) do
        if type(id)=="number" then
            add(math.abs(id),q.id,"all",id<0)
            if id>0 then
                local required=data:GetQuest(id)
                for _,alternative in ipairs(required and required.exclusiveTo or {}) do add(alternative,q.id,"alternative",false,id) end
            end
        end
    end
    for _,id in ipairs(q.preQuestSingle or {}) do
        if type(id)=="number" then add(math.abs(id),q.id,id>0 and "any" or "unknown",id<0) end
    end
    add(q.parentQuest,q.id,"parent");add(q.availableStartingWith,q.id,"opens")
    add(q.id,q.nextQuestInChain,"next");add(q.id,q.breadcrumbForQuestId,"breadcrumb")
    add(q.availableUntilCompleted,q.id,"closes");add(q.disabledByQuest,q.id,"disables")
    for _,id in ipairs(q.exclusiveTo or {}) do add(q.id,id,"exclusive") end
end

function C.Descendants(root,index)
    if index.descendants[root] then return index.descendants[root] end
    local ids,seen,head={root},{[root]=true},1
    while head<=#ids do
        local id=ids[head];head=head+1
        for _,edge in ipairs(index.outgoing[id] or {}) do
            if forward[edge.kind] and not seen[edge.to] then seen[edge.to]=true;ids[#ids+1]=edge.to end
        end
    end
    table.sort(ids)
    local result={ids=ids,members=seen}
    index.descendants[root]=result
    return result
end

function C:Snapshot(state)
    local roots={}
    for id,value in pairs(A.char.deferredChains or {}) do if value and valid(id) then roots[#roots+1]=id end end
    table.sort(roots)
    local key=table.concat(roots,":")
    local index=A.Data.chainIndex
    if index~=self.deferredIndex or key~=self.deferredKey then
        self.deferredMap={}
        if index then
            for _,root in ipairs(roots) do
                for _,id in ipairs(C.Descendants(root,index).ids) do self.deferredMap[id]=self.deferredMap[id] or root end
            end
        end
        self.deferredIndex,self.deferredKey=index,key
    end
    state.chainDeferred=self.deferredMap or {}
    return "chains:"..key
end

function C.Preview(id,data,state)
    if not valid(id) then return nil,"请输入有效任务 ID" end
    if not data.chainIndex then return nil,"任务关系索引正在建立" end
    if not data.chainIndex.nodes[id] then return nil,"当前数据中没有此任务或关联" end
    local list={}
    for _,questId in ipairs(C.Descendants(id,data.chainIndex).ids) do list[#list+1]=questId end
    return {root=id,ids=list,revision=state.revision,index=data.chainIndex}
end

function C:Defer(preview)
    if type(preview)~="table" or not valid(preview.root) or type(preview.ids)~="table" or not A.ready or not A.Data.chainIndex or preview.index~=A.Data.chainIndex or
        preview.revision~=A.state.revision or A.refreshAt then return false,"任务状态已变化，请重新查看暂缓范围" end
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先结束当前副本行程，再暂缓整链" end
    local actual=C.Descendants(preview.root,A.Data.chainIndex)
    if #actual.ids~=#preview.ids then return false,"暂缓范围已变化，请重新查看" end
    for i,id in ipairs(actual.ids) do if id~=preview.ids[i] then return false,"暂缓范围已变化，请重新查看" end end
    A.char.deferredChains=A.char.deferredChains or {}
    A.char.deferredChains[preview.root]=true
    local selected=A.char.itinerary
    local clear=A.char.locked and actual.members[A.char.locked]
    for _,group in ipairs(selected and A.Selection.Parse(selected.sequence) or {}) do
        for _,id in ipairs(group) do if actual.members[id] then clear=true end end
    end
    if clear then A.Selection:Clear() end
    local source=(A.Content.gearSources or {})[A.char.gearTarget]
    if source and source.questId and actual.members[source.questId] then A.char.gearTarget,A.char.gearBaseline=nil,nil end
    A.State:Refresh(true)
    return true
end

function C:Restore(id)
    if not A.char.deferredChains or not A.char.deferredChains[id] then return false,"此任务没有独立的整链暂缓记录" end
    A.char.deferredChains[id]=nil
    if A.ready then A.State:Refresh(true) end
    return true
end

function C.Related(id,index)
    local related,seen={},{}
    for _,group in ipairs({index.incoming[id] or {},index.outgoing[id] or {}}) do
        for _,edge in ipairs(group) do
            if not seen[edge.key] then
                related[#related+1]={id=edge.from==id and edge.to or edge.from,edge=edge,incoming=edge.to==id}
                seen[edge.key]=true
            end
        end
    end
    table.sort(related,function(a,b)
        if a.id~=b.id then return a.id<b.id end
        return a.edge.key<b.edge.key
    end)
    return related
end

function C.Label(edge)
    return edge.kind=="all" and edge.exact and "全部·精确交付" or C.labels[edge.kind] or edge.kind
end

function C.Graph(id,data,state,limit)
    limit=math.min(40,math.max(1,limit or 40))
    local index=data.chainIndex or C.NewIndex()
    local graph={nodes={},edges={},byId={},related=C.Related(id,index),width=536,height=190}
    local queue,head={{id=id,rank=0}},1
    graph.byId[id]=queue[1]
    while head<=#queue do
        local node=queue[head];head=head+1
        for _,entry in ipairs(C.Related(node.id,index)) do
            if not graph.byId[entry.id] then
                if #queue<limit then
                    local rank=node.rank+(entry.edge.kind=="exclusive" and 0 or entry.incoming and -1 or 1)
                    local nextNode={id=entry.id,rank=rank}
                    graph.byId[entry.id]=nextNode;queue[#queue+1]=nextNode
                else graph.truncated=true end
            end
        end
    end
    local minRank,maxRank=0,0
    for _,node in ipairs(queue) do minRank=math.min(minRank,node.rank);maxRank=math.max(maxRank,node.rank) end
    table.sort(queue,function(a,b) return a.rank==b.rank and a.id<b.id or a.rank<b.rank end)
    local rows={}
    for _,node in ipairs(queue) do
        rows[node.rank]=(rows[node.rank] or 0)+1
        node.x,node.y=12+(node.rank-minRank)*204,12+(rows[node.rank]-1)*84
        local q=data:GetQuest(node.id)
        node.title=q and q.title or ("任务 #"..node.id.."（资料缺失）")
        node.status=q and A.State.Status(state,node.id) or "missing"
        node.eligible,node.reason=false,"任务资料缺失"
        if q then node.eligible,node.reason=A.Eligibility.Check(q,state,data) end
        node.skipped=state.skipped and state.skipped[node.id]
        node.deferredRoot=state.chainDeferred and state.chainDeferred[node.id]
        graph.nodes[#graph.nodes+1]=node
        graph.height=math.max(graph.height,node.y+76)
    end
    graph.width=math.max(536,(maxRank-minRank+1)*204+96)
    local seen={}
    for _,node in ipairs(queue) do
        for _,edge in ipairs(index.outgoing[node.id] or {}) do
            if graph.byId[edge.to] and not seen[edge.key] then
                seen[edge.key]=true
                if #graph.edges<120 then graph.edges[#graph.edges+1]=edge else graph.edgesTruncated=true end
            end
        end
    end
    local visiting,visited={},{}
    local function visit(questId)
        if visiting[questId] then graph.cycle=true;return end
        if visited[questId] then return end
        visiting[questId]=true
        for _,edge in ipairs(index.outgoing[questId] or {}) do
            if forward[edge.kind] and graph.byId[edge.to] then visit(edge.to) end
        end
        visiting[questId],visited[questId]=nil,true
    end
    for _,node in ipairs(queue) do visit(node.id) end
    return graph
end

-- Data stays quest-ID based. Layout positions never define prerequisite semantics.
function A.Chains.Explain(id, data, state)
    local nodes, visiting, visited, cycles = {}, {}, {}, {}
    local function visit(questId, depth)
        if visiting[questId] then cycles[#cycles + 1] = questId; return end
        if visited[questId] then return end
        local q = data:GetQuest(questId)
        if not q then nodes[#nodes + 1] = {id = questId, status = "missing", depth = depth};visited[questId]=true; return end
        visiting[questId] = true
        for _, required in ipairs(q.preQuestGroup or {}) do if required ~= 0 then visit(math.abs(required), depth + 1) end end
        for _, required in ipairs(q.preQuestSingle or {}) do if required > 0 then visit(required, depth + 1) end end
        local eligible, reason = A.Eligibility.Check(q, state, data)
        nodes[#nodes + 1] = { id = questId, title = q.title, depth = depth,
            status = A.State.Status(state, questId), eligible = eligible, reason = reason,
            all = q.preQuestGroup, any = q.preQuestSingle, exclusive = q.exclusiveTo }
        visiting[questId], visited[questId] = nil, true
    end
    visit(id, 0)
    return nodes, cycles
end
