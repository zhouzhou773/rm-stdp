using Clustering
include("datasets.jl")

function classify(n::Network, X::Array{Float64}, Y::Array{Int64}, pcfg::Dict,
                  train::Bool=true)
    labels = zeros(Int64, length(Y))
    oneh = onehot(Y)
    ma_reward = -Inf
    if ~pcfg["supervised"]
        if train
            n.da[1] = 1.0
        else
            n.da[1] = 0.0
        end
    end
    for sample in eachindex(Y)
        data_in = X[:, sample] * pcfg["fr"]
        ins = rand(n.nin, pcfg["tinput"])
        inputs = falses(n.nin, pcfg["tinput"])
        for i in 1:n.nin
            inputs[i, :] = ins[i, :] .< data_in[mod(i, length(data_in))+1]
        end
        for t in 1:pcfg["tinput"]
            outs = step!(n, inputs[:, t], train)
        end
        ocount = zeros(pcfg["n_classes"])
        for t in 1:pcfg["toutput"]
            outs = step!(n, train)
            for o in 1:length(outs)
                if outs[o]
                    ocount[mod(o, length(ocount))+1] += 1.0
                end
            end
        end
        for t in 1:pcfg["trest"]
            step!(n, train)
        end
        labels[sample] = indmax(ocount)
        ocount /= sum(ocount)
        if pcfg["supervised"] && train
            error = mean(sum((oneh[sample, :] .- ocount).^2))
            reward = 1.0 - error
            if ma_reward == -Inf
                ma_reward = reward
            else
                ma_reward = (1.0 - pcfg["ma_rate"]) * ma_reward + pcfg["ma_rate"] * reward
            end
            dop = 0.0
            if ma_reward != 0.0
                dop = reward / ma_reward
            end
            if dop > 1.0
                n.da[1] += (dop - 1.0)
            end
        end
    end

    mean(Y .== labels), randindex(Y, labels)[1]
end

function run_classify(n::Network, X::Array{Float64}, Y::Array{Int64}, pcfg::Dict)
    init_weights = copy(n.weights)
    trainx, trainy, testx, testy = train_test_split(X, Y)
    static_count = 0

    for i in 1:pcfg["n_epochs"]
        weights = copy(n.weights)
        acc, rindex = classify(n, trainx, trainy, pcfg, true)
        dweight = sum(abs.(n.weights - weights)) / length(n.weights)
        Logging.info(@sprintf("T: %s %d %d %d %d %0.6f %0.6f %e %e",
                              pcfg["data"], pcfg["seed"], pcfg["supervised"],
                              i, static_count, acc, rindex,
                              sum(abs.(n.weights - init_weights)) / length(n.weights),
                              dweight))
        if dweight < (0.001 / length(n.weights))
            static_count += 1
        else
            static_count = 0
        end
        if static_count > 10
            break
        end
    end

    acc, rindex = classify(n, testx, testy, pcfg, false)
    fit = rindex
    if pcfg["supervised"]
        fit = acc
    end
    fit
end
