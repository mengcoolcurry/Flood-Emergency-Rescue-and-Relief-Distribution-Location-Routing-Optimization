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
destroyFraction = 0.40; % 移除数量上限比例
minRemove   = 4;        % 每次最少移除的任务数
pWorst      = 3;        % 最差移除的随机化参数
pShaw       = 6;        % 相关性移除的随机化参数

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
T = -startWorse*currentCost/log(0.5);   % 初始温度标定
visited = containers.Map('KeyType','char','ValueType','logical');
visited(solution_key(currentSolution)) = true;
rescue_runtime('record',0,bestCost/60);

%% ALNS主循环
for iter = 1:maxIter
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
    key = solution_key(newSolution);
    isNew = ~isKey(visited,key);
    score = 0;
    if newCost < bestCost
        currentSolution = newSolution; currentCost = newCost;
        bestSolution = newSolution; bestCost = newCost;
        score = sigma1;
    elseif newCost < currentCost                  % 优于当前解
        currentSolution = newSolution; currentCost = newCost;
        if isNew, score = sigma2; end
    elseif rand < exp(-(newCost-currentCost)/T)
        currentSolution = newSolution; currentCost = newCost;
        if isNew, score = sigma3; end
    end
    if isequal(currentSolution,newSolution), visited(key) = true; end
    destroyScores(dIdx) = destroyScores(dIdx) + score;
    insertScores(iIdx)  = insertScores(iIdx) + score;

    if mod(iter, segment) == 0
        used = destroyUsage > 0;
        destroyWeights(used) = (1-rho)*destroyWeights(used) ...
                             + rho*destroyScores(used)./destroyUsage(used);
        used = insertUsage > 0;
        insertWeights(used) = (1-rho)*insertWeights(used) ...
                            + rho*insertScores(used)./insertUsage(used);
        destroyScores(:) = 0; destroyUsage(:) = 0;
        insertScores(:)  = 0; insertUsage(:)  = 0;
    end

    T = T * coolingRate;
    rescue_runtime('record',iter,bestCost/60);
end

solution = bestSolution; % 只返回最好路线；
end

function key = solution_key(R)
key = strjoin(cellfun(@(r) sprintf('%d,',r), R, 'UniformOutput', false), '|');
end
