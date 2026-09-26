function report=analyze_results(batchDir,options)
% 多次运行统计与Excel导出。
scriptDir=fileparts(mfilename('fullpath'));  
if nargin<1 || isempty(batchDir), batchDir=latest_batch(fullfile(scriptDir,'results')); end
if nargin<2, options=struct; end
if ~isfield(options,'outputDir'), options.outputDir=fullfile(scriptDir,'results','statistics'); end
[runs,histories]=read_batch(batchDir);
summary=describe_runs(runs);
byIteration=summarize_curves(runs,histories);
report=struct('summary',summary,'runs',runs,'byIteration',byIteration);
out=char(options.outputDir); if ~isfolder(out), mkdir(out); end
% 鲁棒批次
[~,batchName,batchExt]=fileparts(char(batchDir));
batchName=[batchName,batchExt];
% 批次名
labelPrefix=sprintf('batch_%s_%s',runs.Algorithm(1),runs.Case(1));
if startsWith(batchName,labelPrefix)
    label=batchName;
else
    label=sprintf('%s_%s_%s',runs.Case(1),runs.Algorithm(1),batchName);
end
report.excelPath=fullfile(out,[label,'_statistics.xlsx']);
temporary=[tempname(out),'.xlsx']; cleanup=onCleanup(@()remove_temporary(temporary));
write_sheet(summary,temporary,'Summary');
write_sheet(runs,temporary,'Runs');
write_sheet(byIteration,temporary,'ByIteration');
tables={summary,runs,byIteration};
fit_columns(temporary,tables); 
[ok,msg]=movefile(temporary,report.excelPath,'f'); assert(ok,'%s',msg);
fprintf('统计Excel已保存：%s\n',report.excelPath);
end

function path=latest_batch(resultsRoot)
items=dir(fullfile(resultsRoot,'batch_*')); items=items([items.isdir]);
valid=false(size(items));
for k=1:numel(items)
    valid(k)=~isempty(dir(fullfile(items(k).folder,items(k).name,'*','result.mat')));
end
items=items(valid);
if isempty(items)
    path=fullfile(resultsRoot,'seed_1');
    assert(isfile(fullfile(path,'result.mat')),'没有可统计的结果，请先运行main.m。');
else
    [~,k]=max([items.datenum]); path=fullfile(items(k).folder,items(k).name);
end
end

function [runs,histories]=read_batch(batchDir)
assert(isfolder(batchDir),'批次目录不存在：%s',batchDir);
if isfile(fullfile(batchDir,'result.mat'))
    files=dir(fullfile(batchDir,'result.mat')); 
else
    files=dir(fullfile(batchDir,'*','result.mat'));
end
assert(~isempty(files),'该目录中没有单次result.mat；请选择具体批次目录。');
runs=table; histories=cell(numel(files),1);
for k=1:numel(files)
    source=fullfile(files(k).folder,files(k).name); loaded=load(source,'result','d');
    r=loaded.result;
    assert(r.hasSolution && strcmp(r.status,'FEASIBLE'),'发现非可行结果：%s',source);
    assert(isfinite(r.worst.TT) && isfinite(r.elapsedSeconds) && r.elapsedSeconds>=0,'结果含无效指标。');
    assert(isfield(r,'algorithm'),'Rescue:LegacyResult', ...
        '结果缺少algorithm字段，请重新运行生成：%s',source);
    algorithm=string(r.algorithm);
    signature=struct('data',rmfield_if(loaded.d,{'notes'}));
    if k==1
        first=struct('signature',signature,'algorithm',algorithm,'case',string(r.config.name));
    else
        assert(isequaln(first.signature,signature) && first.algorithm==algorithm ...
            && first.case==string(r.config.name), ...
            '一个批次内包含不同模型、算法或算例，请分开统计。');
    end
    runNumber=k; if isfield(r,'runIndex'), runNumber=r.runIndex; end
    h=table; iterations=NaN;
    if isfield(r,'convergence') && ~isempty(r.convergence)
        h=r.convergence;
        assert(all(ismember({'Iteration','BestObjectiveHours'},h.Properties.VariableNames)));
        assert(h.Iteration(1)==0 && all(diff(h.Iteration)==1),'迭代编号不连续。');
        assert(all(isfinite(h{:,:}),'all'));
        assert(all(diff(h.BestObjectiveHours)<=1e-8) && abs(h.BestObjectiveHours(end)-r.worst.TT)<1e-6);
        iterations=h.Iteration(end);
    end
    histories{k}=h;
    row=table(string(r.config.name),algorithm,runNumber,r.seed,r.worst.TT,r.elapsedSeconds, ...
        iterations,~isempty(h), ...
        'VariableNames',{'Case','Algorithm','Run','Seed','ObjectiveHours','RuntimeSeconds', ...
        'Iterations','HasConvergence'});
    runs=[runs;row]; 
