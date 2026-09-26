function varargout=rescue_model(action,varargin)
% 目标评价
switch action
    case 'evaluate'
        [varargout{1:nargout}]=rescue_evaluate(varargin{:});
    case 'route'
        varargout{1}=rescue_route_cost(varargin{:});
    case 'decode'
        [varargout{1:nargout}]=rescue_decode(varargin{:});
    otherwise
        error('Rescue:Action','rescue_model不支持操作：%s',action);
end
end

function [cost,s,p]=rescue_evaluate(R,partial)
% 评价编码R：R{v}为车辆v的中心和任务序列，R{V+1}为未分配任务
global RESCUE;
d=RESCUE.d; cfg=RESCUE.cfg; RESCUE.evaluations=RESCUE.evaluations+1;
if nargin<2, partial=false; end
s=struct('VT',0,'B',0,'H',0,'extra',0,'feasible',false,'objective',inf,'tau',zeros(d.n,1));
p=struct('x',zeros(size(d.arc,1),1),'boat',zeros(d.n*d.nB,d.V), ...
    'heli',zeros(d.n*d.nH,d.V),'open',zeros(d.nD,1));
if partial
    R=rescue_routes('landFirst',R); R=rescue_routes('centers',R);
end
viol=0; seen=[]; U=zeros(d.n,1); P=U; dev=U; L=U; B=U; H=U; ground=U;
stock=zeros(d.nD,1);
for v=1:d.V
    r=R{v}; if isempty(r), continue; end
    center=d.depotIdx(r(1));
    if center==0, viol=viol+1; r=[d.depot(1),r]; center=1; end
    p.open(center)=1; jobs=r(2:end);
    if any(~d.isTask(jobs)), viol=viol+numel(jobs); continue; end
    seen=[seen,jobs]; load=sum(d.material(jobs));
    viol=viol+max(0,load-d.Q(v)); stock(center)=stock(center)+load;
    landpos=find(d.isLandNode(r));
    if isempty(landpos), viol=viol+numel(jobs); continue; end
    viol=viol+landpos(1)-2; prev=r(1); active=false;
    for k=1:numel(landpos)
        ix=landpos(k); node=r(ix); j=d.landIdx(node);
        if k<numel(landpos), last=landpos(k+1)-1; else, last=numel(r); end
        tasks=r(ix+1:last);
        % bq/hq按任务在块内出现的先后排列。
        bq=d.boatIdx(tasks); bq=bq(bq>0);
        hq=d.heliIdx(tasks); hq=hq(hq>0);
        B(j)=sum(d.timeB(j,bq,v)); H(j)=sum(d.timeH(j,hq,v));
        viol=viol+sum(d.access(j,bq,v)==0);
        p.boat(j+(bq-1)*d.n,v)=1; p.heli(j+(hq-1)*d.n,v)=1;
        first=~active && ~isempty(hq);
        L(j)=max([d.service(node),B(j)+d.recoverB(v)*(~isempty(bq))*(k<numel(landpos)), ...
            H(j)]);
        U(j)=d.road(prev,node,v); dev(j)=d.dev(prev,node,v); ground(j)=d.service(node);
        pi=d.landIdx(prev); if active && pi>0, P(j)=d.phi(pi,j,v); end
        a=d.arcIndex(prev,j,v);
        if a==0, viol=viol+1; else, p.x(a)=1; end
        prev=node; active=active || first;
    end
end
viol=viol+numel(seen)-numel(unique(seen))+sum(max(0,stock-d.stock));
if ~partial
    viol=viol+numel(setdiff(d.taskNodes,seen));
    if numel(R)>d.V, viol=viol+numel(R{d.V+1}); end
end
% 共同预算下的精确最大值。仅当道路分支占优时才允许紧凑求值
a=U+L; b=P+H;
o=rescue_oracle(a,b,dev,d.Gamma);
if ~o.exact, viol=viol+1; end
s.objective=o.value; s.tau=o.tau; s.VT=sum(U+dev.*o.tau+ground);
s.B=sum(B); s.H=sum(H); s.extra=o.value-s.VT; s.feasible=viol<1e-7;
cost=o.value+1e5*viol;
end

%% 单车路线的局部评价
function cost=rescue_route_cost(r,v)
global RESCUE;
d=RESCUE.d; RESCUE.evaluations=RESCUE.evaluations+1;
r=r(:)'; r=r(d.isTask(r));
k=find(d.isLandNode(r),1);
if ~isempty(k), r([1,k])=r([k,1]); end

