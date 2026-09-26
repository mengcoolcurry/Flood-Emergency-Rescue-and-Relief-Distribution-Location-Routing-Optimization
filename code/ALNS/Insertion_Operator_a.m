function newRoute=Insertion_Operator_a(InitialRoute,delete_route)
% 贪心插入
global V_num RESCUE;
routeCost=zeros(1,V_num); known=false(1,V_num);
load_v=zeros(1,V_num);   % 各车当前任务载重
for v=1:V_num, load_v(v)=sum(RESCUE.d.material(InitialRoute{1,v})); end
isWater=~ismember(delete_route,RESCUE.d.land); 
for i=1:size(delete_route,2)
    min_t=inf(1,V_num); min_r=cell(1,V_num); min_cost=zeros(1,V_num);
    w=RESCUE.d.material(delete_route(i));
    fits=(load_v+w<=RESCUE.d.Q(1:V_num)+1e-8);
    if ~any(fits), fits(:)=true; end   % 全满时退回原口径
    for v=find(fits)
        route=InitialRoute{1,v};
        if ~known(v)
            routeCost(v)=CalRouteTime(route,v); known(v)=true;
        end
        route_time=routeCost(v);
        nR=size(route,2);
        plist=0;
        if nR>0, plist=[plist,nR]; end
        plist=[plist,1:(nR-1)];
        dedupe=~isempty(isWater) && isWater(i);
        allSame=false; sig=[]; seenBlock=false(1,nR+1);
        if dedupe
            isL=ismember(route,RESCUE.d.land); fl=find(isL,1);
            if isempty(fl)
                allSame=true; 
            else
                sig=[0,cummax((1:nR).*isL)]; sig(sig==0)=fl;
            end
        end
        firstEval=true;
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
            candidate=[route(1:p),delete_route(i),route(p+1:end)];
            candidate_time=CalRouteTime(candidate,v);
            delta=candidate_time-route_time;
            if firstEval || delta<min_t(v)
                min_r{v}=candidate; min_cost(v)=candidate_time; min_t(v)=delta;
            end
            firstEval=false;
        end
    end
    [~,mk]=min(min_t);
    InitialRoute{1,mk}=min_r{mk};
    routeCost(mk)=min_cost(mk);
    load_v(mk)=load_v(mk)+w;
end
newRoute=adjust2(InitialRoute);
newRoute=adjust(newRoute);
newRoute{V_num+1}=[];
end
