function solution=search_once()

global V_num;

%% 算法超参数
T0 = 100 ;  % 初始温度
Ts = 1 ;    % 最终温度
iter = 400; % 迭代次数
LK = 100;   % 内循环次数
r = round((Ts/T0)^(1/iter),3) ; % 降温速率
T = T0;

%% 初始解生成
pop.value = rescue_routes('initial',1);
[pop.obj,~,~,~,~,~,~] = CalTime(pop.value);
bestObj = pop.obj;
rescue_runtime('record',0,bestObj/60);
bestRoute=pop.value;

%% SAA主循环
for it = 1:1:iter
    for i = 1:1:LK
        a = randi([1,4]);
        newpopvalue = lowOperator(pop.value,a);
        [newpopobj ,~,~,~,~,~,~] = CalTime(newpopvalue);
        % Metropolis接受准则
        if newpopobj < pop.obj
            pop.value = newpopvalue;
            pop.obj = newpopobj;
        else
            p = exp(-(newpopobj-pop.obj)/T);
            if rand(1) < p
                pop.value = newpopvalue;
                pop.obj = newpopobj;
            end
        end
        if pop.obj < bestObj
            bestObj = pop.obj;
            bestRoute = pop.value;
        end
    end
    T = r*T;
    rescue_runtime('record',it,bestObj/60);

end
solution=bestRoute; % 只返回最好路线；
end
