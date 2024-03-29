module DipoleRadiators

export fields, total, mtle, BiGaussianCurrent, CurrentPulse, TLDipole, image
export SplineCurrent

using StaticArrays
using LinearAlgebra
using Parameters
using Interpolations
using SpecialFunctions: erf
using ForwardDiff: derivative
import Dierckx

include("cumtrapz.jl")
include("fieldcomponents.jl")

const ε_0 = 8.8541878128e-12
const c_0 = 2.99792458e8
    
abstract type AbstractDipole end
abstract type AbstractCurrent end


"""
Almost-general dipole element of a transmission line.  It includes a location
`r`, a length vector `l`, an attenuation factor `w` and a delay time
`τ` as well as an instance of the current with τ=0 and w=1.
"""
struct TLDipole{T,I} <: AbstractDipole
    # Location of the dipole
    r::SVector{3, T}

    # Vector from r to the end of the dipole
    l::SVector{3, T}

    # Attenuation factor
    w::T

    # Delay time
    τ::T

    # Current instance to determine the current with τ=0, w=1.
    pulse::I
end


pos(dip::TLDipole) = dip.r
lvec(dip::TLDipole) = dip.l

function image(dip::TLDipole, z=0)
    TLDipole(@SVector([dip.r[1], dip.r[2], 2 * z - dip.r[3]]),
             @SVector([-dip.l[1], -dip.l[2], dip.l[3]]),
             dip.w,
             dip.τ,
             dip.pulse)
end

image(tl::Vector{<:AbstractDipole}, z=0) = [image(d, z) for d in tl]


"""
   mtle(pulse::AbstractCurrent, r0, r1, v, λ, n; mirror=false)

Builds a MTLE transmission line as a combination of dipoles `n` dipoles. 
`pulse` is the current pulse.  `r0` and `r1` are the injection and the end 
point of the TL, `v` is the propagation velocity of the current pulse, 
`λ` is the attenuation length.  If `mirror` is true, adds an image TL
considering that z=0 is the surface of a perfect conductor.

To join several MTLEs easily we allow an extra constant attenuation `w0`
and an extra delay `t0`.
"""
function mtle(pulse::AbstractCurrent, r0, r1, v, λ, n;
              mirror=false, w0=1.0, t0=0.0)
    L = norm(r1 .- r0)

    # Vector from one dipole to the next
    d = (r1 .- r0) ./ n
    
    tl = map(1:n) do i
        # midpoint of the dipole
        r = r0 .+ (i - .5) .* d

        # Distance to the injection point
        s = (i - 1) * L / n

        # Delay
        τ = s / v + t0

        # Attenuation
        w = w0 * exp(-s / λ)

        TLDipole(r, d, w, τ, pulse)
    end

    if mirror
        tl1 = image(tl)
        tl = vcat(tl, tl1)
    end
    tl
end


"""
A `Propagator` struct contains the data to quickly compute the field created
by some dipole at some location.
"""
struct Propagator{T}
    # Vectors to indicate the direction and magnitude of the three
    # field components (electrostatic, ...)
    v::FieldComponents{T}

    # Time delay
    Δt::T
end


function Propagator(d::AbstractDipole, robs::AbstractVector)
    mats = directionalmats(d, robs)
    v = FieldComponents(mats[1] * lvec(d),
                        mats[2] * lvec(d),
                        mats[3] * lvec(d))
    Δt = proptime(d, robs)
    Propagator(v, Δt)
end


"""
Computes the matrices that give the three components of the electric field 
at `robs` generated by the dipole `d`.
"""
function directionalmats(d::AbstractDipole, robs)
    r = robs .- pos(d)
    n = normalize(r)
    rabs = norm(r)
    
    # This builds a matrix such that nn[i, j] = nn[i] * nn[j]
    nn = n * n'

    # Electrostatic, induction, radiation fields
    ((3nn - I) ./ (4π * ε_0 * rabs^3),
     (3nn - I) ./ (4π * ε_0 * rabs^2 * c_0),
     (nn - I) ./ (4π * ε_0 * rabs^1 * c_0^2)) 
end


"""
Propagation time from the dipole location to robs.
"""
function proptime(d::AbstractDipole, robs)
    norm(pos(d) .- robs) / c_0
end


function remotefield(d::AbstractDipole, prop::Propagator, t)
    @unpack w, τ, pulse = d
    @unpack Δt, v = prop
    
    #electrostatic, induction, radiation fields
    estat = w * icurrent(pulse, t - τ - Δt) * v.static
    eind = w * current(pulse, t - τ - Δt) * v.induction
    erad = w * dcurrent(pulse, t - τ - Δt) * v.radiation

    FieldComponents(estat, eind, erad)
end



"""
An arbitrary current pulse.
"""
struct (CurrentPulse{T, F <: Function, I <: AbstractInterpolation}
        <: AbstractCurrent)

    "Function containing the current pulse."
    func::F

    "Smallest time considered"
    mint::T
    
    "Largest time considered in the integration."    
    maxt::T

    "Time interval in the interpolation of the integration."
    dt::T

    intinterp::I
