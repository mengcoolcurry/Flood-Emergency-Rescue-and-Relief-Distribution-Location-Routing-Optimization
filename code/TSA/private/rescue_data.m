function [d,cfg]=rescue_data(script_dir,case_overrides)
% 读取Excel表并构造模型数据
assert(nargin>=2 && isstruct(case_overrides) && isfield(case_overrides,'nVehicles'), ...
    'Rescue:Config','请从main.m传入模型参数，或运行Point_map绘制节点。');

data_dir=fullfile(script_dir,'data'); 
if exist('case_overrides','var') && isfield(case_overrides,'dataDir')
    data_dir=case_overrides.dataDir;
end
node_data=readmatrix(fullfile(data_dir,'i_data.xlsx'),'Sheet',1);
node_type=readmatrix(fullfile(data_dir,'nodetype.xlsx'),'Sheet',1);
nodeij=readmatrix(fullfile(data_dir,'nodeij.xlsx'),'Sheet',1);
cfg=case_overrides;
cfg.dataDir=data_dir;
if isempty(cfg.boatAccess)
    cfg.boatAccess=true(sum(node_type(:)==1),sum(node_type(:)==2));
end

d=validate_input(cfg,node_data,node_type,nodeij);
d.modelVersion='first-task-first-leg-excluded-v4';
d.initialFlight=zeros(d.n,d.V);
node_id=d.id; n_nodes=d.N; n_combinations=d.V;
truck_nodes=d.land; boat_nodes=d.boat; heli_nodes=d.heli; depot_nodes=d.depot;
demand_material=d.material; demand_rescue=d.people; service=d.service;
x_coord=d.xy(:,1); y_coord=d.xy(:,2);
% 卡车只能访问truck_nodes
dist_matrix=zeros(n_nodes,n_nodes);
for i=1:n_nodes
    for j=1:n_nodes
        dist_matrix(i,j)=sqrt((x_coord(i)-x_coord(j))^2+(y_coord(i)-y_coord(j))^2);
    end
end

d.dist=dist_matrix;
d.road=zeros(d.N,d.N,d.V); d.dev=d.road; d.phi=zeros(d.n,d.n,d.V);
d.allowed=true(d.N,d.N,d.V);
if ~isempty(cfg.roadAllowed), d.allowed=expand_cube(cfg.roadAllowed,d.N,d.N,d.V,'roadAllowed',true); end
for v=1:d.V
    d.road(:,:,v)=d.dist/d.vT(v);
    d.phi(:,:,v)=d.dist(d.land,d.land)/d.vH(v)+d.kappa(v);
end
if ~isempty(cfg.roadTimeHours), d.road=expand_cube(cfg.roadTimeHours,d.N,d.N,d.V,'roadTimeHours',false); end
if ~isempty(cfg.heliTransferHours), d.phi=expand_cube(cfg.heliTransferHours,d.n,d.n,d.V,'heliTransferHours',false); end
if ~isempty(cfg.roadDeviationHours)
    d.dev=expand_cube(cfg.roadDeviationHours,d.N,d.N,d.V,'roadDeviationHours',false);
elseif ~isempty(cfg.roadDeviationRatio)
    ratio=expand_vector(cfg.roadDeviationRatio,d.V,'roadDeviationRatio',false);
    assert(all(ratio<1),'Rescue:Deviation','道路相对偏差须小于1。');
    for v=1:d.V, d.dev(:,:,v)=ratio(v)*d.road(:,:,v); end
end
if strcmp(cfg.mode,'nominal'), d.Gamma=0; else, d.Gamma=cfg.Gamma; end
validateattributes(d.Gamma,{'numeric'},{'scalar','finite','>=',0,'<=',d.n});
oldB=find(d.type==2); oldH=find(d.type==3);
if isempty(oldB)
    d.access=zeros(d.n,0,d.V);
else
    assert(~isempty(cfg.boatAccess),'Rescue:MissingAccess','须提供boatAccess，不能由欧氏距离推断可达。');
    a=expand_cube(cfg.boatAccess,d.n,numel(oldB),d.V,'boatAccess',true);
    [~,loc]=ismember(d.boat,oldB); d.access=a(:,loc,:);
