export total, stat, ind, rad

struct FieldComponents{T}
    stat::SVector{3, T}
    ind::SVector{3, T}
    rad::SVector{3, T}
end


function Base.zero(::Type{FieldComponents{T}}) where T
    FieldComponents(zero(SVector{3, T}),
                    zero(SVector{3, T}),
                    zero(SVector{3, T}))
end
                                             

function Base.:+(f1::FieldComponents, f2::FieldComponents)
    FieldComponents(f1.stat .+ f2.stat,
                    f1.ind .+ f2.ind,
                    f1.rad .+ f2.rad)
end
                    

total(f::FieldComponents) = f.stat .+ f.ind .+ f.rad
stat(f::FieldComponents) = f.stat
ind(f::FieldComponents) = f.ind
rad(f::FieldComponents) = f.rad

# Go-through functions
total(v::Vector{<:FieldComponents})  = hcat([total(f) for f in v]...)
stat(v::Vector{<:FieldComponents})  = hcat([stat(f) for f in v]...)
ind(v::Vector{<:FieldComponents})  = hcat([ind(f) for f in v]...)
rad(v::Vector{<:FieldComponents})  = hcat([rad(f) for f in v]...)

stat(v::Vector{<:FieldComponents}, i::Int)  = [stat(f)[i] for f in v]
ind(v::Vector{<:FieldComponents}, i::Int)  = [ind(f)[i] for f in v]
rad(v::Vector{<:FieldComponents}, i::Int)  = [rad(f)[i] for f in v]
total(v::Vector{<:FieldComponents}, i::Int)  =[stat(f)[i] + ind(f)[i] + rad(f)[i]
                                             for f in v]
