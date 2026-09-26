function [newRoute,delete_route] = delete_Operator_a(InitialRoute)
% 随机移除算子
    global V_num RESCUE;
    delete_route = [];
    InitialRoute=rescue_strip(InitialRoute);
    total=sum(cellfun(@numel,InitialRoute(1:V_num)));
    n=removal_count(total);
    for i = 1:n
        v = randi([1,V_num]);
        route = InitialRoute{1,v};
        while size(route,2) == 0
            v = randi([1,V_num]);
            route = InitialRoute{1,v};
        end
        m = randi([1,size(route,2)]);
        delete_route(end+1) = InitialRoute{1,v}(m);
        InitialRoute{1,v}(m) = [];
    end
    newRoute = InitialRoute;
end