if ~isempty(r) && d.isLandNode(r(1))
    load=sum(d.material(r));
    [~,ord]=sort(d.road(d.depot,r(1),v));
    for b=reshape(ord(d.allowed(d.depot(ord),r(1),v)),1,[])
        if d.stock(b)+1e-8>=load, r=[d.depot(b),r]; break; end
    end
end

viol=0; seen=[]; U=zeros(d.n,1); P=U; dev=U; L=U; B=U; H=U;
stock=zeros(d.nD,1);
while ~isempty(r)   
    center=d.depotIdx(r(1));
    if center==0, viol=viol+1; r=[d.depot(1),r]; center=1; end
    jobs=r(2:end);
    if any(~d.isTask(jobs)), viol=viol+numel(jobs); break; end
    seen=jobs; load=sum(d.material(jobs));
    viol=viol+max(0,load-d.Q(v)); stock(center)=stock(center)+load;
    landpos=find(d.isLandNode(r));
    if isempty(landpos), viol=viol+numel(jobs); break; end
    viol=viol+landpos(1)-2; prev=r(1); active=false; nl=numel(landpos);
    for k=1:nl
        ix=landpos(k); node=r(ix); j=d.landIdx(node);
        if k<nl, last=landpos(k+1)-1; else, last=numel(r); end
        tasks=r(ix+1:last);
        bq=d.boatIdx(tasks); bq=bq(bq>0);
        hq=d.heliIdx(tasks); hq=hq(hq>0);
        B(j)=sum(d.timeB(j,bq,v)); H(j)=sum(d.timeH(j,hq,v));
        viol=viol+sum(d.access(j,bq,v)==0);
        first=~active && ~isempty(hq);
        L(j)=max([d.service(node),B(j)+d.recoverB(v)*(~isempty(bq))*(k<nl),H(j)]);
        U(j)=d.road(prev,node,v); dev(j)=d.dev(prev,node,v);
        pj=d.landIdx(prev); if active && pj>0, P(j)=d.phi(pj,j,v); end
        if d.arcIndex(prev,j,v)==0, viol=viol+1; end
        prev=node; active=active || first;
    end
    break;
end
% 重复任务数
nUnique=numel(seen)-sum(diff(sort(seen))==0);
viol=viol+numel(seen)-nUnique+sum(max(0,stock-d.stock));
o=rescue_oracle(U+L,P+H,dev,d.Gamma);
if ~o.exact, viol=viol+1; end
cost=o.value+1e5*viol;
end

%% 解码
function [s,p,trips]=rescue_decode(d,p,tau)
if nargin<3, tau=zeros(d.n,1); end
assert(numel(tau)==d.n&&all(tau>=-1e-9)&&all(tau<=1+1e-9)&&sum(tau)<=d.Gamma+1e-7, ...
    'Rescue:Scenario','场景不在共同预算不确定集中。');
tol=1e-6;
p.visit=zeros(d.n,d.V); p.endpoint=zeros(d.n,d.V);
p.B=zeros(d.n,d.V); p.H=p.B; p.L=p.B; p.U=p.B; p.Phi=p.B; p.D=p.B;
p.Wstation=p.B; p.W=zeros(1,d.V); p.origin=zeros(d.nD,d.V);
p.first=zeros(d.n,d.V); p.active=zeros(d.n,d.V);
chosen=find(p.x>0.5);
assert(numel(chosen)==d.n,'Rescue:Decode','选中道路弧数量必须等于陆地点数量。');
for a=chosen'
    i=d.arc(a,1); j=d.arc(a,2); v=d.arc(a,3);
    p.visit(j,v)=p.visit(j,v)+1; p.endpoint(j,v)=p.endpoint(j,v)+1;
    li=find(d.land==i); bi=find(d.depot==i);
    if ~isempty(li), p.endpoint(li,v)=p.endpoint(li,v)-1; end
    if ~isempty(bi), p.origin(bi,v)=p.origin(bi,v)+1; end
    p.U(j,v)=d.tbar(a); p.D(j,v)=d.that(a);
