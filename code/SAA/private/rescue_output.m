function varargout=rescue_output(action,varargin)
% 结果输出
switch action
    case 'save'
        [varargout{1:nargout}]=rescue_finish(varargin{:});
    case 'draw'
        [varargout{1:nargout}]=rescue_draw(varargin{:});
    case 'routeLines'
        [varargout{1:nargout}]=rescue_route_lines(varargin{:});
    otherwise
        error('Rescue:Action','rescue_output不支持操作：%s',action);
end
end

%% 保存并验证
function result=rescue_finish(R,algorithm)
global RESCUE;
runtime=toc(RESCUE.started); [cost,s,p]=rescue_model('evaluate',R,false);
assert(s.feasible,'Rescue:FinalInfeasible','Final solution violates the model; no objective is published.');
[nominal,p,trips]=rescue_model('decode',RESCUE.d,p,zeros(RESCUE.d.n,1));
worst=rescue_model('decode',RESCUE.d,p,s.tau);
assert(abs(cost-worst.TT)<1e-6,'Independent decode objective mismatch');
result=struct('hasSolution',true,'status','FEASIBLE','upperBound',cost, ...
    'plan',p,'nominal',nominal,'worst',worst,'trips',trips, ...
    'elapsedSeconds',runtime,'seed',RESCUE.seed, ...
    'config',RESCUE.cfg,'encoding',{R});
result.algorithm=algorithm; result.runIndex=RESCUE.runIndex; result.totalRuns=RESCUE.totalRuns;
result.convergence=array2table(RESCUE.history,'VariableNames', ...
    {'Iteration','BestObjectiveHours'});
assert(~isempty(RESCUE.history) && abs(RESCUE.history(end,2)-cost)<1e-6, ...
    'Rescue:Convergence','最后的收敛目标值必须与最终结果一致。');
result.iterations=RESCUE.history(end,1);
out=RESCUE.outputDir; if ~isfolder(out), mkdir(out); end
d=RESCUE.d; save(fullfile(out,'result.mat'),'result','d','-v7');
writetable(result.convergence,fullfile(out,'convergence.csv'));
writetable(worst.stations,fullfile(out,'stations_worst.csv'));
writetable(nominal.stations,fullfile(out,'stations_nominal.csv'));
writetable(trips,fullfile(out,'trips.csv'));
rescue_report(algorithm,d,result,runtime,out,RESCUE.seed);
end

%% 结果文本与路线图
function rescue_report(algorithm,d,result,runtime,out,seed)
if ~isfolder(out), mkdir(out); end
f=result.worst.TT;
lines={sprintf(['%s: %d land-based rescue points; %d water-based rescue points for inflatable boats; ' ...
    '%d water-based rescue points for helicopters; %d candidate distribution centers; ' ...
    '%d available vehicles'], ...
    result.config.name,d.n,d.nB,d.nH,d.nD,d.V),sprintf('Algorithm: %s',algorithm),sprintf('Seed: %d',seed), ...
    sprintf('Status: %s',result.status),sprintf('Objective: %.6f h',f), ...
    sprintf('VT: %.6f h',result.worst.VT),sprintf('VCHCT: %.6f h',result.worst.VCHCT), ...
    sprintf('Runtime: %.3f s',runtime), ...
    sprintf('Vehicles: %d / %d',sum(~cellfun(@isempty,result.worst.routes)),d.V)};
for v=1:d.V
    r=result.worst.routes{v};
    lines{end+1}=sprintf('Route %d: %s | Load: %.3f kg | Finish: %.6f h', ...
        v,strjoin(string(r),' -> '),result.plan.W(v),result.worst.finish(v));
    first=result.worst.stations(result.worst.stations.Vehicle==v & result.worst.stations.FirstHeliTask==1,:);
    if ~isempty(first)
        lines{end+1}=sprintf('Helicopter %d: First Land %g | Trigger: %.6f h | Accounting Ready: %.6f h', ...
            v,first.LandID,first.HangarTriggerAccountingTime,first.HeliAccountingReady);
    else
        lines{end+1}=sprintf('Helicopter %d: Not dispatched',v);
    end
