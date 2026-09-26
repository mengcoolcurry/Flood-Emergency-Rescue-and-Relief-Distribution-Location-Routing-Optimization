function [newRoute,delete_route]=delete_Operator_b(InitialRoute)
% 最差移除算子
global V_num RESCUE;
pWorst=RESCUE.pWorst;   
newRoute=rescue_strip(InitialRoute); delete_route=[];
total=sum(cellfun(@numel,newRoute(1:V_num)));
n=removal_count(total);
dirty=true(1,V_num); saving=cell(1,V_num);
for k=1:n
    for v=1:V_num
        if dirty(v)
            r=newRoute{v}; base=CalRouteTime(r,v);
            saving{v}=zeros(1,numel(r));
            for j=1:numel(r)
                trial=r; trial(j)=[]; saving{v}(j)=base-CalRouteTime(trial,v);
            end
            dirty(v)=false;
        end
    end
    lens=cellfun(@numel,saving);
    if sum(lens)==0, break; end
    vOf=repelem(1:V_num,lens);
    jOf=cell2mat(arrayfun(@(m) 1:m,lens,'UniformOutput',false));
    [~,L]=sort([saving{:}],'descend');
    pick=L(floor(rand^pWorst*numel(L))+1);
    v=vOf(pick); j=jOf(pick);
    delete_route(end+1)=newRoute{v}(j);
    newRoute{v}(j)=[];
    dirty(v)=true;
end
end
