function [newRoute] = Insertion_Operator_b(InitialRoute,delete_route)
% 随机插入
global V_num
    for i = 1:1:size(delete_route,2)
        randV = randi([1,V_num]);
        route = InitialRoute{1,randV};
        pos = randi([0,numel(route)]);
        route = [route(1:pos),delete_route(i),route(pos+1:end)];
        InitialRoute{1,randV} = route;
    end
    newRoute = InitialRoute;
    newRoute = adjust2(newRoute);
    newRoute = adjust(newRoute);
    newRoute{V_num+1} = [];
end
