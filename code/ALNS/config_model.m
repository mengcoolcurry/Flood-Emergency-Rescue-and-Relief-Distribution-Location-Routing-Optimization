%% 模型参数
function cfg = config_model(caseName,dataDir)


cfg = struct;   
cfg.name = caseName;          % 算例名称
cfg.dataDir = dataDir;        

cfg.nVehicles = 12;           % 可用车辆数量上限
cfg.truckCapacity = 300;      % Q_v 
cfg.boatCargoCapacity = 50;   % Q_vc
cfg.heliCargoCapacity = 100;  % Q_vh
cfg.boatPeopleCapacity = 5;   % QP_vc 
cfg.heliPeopleCapacity = 5;   % QP_vh
cfg.truckSpeed = 15;          % 卡车速度
cfg.boatSpeed = 20;           % 冲锋舟速度
cfg.heliSpeed = 60;           % 直升机速度
cfg.boatPrep = 0.1;           % t_gc 
cfg.heliPrep = 0.2;           % t_gh 
cfg.boatRecovery = 0.05;      % t_ac 
cfg.boatUnload = 0.05;        % t_dc 
cfg.heliUnload = 0.05;        % t_dh 
cfg.heliTransferFixed = 0;    % 站间飞行外的固定处理时间
cfg.distanceScaleKm = 1;      % 坐标单位换系数
cfg.serviceScaleHours = 1/60; % 服务时间转换系数

cfg.coordinateRows = [];      
cfg.centerStock = [];         
cfg.centerStockFromRescueRow = true; 
cfg.boatAccess = [];          % 陆地点→水域救援点（冲锋舟）的可达 0/1 矩阵


cfg.roadAllowed = [];         
cfg.roadTimeHours = [];       
cfg.roadDeviationHours = [];  
cfg.boatDistanceKm = [];      
cfg.heliDistanceKm = [];      
cfg.heliTransferHours=[];     

cfg.mode = 'nominal';            % 鲁棒评价：nominal/robust
cfg.roadDeviationRatio = 0.2;    % 最大道路延误
cfg.Gamma = 2;                   % 共同预算

end