end
assert(all(sum(p.visit,2)==1)&&all(p.endpoint(:)>=0),'Rescue:Decode','陆地覆盖/终点度数错误。');
assert(all(sum(p.origin,1)<=1),'Rescue:Decode','某车辆多中心出发。');
for v=1:d.V
    ab=reshape(p.boat(:,v),d.n,d.nB); ah=reshape(p.heli(:,v),d.n,d.nH);
    assert(all(ab<=p.visit(:,v),'all')&&all(ah<=p.visit(:,v),'all'),'Rescue:Decode','水域任务挂在未访问陆地点。');
    assert(all(ab<=d.access(:,:,v),'all'),'Rescue:Decode','舟艇任务违反水路可达性。');
    p.B(:,v)=sum(d.timeB(:,:,v).*ab,2); p.H(:,v)=sum(d.timeH(:,:,v).*ah,2);
    % 由实际路线顺序与任务分配独立判定首次使用直升机的救援点
    at=chosen(d.arc(chosen,3)==v & ismember(d.arc(chosen,1),d.depot));
    active=false; walked=[];
    while ~isempty(at)
        assert(numel(at)==1 && ~ismember(at,walked),'Rescue:DispatchRoute','Branch or cycle in route.');
        walked(end+1)=at; jj=d.arc(at,2);
        if active, p.Phi(jj,v)=d.arcPhi(at); end
        p.first(jj,v)=~active && any(ah(jj,:)>0.5);
        active=active || p.first(jj,v); p.active(jj,v)=active;
        at=chosen(d.arc(chosen,3)==v & d.arc(chosen,1)==d.land(jj));
    end
    p.Wstation(:,v)=d.material(d.land).*p.visit(:,v)+ ...
        ab*reshape(d.material(d.boat),[],1)+ah*reshape(d.material(d.heli),[],1);
    p.W(v)=sum(p.Wstation(:,v));
    recover=d.recoverB(v)*double(any(ab>0.5,2)).*(1-p.endpoint(:,v));
    p.L(:,v)=max([d.service(d.land).*p.visit(:,v),p.B(:,v)+recover,p.H(:,v)],[],2);
