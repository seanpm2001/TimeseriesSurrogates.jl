using LombScargle

export LS
"""
LS(t; tol=1, N_total=10000, N_acc=2000,q=1)
Compute a surrogate of an irregular time series with supporting time steps `t` based on the simulated annealing algorithm described in [^SchreiberSchmitz1999].

LS surrogates preserve the periodogram and the amplitude distribution of the original signal.

This algorithm starts with a random permutation of the original data.
Then it iteratively approaches the power spectrum of the original data by swapping two randomly selected values in the surrogate data
if the minkowski distance of order `q` between the power spectrum of the surrogate data and the original data is less than before.
The iteration procedure ends when the relative deviation between the periodograms is less than `tol` or when `N_total` number of tries or `N_acc` number of actual swaps is reached.

It is similar to the [`IAAFT`](@ref) method for regular time series.

[^SchmitzSchreiber1999]: A.Schmitz T.Schreiber (1999). "Testing for nonlinearity in unevenly sampled time series" [Phys. Rev E](https://journals.aps.org/pre/pdf/10.1103/PhysRevE.59.4044)
"""
struct LS{T<:AbstractVector,S<:Real} <: Surrogate
    t::T
    tol::S
    N_total::Int
    N_acc::Int
    q::Int
end

LS(t;tol=1.0, N_total=10000, N_acc=5000, q=1) = LS(t, tol, N_total, N_acc,q)


function surrogenerator(x, method::LS)
    lsplan = LombScargle.plan(method.t, x, fit_mean=false)
    x_ls = lombscargle(lsplan)
    # We have to copy the power vector here, because we are reusing lsplan later on
    xpower = copy(x_ls.power)
    dist=Minkowski(method.q)
    init = (lsplan=lsplan, xpower=xpower, n=length(x), dist=dist)
    return SurrogateGenerator(method, x, init)
end


function (sg::SurrogateGenerator{<:LS})()
    lsplan, xpower, n, dist = sg.init
    t = sg.method.t
    tol = sg.method.tol
    s = surrogate(t, RandomShuffle())
    #_perodogram! reuses the lsplan with a shuffled time vector.
    # This is the same as shuffling the signal
    spower = LombScargle._periodogram!(s, lsplan)
    lossold = evaluate(dist,xpower, spower)
    i = j = 0
    newsurr = zero(s)
    while i < sg.method.N_total && j<sg.method.N_acc
        if mod(i,2000) ==0
            @show i, j,lossold
        end

        k,l = sample(1:n,2, replace=false)
        copy!(newsurr, s)
        #@show s
        newsurr[[k,l]] .= s[[l,k]]
        #lsplan = LombScargle.plan(t, newsurr, fit_mean=false)
        #s_ls = lombscargle(lsplan)
        spower = LombScargle._periodogram!(newsurr, lsplan)
        lossnew = evaluate(dist,xpower, spower)
        if lossnew < lossold
            lossnew <= tol && break
            s, lossold = copy(newsurr), lossnew
            j += 1
        #=else
            ## Implement drawing with a probability p
            lossdiff = lossnew - lossold
            @show lossdiff
            T = 1
            p = exp(-lossdiff/log(i)) # Where does T come from?
            if rand() < p
                @show p
                surr, lossold = newsurr, lossnew
                j += 1
            end
        =#
        end
        i+=1
    end
    @info i,j, lossold
    #Use the permutation of the time vector to permute the signal vector
    perm = sortperm(sortperm(s)) # This gives us the inverse permutation from t to perm
    @assert t[perm] == s # Check, whether this worked as expected
    return sg.x[perm]
end
