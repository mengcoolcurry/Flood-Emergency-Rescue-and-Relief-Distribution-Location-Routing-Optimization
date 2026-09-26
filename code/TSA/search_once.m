function solution=search_once()

global V_num;

%% 算法超参数
count = 400;        % 迭代次数
tabuLength = 10;    % 禁忌表长度
candidateNum = 100; % 每轮候选解个数

%% 初始解生成
tabuList = {};      % 禁忌表
candidatesList = cell(candidateNum,V_num+1); % 候选解集合
initialRoute = rescue_routes('initial',1);
[fitness,~,~,~,~,~,~]  = CalTime(initialRoute);
bestRoute = initialRoute;
bestValue = fitness;
rescue_runtime('record',0,bestValue/60);

%% TSA主循环
for p = 1:1:count
    % 产生邻域候选集
    for i = 1:1:candidateNum
        action = randi([1,4]);
        candidatesList(i,1:V_num+1) = lowOperator(initialRoute,action);
    end
    for i = 1:1:candidateNum
        candidatesFit(i) = CalTime(candidatesList(i,:));
    end
    % 选出非禁忌的最优候选；渴望准则
    bestIdx = 0; bestFit = inf; bestSig = '';
    for i = 1:1:candidateNum
        sig = route_signature(candidatesList(i,1:V_num+1));
        isTabu     = any(strcmp(tabuList,sig));
        aspiration = candidatesFit(i) < bestValue;
        if (~isTabu || aspiration) && candidatesFit(i) < bestFit
            bestFit = candidatesFit(i); bestIdx = i; bestSig = sig;
        end
    end
    if bestIdx == 0
        [bestFit,bestIdx] = min(candidatesFit);
        bestSig = route_signature(candidatesList(bestIdx,1:V_num+1));
    end
    % 移动并更新禁忌表
    initialRoute = candidatesList(bestIdx,1:V_num+1);
    tabuList{end+1} = bestSig;
    if numel(tabuList) > tabuLength
        tabuList(1) = [];
    end
    if bestFit < bestValue
        bestValue = bestFit;
        bestRoute = initialRoute;
    end
    rescue_runtime('record',p,bestValue/60);

end
solution = bestRoute; % 只返回最好路线；
end

function sig = route_signature(R)
global V_num;
parts = cell(1,V_num);
for v = 1:V_num
    parts{v} = sprintf('%d-',R{1,v});
end
sig = strjoin(parts,'|');
end
