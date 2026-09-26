%% 第1部分  参数设置
clear; clc; close all;
program_timer = tic;                                  

% 文件与输出
script_folder = fileparts(mfilename('fullpath'));      
if isempty(script_folder), script_folder = pwd; end    
data_folder = fullfile(script_folder, 'data', 'C101');        
file_node   = 'i_data.xlsx';                           
file_type   = 'nodetype.xlsx';                         
file_coord  = 'nodeij.xlsx';                           

% 数据表的读取方式与单位
coordinate_rows      = [];       
                                 
hangar_xy            = [50 45];  
distance_to_km       = 1;        
service_time_to_hour = 1/60;     % 服务时间换算为 h 的系数（分钟填 1/60，秒填 1/3600）
center_stock         = [];       % Q_b：各配送中心库存 (kg)
                                 

% 参数
V       = 2;      % 车辆数上限
Q_v     = 300;    % Q_v  
Q_vc    = 50;     % Q_vc 
Q_vh    = 100;    % Q_vh
QP_vc   = 5;      % QP_vc
QP_vh   = 5;      % QP_vh
sp_T    = 15;     % 车辆速度
sp_c    = 20;     % 冲锋舟速度
sp_h    = 60;     % 直升机速度
t_gc    = 0.1;    % t_gc 
t_gh    = 0.2;    % t_gh
t_ac    = 0.05;   % t_ac
t_dc    = 0.05;   % t_dc
t_dh    = 0.05;   % t_dh
kappa_h = 0;      

% 可达性与可选实测矩阵
a_c_input          = []; 
                          
road_allowed_input = []; 
road_time_input    = [];  
road_dev_input     = [];

% 鲁棒参数
model_mode     = 'nominal'; % robust/nominal
                            
Gamma          = 2;         
road_dev_ratio = 0.2;       

% CPLEX 求解参数
cplex_params = struct();
cplex_params.timelimit     = 3600;   
cplex_params.mipgap        = 0.001;  
cplex_params.absmipgap     = 1e-10;  
cplex_params.randomseed    = 1;      
cplex_params.threads       = 0;      
cplex_params.presolve      = 1;     
cplex_params.cuts          = 0;     
cplex_params.heuristicfreq = 0;     
cplex_params.symmetry      = -1;     
cplex_params.mipdisplay    = 2;     
tol = 1e-5;

%% 第2部分  读取 data 文件夹中的数据
yalmip('clear');                                                  

node_data  = readmatrix(fullfile(data_folder, file_node),  'Sheet', 1);   % 4 × N
node_type  = readmatrix(fullfile(data_folder, file_type),  'Sheet', 1);   % 1 × N
coord_data = readmatrix(fullfile(data_folder, file_coord), 'Sheet', 1);   % 每行一个坐标

N         = size(node_data, 2);                        % 节点总数
node_id   = node_data(1, :)';                          % 节点ID
row2      = node_data(2, :)';                          % 水域点待运人数；配送中心列是库存
c         = node_data(3, :)';                          % 物资需求
t_srv     = node_data(4, :)' * service_time_to_hour;   % 服务时间
node_type = node_type(:)';

if isempty(coordinate_rows), coordinate_rows = 1:N; end
assert(numel(coordinate_rows) == N && max(coordinate_rows) <= size(coord_data, 1), ...
    'nodeij.xlsx 的行数不足，或 coordinate_rows 没有给出 N 个行号。');
xy = coord_data(coordinate_rows, 1:2) * distance_to_km;       % N×2 节点坐标 (km)
assert(all(isfinite(xy(:))), '坐标中有空值或非数值。');
hangar_xy = hangar_xy * distance_to_km;                        % 机库坐标 (km)，只用于画图


%% 集合与模型参数
I1 = find(node_type == 1);    
I2 = find(node_type == 2);    
I3 = find(node_type == 3);    
I0 = find(node_type == 4);   
assert(~isempty(I1) && ~isempty(I0), '至少需要 1 个陆地救援点和 1 个配送中心。');

P = row2;  P(I0) = 0;          % P_q、P_m：水域点待运人数
Q_b = zeros(N, 1);             % Q_b：配送中心库存 (kg)
if isempty(center_stock)
    Q_b(I0) = row2(I0);
else
    Q_b(I0) = center_stock;
end

% 双向需求均为零的水域点预先删除
I2_in_data = I2;               
I2 = I2(c(I2) > 0 | P(I2) > 0);
I3 = I3(c(I3) > 0 | P(I3) > 0);
n  = numel(I1);              

isI0 = false(N, 1);  isI0(I0) = true;     
isI1 = false(N, 1);  isI1(I1) = true;     

Q_v   = per_vehicle(Q_v,   V, 'Q_v',   true);
Q_vc  = per_vehicle(Q_vc,  V, 'Q_vc',  true);
Q_vh  = per_vehicle(Q_vh,  V, 'Q_vh',  true);
QP_vc = per_vehicle(QP_vc, V, 'QP_vc', true);
QP_vh = per_vehicle(QP_vh, V, 'QP_vh', true);
sp_T  = per_vehicle(sp_T,  V, 'sp_T',  true);
sp_c  = per_vehicle(sp_c,  V, 'sp_c',  true);
sp_h  = per_vehicle(sp_h,  V, 'sp_h',  true);
t_gc  = per_vehicle(t_gc,  V, 't_gc',  false);
t_gh  = per_vehicle(t_gh,  V, 't_gh',  false);
t_ac  = per_vehicle(t_ac,  V, 't_ac',  false);
t_dc  = per_vehicle(t_dc,  V, 't_dc',  false);
t_dh  = per_vehicle(t_dh,  V, 't_dh',  false);
kappa_h        = per_vehicle(kappa_h,        V, 'kappa_h',        false);
road_dev_ratio = per_vehicle(road_dev_ratio, V, 'road_dev_ratio', false);

% d_ij、t̄_ijv、t̂_ijv
d = zeros(N, N);
for i = 1:N
    for j = 1:N
        d(i, j) = sqrt((xy(i, 1) - xy(j, 1))^2 + (xy(i, 2) - xy(j, 2))^2);   % 欧氏距离 (km)
    end
