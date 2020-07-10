""" Cumulative trapezoidal integration of a function with values `f` evaluated 
    at `x`.  The result is stored in `r`.
"""
function cumtrapz!(r, x, f)
    @assert length(x) == length(f)
    @assert length(r) == length(r)
    cum = zero(eltype(r))
    
    for i in eachindex(x)
        r[i] = cum
        if i != lastindex(x)
            cum += 0.5 * (f[i + 1] + f[i]) * (x[i + 1] - x[i])
        end
    end
    r
end

""" Like `cumtrapz!` but allocates the output vector. """
function cumtrapz(x, f)
    r = similar(f)
    cumtrapz!(r, x, f)
end