end
assert(all(reshape(sum(sum(d.access,1),3),[],1)>0),'Rescue:UnreachableWater','某舟艇点无可行陆水组合。');
bDist=repmat(d.dist(d.land,oldB),1,1,d.V);
hDist=repmat(d.dist(d.land,oldH),1,1,d.V);
if ~isempty(cfg.boatDistanceKm), bDist=expand_cube(cfg.boatDistanceKm,d.n,numel(oldB),d.V,'boatDistanceKm',false); end
if ~isempty(cfg.heliDistanceKm), hDist=expand_cube(cfg.heliDistanceKm,d.n,numel(oldH),d.V,'heliDistanceKm',false); end
[~,bl]=ismember(d.boat,oldB); [~,hl]=ismember(d.heli,oldH);
bDist=bDist(:,bl,:); hDist=hDist(:,hl,:);
d.RB=zeros(d.nB,d.V); d.RH=zeros(d.nH,d.V);
d.timeB=zeros(d.n,d.nB,d.V); d.timeH=zeros(d.n,d.nH,d.V); d.Lbar=zeros(d.n,d.V);
for v=1:d.V
    % 两向趟数取最大，人数与kg分别除对应容量。
    d.RB(:,v)=max(ceil(d.material(d.boat)/d.QB(v)),ceil(d.people(d.boat)/d.PB(v)));
    d.RH(:,v)=max(ceil(d.material(d.heli)/d.QH(v)),ceil(d.people(d.heli)/d.PH(v)));
    % 准备、往返、水域服务、下客都在每趟内计一次。
    d.timeB(:,:,v)=(d.prepB(v)+2*bDist(:,:,v)/d.vB(v)+d.service(d.boat)'+d.unloadB(v)).*d.RB(:,v)';
    d.timeH(:,:,v)=(d.prepH(v)+2*hDist(:,:,v)/d.vH(v)+d.service(d.heli)'+d.unloadH(v)).*d.RH(:,v)';
    d.Lbar(:,v)=max([d.service(d.land),sum(d.timeB(:,:,v),2)+d.recoverB(v),sum(d.timeH(:,:,v),2)],[],2);
end

d.arc=zeros(0,3); d.tbar=[]; d.that=[]; d.arcPhi=[]; d.compactEligible=true;
for v=1:d.V
    for j=1:d.n
        for i=[d.depot;d.land]'
            dest=d.land(j);
            if i==dest||~d.allowed(i,dest,v), continue; end
            t=d.road(i,dest,v); h=d.dev(i,dest,v);
            assert(t-h>0,'Rescue:RoadTime','道路ID %g->%g须tBar-tHat>0。',d.id(i),d.id(dest));
            [isLand,li]=ismember(i,d.land); phi=0;
            if isLand
                phi=d.phi(li,j,v);
                if phi>t+1e-10, d.compactEligible=false; end
            end
            d.arc(end+1,:)=[i,j,v]; d.tbar(end+1,1)=t;
            d.that(end+1,1)=h; d.arcPhi(end+1,1)=phi;
        end
    end
end
assert(~isempty(d.arc),'Rescue:NoArcs','无合法道路弧。');
for j=1:d.n
    assert(any(d.arc(:,2)==j),'Rescue:UnreachableLand','陆地点ID %g无入弧。',d.id(d.land(j)));
end

d.arcIndex=zeros(d.N,d.n,d.V,'uint32');
for a=1:size(d.arc,1)
    assert(d.arcIndex(d.arc(a,1),d.arc(a,2),d.arc(a,3))==0, ...
        'Rescue:DuplicateArc','弧表出现重复的(i,j,v)。');
    d.arcIndex(d.arc(a,1),d.arc(a,2),d.arc(a,3))=a;
end

d.landIdx=zeros(1,d.N); d.landIdx(d.land)=1:d.n;
d.boatIdx=zeros(1,d.N); d.boatIdx(d.boat)=1:d.nB;
d.heliIdx=zeros(1,d.N); d.heliIdx(d.heli)=1:d.nH;
d.depotIdx=zeros(1,d.N); d.depotIdx(d.depot)=1:d.nD;
d.taskNodes=[d.land;d.boat;d.heli];
d.isTask=false(1,d.N); d.isTask(d.taskNodes)=true;
d.isLandNode=false(1,d.N); d.isLandNode(d.land)=true;

time_matrix_truck=d.road;
boat_trip_count=d.RB; heli_trip_count=d.RH;
boat_task_time=d.timeB; heli_task_time=d.timeH;
fprintf(['\n' ...
    '%s: %d land-based rescue points; %d water-based rescue points for inflatable boats; ' ...
    '%d water-based rescue points for helicopters; %d candidate distribution centers; ' ...
    '%d available vehicles\n'], ...
    cfg.name,d.n,d.nB,d.nH,d.nD,d.V);

end
function d=validate_input(cfg,node_data,node_type,nodeij)

required={'distanceScaleKm','serviceScaleHours','boatPeopleCapacity', ...
    'heliPeopleCapacity','boatUnload','heliUnload','heliTransferFixed'};
missing=required(cellfun(@(s)~isfield(cfg,s)||isempty(cfg.(s)),required));
if strcmp(cfg.mode,'robust')
    if isempty(cfg.Gamma), missing{end+1}='Gamma'; end
    if isempty(cfg.roadDeviationRatio)&&isempty(cfg.roadDeviationHours)
        missing{end+1}='roadDeviationRatio或roadDeviationHours';
    end
end
assert(isempty(missing),'Rescue:MissingParameters', ...
    '原资料缺失/未确认参数：%s。请在本脚本第2节补齐cfg参数。',strjoin(missing,', '));
assert(ismember(cfg.mode,{'nominal','robust'}),'Rescue:Mode','mode须为nominal/robust。');
validateattributes(cfg.nVehicles,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(cfg.distanceScaleKm,{'numeric'},{'scalar','positive','finite'});
validateattributes(cfg.serviceScaleHours,{'numeric'},{'scalar','positive','finite'});
raw=node_data; typ=node_type;
% 最后一行永远是机库
assert(ismember(size(nodeij,2),[2,3]) && size(nodeij,1)>=2, ...
    'Rescue:Coordinates','nodeij须为[x y]或[ID x y]，且最后一行为机库。');
hangar=nodeij(end,end-1:end);
assert(all(isfinite(hangar)),'Rescue:Coordinates','机库坐标必须为有限数值。');
d.hangar=hangar*cfg.distanceScaleKm;
xy=nodeij(1:end-1,:);
assert(size(raw,1)==4&&all(isfinite(raw(:))),'Rescue:DataShape','i_data必须为有限数值4×N。');
d.N=size(raw,2); d.id=raw(1,:)'; d.type=typ(:); d.V=cfg.nVehicles;
assert(numel(unique(d.id))==d.N&&all(d.id==fix(d.id)),'Rescue:NodeID','ID必须唯一且为整数。');
assert(isvector(typ)&&numel(typ)==d.N&&all(ismember(typ(:),1:4)), ...
    'Rescue:NodeType','nodetype须为与节点列序一致的N元素1/2/3/4向量。');
assert(all(raw(2:4,:)>=0,'all'),'Rescue:NegativeData','需求、库存候选值和服务时间不能为负。');
d.land=find(d.type==1); d.boat=find(d.type==2); d.heli=find(d.type==3); d.depot=find(d.type==4);
assert(~isempty(d.land)&&~isempty(d.depot),'Rescue:Sets','至少需要1个陆地点和1个中心。');
if size(xy,2)==3
    assert(size(xy,1)==d.N&&numel(unique(xy(:,1)))==d.N,'Rescue:Coordinates','坐标ID须唯一且数量=N。');
    [ok,loc]=ismember(d.id,xy(:,1));
    assert(all(ok),'Rescue:Coordinates','坐标表缺少ID。'); xy=xy(loc,2:3);
else
    assert(size(xy,2)==2,'Rescue:Coordinates','nodeij须为[x y]或[ID x y]。');
    if ~isempty(cfg.coordinateRows)
        r=cfg.coordinateRows(:);
        assert(numel(r)==d.N&&numel(unique(r))==d.N&&all(r==fix(r))&& ...
            all(r>=1&r<=size(xy,1)),'Rescue:Coordinates','coordinateRows须为N个不同有效行号。');
        xy=xy(r,:);
    end
    assert(size(xy,1)==d.N,'Rescue:Coordinates', ...
        '坐标行数与节点数不符，请确认多余点身份并设置coordinateRows。');
end
assert(all(isfinite(xy(:))),'Rescue:Coordinates','坐标有NaN/Inf。');
d.xy=xy*cfg.distanceScaleKm;
d.material=raw(3,:)'; d.people=raw(2,:)'; d.service=raw(4,:)'*cfg.serviceScaleHours;
assert(all(d.material(d.depot)==0)&&all(d.service(d.depot)==0), ...
    'Rescue:DepotData','中心不应设置配送需求/现场服务，库存请用centerStock。');
if isempty(cfg.centerStock)
    assert(cfg.centerStockFromRescueRow,'Rescue:MissingStock', ...
        '须提供centerStock，或确认第2行中心值为库存后设置centerStockFromRescueRow=true。');
    d.stock=d.people(d.depot);
else
    d.stock=expand_vector(cfg.centerStock,numel(d.depot),'centerStock',false)';
end
d.people(d.depot)=0;
water=[d.boat;d.heli];
assert(all(d.people(water)==fix(d.people(water))),'Rescue:People','水域人数须为非负整数。');
emptyWater=water(d.material(water)==0&d.people(water)==0);
if ~isempty(emptyWater)
    % 预处理删除双向零需求水域点
    d.boat=setdiff(d.boat,emptyWater,'stable'); d.heli=setdiff(d.heli,emptyWater,'stable');
end
d.n=numel(d.land); d.nB=numel(d.boat); d.nH=numel(d.heli); d.nD=numel(d.depot);

names={'truckCapacity','boatCargoCapacity','heliCargoCapacity','boatPeopleCapacity', ...
    'heliPeopleCapacity','truckSpeed','boatSpeed','heliSpeed','boatPrep','heliPrep', ...
    'boatRecovery','boatUnload','heliUnload','heliTransferFixed'};
targets={'Q','QB','QH','PB','PH','vT','vB','vH','prepB','prepH','recoverB','unloadB','unloadH','kappa'};
for k=1:numel(names), d.(targets{k})=expand_vector(cfg.(names{k}),d.V,names{k},k<=8); end
assert(all(d.PB==fix(d.PB))&&all(d.PH==fix(d.PH)),'Rescue:PeopleCapacity','载客能力须为正整数。');
assert(sum(d.material)<=sum(d.Q)+1e-8,'Rescue:InsufficientCapacity','总物资需求超过全车队净载重。');
assert(sum(d.material)<=sum(d.stock)+1e-8,'Rescue:InsufficientStock','总库存不足。');
assert(max(d.material)<=max(d.Q)+1e-8,'Rescue:TaskCapacity','某点全部物资超过任何一辆车的净容量。');
end


function x=expand_vector(x,n,name,positive)
validateattributes(x,{'numeric'},{'vector','real','finite','nonempty','nonnegative'},mfilename,name);
if isscalar(x), x=repmat(x,1,n); else, x=x(:)'; end
assert(numel(x)==n,'Rescue:ParameterShape','%s须为标量或%d元素。',name,n);
if positive, assert(all(x>0),'Rescue:ParameterValue','%s须为正。',name); end
end


function x=expand_cube(x,r,c,v,name,binary)
assert((isnumeric(x)||islogical(x))&&isreal(x)&&all(isfinite(x(:)))&&all(x(:)>=0), ...
    'Rescue:MatrixValue','%s须为有限非负数。',name);
assert(size(x,1)==r&&size(x,2)==c&&ndims(x)<=3&&ismember(size(x,3),[1,v]), ...
    'Rescue:MatrixShape','%s要求%d×%d或%d×%d×%d。',name,r,c,r,c,v);
if size(x,3)==1, x=repmat(x,1,1,v); end
if binary, assert(all(ismember(x(:),[0,1])),'Rescue:MatrixValue','%s只能为0/1。',name); end
x=double(x);
end