end
tbar = zeros(N, N, V);                     % t̄_ijv：道路名义时间
for v = 1:V
    tbar(:, :, v) = d / sp_T(v);
end
if ~isempty(road_time_input), tbar = to_3d(road_time_input, N, N, V, 'road_time_input'); end
that = zeros(N, N, V);                     % t̂_ijv：道路时间的非负偏差
for v = 1:V
    that(:, :, v) = road_dev_ratio(v) * tbar(:, :, v);
end
if ~isempty(road_dev_input), that = to_3d(road_dev_input, N, N, V, 'road_dev_input'); end

% 合法车辆弧集合
road_ok = true(N, N, V);
if ~isempty(road_allowed_input), road_ok = to_3d(road_allowed_input, N, N, V, 'road_allowed_input') > 0.5; end
A = false(N, N, V);                       
for v = 1:V
    for i = [I0, I1]
        for j = I1
            if i ~= j && road_ok(i, j, v)
                A(i, j, v) = true;
            end
        end
    end
end

% 直升机陆地站间转场时间
phi = zeros(N, N, V);
for v = 1:V
    for i = I1
        for j = I1
            if i ~= j
                phi(i, j, v) = d(i, j) / sp_h(v) + kappa_h(v);
            end
        end
    end
end

% 舟艇水路可达性
a_c = zeros(N, N, V);                     
if isempty(a_c_input)
    a_c(I1, I2_in_data, :) = 1;
else
    a_c(I1, I2_in_data, :) = to_3d(a_c_input, n, numel(I2_in_data), V, 'a_c_input');
end

% 陆地点—水域点单程时间
t_c = zeros(N, N, V);                      
t_h = zeros(N, N, V);                      
for v = 1:V
    for j = I1
        for q = I2
            t_c(j, q, v) = d(j, q) / sp_c(v);
        end
        for m = I3
            t_h(j, m, v) = d(j, m) / sp_h(v);
        end
    end
end

% 往返趟数
R_c = zeros(N, V);                        
R_h = zeros(N, V);                       
for v = 1:V
    for q = I2
        R_c(q, v) = max(ceil(c(q) / Q_vc(v)), ceil(P(q) / QP_vc(v)));
    end
    for m = I3
        R_h(m, v) = max(ceil(c(m) / Q_vh(v)), ceil(P(m) / QP_vh(v)));
    end
end

% 每趟历时
Mp_c = zeros(N, N, V);                     
Mp_h = zeros(N, N, V);                     
for v = 1:V
    for j = I1
        for q = I2
            Mp_c(j, q, v) = t_gc(v) + 2 * t_c(j, q, v) + t_srv(q) + t_dc(v);
        end
        for m = I3
            Mp_h(j, m, v) = t_gh(v) + 2 * t_h(j, m, v) + t_srv(m) + t_dh(v);
        end
    end
end

% 时间上界
Lbar = zeros(N, V);
Mbar = zeros(N, V);
for v = 1:V
    for j = I1
        boat_all = 0;
        for q = I2
            boat_all = boat_all + R_c(q, v) * Mp_c(j, q, v);
        end
        heli_all = 0;
        for m = I3
            heli_all = heli_all + R_h(m, v) * Mp_h(j, m, v);
        end
        Lbar(j, v) = max([t_srv(j), boat_all + t_ac(v), heli_all]);
        phi_max = 0;
        for i = I1
            if A(i, j, v)
                phi_max = max(phi_max, phi(i, j, v));
            end
        end
        Mbar(j, v) = Lbar(j, v) + phi_max;
    end
end

% 鲁棒形式
compact_robust = true;
for v = 1:V
    for i = I1
        for j = I1
            if A(i,j,v) && phi(i,j,v) > tbar(i,j,v)
                compact_robust = false;
            end
        end
    end
end
if strcmp(model_mode, 'nominal')
    Gamma = 0;
elseif ~strcmp(model_mode, 'robust')
    error('model_mode 只能是 robust 或 nominal。');
end
general_robust = strcmp(model_mode,'robust') && ~compact_robust;

% 输入检查
assert(all(P([I2, I3]) == fix(P([I2, I3]))), '水域点待运人数必须是整数。');
assert(all(QP_vc == fix(QP_vc)) && all(QP_vh == fix(QP_vh)), '舟艇/直升机载客人数必须是正整数。');
assert(all(c(I0) == 0) && all(t_srv(I0) == 0), '配送中心列的物资需求和服务时间应为 0。');
assert(all(road_dev_ratio < 1), 'road_dev_ratio 必须小于 1。');
assert(Gamma >= 0 && Gamma <= n, 'Γ 必须满足 0 ≤ Γ ≤ n。');
assert(all(that(A) >= 0) && all(tbar(A) - that(A) > 0), '合法弧上必须满足 t̂ ≥ 0 且 t̄ − t̂ > 0。');
for j = I1
    assert(any(reshape(A(:, j, :), [], 1)), '陆地点 ID %g 没有任何合法入弧。', node_id(j));
end
for v = 1:V
    assert(any(reshape(A(I0, :, v), [], 1)), '车辆 %d 没有从配送中心出发的合法弧。', v);
end
for q = I2
    assert(any(reshape(a_c(I1, q, :), [], 1)), '舟艇水域点 ID %g 没有可达的陆地点。', node_id(q));
end
assert(sum(c) <= sum(Q_v) + 1e-9, '总物资需求超过全部车辆净载重之和。');
assert(sum(c) <= sum(Q_b) + 1e-9, '总物资需求超过全部配送中心库存之和。');

fprintf('算例：%d 个陆地点，%d 个舟艇水域点，%d 个直升机水域点，%d 个配送中心，%d 辆车，合法弧 %d 条。\n', ...
    n, numel(I2), numel(I3), numel(I0), V, nnz(A));


S = struct('N', N, 'V', V, 'I0', I0, 'I1', I1, 'I2', I2, 'I3', I3, 'isI1', isI1, ...
    'node_id', node_id, 'xy', xy, 'hangar_xy', hangar_xy, 'c', c, 'P', P, 't_srv', t_srv, ...
    'tbar', tbar, 'that', that, 'phi', phi, 'R_c', R_c, 'R_h', R_h, 'Mp_c', Mp_c, 'Mp_h', Mp_h, ...
    't_ac', t_ac, 'Q_vc', Q_vc, 'Q_vh', Q_vh, 'QP_vc', QP_vc, 'QP_vh', QP_vh, 'Gamma', Gamma);


