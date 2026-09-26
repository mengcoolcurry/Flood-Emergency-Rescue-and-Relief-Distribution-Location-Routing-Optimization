function newpop=lowOperator(pop,action)
% 邻域算子
global V_num;
pop=rescue_strip(pop);
lens=cellfun(@numel,pop(1:V_num));
if (action<=2 && ~any(lens>=2)) || (action==3 && sum(lens>0)<2) ...
        || (action==4 && (~any(lens>0) || V_num<2))
 newpop=rescue_repair(pop); return;
end
    if action == 1
        %线路内2-opt,任选一条路径间的两个节点，将节点间逆向排序
        v = randi([1,V_num ]);
        route = pop{1,v};
        while size(route(:),1) < 2
            v = randi([1,V_num ]);
            route = pop{1,v};
        end
        a = randi([1,size(route(:),1)]);
        b = randi([1,size(route(:),1)]);
        if a>b
            route1_ab = route(b:a);
            route1_ab = fliplr(route1_ab);
            route(b:a) = route1_ab;
        else
            route1_ab = route(a:b);
            route1_ab = fliplr(route1_ab);
            route(a:b) = route1_ab;
        end
        pop{1,v} = route;
    elseif action == 2
        %单点交换，任选一条路径间的两点进行交换
        v = randi([1,V_num]);
        route = pop{1,v};
        while size(route(:),1) < 2
            v = randi([1,V_num]);
            route = pop{1,v};
        end
        a = randi([1,size(route(:),1)]);
        b = randi([1,size(route(:),1)]);
        r_a = route(a);
        r_b = route(b);
        route(a) = r_b;
        route(b) = r_a;
        pop{1,v} = route;
    elseif action == 3
        %线路间单点交换
        v1 = randi([1,V_num ]);
        v2 = randi([1,V_num ]);
        while v2 == v1
            v2 = randi([1,V_num ]);
        end
        route1 = pop{1,v1};
        route2 = pop{1,v2};
        while size(route1(:),1) == 0 || size(route2(:),1) == 0
            v1 = randi([1,V_num ]);
            v2 = randi([1,V_num ]);
            while v2 == v1
                v2 = randi([1,V_num ]);
            end
            route1 = pop{1,v1};
            route2 = pop{1,v2};
        end
        a = randi([1,size(route1(:),1)]);
        b = randi([1,size(route2(:),1)]);
        r1 = route1(a);
        r2 = route2(b);
        route1(a) = r2;
        route2(b) = r1;
        pop{1,v1} = route1;
        pop{1,v2} = route2;
    elseif action == 4
        %线路间or-opt，把一条路径的连续片段整体搬到另一条路径
        src = find(lens>0);
        v1 = src(randi(numel(src)));
        dst = setdiff(1:V_num,v1);
        v2 = dst(randi(numel(dst)));
        route1 = pop{1,v1};
        route2 = pop{1,v2};
        a = randi([1,numel(route1)]);
        b = randi([a,numel(route1)]);
        seg = route1(a:b);
        route1(a:b) = [];
        c = randi([0,numel(route2)]);   %c=0表示插到队首
        route2 = [route2(1:c),seg,route2(c+1:end)];
        pop{1,v1} = route1;
        pop{1,v2} = route2;
    end
    newpop = rescue_repair(pop);
end


