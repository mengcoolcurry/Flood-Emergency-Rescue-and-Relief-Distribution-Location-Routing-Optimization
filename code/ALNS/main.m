%% ALNS
clearvars -except run_options;
clc;
script_dir = fileparts(mfilename('fullpath')); 
addpath(script_dir,'-begin');                  
if ~exist('run_options','var'), run_options = struct; end
numRuns = 20;                                  % 运行次数
baseSeed = 1;                                  % 随机数种子
caseName = 'GRC101';                            
    
% nominal/robust
evalMode = 'nominal';
if isfield(run_options,'evalMode'), evalMode = run_options.evalMode; end
assert(ismember(evalMode,{'nominal','robust'}),'evalMode 只能是 nominal 或 robust。');

dataDir = fullfile(fileparts(script_dir),'data',caseName);
outputRoot = fullfile(script_dir,'results',evalMode);

cfg = config_model(caseName,dataDir);
cfg.mode = evalMode;        

settings = struct('numRuns',numRuns,'seed',baseSeed, ...
    'outputDir',outputRoot,'algorithm','ALNS');
runSummary = rescue_runtime('run',script_dir,settings,cfg,run_options,@search_once);
