function Route=adjust(Route)
% 把每辆车的首个陆地点换到队首，使其后的水域任务有发射点。
Route=rescue_routes('landFirst',Route);
end
