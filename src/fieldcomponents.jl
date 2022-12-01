export total, static, induction, radiation

struct FieldComponents{T}
    static::SVector{3, T}
    induction::SVector{3, T}
    radiation::SVector{3, T}
end


function Base.zero(::Type{FieldComponents{T}}) where T
    FieldComponents(zero(SVector{3, T}),
                    zero(SVector{3, T}),
                    zero(SVector{3, T}))
end
                                             

function Base.:+(f1::FieldComponents, f2::FieldComponents)
    FieldComponents(f1.static .+ f2.static,
                    f1.induction .+ f2.induction,
                    f1.radiation .+ f2.radiation)
end

function Base.:*(a::Real, f::FieldComponents)
    FieldComponents(a * f.static,
                    a * f.induction,
                    a * f.radiation)
end

Base.:*(f::FieldComponents, a::Real) = a * f


total(f::FieldComponents) = f.static .+ f.induction .+ f.radiation
static(f::FieldComponents) = f.static
induction(f::FieldComponents) = f.induction
radiation(f::FieldComponents) = f.radiation

# Go-through functions
total(v::Vector{<:FieldComponents})  = hcat([total(f) for f in v]...)
static(v::Vector{<:FieldComponents})  = hcat([static(f) for f in v]...)
induction(v::Vector{<:FieldComponents})  = hcat([induction(f) for f in v]...)
radiation(v::Vector{<:FieldComponents})  = hcat([radiation(f) for f in v]...)

static(v::Vector{<:FieldComponents}, i::Int)  = [static(f)[i] for f in v]
induction(v::Vector{<:FieldComponents}, i::Int)  = [induction(f)[i] for f in v]
radiation(v::Vector{<:FieldComponents}, i::Int)  = [radiation(f)[i] for f in v]
total(v::Vector{<:FieldComponents}, i::Int)  = [
    static(f)[i] + induction(f)[i] + radiation(f)[i] for f in v]