%% 决策变量
alpha_b = binvar(N, 1);                    % α_b
alpha_b(~isI0) = 0;

x = binvar(N, N, V, 'full');               % x_ijv
x(~A) = 0;

dom_c = false(N, N, V);  dom_c(I1, I2, :) = true;
alpha_c = binvar(N, N, V, 'full');         % α_jqvc
alpha_c(~dom_c) = 0;

dom_h = false(N, N, V);  dom_h(I1, I3, :) = true;
alpha_h = binvar(N, N, V, 'full');         % α_jmvh
alpha_h(~dom_h) = 0;

f = binvar(N, V, 'full');                  % f_jv
f(~isI1, :) = 0;

aH = binvar(N, V, 'full');                 % a^H_jv
aH(~isI1, :) = 0;

w = sdpvar(N, N, V, 'full');               % w_ijv
w(~A) = 0;

pi_ = sdpvar(N, V, 'full');                % π_jv
pi_(~isI1, :) = 0;

lambda = sdpvar(N, V, 'full');             % λ_bv
lambda(~isI0, :) = 0;

L = sdpvar(N, V, 'full');                  % L_jv
L(~isI1, :) = 0;

%% 路线、覆盖与物资
Constraints = [];                          

alpha_bv = cell(N, V);                     % 车辆 v 是否从配送中心 b 出发
for b = I0
    for v = 1:V
        alpha_bv{b, v} = sum(x(b, I1, v));
    end
end
alpha_bv = cell_to_expr(alpha_bv);

eta = cell(1, V);                          % 车辆 v 是否启用
for v = 1:V
    eta{v} = sum(alpha_bv(I0, v));
end
eta = cell_to_expr(eta);

y = cell(N, V);                            % 车辆 v 是否访问陆地点 j
for j = I1
    for v = 1:V
        y{j, v} = sum(x([I0, I1], j, v));
    end
end
y = cell_to_expr(y);

e = cell(N, V);                            % 陆地点 j 是否为车辆 v 的路线终点
for j = I1
    for v = 1:V
        e{j, v} = y(j, v) - sum(x(j, I1, v));
    end
end
e = cell_to_expr(e);

for b = I0
    for v = 1:V
        Constraints = [Constraints, alpha_bv(b, v) <= alpha_b(b)];
    end
    Constraints = [Constraints, alpha_b(b) <= sum(alpha_bv(b, :))];
end

for v = 1:V
    Constraints = [Constraints, sum(alpha_bv(I0, v)) <= 1];
end

for j = I1
    Constraints = [Constraints, sum(y(j, :)) == 1];
    for v = 1:V
        Constraints = [Constraints, y(j, v) <= eta(v)];
    end
end

for q = I2
    total = 0;
    for j = I1
        for v = 1:V
            total = total + alpha_c(j, q, v);
        end
    end
    Constraints = [Constraints, total == 1];
end
for j = I1
    for q = I2
        for v = 1:V
            Constraints = [Constraints, alpha_c(j, q, v) <= y(j, v)];
            Constraints = [Constraints, alpha_c(j, q, v) <= a_c(j, q, v)];
        end
    end
end

for m = I3
    total = 0;
    for j = I1
        for v = 1:V
            total = total + alpha_h(j, m, v);
        end
    end
    Constraints = [Constraints, total == 1];
    for j = I1
        for v = 1:V
            Constraints = [Constraints, alpha_h(j, m, v) <= y(j, v)];
        end
    end
end

for j = I1
    for v = 1:V
        Constraints = [Constraints, sum(x(j, I1, v)) <= y(j, v)];
    end
end

for j = I1
    for v = 1:V
        Constraints = [Constraints, y(j, v) <= pi_(j, v), pi_(j, v) <= n * y(j, v)];
    end
end

for v = 1:V
    for i = I1
        for j = I1
            if A(i, j, v)
                Constraints = [Constraints, pi_(j, v) >= pi_(i, v) + 1 - (n + 1) * (1 - x(i, j, v))];
            end
        end
    end
end

W_jv = cell(N, V);
for j = I1
    for v = 1:V
        W_jv{j, v} = c(j) * y(j, v);
        for q = I2
            W_jv{j, v} = W_jv{j, v} + c(q) * alpha_c(j, q, v);
        end
        for m = I3
            W_jv{j, v} = W_jv{j, v} + c(m) * alpha_h(j, m, v);
        end
    end
end
W_jv = cell_to_expr(W_jv);
W_v = cell(1, V);
for v = 1:V
    W_v{v} = sum(W_jv(I1, v));
end
W_v = cell_to_expr(W_v);

for v = 1:V
    Constraints = [Constraints, W_v(v) <= Q_v(v) * eta(v)];
end

for j = I1
    for v = 1:V
        Constraints = [Constraints, pi_(j, v) >= 0];
    end
end

for b = I0
    for v = 1:V
        Constraints = [Constraints, 0 <= lambda(b, v), lambda(b, v) <= Q_v(v) * alpha_bv(b, v)];
        Constraints = [Constraints, lambda(b, v) <= W_v(v)];
        Constraints = [Constraints, lambda(b, v) >= W_v(v) - Q_v(v) * (1 - alpha_bv(b, v))];
    end
end

for b = I0
    Constraints = [Constraints, sum(lambda(b, :)) <= Q_b(b) * alpha_b(b)];
end


%% 往返趟次与资源作业
B = cell(N, V);                            % 舟艇在陆地点 j 完成全部任务的作业量
H = cell(N, V);                            % 直升机在陆地点 j 完成全部任务的作业量
for j = I1
    for v = 1:V
        B{j, v} = 0;
        for q = I2
            B{j, v} = B{j, v} + R_c(q, v) * Mp_c(j, q, v) * alpha_c(j, q, v);
        end
        H{j, v} = 0;
        for m = I3
            H{j, v} = H{j, v} + R_h(m, v) * Mp_h(j, m, v) * alpha_h(j, m, v);
        end
    end
