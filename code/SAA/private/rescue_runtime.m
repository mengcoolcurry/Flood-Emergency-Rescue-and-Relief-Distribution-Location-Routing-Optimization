function varargout=rescue_runtime(action,varargin)
switch action
    case 'run'
        [varargout{1:nargout}]=run_batch(varargin{:});
    case 'record'
        record_iteration(varargin{:});
    otherwise
        error('Rescue:Action','rescue_runtime不支持操作：%s',action);
end
end

%% 多次实验
function runSummary=run_batch(script_dir,settings,cfg,run_options,search_once)
numRuns=settings.numRuns;
baseSeed=settings.seed;
outputRoot=settings.outputDir;

if isfield(run_options,'numRuns'), numRuns=run_options.numRuns; end
if isfield(run_options,'seed'), baseSeed=run_options.seed; end
if isfield(run_options,'outputDir'), outputRoot=run_options.outputDir; end
if isfield(run_options,'model')
    names=fieldnames(run_options.model);
    for k=1:numel(names)
        assert(isfield(cfg,names{k}),'Rescue:Overrides','未知参数字段：%s',names{k});
        cfg.(names{k})=run_options.model.(names{k});
    end
end
if isfield(run_options,'plotOnly') && run_options.plotOnly
    [d,cfg]=rescue_data(script_dir,cfg);
    rescue_output('draw',d);
    runSummary=table;
    return;
end
validateattributes(numRuns,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(baseSeed,{'numeric'},{'scalar','integer','nonnegative','finite'});
assert(baseSeed+numRuns-1<=2^32-1,'随机种子超出MATLAB允许范围。');
% batch_算法_算例_标识号
batchTag='';
if isfield(cfg,'mode') && strcmp(cfg.mode,'robust')
    batchTag=sprintf('_G%s_R%s',num2str(cfg.Gamma),num2str(cfg.roadDeviationRatio));
end
batchPrefix=sprintf('batch_%s_%s%s',settings.algorithm,cfg.name,batchTag);
assert(isempty(regexp(batchPrefix,'[<>:"/\\|?*]','once')),'算例名或算法名包含非法路径字符。');
pattern=['^',regexptranslate('escape',batchPrefix),'_(\d+)$'];
batchIndex=0;
existing=dir(fullfile(outputRoot,[batchPrefix,'_*']));
for k=1:numel(existing)
    if ~existing(k).isdir, continue; end
    token=regexp(existing(k).name,pattern,'tokens','once');
    if ~isempty(token), batchIndex=max(batchIndex,str2double(token{1})); end
end
batchDir=fullfile(outputRoot,sprintf('%s_%d',batchPrefix,batchIndex+1));
while isfolder(batchDir)   
    batchIndex=batchIndex+1;
    batchDir=fullfile(outputRoot,sprintf('%s_%d',batchPrefix,batchIndex+1));
end
mkdir(batchDir);
runSummary=table;
for runIndex=1:numRuns
    options=struct('seed',baseSeed+runIndex-1,'model',cfg);
    options.runIndex=runIndex; options.totalRuns=numRuns;
    runName=sprintf('%s_%s_%d',cfg.name,settings.algorithm,runIndex);
    assert(isempty(regexp(runName,'[<>:"/\\|?*]','once')),'算例名或算法名包含非法路径字符。');
    options.outputDir=fullfile(batchDir,runName);
    fprintf('\n第%d/%d次运行（种子%d）\n',runIndex,numRuns,options.seed);
    rescue_init(script_dir,options,settings.algorithm);
    route=search_once();
    result=rescue_output('save',route,settings.algorithm);
    row=table(runIndex,result.seed,result.worst.TT,result.worst.VT,result.worst.VCHCT, ...
        result.elapsedSeconds, ...
        'VariableNames',{'Run','Seed','ObjectiveHours','VTHours','VCHCTHours','RuntimeSeconds'});
    runSummary=[runSummary;row];
    writetable(runSummary,fullfile(batchDir,'runs_summary.csv'));
end
fprintf('\n本批结果已保存：%s\n',batchDir);
% 统计Excel写到results/statistics
analyze_results(batchDir,struct('outputDir',fullfile(outputRoot,'statistics')));

end

%% 运行状态初始化
function rescue_init(script_dir,options,algorithm)
global RESCUE V_num i_data I1 I2 I3 I4 dij_v;
overrides=struct;
if isfield(options,'model'), overrides=options.model; end
[d,cfg]=rescue_data(script_dir,overrides);
RESCUE=struct('d',d,'cfg',cfg,'algorithm',algorithm,'seed',1, ...
    'evaluations',0,'destroyFraction',0.5,'outputDir',fullfile(script_dir,'results','seed_1'));
if isfield(options,'seed'), RESCUE.seed=options.seed; end
RESCUE.outputDir=fullfile(script_dir,'results',sprintf('seed_%d',RESCUE.seed));
if isfield(options,'outputDir'), RESCUE.outputDir=options.outputDir; end
rng(RESCUE.seed,'twister');
V_num=d.V; i_data=[d.id';d.people';d.material';d.service'];
I1=i_data(:,d.land); I2=i_data(:,d.boat); I3=i_data(:,d.heli); I4=i_data(:,d.depot);
dij_v=d.dist;
RESCUE.runIndex=options.runIndex; RESCUE.totalRuns=options.totalRuns;
RESCUE.history=zeros(0,2); % 迭代编号、最好目标值(小时)
RESCUE.started=tic;
end

%% 收敛记录
function record_iteration(iteration,bestObjectiveHours)
global RESCUE;
validateattributes(iteration,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(bestObjectiveHours,{'numeric'},{'scalar','finite','nonnegative'});
if isempty(RESCUE.history)
    assert(iteration==0,'首个收敛记录必须为初始化的第0轮。');
else
    assert(iteration==RESCUE.history(end,1)+1,'收敛迭代编号须连续递增。');
    assert(bestObjectiveHours<=RESCUE.history(end,2)+1e-8,'最好目标值不应随迭代增加。');
end
RESCUE.history(end+1,:)=[iteration,bestObjectiveHours];
end
