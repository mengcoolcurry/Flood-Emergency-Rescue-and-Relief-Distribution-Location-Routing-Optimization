function [newRoute,delete_route] = delete_Operator_c(InitialRoute)
% 相关性移除算子
    global V_num dij_v RESCUE;
    pShaw = RESCUE.pShaw;   % 随机化参数p
    delete_route = [];
    InitialRoute = rescue_strip(InitialRoute);
    rest = [InitialRoute{1:V_num}];
    total = numel(rest);
    if total < 1, newRoute = InitialRoute; return; end
    % 移除数量
    n = removal_count(total);
    k = randi(total);
    delete_route(end+1) = rest(k);
    rest(k) = [];
    while numel(delete_route) < n
        ref = delete_route(randi(numel(delete_route)));
        [~,L] = sort(dij_v(ref,rest),'ascend');
        k = L(floor(rand^pShaw*numel(L))+1);
        delete_route(end+1) = rest(k);
        rest(k) = [];
    end
    for v2 = 1:V_num
        InitialRoute{v2} = InitialRoute{v2}(~ismember(InitialRoute{v2},delete_route));
    end
    newRoute = InitialRoute;
end
