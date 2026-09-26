function [newroute_v1,newroute_v2] = crossover(route_v1,route_v2)
% 交叉算子
    global V_num;
    route_v1=rescue_strip(route_v1); route_v2=rescue_strip(route_v2);
    for v = 1:1:V_num
        len1(v) = size(route_v1{1,v},2);
        len2(v) = size(route_v2{1,v},2);
    end

    crossroute1 = [];
    crossroute2 = [];
    for v = 1:1:V_num
        for i =1:1:len1(v)
            crossroute1(end+1) = route_v1{1,v}(1,i);
        end
        for i =1:1:len2(v)    
            crossroute2(end+1) = route_v2{1,v}(1,i);
        end
    end
    if numel(crossroute1)<2, newroute_v1=route_v1; newroute_v2=route_v2; return; end
    % 两父代任务数不同时不交叉
    if numel(crossroute1)~=numel(crossroute2), newroute_v1=route_v1; newroute_v2=route_v2; return; end
    a = randi(size(crossroute1,2));%随机选交叉点
    b = randi(size(crossroute2,2));%随机选交叉点
    while a == b
        b = randi(size(crossroute2,2)); %保证选的点不重复
    end
    if a > b
        c = a;
        a = b;
        b = c;
    end
    crossroute1_ab = crossroute1(a:b);
    crossroute2_ab = crossroute2(a:b);
  
    new_crossroute1 = [crossroute2_ab,crossroute1];
    new_crossroute2 = [crossroute1_ab,crossroute2];
    
    % 去重保留首次出现
    new_crossroute1 = unique(new_crossroute1,'stable');
    new_crossroute2 = unique(new_crossroute2,'stable');
    startIndex1 = 1;
    startIndex2 = 1;
    for v = 1:V_num
        endIndex1 = startIndex1 + len1(v) - 1;
        endIndex2 = startIndex2 + len2(v) - 1;
        newroute1{v} = new_crossroute1(startIndex1:endIndex1);
        newroute2{v} = new_crossroute2(startIndex2:endIndex2);
        startIndex1 = endIndex1 + 1;
        startIndex2 = endIndex2 + 1;
    end
    newroute_v1 = newroute1;
    newroute_v2 = newroute2;
    newroute_v1{V_num+1} = [];
    newroute_v2{V_num+1} = [];
end