end
B = cell_to_expr(B);
H = cell_to_expr(H);


%% 次任务启用状态

for v = 1:V
    for j = I1
        for i = I1
            if A(i, j, v)
                Constraints = [Constraints, 0 <= w(i, j, v), w(i, j, v) <= x(i, j, v)];
                Constraints = [Constraints, w(i, j, v) <= aH(i, v)];
                Constraints = [Constraints, w(i, j, v) >= x(i, j, v) + aH(i, v) - 1];
            end
        end
        for b = I0
            if A(b, j, v)
                Constraints = [Constraints, w(b, j, v) == 0];
            end
        end
    end
end

bH = cell(N, V);                           % 到达陆地点 j 之前直升机是否已启用
for j = I1
    for v = 1:V
        bH{j, v} = sum(w([I0, I1], j, v));
    end
end
bH = cell_to_expr(bH);
for j = I1
    for v = 1:V
        Constraints = [Constraints, aH(j, v) == bH(j, v) + f(j, v)];
        Constraints = [Constraints, 0 <= aH(j, v), aH(j, v) <= y(j, v)];
    end
end

for j = I1
    for v = 1:V
        Constraints = [Constraints, f(j, v) <= sum(alpha_h(j, I3, v))];
        for m = I3
            Constraints = [Constraints, alpha_h(j, m, v) <= aH(j, v)];
        end
    end
end
for v = 1:V
    Constraints = [Constraints, sum(f(I1, v)) <= 1];
end

%% 并行历时中的线性表达式
U   = cell(N, V);                          % 驶入陆地点 j 的道路时间
Phi = cell(N, V);                          % 直升机驶入陆地点 j 的站间转场时间
for j = I1
    for v = 1:V
        U{j, v} = 0;
        for i = [I0, I1]
            if A(i, j, v)
                U{j, v} = U{j, v} + tbar(i, j, v) * x(i, j, v);
            end
        end
        Phi{j, v} = 0;
        for i = I1
            if A(i, j, v)
                Phi{j, v} = Phi{j, v} + phi(i, j, v) * w(i, j, v);
            end
        end
    end
end
U   = cell_to_expr(U);
Phi = cell_to_expr(Phi);


%% 时间线性化
for j = I1
    for v = 1:V
        Constraints = [Constraints, L(j, v) >= t_srv(j) * y(j, v)];
        Constraints = [Constraints, L(j, v) >= B(j, v)];
        Constraints = [Constraints, L(j, v) >= H(j, v)];
    end
end

for j = I1
    for v = 1:V
        for q = I2
            Constraints = [Constraints, L(j, v) >= B(j, v) + t_ac(v) * (alpha_c(j, q, v) - e(j, v))];
        end
    end
end

for j = I1
    for v = 1:V
        Constraints = [Constraints, 0 <= L(j, v), L(j, v) <= Lbar(j, v) * y(j, v)];
    end
end

%% 第10部分  目标函数
if strcmp(model_mode, 'robust')
    f_obj = sdpvar(1,1);
    Objective = f_obj;
    if compact_robust
        % 共同预算。
        arc_list = find(A);
        z = sdpvar(1,1); p = sdpvar(numel(arc_list),1);
        Constraints = [Constraints, z>=0, p>=0, ...
            z+p >= that(arc_list).*x(arc_list), ...
            f_obj >= sum(U(I1,:),'all')+sum(L(I1,:),'all')+Gamma*z+sum(p)];
        fprintf('鲁棒模型：紧凑预算形式，无陆地点枚举规模限制。\n');
    else
        % 一般形式用有限极点场景逐步生成；初始场景 tau=0。
        scenario_history = zeros(N,1);
        Constraints = [Constraints, scenario_constraints(S,x,L,Phi,H,f_obj,zeros(N,1))];
        fprintf('鲁棒模型：一般场景约束生成，精确分离共同预算最坏场景。\n');
    end
else
    % 名义模型
    M = sdpvar(N, V, 'full');                             % 陆地点 j 的协同历时
    M(~isI1, :) = 0;
    
    for j = I1
        for v = 1:V
            Constraints = [Constraints, M(j, v) >= L(j, v) - t_srv(j) * y(j, v)];
            Constraints = [Constraints, M(j, v) >= Phi(j, v) + H(j, v) - U(j, v) - t_srv(j) * y(j, v)];
            Constraints = [Constraints, 0 <= M(j, v), M(j, v) <= Mbar(j, v) * y(j, v)];
        end
    end
    
    Objective = 0;
    for v = 1:V
        for j = I1
            for i = [I0, I1]
                if A(i, j, v)
                    Objective = Objective + tbar(i, j, v) * x(i, j, v);
                end
            end
            Objective = Objective + t_srv(j) * y(j, v) + M(j, v);
        end
    end
end


%%  CPLEX调用
[~, case_name] = fileparts(data_folder);
result_name = [case_name, '_', model_mode];
run_folder  = [case_name, '_Cplex'];
if strcmp(model_mode, 'robust')
    run_folder = sprintf('%s_G%s_R%s', run_folder, num2str(Gamma), num2str(road_dev_ratio));
    run_folder = regexprep(run_folder, '\s+', '');   
end
assert(isempty(regexp(run_folder, '[<>:"/\\|?*]', 'once')), ...
    '算例名或鲁棒参数含非法路径字符：%s', run_folder);
out_folder = fullfile(script_folder, 'Cplex_results', run_folder);
if ~exist(out_folder, 'dir'), mkdir(out_folder); end
log_file = fullfile(out_folder, 'solver.log');                   % CPLEX 的原生求解日志
if exist(log_file, 'file'), delete(log_file); end
build_seconds = toc(program_timer);
fprintf('建模完成，用时 %.1f s，开始调用 CPLEX……\n', build_seconds);

