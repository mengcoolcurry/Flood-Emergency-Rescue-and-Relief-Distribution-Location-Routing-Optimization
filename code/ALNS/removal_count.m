function n=removal_count(total)
% 破坏算子本次移除的任务数
global RESCUE;
hi=max(RESCUE.minRemove,ceil(total*RESCUE.destroyFraction));
lo=min(RESCUE.minRemove,hi);
n=min(randi([lo,hi]),total);
end
