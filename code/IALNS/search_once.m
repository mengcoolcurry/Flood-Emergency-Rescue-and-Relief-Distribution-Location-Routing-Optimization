function solution=search_once()

global RESCUE;

%% 算法超参数
maxIter     = 400;      % 最大迭代次数
segment     = 50;       % 权重更新周期
rho         = 0.1;      % 权重更新系数
sigma1      = 33;       % s1
sigma2      = 9;        % s2
sigma3      = 13;       % s3
startWorse  = 0.05;     % 初始温度
coolingRate = 0.995;    % 降温速率
destroyFraction = 0.50; % 移除数量上限比例
minRemove   = 8;        % 每次最少移除的任务数
pWorst      = 10;       % 最差移除的随机化参数
pShaw       = 6;        % 相关性移除的随机化参数
eliteSize   = 5;        % 精英池容量
stagnation  = 40;       % 停滞代数
intensSteps = 3;        % 集中强化的最大步数
eliteGap    = 0.02;     
gapIter     = 80;      

%% 搜索过程
RESCUE.destroyFraction = destroyFraction;
RESCUE.minRemove = minRemove; RESCUE.pWorst = pWorst; RESCUE.pShaw = pShaw;

% 算子定义
destroyOps = {@delete_Operator_a, @delete_Operator_b, @delete_Operator_c};
%              a.随机移除          b.最差移除          c.相关性移除
insertOps  = {@Insertion_Operator_a, @Insertion_Operator_b, @Insertion_Operator_c};
%              a.贪心插入          b.随机插入              c.后悔值插入
numDestroy = numel(destroyOps);
numInsert  = numel(insertOps);

% 所有算子权重
destroyWeights = ones(1, numDestroy);
destroyScores  = zeros(1, numDestroy);
destroyUsage   = zeros(1, numDestroy);
insertWeights  = ones(1, numInsert);
insertScores   = zeros(1, numInsert);
insertUsage    = zeros(1, numInsert);

%% 初始解生成
currentSolution = rescue_routes('initial',1);
[currentCost,~,~,~,~,~,~] = CalTime(currentSolution);
bestSolution = currentSolution;
bestCost = currentCost;
T0 = -startWorse*currentCost/log(0.5);  % 基准温度初值标定
visited = containers.Map('KeyType','char','ValueType','logical');
key = solution_key(currentSolution);
visited(key) = true;
elite = struct('sol',{{currentSolution}},'cost',currentCost,'key',{{key}});
rescue_runtime('record',0,bestCost/60); 

%% IALNS主循环
iter = 0; adaptiveIter = 0; noImprove = 0;
while iter < maxIter
    iter = iter + 1; adaptiveIter = adaptiveIter + 1;

    
    dIdx = rouletteWheel(destroyWeights);
    iIdx = rouletteWheel(insertWeights);
    destroyUsage(dIdx) = destroyUsage(dIdx) + 1;
    insertUsage(iIdx)  = insertUsage(iIdx) + 1;

    % 破坏与修复
    [newRoute,delete_route] = destroyOps{dIdx}(currentSolution);
    newRoute = insertOps{iIdx}(newRoute,delete_route);
    newSolution = rescue_routes('repair',newRoute);
    [newCost,~,~,~,~,~,~] = CalTime(newSolution);

    % 模拟退火接受准则与三级评分
    T = max(T0*(1+cos(iter*pi/gapIter)), eps);   % 余弦回温
    key = solution_key(newSolution);
    isNew = ~isKey(visited,key);
    score = 0; improvedBest = false;
    if newCost < bestCost                      
        currentSolution = newSolution; currentCost = newCost;
        bestSolution = newSolution; bestCost = newCost;
        score = sigma1; improvedBest = true;
    elseif newCost < currentCost                  % 优于当前解
        currentSolution = newSolution; currentCost = newCost;
        if isNew, score = sigma2; end
    elseif rand < exp(-(newCost-currentCost)/T)   
        currentSolution = newSolution; currentCost = newCost;
        if isNew, score = sigma3; end
    end
    if isequal(currentSolution,newSolution)
        visited(key) = true;
        elite = update_elite(elite,newSolution,newCost,key,eliteSize);
    end
    destroyScores(dIdx) = destroyScores(dIdx) + score;
    insertScores(iIdx)  = insertScores(iIdx) + score;

    
    if mod(adaptiveIter, segment) == 0
        used = destroyUsage > 0;
        destroyWeights(used) = (1-rho)*destroyWeights(used) ...
                             + rho*destroyScores(used)./destroyUsage(used);
        used = insertUsage > 0;
        insertWeights(used) = (1-rho)*insertWeights(used) ...
                            + rho*insertScores(used)./insertUsage(used);
        destroyScores(:) = 0; destroyUsage(:) = 0;
        insertScores(:)  = 0; insertUsage(:)  = 0;
    end

    T0 = T0 * coolingRate;                   
    rescue_runtime('record',iter,bestCost/60);

   
    if improvedBest
        for step = 1:intensSteps
            if iter >= maxIter, break; end
            iter = iter + 1;
            [trial,removed] = delete_Operator_b(bestSolution);
            trial = Insertion_Operator_a(trial,removed);
            trial = rescue_routes('repair',trial);
            [trialCost,~,~,~,~,~,~] = CalTime(trial);
            accepted = trialCost < bestCost;
            if accepted
                bestSolution = trial; bestCost = trialCost;
                currentSolution = trial; currentCost = trialCost;
                key = solution_key(trial); visited(key) = true;
                elite = update_elite(elite,trial,trialCost,key,eliteSize);
            end
            T0 = T0 * coolingRate;
            rescue_runtime('record',iter,bestCost/60);
            if ~accepted, break; end
        end
    end

    
    if improvedBest, noImprove = 0; else, noImprove = noImprove + 1; end
    if noImprove >= stagnation
        cand = find(elite.cost <= bestCost*(1+eliteGap));
        k = cand(randi(numel(cand)));
        currentSolution = elite.sol{k}; currentCost = elite.cost(k);
        noImprove = 0;
    end
end

solution = bestSolution; % 只返回最好路线；
end

function elite = update_elite(elite,sol,cost,key,K)
if any(strcmp(elite.key,key)), return; end
if numel(elite.cost) < K
    elite.sol{end+1} = sol; elite.cost(end+1) = cost; elite.key{end+1} = key;
else
    [worst,k] = max(elite.cost);
    if cost < worst
        elite.sol{k} = sol; elite.cost(k) = cost; elite.key{k} = key;
    end
end
end

function key = solution_key(R)
key = strjoin(cellfun(@(r) sprintf('%d,',r), R, 'UniformOutput', false), '|');
end