ops = sdpsettings('solver', 'cplex', 'verbose', 1);
solve_clock = tic; lower_bound = -inf; has_solution = false;
best_upper = inf; generation_round = 0; robust_certified = ~general_robust;
while true
    generation_round = generation_round+1;
    time_left = max(0.01,cplex_params.timelimit-toc(solve_clock));
    current_cpx = solve_cplex(Constraints,Objective,ops,cplex_params,time_left,log_file);
    if isfinite(current_cpx.objbound)
        lower_bound=max(lower_bound,current_cpx.objbound);
    end
    if isempty(current_cpx.x)
        if ~has_solution, cpx=current_cpx; end
        break;
    end
    residual=check(Constraints);
    current_violation=max(0,-min(residual));
    binary_values=[value(alpha_b(I0));value(x(A));value(alpha_c(dom_c)); ...
        value(alpha_h(dom_h));reshape(value(f(I1,:)),[],1)];
    assert(current_violation<=tol && all(isfinite(binary_values)) && ...
        max(abs(binary_values-round(binary_values)))<=tol,'求解结果未通过可行性校验。');
    current_X=round(value(x)); current_AC=round(value(alpha_c));
    current_AH=round(value(alpha_h)); current_FF=round(value(f));
    current_nominal=decode_plan(S,current_X,current_AC,current_AH,zeros(N,1));
    if strcmp(model_mode,'robust')
        [current_upper,current_tau]=worst_case(S,current_nominal);
    else
        current_upper=current_nominal.TT; current_tau=zeros(N,1);
    end
    if current_upper<best_upper
        best_upper=current_upper; X=current_X; AC=current_AC; AH=current_AH;
        FF=current_FF; cpx=current_cpx; max_violation=current_violation;
    end
    has_solution=true;
    robust_certified = best_upper-lower_bound <= ...
        max(10*tol,cplex_params.mipgap*max(abs(best_upper),1e-10));
    if ~general_robust || robust_certified, break; end
    fprintf('场景生成第%d轮：可行上界 %.8f，下界 %.8f h。\n', ...
        generation_round,best_upper,lower_bound);
    if toc(solve_clock)>=cplex_params.timelimit, break; end
    if any(max(abs(scenario_history-current_tau),[],1)<=1e-10), break; end
    scenario_history(:,end+1)=current_tau;
    Constraints=[Constraints,scenario_constraints(S,x,L,Phi,H,f_obj,current_tau)];
end
solve_seconds=toc(solve_clock);
status=cpx.status;                         
if general_robust && has_solution
    if robust_certified, status='ROBUST_GAP_CERTIFIED'; else, status='ROBUST_FEASIBLE'; end
end


%% 解码与核验
if ~has_solution
    if strcmp(status, 'INFEASIBLE')
        fprintf('\n状态：INFEASIBLE。模型无可行解，请检查容量、库存、可达性等参数。\n');
    else
        fprintf('\n状态：%s。CPLEX 没有得到整数可行解（下界 %.6f h），不输出路线和图片；可增大 timelimit 后重试。\n', status, lower_bound);
    end
    result = struct('status', status, 'hasSolution', false, 'lowerBound', lower_bound, 'solveSeconds', solve_seconds);
    save(fullfile(out_folder, 'result.mat'), 'result');
    return;
end

% 名义场景
nominal = decode_plan(S, X, AC, AH, zeros(N, 1));
assert(isequal(nominal.first_heli, FF), '解码得到的首个直升机任务站与变量 f 不一致。');

% 最坏场景
if strcmp(model_mode, 'robust')
    [worst_value, worst_tau] = worst_case(S, nominal);
    worst = decode_plan(S, X, AC, AH, worst_tau);
    assert(abs(worst.TT - worst_value) <= 1e-6, '最坏目标不一致。');
else
    worst = nominal;                       % 名义模型
end
objective = worst.TT;                      % 最坏情况总完成时间
trips = trip_table(S, AC, AH);             % 逐趟物资与人数
gap = 100 * max(0, objective - lower_bound) / max(abs(objective), 1e-10);
fprintf('\n主问题目标 = %.6f h，独立复算的完整目标 = %.6f h，下界 = %.6f h，Gap = %.4f %%\n', ...
    cpx.objval, objective, lower_bound, gap);


%% 输出结果与画图
runtime = toc(program_timer);
% 文字汇总
lines = {sprintf('Experiment: %s', result_name), sprintf('Algorithm: %s', 'cplex'), sprintf('Seed: %d', cplex_params.randomseed), ...
    sprintf('Status: %s', status), sprintf('Objective: %.6f h', objective), ...
    sprintf('VT: %.6f h', worst.VT), sprintf('VCHCT: %.6f h', worst.VCHCT), ...
    sprintf('Runtime: %.3f s', runtime), sprintf('Gap: %.6f %%', gap), ...
    sprintf('Lower Bound: %.6f h', lower_bound), ...
    sprintf('Vehicles: %d / %d', sum(~cellfun(@isempty, worst.routes)), V)};
for v = 1:V
    lines{end+1} = sprintf('Route %d: %s | Load: %.3f kg | Finish: %.6f h', ...
        v, strjoin(string(worst.routes{v}), ' -> '), worst.load(v), worst.finish(v)); 
    first_row = worst.stations(worst.stations.Vehicle == v & worst.stations.FirstHeliTask == 1, :);
    if ~isempty(first_row)
        lines{end+1} = sprintf('Helicopter %d: First Land %g | Trigger: %.6f h | Accounting Ready: %.6f h', ...
            v, first_row.LandID, first_row.HangarTriggerAccountingTime, first_row.HeliAccountingReady);
    else
        lines{end+1} = sprintf('Helicopter %d: Not dispatched', v);
    end
end
summary_text = strjoin(lines, newline);
fprintf('\n%s\n', summary_text);
fid = fopen(fullfile(out_folder, 'summary.txt'), 'w', 'n', 'UTF-8'); fprintf(fid, '%s\n', summary_text); fclose(fid);
summary = struct('Algorithm', 'cplex', 'Seed', cplex_params.randomseed, 'Status', status, 'Objective', objective, ...
    'VT', worst.VT, 'VCHCT', worst.VCHCT, 'Runtime', runtime, 'Gap', gap, 'LowerBound', lower_bound);
fid = fopen(fullfile(out_folder, 'summary.json'), 'w'); fprintf(fid, '%s', jsonencode(summary)); fclose(fid);

% 逐站时刻表与逐趟装载表
writetable(worst.stations,   fullfile(out_folder, 'stations_worst.csv'));
writetable(nominal.stations, fullfile(out_folder, 'stations_nominal.csv'));
writetable(trips,            fullfile(out_folder, 'trips.csv'));