end


function CurrentPulse(func, mint, maxt, dt)
    t = range(mint, stop=maxt + dt, step=dt)
    f = map(func, t)
    r = cumtrapz(t, f)

    CurrentPulse(func, mint, maxt, dt, LinearInterpolation(t, r))
end


function current(pulse::CurrentPulse{T,F,I}, t) where {T,F,I}
    typ = promote_type(T, typeof(t))
    (t <= pulse.mint) && return zero(typ)

    pulse.func(t)::typ
end

function dcurrent(pulse::CurrentPulse{T,F,I}, t) where {T,F,I}
    typ = promote_type(T, typeof(t))
    (t <= pulse.mint) && return zero(typ)

    derivative(pulse.func, t)::typ
end

function icurrent(pulse::CurrentPulse{T,F,I}, t) where {T,F,I}
    typ = promote_type(T, typeof(t))
    (t <= pulse.mint) && return zero(typ)

    (t > pulse.maxt) && (t = pulse.maxt)
    pulse.intinterp(t)
end



"""
A current pulse with a bi-gaussian profile.
"""
struct BiGaussianCurrent{T} <: AbstractCurrent
    "Pulse amplitude."
    I0::T

    "Time-scale of the decaying term. "
    τ1::T

    "Time-scale of the increasing term."
    τ2::T
end


function current(pulse::BiGaussianCurrent{T}, t) where T
    typ = promote_type(T, typeof(t))
    (t <= 0) && return zero(typ)

    @unpack I0, τ1, τ2 = pulse
    I0 * (exp(-t^2 / τ1^2) - exp(-t^2 / τ2^2))
end

function dcurrent(pulse::BiGaussianCurrent{T}, t) where T
    typ = promote_type(T, typeof(t))
    (t <= 0) && return zero(typ)

    @unpack I0, τ1, τ2 = pulse
    I0 * (-2t * exp(-t^2 / τ1^2) / τ1^2 + 2t * exp(-t^2 / τ2^2) / τ2^2)
end

function icurrent(pulse::BiGaussianCurrent{T}, t) where T
    typ = promote_type(T, typeof(t))
    (t <= 0) && return zero(typ)

    @unpack I0, τ1, τ2 = pulse
    0.5 * sqrt(π) * I0 * (τ1 * erf(t / τ1) + τ2 * erf(t / τ2))
end


"""
A current pulse with a profile given by discrete times and values.
The integral and derivative are then computed numerically.
"""
struct SplineCurrent <: AbstractCurrent
    curr::Dierckx.Spline1D

    tmin::Float64
    tmax::Float64
end

function SplineCurrent(t, i)
    tmin, tmax = extrema(t)
    SplineCurrent(Dierckx.Spline1D(t, i), tmin, tmax)    
end


current(p::SplineCurrent, t) = (p.tmin < t < p.tmax) ? p.curr(t) : 0.0
dcurrent(p::SplineCurrent, t) = (p.tmin < t < p.tmax) ? Dierckx.derivative(p.curr, t) : 0.0
icurrent(p::SplineCurrent, t) = Dierckx.integrate(p.curr, p.tmin, clamp(t, p.tmin, p.tmax))

# Poor's man implementation of a fill-array
struct FillOnes; end
@inline Base.getindex(::FillOnes, k::Int) = 1


"""
    Compute the fields created by the transmission line `tl` at observation point `robs`
    and times in vector `t`.
"""
function fields(tl::AbstractVector{<:AbstractDipole}, robs, t, f=FillOnes())
    e = zeros(FieldComponents{eltype(t)}, length(t))
    fields!(e, tl, robs, t)
end


"""
    Compute fields and store them in a pre-allocated array `e`.  Optionally `f` multiplies
    the effect of the dipole with index `i` in the line by a factor `f[i]` (defaults to 1).
    If provided, `props` is a vector with pre-allocated space for `Propagator` instances.
"""
function fields!(e, tl::Vector{<:AbstractDipole}, robs, t, f=FillOnes(); props=nothing)
    if isnothing(props)
        props = [Propagator(d, robs) for d in tl]
    else
        @assert size(tl) == size(props) "props must have the same size as the transmission line"

        for i in eachindex(tl)
            props[i] = Propagator(tl[i], robs)
        end
    end
    
    for i in eachindex(t)
        for j in eachindex(tl)
            e[i] += remotefield(tl[j], props[j], t[i]) * f[j]
        end
    end
    e
end


@generated function fields!(e, tpl::T, robs, t) where T <: Tuple
    L = fieldcount(T)

    out = quote end

    for i in 1:L
        push!(out.args,
              quote
              fields!(e, tpl[$i], robs, t)
              end
              )
    end
    push!(out.args, :(return e))
    
    out
end

function fields(tpl::Tuple, robs, t)
    e = zeros(FieldComponents{eltype(t)}, length(t))
    fields!(e, tpl, robs, t)
end


end # module
