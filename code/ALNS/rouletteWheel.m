% 轮盘赌选择
function idx = rouletteWheel(weights)
    if sum(weights) == 0
        weights = ones(size(weights));
    end
    prob = weights / sum(weights);
    r = rand();
    cumProb = cumsum(prob);
    idx = find(r <= cumProb, 1, 'first');
end