end
[runs,order]=sortrows(runs,{'Run','Seed'}); histories=histories(order);
assert(numel(unique(runs.Seed))==height(runs),'同一批次存在重复种子，不能当作独立重复实验。');
end

function result=rmfield_if(result,names)
for k=1:numel(names), if isfield(result,names{k}), result=rmfield(result,names{k}); end; end
end

function output=describe_runs(runs)
output=table;
for metric={'ObjectiveHours','RuntimeSeconds'}
    x=runs.(metric{1}); [lo,i]=min(x); [hi,j]=max(x);
    row=table(runs.Case(1),runs.Algorithm(1),string(metric{1}),numel(x),mean(x),sample_std(x), ...
        lo,hi,median(x),runs.Run(i),runs.Seed(i),runs.Run(j),runs.Seed(j), ...
        'VariableNames',{'Case','Algorithm','Metric','N','Mean','SampleStd','Best','Worst','Median', ...
        'BestRun','BestSeed','WorstRun','WorstSeed'});
    output=[output;row];
end
end

function byIteration=summarize_curves(runs,histories)
% 按迭代汇总20次运行的最好目标值
long=table(zeros(0,1),zeros(0,1),'VariableNames',{'Iteration','BestObjectiveHours'});
for k=1:height(runs)
    h=histories{k}; if isempty(h), continue; end
    long=[long;table(h.Iteration,h.BestObjectiveHours, ...
        'VariableNames',long.Properties.VariableNames)];
end
byIteration=array2table(zeros(0,6),'VariableNames', ...
    {'Iteration','N','MeanObjectiveHours','SampleStdHours','BestHours','WorstHours'});
for iteration=reshape(unique(long.Iteration),1,[])
    values=long.BestObjectiveHours(long.Iteration==iteration);
    byIteration(end+1,:)={iteration,numel(values),mean(values),sample_std(values),min(values),max(values)}; %#ok<AGROW>
end
end

function value=sample_std(x)
if numel(x)<2, value=NaN; else, value=std(x,0); end
end

function write_sheet(t,path,sheet)
assert(height(t)<1048576,'数据超过Excel行数上限，请缩小本次统计范围。');
writetable(t,path,'Sheet',sheet,'WriteMode','overwritesheet','AutoFitWidth',true);
end

function remove_temporary(path)
if isfile(path), delete(path); end
end

function fit_columns(file,tables)
parent=fileparts(file); folder=tempname(parent); mkdir(folder);
cleanup=onCleanup(@()remove_package_folder(folder,parent));
unzip(file,folder);
for sheet=1:numel(tables)
    path=fullfile(folder,'xl','worksheets',sprintf('sheet%d.xml',sheet));
    doc=xmlread(path); columns=doc.getElementsByTagName('col'); t=tables{sheet};
    for j=0:columns.getLength()-1
        node=columns.item(j); index=str2double(char(node.getAttribute('min')));
        if index>width(t), continue; end
        name=t.Properties.VariableNames{index}; text=[string(name);string(t.(name))];
        sizes=zeros(numel(text),1);
        for row=1:numel(text)
            if ismissing(text(row)), continue; end
            chars=char(text(row)); sizes(row)=numel(chars)+sum(double(chars)>127);
        end
        required=min(255,max(sizes)+2);
        old=str2double(char(node.getAttribute('width')));
        node.setAttribute('width',num2str(max(old,required)));
    end
    xmlwrite(path,doc);
end
package=[tempname(parent),'.zip']; zipCleanup=onCleanup(@()remove_temporary(package));
entries=dir(folder); names={entries(~ismember({entries.name},{'.','..'})).name};
zip(package,names,folder);
[ok,msg]=movefile(package,file,'f'); assert(ok,'%s',msg);
end

function remove_package_folder(folder,parent)
% 清理由本函数在输出目录下创建的临时包目录
resolved=char(java.io.File(folder).getCanonicalPath());
allowed=[char(java.io.File(parent).getCanonicalPath()),filesep];
assert(startsWith(resolved,allowed),'临时包目录不在预期输出目录内。');
if isfolder(folder), rmdir(folder,'s'); end
end
