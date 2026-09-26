function [time,allVT,allCT,allHT,allVCT,allVHT,allVCHCT]=CalTime(Route)
% 目标评价
[c,s]=rescue_model('evaluate',Route,false); time=60*c; allVT=60*s.VT; allCT=60*s.B; allHT=60*s.H; allVCT=0; allVHT=0; allVCHCT=60*s.extra;
end