% 路线图
draw_routes(S, worst, AC, AH, objective, out_folder);

% 保存全部结果
result = struct('status', status, 'hasSolution', true, 'objective', objective, ...
    'cplexObjective', cpx.objval, 'lowerBound', lower_bound, 'gapPercent', gap, ...
    'solveSeconds', solve_seconds, 'buildSeconds', build_seconds, 'runtime', runtime, ...
    'robustCertified', robust_certified, 'generationRounds', generation_round, ...
    'compactRobust', compact_robust, 'maxConstraintViolation', max_violation, 'modelMode', model_mode, 'Gamma', Gamma, ...
    'cplexStatus', cpx.cplexstatus, 'cplexStatusString', cpx.statusstring);
result.nominal = nominal;  result.worst = worst;  result.trips = trips;
result.X = X;  result.alpha_c = AC;  result.alpha_h = AH;  result.f = FF;
save(fullfile(out_folder, 'result.mat'), 'result', 'S', 'cplex_params');
fprintf('\n结果已保存到：%s\n', out_folder);
if usejava('desktop')                     
    openfig(fullfile(out_folder, 'routes.fig'), 'visible');
end


%% 局部函数
function value = per_vehicle(value, V, name, must_be_positive)
assert(isnumeric(value) && isvector(value) && all(isfinite(value)) && all(value >= 0), ...
    '参数 %s 必须是非负的有限数。', name);
if isscalar(value)
    value = repmat(value, 1, V);
end
value = reshape(value, 1, []);
assert(numel(value) == V, '参数 %s 必须是标量或 1×%d 向量。', name, V);
if must_be_positive
    assert(all(value > 0), '参数 %s 必须为正数。', name);
end
end

function M3 = to_3d(M, rows, cols, V, name)
assert(isnumeric(M) || islogical(M), '%s 必须是数值矩阵。', name);
assert(size(M, 1) == rows && size(M, 2) == cols && ismember(size(M, 3), [1, V]), ...
    '%s 的大小必须是 %d×%d 或 %d×%d×%d。', name, rows, cols, rows, cols, V);
M3 = double(M);
if size(M3, 3) == 1
    M3 = repmat(M3, 1, 1, V);
end
end

function E = cell_to_expr(E_cell)
E_cell(cellfun(@isempty, E_cell)) = {0};
E = reshape([E_cell{:}], size(E_cell));
end

function out = solve_cplex(Constraints, Objective, ops, P, time_left, log_file)
[interfacedata, recoverdata, diagnostic] = export(Constraints, Objective, ops, [], []);
if ~isempty(diagnostic), error('YALMIP 编译模型失败：%s', diagnostic.info); end
assert(startsWith(lower(interfacedata.solver.tag), 'cplex'), ...
    'YALMIP 选中的求解器是 %s，不是 CPLEX（请检查 CPLEX 的 MATLAB 接口是否在路径上）。', interfacedata.solver.tag);
[model, nonlinear_remain] = yalmip2cplex(interfacedata);
assert(~nonlinear_remain, '模型中含非线性项，CPLEX 无法求解。');
n_var = numel(model.f);
lb = model.lb;  ub = model.ub;
if isempty(lb), lb = -inf(n_var, 1); end
if isempty(ub), ub =  inf(n_var, 1); end
isB = model.ctype(:) == 'B';              
lb(isB) = max(lb(isB), 0);  ub(isB) = min(ub(isB), 1);

cplex = Cplex('rescue');
cplex.Model.sense = 'minimize';
cplex.Model.obj   = full(model.f(:));
cplex.Model.lb    = full(lb(:));
cplex.Model.ub    = full(ub(:));
cplex.Model.ctype = model.ctype(:)';
n_eq = numel(model.beq);  n_in = numel(model.bineq);
cplex.Model.A   = sparse([model.Aeq; model.Aineq]);                  
cplex.Model.lhs = full([model.beq(:); -inf(n_in, 1)]);
cplex.Model.rhs = full([model.beq(:); model.bineq(:)]);
assert(size(cplex.Model.A, 1) == n_eq + n_in, 'CPLEX 约束矩阵行数不一致。');


cplex.Param.timelimit.Cur                  = time_left;
cplex.Param.mip.tolerances.mipgap.Cur      = P.mipgap;
cplex.Param.mip.tolerances.absmipgap.Cur   = P.absmipgap;
cplex.Param.randomseed.Cur                 = P.randomseed;
cplex.Param.threads.Cur                    = P.threads;
cplex.Param.preprocessing.presolve.Cur     = P.presolve;
cut_names = fieldnames(cplex.Param.mip.cuts);
for k = 1:numel(cut_names)                 % 所有割平面族统一设置
    cplex.Param.mip.cuts.(cut_names{k}).Cur = P.cuts;
end
cplex.Param.mip.strategy.heuristicfreq.Cur = P.heuristicfreq;
cplex.Param.preprocessing.symmetry.Cur     = P.symmetry;
cplex.Param.mip.display.Cur                = P.mipdisplay;

