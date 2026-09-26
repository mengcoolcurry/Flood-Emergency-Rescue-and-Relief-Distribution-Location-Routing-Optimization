if ~exist('run_options','var'), run_options=struct; end
run_options.plotOnly=true;
run(fullfile(fileparts(mfilename('fullpath')),'main.m'));
run_options=rmfield(run_options,'plotOnly');