end
for q=1:d.nB, assert(sum(p.boat((q-1)*d.n+(1:d.n),:),'all')==1,'Rescue:Decode','冲锋舟点分配错误。'); end
for h=1:d.nH, assert(sum(p.heli((h-1)*d.n+(1:d.n),:),'all')==1,'Rescue:Decode','直升机点分配错误。'); end
assert(all(p.W<=d.Q+tol),'Rescue:Decode','车辆净容量超限。');
assert(all(p.origin*p.W'<=d.stock+tol),'Rescue:Decode','中心库存超限。');
assert(all(p.open==double(any(p.origin,2))),'Rescue:Decode','启用中心与实际出发不一致。');

s.routes=cell(1,d.V); s.finish=zeros(1,d.V); s.VT=0; rows=zeros(0,22);
visitedArcs=[];
for v=1:d.V
    starts=chosen(d.arc(chosen,3)==v & ismember(d.arc(chosen,1),d.depot));
    if isempty(starts)
        assert(~any(p.visit(:,v)),'Rescue:Decode','未出发车辆存在任务/子回路。'); continue;
    end
    a=starts(1); route=d.id(d.arc(a,1)); clock=0; remaining=p.W(v); count=0;
    while ~isempty(a)
        assert(~ismember(a,visitedArcs),'Rescue:Decode','存在闭环。');
        visitedArcs(end+1)=a; count=count+1;
        assert(count<=d.n,'Rescue:Decode','路线长度超过陆地点数。');
        j=d.arc(a,2); globalJ=d.land(j); route(end+1)=d.id(globalJ);
        road=d.tbar(a)+d.that(a)*tau(j); phi=p.Phi(j,v);
        truckArrival=clock+road; heliArrival=NaN; dispatch=NaN;
        if p.first(j,v)
            dispatch=truckArrival;
            heliArrival=dispatch; 
        elseif p.active(j,v)
            heliArrival=clock+phi;
        end
        heliStart=NaN;
        ah=reshape(p.heli(:,v),d.n,d.nH);
        if any(ah(j,:)>0.5), heliStart=max(truckArrival,heliArrival); end
        duration=max(road+p.L(j,v),phi+p.H(j,v));
        finish=clock+duration; remaining=remaining-p.Wstation(j,v);
        ground=d.service(globalJ); extra=duration-road-ground;
        assert(extra>=-tol,'Rescue:Decode','负协同历时。');
        recovery=0;
        ab=reshape(p.boat(:,v),d.n,d.nB);
        if any(ab(j,:))&&p.endpoint(j,v)==0, recovery=d.recoverB(v); end
        rows(end+1,:)=[v,d.id(globalJ),d.id(d.arc(a,1)),road,phi,truckArrival, ...
            heliArrival,ground,p.B(j,v),p.H(j,v),recovery,p.L(j,v), ...
            extra,finish,p.Wstation(j,v),max(0,remaining),p.endpoint(j,v),tau(j), ...
            p.first(j,v),p.active(j,v),dispatch,heliStart];
        s.VT=s.VT+road+ground; clock=finish;
        next=chosen(d.arc(chosen,1)==globalJ & d.arc(chosen,3)==v);
        assert(numel(next)<=1,'Rescue:Decode','路线出现分叉。'); a=next;
    end
    s.routes{v}=route; s.finish(v)=clock;
    assert(abs(remaining)<=tol,'Rescue:Decode','路线结束仍有未分配物资。');
end
assert(numel(visitedArcs)==numel(chosen),'Rescue:Decode','存在与中心不连通的选中弧。');
s.TT=sum(s.finish); s.VCHCT=s.TT-s.VT; s.tau=tau(:);
assert(abs(s.TT-s.VT-s.VCHCT)<tol,'Rescue:Decode','时间分项不一致。');
s.stations=array2table(rows,'VariableNames',{'Vehicle','LandID','FromID','RoadHours', ...
    'HeliTransferHours','TruckArrival','HeliAccountingReady','GroundHours','BoatHours', ...
    'HeliHours','RecoveryHours','LocalParallelHours','ExtraHours','FinishHours', ...
    'MaterialKg','RemainingKg','IsEndpoint','Tau','FirstHeliTask','HeliActive', ...
    'HangarTriggerAccountingTime','HeliWorkStart'});

%% 逐趟货物/人数构造；每个水域点全部趟次使用同一资源和接收点
tripRows=zeros(0,8);
for kind=1:2
    if kind==1
        nodes=d.boat; assignment=p.boat; cargo=d.QB; people=d.PB; R=d.RB;
    else
        nodes=d.heli; assignment=p.heli; cargo=d.QH; people=d.PH; R=d.RH;
    end
    for q=1:numel(nodes)
        [j,v]=find(assignment((q-1)*d.n+(1:d.n),:)>0.5);
        totalD=0; totalP=0;
        for r=1:R(q,v)
            dr=min(cargo(v),max(d.material(nodes(q))-(r-1)*cargo(v),0));
            pr=min(people(v),max(d.people(nodes(q))-(r-1)*people(v),0));
            tripRows(end+1,:)=[kind,v,d.id(d.land(j)),d.id(nodes(q)),r,dr,pr,d.id(d.land(j))];
            totalD=totalD+dr; totalP=totalP+pr;
        end
        assert(abs(totalD-d.material(nodes(q)))<tol&&totalP==d.people(nodes(q)), ...
            'Rescue:Decode','逐趟需求未精确满足。');
    end
end
trips=array2table(tripRows,'VariableNames',{'ResourceType','Vehicle','LaunchLandID', ...
    'WaterID','Trip','MaterialKg','People','ReturnLandID'});
end

%% 共同预算下的最坏场景计算
function o=rescue_oracle(a,b,dev,Gamma)
a=a(:); b=b(:); dev=dev(:); n=numel(a);
assert(numel(b)==n&&numel(dev)==n&&all(dev>=0)&&Gamma>=0&&Gamma<=n, ...
    'Rescue:OracleInput','分离输入维度/预算/偏差非法。');
o=struct('value',sum(max(a,b)),'upper',sum(max(a+dev,b)), ...
    'delta',double(a>=b),'tau',zeros(n,1),'exact',false);
if Gamma==0
    o.upper=o.value; o.exact=true; return;
end
if all(a>=b-1e-12)
    [protection,tau]=budget_support(dev,Gamma);
    o.value=sum(a)+protection; o.upper=o.value;
    o.delta=ones(n,1); o.tau=tau; o.exact=true; return;
end
k=min(floor(Gamma+1e-12),n); rho=Gamma-k;
gain=max(a+dev,b)-max(a,b);
[~,order]=sort(gain,'descend');
tau=zeros(n,1); tau(order(1:k))=1;
o.tau=tau; o.value=sum(max(a+dev.*tau,b));
if rho>1e-12 && k<n
    for q=1:n
        rest=order(order~=q);
        trial=zeros(n,1); trial(rest(1:k))=1; trial(q)=rho;
        val=sum(max(a+dev.*trial,b));
        if val>o.value, o.value=val; o.tau=trial; end
    end
end
o.upper=o.value; o.delta=double(a+dev.*o.tau>=b); o.exact=true;
end

function [beta,tau]=budget_support(c,Gamma)
[s,idx]=sort(c,'descend'); n=numel(c); k=min(floor(Gamma),n);
tau=zeros(n,1); tau(idx(1:k))=1;
if k<n, tau(idx(k+1))=Gamma-k; end
beta=s'*tau(idx);
end