% 求解日志
fid = fopen(log_file, 'a', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
cplex.DisplayFunc = @(str) cplex_log_line(fid, str);
cplex.solve();

sol = cplex.Solution;
out.cplexstatus  = sol.status;
out.statusstring = sol.statusstring;
out.status       = cplex_status_name(sol.status);
out.objval   = NaN;  out.objbound = -inf;  out.x = [];
if isfield(sol, 'bestobjval') && isfinite(sol.bestobjval)
    out.objbound = sol.bestobjval + interfacedata.f;                   
end
if isfield(sol, 'x') && ~isempty(sol.x) && ~any(isnan(sol.x))
    x = sol.x(:);
    if ~isempty(model.NegativeSemiVar), x(model.NegativeSemiVar) = -x(model.NegativeSemiVar); end
    out.x      = recoverdata.x_equ + recoverdata.H * x;                 
    out.objval = sol.objval + interfacedata.f;
    yalmip('setsolution', struct('variables', recoverdata.used_variables(:), ...
        'optvar', out.x, 'values', []));                            
end
end

% 输出转换
function name = cplex_status_name(code)
switch code
    case {1, 101, 102},      name = 'OPTIMAL';        % 最优
    case {3, 103},           name = 'INFEASIBLE';
    case {2, 118},           name = 'UNBOUNDED';
    case {4, 119},           name = 'INF_OR_UNBD';
    case {11, 107, 108},     name = 'TIME_LIMIT';     
    case {105, 106},         name = 'NODE_LIMIT';
    case 104,                name = 'SOLUTION_LIMIT';
    case {13, 113, 114},     name = 'INTERRUPTED';
    otherwise,               name = sprintf('CPLEX_STATUS_%d', code);
end
end

function cplex_log_line(fid, str)
str = regexprep(char(str), '[\r\n]+$', '');
fprintf('%s\n', str);
fprintf(fid, '%s\n', str);
end

function s = decode_plan(S, X, AC, AH, tau)
N = S.N;  V = S.V;
s.routes = cell(1, V);                     % 每辆车的路线（节点ID）
s.route_nodes = cell(1, V);                % 每辆车的路线（节点编号）
s.finish = zeros(1, V);                    % 车辆 v 所在协同单元的完成时刻
s.load = zeros(1, V);                      % 车辆 v 的装载量
s.first_heli = zeros(N, V);                % f_jv
[s.U, s.L, s.Phi, s.H, s.dev] = deal(zeros(N, 1));   % 每个陆地点的 U(t̄)、L、Φ、H 以及入弧 t̂
T1 = 0;  T2 = 0;  rows = zeros(0, 23);
visited = false(N, 1);
for v = 1:V
    % 车辆 v 的出发弧
    route = [];
    for b = S.I0
        j = find(X(b, :, v) > 0.5);
        assert(numel(j) <= 1, '车辆 %d 从同一中心出发了多条弧。', v);
        if ~isempty(j)
            assert(isempty(route), '车辆 %d 从多个中心出发。', v);
            route = [b, j];
        end
    end
    if isempty(route)
        assert(~any(X(:, :, v) > 0.5, 'all'), '车辆 %d 没有出发却有被选中的弧（子回路）。', v);
        continue;
    end
    % 沿 x = 1 的弧依次走到终点（开放路径，不回库）
    while true
        next_node = find(X(route(end), :, v) > 0.5);
        if isempty(next_node), break; end
        assert(numel(next_node) == 1 && ~ismember(next_node, route), '车辆 %d 的路线出现分叉或回路。', v);
        route(end+1) = next_node; 
    end
    % 本车装载量
    for k = 2:numel(route)
        j = route(k);
        s.load(v) = s.load(v) + S.c(j) + sum(S.c(S.I2)' .* AC(j, S.I2, v)) + sum(S.c(S.I3)' .* AH(j, S.I3, v));
    end
    remaining = s.load(v);
    D_prev = 0;                            
    active = false;                        % 直升机是否已启用
    for k = 2:numel(route)
        i = route(k - 1);  j = route(k);
        visited(j) = true;
        is_end = (k == numel(route));
        t_tilde = S.tbar(i, j, v) + S.that(i, j, v) * tau(j);                  
        B = 0;
        for q = S.I2
            B = B + S.R_c(q, v) * S.Mp_c(j, q, v) * AC(j, q, v);                
        end
        H = 0;
        for m = S.I3
            H = H + S.R_h(m, v) * S.Mp_h(j, m, v) * AH(j, m, v);               
        end
        chi = max([0, AC(j, S.I2, v)]);                                         
        e_jv = double(is_end);                                                  % 终点标记
        recovery = S.t_ac(v) * chi * (1 - e_jv);                                % 非末站有舟任务时回收一次
        L = max([S.t_srv(j), B + recovery, H]);                                
        has_heli_task = any(AH(j, S.I3, v) > 0.5);
        f_jv = ~active && has_heli_task;                                        % 首个有直升机任务的站
        w_ijv = double(S.isI1(i) && active);                                  
        Phi = S.phi(i, j, v) * w_ijv;                                          
        U = t_tilde;                                                           
        D = D_prev + max(t_tilde + L, Phi + H);                                 
        M = max(L - S.t_srv(j), Phi + H - U - S.t_srv(j));                     
        T1 = T1 + t_tilde + S.t_srv(j);                                         
        T2 = T2 + M;                                                            
        truck_arrival = D_prev + t_tilde;
        if f_jv                                                                 % 首站核算就绪 = 卡车到达
            trigger = truck_arrival;  heli_ready = truck_arrival;
        elseif active                                                           % 已启用：从上一站共同释放后飞来
            trigger = NaN;            heli_ready = D_prev + Phi;
        else                                                                    % 未启用：没有飞机时钟
            trigger = NaN;            heli_ready = NaN;
        end
        heli_start = NaN;
        if has_heli_task, heli_start = max(truck_arrival, heli_ready); end
        active = active || f_jv;                                                
        W_j = S.c(j) + sum(S.c(S.I2)' .* AC(j, S.I2, v)) + sum(S.c(S.I3)' .* AH(j, S.I3, v));  
        remaining = remaining - W_j;
        s.first_heli(j, v) = f_jv;
        s.U(j) = S.tbar(i, j, v);  s.L(j) = L;  s.Phi(j) = Phi;  s.H(j) = H;  s.dev(j) = S.that(i, j, v);
        rows(end+1, :) = [v, S.node_id(j), S.node_id(i), t_tilde, Phi, truck_arrival, heli_ready, ...
            S.t_srv(j), B, H, recovery, L, M, D, W_j, max(0, remaining), e_jv, tau(j), ...
            f_jv, active, trigger, 0, heli_start]; %#ok<AGROW>
        D_prev = D;
    end
    s.finish(v) = D_prev;                                                       
    s.route_nodes{v} = route;
    s.routes{v} = S.node_id(route)';
end
assert(all(visited(S.I1)), '有陆地点没有被任何车辆访问。');
s.TT = sum(s.finish);                                                           
s.VT = T1;                                                                      
s.VCHCT = T2;                                                                   
assert(abs(s.TT - (T1 + T2)) <= 1e-8, ' TT = T1 + T2 不成立。');
s.tau = tau;
s.stations = array2table(rows, 'VariableNames', {'Vehicle', 'LandID', 'FromID', 'RoadHours', ...
    'HeliTransferHours', 'TruckArrival', 'HeliAccountingReady', 'GroundHours', 'BoatHours', ...
    'HeliHours', 'RecoveryHours', 'LocalParallelHours', 'ExtraHours', 'FinishHours', ...
    'MaterialKg', 'RemainingKg', 'IsEndpoint', 'Tau', 'FirstHeliTask', 'HeliActive', ...
    'HangarTriggerAccountingTime', 'InitialLegChargedHours', 'HeliWorkStart'});
end

function C = scenario_constraints(S,x,L,Phi,H,f_obj,tau)
% 一般鲁棒式的等价场景上图
T=sdpvar(numel(S.I1),S.V,'full');
Ut=cell(numel(S.I1),S.V);
for jj=1:numel(S.I1)
    j=S.I1(jj);
    for v=1:S.V
        Ut{jj,v}=sum((S.tbar(:,j,v)+S.that(:,j,v)*tau(j)).*x(:,j,v));
    end
end
Ut=cell_to_expr(Ut);
C=[T(:)>=0, reshape(T-Ut-L(S.I1,:),[],1)>=0, ...
    reshape(T-Phi(S.I1,:)-H(S.I1,:),[],1)>=0, f_obj>=sum(T(:))];
end

function [best_value, best_tau] = worst_case(S, nominal)
j=S.I1; n=numel(j); g=S.Gamma; k=floor(g); r=g-k;
a=nominal.U(j)+nominal.L(j); b=nominal.Phi(j)+nominal.H(j);
d=nominal.dev(j); base=max(a,b); gain=max(a+d,b)-base;
[~,order]=sort(gain,'descend'); tau=zeros(n,1); tau(order(1:k))=1;
best_value=sum(max(a+d.*tau,b)); best_land=tau;
if r>0 && k<n
    for q=1:n
        other=order(order~=q); tau=zeros(n,1);
        tau(other(1:k))=1; tau(q)=r;
        val=sum(max(a+d.*tau,b));
        if val>best_value, best_value=val; best_land=tau; end
    end
end
best_tau=zeros(S.N,1); best_tau(j)=best_land;
end

function trips = trip_table(S, AC, AH)
rows = zeros(0, 8);
for kind = 1:2                             % 1 = 舟艇，2 = 直升机
    if kind == 1
        water = S.I2;  ALPHA = AC;  R = S.R_c;  Q_cargo = S.Q_vc;  Q_people = S.QP_vc;
    else
        water = S.I3;  ALPHA = AH;  R = S.R_h;  Q_cargo = S.Q_vh;  Q_people = S.QP_vh;
    end
    for q = water
        [j, v] = find(reshape(ALPHA(:, q, :), S.N, S.V) > 0.5);   % 分配到的陆地点 j 与车辆 v
        assert(numel(j) == 1, '水域点 ID %g 没有被唯一分配。', S.node_id(q));
        total_material = 0;  total_people = 0;
        for r = 1:R(q, v)
            d_r = min(Q_cargo(v),  max(S.c(q) - (r - 1) * Q_cargo(v), 0));
            p_r = min(Q_people(v), max(S.P(q) - (r - 1) * Q_people(v), 0));
            rows(end+1, :) = [kind, v, S.node_id(j), S.node_id(q), r, d_r, p_r, S.node_id(j)];
            total_material = total_material + d_r;
            total_people = total_people + p_r;
        end
        assert(abs(total_material - S.c(q)) <= 1e-9 && total_people == S.P(q), '逐趟装载没有恰好满足需求。');
    end
end
trips = array2table(rows, 'VariableNames', {'ResourceType', 'Vehicle', 'LaunchLandID', 'WaterID', ...
    'Trip', 'MaterialKg', 'People', 'ReturnLandID'});
end

function draw_routes(S, worst, AC, AH, objective, out_folder)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);  hold(ax, 'on');
if ~isempty(S.hangar_xy)
    scatter(ax, S.hangar_xy(1), S.hangar_xy(2), 45, 'g', 's', 'filled', 'DisplayName', 'Helipad');