end
str=strjoin(lines,newline); fprintf('%s\n',strjoin(lines(2:end),newline));
fid=fopen(fullfile(out,'summary.txt'),'w','n','UTF-8'); fprintf(fid,'%s\n',str); fclose(fid);
fig=figure('Visible','off','Color','w'); ax=axes(fig); hold(ax,'on');
if ~isempty(d.hangar)
    scatter(ax,d.hangar(1),d.hangar(2),45,'g','s','filled','DisplayName','Helipad');
end
scatter(ax,d.xy(d.depot,1),d.xy(d.depot,2),55,'m','^','filled','DisplayName','I0');
scatter(ax,d.xy(d.land,1),d.xy(d.land,2),35,'k','filled','DisplayName','I1');
scatter(ax,d.xy(d.boat,1),d.xy(d.boat,2),35,'b','filled','DisplayName','I2');
scatter(ax,d.xy(d.heli,1),d.xy(d.heli,2),35,'r','filled','DisplayName','I3');
for v=1:d.V
    r=result.worst.routes{v}; [~,idx]=ismember(r,d.id);
    plot(ax,d.xy(idx,1),d.xy(idx,2),'k-','HandleVisibility','off');
    j=find(result.plan.first(:,v)>0.5);
    if ~isempty(j) && ~isempty(d.hangar)
        xy=[d.hangar;d.xy(d.land(j),:)];
        plot(ax,xy(:,1),xy(:,2),'r--','HandleVisibility','off');
    end
end
for k=1:2
    if k==1, nodes=d.boat; assign=result.plan.boat; color='b--'; else, nodes=d.heli; assign=result.plan.heli; color='r--'; end
    for q=1:numel(nodes)
        [j,~]=find(assign((q-1)*d.n+(1:d.n),:)>0.5);
        idx=[d.land(j),nodes(q)];
        plot(ax,d.xy(idx,1),d.xy(idx,2),color,'HandleVisibility','off');
    end
end
grid(ax,'on'); axis(ax,'equal'); legend(ax,'Location','northeast');
xlabel(ax,'x (km)'); ylabel(ax,'y (km)');
% 输出矢量图
exportgraphics(fig,fullfile(out,'routes.pdf'),'ContentType','vector');
savefig(fig,fullfile(out,'routes.fig')); close(fig);
end

%% 绘图
function fig=rescue_draw(d,R)
fig=figure('Color','w'); ax=axes(fig); hold(ax,'on');
if ~isempty(d.hangar), scatter(ax,d.hangar(1),d.hangar(2),45,'g','s','filled','DisplayName','Helipad'); end
scatter(ax,d.xy(d.depot,1),d.xy(d.depot,2),55,'m','^','filled','DisplayName','I0');
scatter(ax,d.xy(d.land,1),d.xy(d.land,2),35,'k','filled','DisplayName','I1');
scatter(ax,d.xy(d.boat,1),d.xy(d.boat,2),35,'b','filled','DisplayName','I2');
scatter(ax,d.xy(d.heli,1),d.xy(d.heli,2),35,'r','filled','DisplayName','I3');
if nargin>1
    for v=1:min(d.V,numel(R))
        [a,b,c]=rescue_route_lines(R{v},d);
        paths={a,b,c}; styles={'k-','b--','r--'};
        for k=1:3
            idx=paths{k}; xy=nan(numel(idx),2); valid=isfinite(idx); xy(valid,:)=d.xy(idx(valid),:);
            plot(ax,xy(:,1),xy(:,2),styles{k},'HandleVisibility','off');
        end
    end
end
grid(ax,'on'); axis(ax,'equal'); legend(ax,'Location','eastoutside'); xlabel(ax,'x (km)'); ylabel(ax,'y (km)');
end

function [truck,boat,heli]=rescue_route_lines(route,d)
truck=route(ismember(route,[d.depot;d.land])); boat=[]; heli=[]; land=[];
for node=reshape(route,1,[])
    if ismember(node,d.land), land=node;
    elseif ~isempty(land) && ismember(node,d.boat), boat=[boat,land,node,land,NaN];
    elseif ~isempty(land) && ismember(node,d.heli), heli=[heli,land,node,land,NaN];
    end
end
end
