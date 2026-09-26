function newRoute=Insertion_Operator_c(InitialRoute,delete_route)
% 后悔值插入
global V_num RESCUE;
USE_REGRET = true;   

m=size(delete_route,2);
if m==0
    newRoute=adjust2(InitialRoute); newRoute=adjust(newRoute); newRoute{V_num+1}=[];
    return;
end

load_v=zeros(1,V_num);   % 各车当前任务载重
for v=1:V_num, load_v(v)=sum(RESCUE.d.material(InitialRoute{1,v})); end
isWater=~ismember(delete_route,RESCUE.d.land); % 陆地任务改变陆地序列
routeCost=zeros(1,V_num); known=false(1,V_num);

cT=inf(m,V_num); cC=zeros(m,V_num); cR=cell(m,V_num); cValid=false(m,V_num);
pending=true(1,m);

for step=1:m
    idx=find(pending);
    fitsAll=false(m,V_num);
    for i=idx
        w=RESCUE.d.material(delete_route(i));
        fits=(load_v+w<=RESCUE.d.Q(1:V_num)+1e-8);
        if ~any(fits), fits(:)=true; end  
        fitsAll(i,:)=fits;
        for v=find(fits)
            if cValid(i,v), continue; end
            if ~known(v)
                routeCost(v)=CalRouteTime(InitialRoute{1,v},v); known(v)=true;
            end
            [cT(i,v),cR{i,v},cC(i,v)]=best_position(InitialRoute{1,v},routeCost(v), ...
                delete_route(i),isWater(i),v);
            cValid(i,v)=true;
        end
    end
    % 选择本轮要安置的任务
    if USE_REGRET
        bestRegret=-inf; pickI=idx(1);
        for i=idx
            t=cT(i,:); t(~fitsAll(i,:))=inf;
            s=sort(t,'ascend');
            if numel(s)>=2 && isfinite(s(2)), rg=s(2)-s(1); else, rg=inf; end
            if rg>bestRegret        
                bestRegret=rg; pickI=i;
            end
        end
    else
        pickI=idx(1);             
    end
    % 在该任务的最优车辆上落位
    t=cT(pickI,:); t(~fitsAll(pickI,:))=inf;
    [~,mk]=min(t);                  
    InitialRoute{1,mk}=cR{pickI,mk};
    routeCost(mk)=cC(pickI,mk); known(mk)=true;
    load_v(mk)=load_v(mk)+RESCUE.d.material(delete_route(pickI));
    pending(pickI)=false;
    cValid(:,mk)=false;             
end
newRoute=adjust2(InitialRoute);
newRoute=adjust(newRoute);
newRoute{V_num+1}=[];
end

function [bestDelta,bestRoute,bestCost]=best_position(route,route_time,task,isWaterTask,v)
% 单个任务在单辆车上的最优插入位置
global RESCUE;
nR=size(route,2);
plist=0;
if nR>0, plist=[plist,nR]; end
plist=[plist,1:(nR-1)];
dedupe=isWaterTask;
allSame=false; sig=[]; seenBlock=false(1,nR+1);
if dedupe
    isL=ismember(route,RESCUE.d.land); fl=find(isL,1);
    if isempty(fl)
        allSame=true;
    else
        sig=[0,cummax((1:nR).*isL)]; sig(sig==0)=fl;
    end
end
bestDelta=inf; bestRoute=route; bestCost=route_time; firstEval=true;
for p=plist
    if dedupe
        if allSame
            if ~firstEval, continue; end
        else
            b=sig(p+1);
            if seenBlock(b), continue; end
            seenBlock(b)=true;
        end
    end
    candidate=[route(1:p),task,route(p+1:end)];
    candidate_time=CalRouteTime(candidate,v);
    delta=candidate_time-route_time;
    if firstEval || delta<bestDelta
        bestRoute=candidate; bestCost=candidate_time; bestDelta=delta;
    end
    firstEval=false;
end
end
