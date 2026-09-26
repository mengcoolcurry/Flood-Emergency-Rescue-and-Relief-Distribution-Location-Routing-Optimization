function varargout=rescue_routes(action,varargin)
% 路线处理
switch action
    case 'initial'
        [varargout{1:nargout}]=rescue_initial(varargin{:});
    case 'repair'
        [varargout{1:nargout}]=rescue_repair(varargin{:});
    case 'strip'
        [varargout{1:nargout}]=rescue_strip(varargin{:});
    case 'landFirst'
        [varargout{1:nargout}]=rescue_land_first(varargin{:});
    case 'centers'
        [varargout{1:nargout}]=rescue_centers(varargin{:});
    otherwise
        error('Rescue:Action','rescue_routes不支持操作：%s',action);
end
end

%% 生成初始解
function R=rescue_initial(popsize)
global RESCUE;
d=RESCUE.d; nodes=[d.land;d.boat;d.heli]'; R=cell(popsize,d.V+1);
for p=1:popsize
    for attempt=1:2000
        trial=cell(1,d.V+1); left=d.Q;
        for node=nodes(randperm(numel(nodes)))
            eligible=find(left>=d.material(node)-1e-8);
            if isempty(eligible), trial{end}(end+1)=node; continue; end
            v=eligible(randi(numel(eligible)));
            trial{v}(end+1)=node; left(v)=left(v)-d.material(node);
        end
        trial=rescue_repair(trial);
        [~,s]=rescue_model('evaluate',trial,false);
        if s.feasible, break; end
    end
    assert(s.feasible,'Rescue:Initialization','Random initialization failed; no feasibility claim is made.');
    R(p,:)=trial;
end
end

%% 修复路线
function R=rescue_repair(R)
global RESCUE;
d=RESCUE.d; R=rescue_strip(R); un=R{d.V+1}; seen=[];
for v=1:d.V
    keep=[]; load=0;
    for node=R{v}
        if ismember(node,seen), continue; end
        seen(end+1)=node;
        if load+d.material(node)<=d.Q(v)+1e-8
            keep(end+1)=node; load=load+d.material(node);
        else
            un(end+1)=node;
        end
    end
    R{v}=keep;
end
un=unique(un,'stable');
for node=un
    for v=1:d.V
        if sum(d.material(R{v}))+d.material(node)<=d.Q(v)+1e-8
            R{v}(end+1)=node; break;
        end
    end
end
assigned=[R{1:d.V}];
R{d.V+1}=setdiff([d.land;d.boat;d.heli]',assigned,'stable');
R=rescue_land_first(R);
% 水域任务必须由同一辆车上可达的陆地点发射。
for v=1:d.V
    r=R{v}; land=0; moved=[];
    for k=1:numel(r)
        node=r(k);
        if ismember(node,d.land), land=find(d.land==node); continue; end
        q=find(d.boat==node);
        if isempty(q) || (land>0 && d.access(land,q,v)), continue; end
        candidates=find(d.access(:,q,v)>0 & ismember(d.land,r));
        if isempty(candidates), continue; end 
        moved(end+1)=node;
    end
    for node=moved
        q=find(d.boat==node);
        candidates=find(d.access(:,q,v)>0 & ismember(d.land,r));
        dest=d.land(candidates(1)); r(r==node)=[];
        ix=find(r==dest,1); r=[r(1:ix),node,r(ix+1:end)];
    end
    R{v}=r;
end
R=rescue_centers(R);
end

%% 剥离中心
function R=rescue_strip(R)
global RESCUE;
d=RESCUE.d;
for v=1:d.V
    r=R{v}; r=r(:)';
    R{v}=r(d.isTask(r));
end
if numel(R)<d.V+1, R{d.V+1}=[]; end
end

%% 调整首个陆地点
function R=rescue_land_first(R)
global RESCUE;
d=RESCUE.d; R=rescue_strip(R);
for v=1:d.V
    r=R{v}; j=find(d.isLandNode(r),1);
    if ~isempty(j)
        r([1,j])=r([j,1]); R{v}=r;
    end
end
for v=1:d.V
    if isempty(R{v}) || any(d.isLandNode(R{v})), continue; end
    target=find(cellfun(@(r)any(d.isLandNode(r)),R(1:d.V)),1);
    if ~isempty(target)
        R{target}=[R{target},R{v}]; R{v}=[];
    end
end
end

%% 分配配送中心
function R=rescue_centers(R)
global RESCUE;
d=RESCUE.d; R=rescue_strip(R);
stock=d.stock; loads=zeros(1,d.V); choices=cell(1,d.V);
for v=1:d.V
    r=R{v};
    if isempty(r), choices{v}=0; continue; end
    loads(v)=sum(d.material(r));
    if ~d.isLandNode(r(1)), choices{v}=[]; continue; end
    [~,ord]=sort(d.road(d.depot,r(1),v));
    choices{v}=ord(d.allowed(d.depot(ord),r(1),v));
end
[ok,origins]=assign(1,stock,zeros(1,d.V));
if ~ok, origins=zeros(1,d.V); end
for v=1:d.V
    if origins(v)>0, R{v}=[d.depot(origins(v)),R{v}]; end
end
    function [ok,origins]=assign(v,remaining,origins)
        if v>d.V, ok=true; return; end
        ok=false;
        for b=reshape(choices{v},1,[])
            if b==0
                [ok,origins]=assign(v+1,remaining,origins);
            elseif remaining(b)+1e-8>=loads(v)
                rem=remaining; rem(b)=rem(b)-loads(v); trial=origins; trial(v)=b;
                [ok,trial]=assign(v+1,rem,trial);
                if ok, origins=trial; end
            end
            if ok, return; end
        end
    end
end
