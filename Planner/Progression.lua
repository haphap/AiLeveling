local _, A = ...
A.Progression = {}
local X = A.Progression

function X.Curve(state)
    local reference=A.Experience
    if not reference or state.clientVersion~=reference.version or
        state.interface~=reference.interface then return nil,"客户端版本未匹配参考经验表" end
    if not reference.xpToLevel[state.level] or reference.xpToLevel[state.level]~=state.maxXP then return nil,"原生当前经验门槛与参考表不符" end
    return reference.xpToLevel,reference.source
end

function X.Advance(state,reward)
    if state.level>=60 then return {level=60,xp=0,maxXP=0} end
    local result={level=state.level,xp=(state.xp or 0)+reward,maxXP=state.maxXP,uncertain=state.xpUncertain}
    local thresholds,source=X.Curve(state)
    result.curveSource=thresholds and source or nil
    thresholds=thresholds or {}
    if result.uncertain then result.reason="等级预测暂不可用";return result end
    while result.level<60 do
        local required=result.maxXP or thresholds[result.level]
        if not required or required<=0 then result.uncertain=true;result.reason="等级预测暂不可用";break end
        if result.xp<required then result.maxXP=required;break end
        result.xp,result.level=result.xp-required,result.level+1
        result.maxXP=thresholds[result.level]
        if result.level>=60 then result.xp,result.maxXP=0,0;break end
        if not result.maxXP and result.xp>0 then result.uncertain=true;result.reason="等级预测暂不可用";break end
        if not result.maxXP and result.xp==0 then break end
    end
    return result
end
