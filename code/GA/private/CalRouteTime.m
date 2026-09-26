function time=CalRouteTime(route,v)
if nargin<2, v=1; end
time=60*rescue_model('route',route,v);
end