end
scatter(ax, S.xy(S.I0, 1), S.xy(S.I0, 2), 55, 'm', '^', 'filled', 'DisplayName', 'I0');
scatter(ax, S.xy(S.I1, 1), S.xy(S.I1, 2), 35, 'k', 'filled', 'DisplayName', 'I1');
scatter(ax, S.xy(S.I2, 1), S.xy(S.I2, 2), 35, 'b', 'filled', 'DisplayName', 'I2');
scatter(ax, S.xy(S.I3, 1), S.xy(S.I3, 2), 35, 'r', 'filled', 'DisplayName', 'I3');
for v = 1:S.V
    route = worst.route_nodes{v};
    plot(ax, S.xy(route, 1), S.xy(route, 2), 'k-', 'HandleVisibility', 'off');      % 车辆路线
    j = find(worst.first_heli(:, v) > 0.5);
    if ~isempty(j) && ~isempty(S.hangar_xy)                                         % 机库 → 首个直升机任务站
        pts = [S.hangar_xy; S.xy(j, :)];
        plot(ax, pts(:, 1), pts(:, 2), 'r--', 'HandleVisibility', 'off');
    end
end
for kind = 1:2
    if kind == 1
        water = S.I2;  ALPHA = AC;  style = 'b--';                                    % 舟艇任务
    else
        water = S.I3;  ALPHA = AH;  style = 'r--';                                    % 直升机任务
    end
    for q = water
        [j, ~] = find(reshape(ALPHA(:, q, :), S.N, S.V) > 0.5);
        pts = S.xy([j, q], :);
        plot(ax, pts(:, 1), pts(:, 2), style, 'HandleVisibility', 'off');
    end
end
grid(ax, 'on');  axis(ax, 'equal');  legend(ax, 'Location', 'northeast');
xlabel(ax, 'x (km)');  ylabel(ax, 'y (km)');

% 输出矢量图
exportgraphics(fig, fullfile(out_folder, 'routes.pdf'), 'ContentType', 'vector');
savefig(fig, fullfile(out_folder, 'routes.fig'));
close(fig);
end
