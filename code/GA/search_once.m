function solution=search_once()

global V_num;

%% 算法超参数
maxGen = 400;           % 代数
popsize = 100;          % 种群规模
nc = 90;                % 子代规模
mu = 0.2;               % 变异率
k_tour = 3;             % 锦标赛规模

%% 初始解生成
empty.value = [];
empty.obj = [];
pop = repmat(empty, popsize, 1);
for p=1:1:popsize
    initialRoute = rescue_routes('initial',1);
    pop(p).value = initialRoute;
    [pop(p).obj,~,~,~,~,~,~]  = CalTime(pop(p).value);
end
[~,bestIndex]=min([pop.obj]);
bestRoute=pop(bestIndex).value;
rescue_runtime('record',0,pop(bestIndex).obj/60);

%% GA主循环
for p = 1:1:maxGen
    popc = repmat(empty, nc+mod(nc,2) ,1);
    % 交叉
    for i = 1:2:nc
        p1 = pop(tournament_select(pop,k_tour));
        p2 = pop(tournament_select(pop,k_tour));
        popc(i).value = p1.value;
        popc(i+1).value = p2.value;
        [popc(i).value, popc(i+1).value] = crossover(p1.value,p2.value);
        popc(i).value = rescue_routes('repair',popc(i).value);
        popc(i+1).value = rescue_routes('repair',popc(i+1).value);
    end
    % 变异
    for i = 1:1:numel(popc)
        if rand <= mu
            popc(i).value = lowOperator(popc(i).value,randi([1,4]));
        end
        [popc(i).obj,~,~,~,~,~,~] = CalTime(popc(i).value);
    end
    % 父子合并后保留最优
    newpop = [pop; popc];
    [~, CDSO] = sort([newpop.obj] );
    pop = newpop(CDSO);
    pop = pop(1:popsize);
    bestRoute = pop(1).value;
    rescue_runtime('record',p,pop(1).obj/60);

end
solution = bestRoute; % 只返回最好路线；
end

function idx = tournament_select(pop,k)
% 锦标赛选择
cand = randi(numel(pop),1,k);
[~,b] = min([pop(cand).obj]);
idx = cand(b);
end
