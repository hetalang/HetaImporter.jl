"""
    HetaParameters(tunable, nderived, ndiscrete, initialize_parameters!)

Runtime parameter storage used by the native Julia backend. `tunable` contains
the flat values exposed to optimizers, `derived` contains values recalculated
from tunables at the start of a solve, and `discrete` contains values that
callbacks may mutate during integration.

`initialize_parameters!(derived, discrete, tunable)` is generated with the
model. It is called by the constructor and whenever the `Tunable` portion is
replaced. Replacing only the `Discrete` portion restores values saved during
a simulation without reinitializing them.
"""
struct HetaParameters{
  T<:AbstractVector,
  R<:AbstractVector,
  D<:AbstractVector,
  F,
}
  tunable::T
  derived::R
  discrete::D
  initialize_parameters!::F
end

function HetaParameters(
  tunable::AbstractVector,
  nderived::Integer,
  ndiscrete::Integer,
  initialize_parameters!,
)
  nderived >= 0 || throw(ArgumentError("nderived must be non-negative"))
  ndiscrete >= 0 || throw(ArgumentError("ndiscrete must be non-negative"))
  derived = Vector{eltype(tunable)}(undef, nderived)
  discrete = Vector{eltype(tunable)}(undef, ndiscrete)
  initialize_parameters!(derived, discrete, tunable)
  return HetaParameters(tunable, derived, discrete, initialize_parameters!)
end

function _heta_reinitialize_parameters(p::HetaParameters, tunable::AbstractVector)
  derived = Vector{eltype(tunable)}(undef, length(p.derived))
  discrete = Vector{eltype(tunable)}(undef, length(p.discrete))
  p.initialize_parameters!(derived, discrete, tunable)
  return derived, discrete
end

function _heta_reinitialize_parameters!(p::HetaParameters)
  p.initialize_parameters!(p.derived, p.discrete, p.tunable)
  return p
end

Base.copy(p::HetaParameters) = HetaParameters(
  copy(p.tunable),
  copy(p.derived),
  copy(p.discrete),
  p.initialize_parameters!,
)
Base.length(p::HetaParameters) = length(p.tunable) + length(p.derived) + length(p.discrete)

function Base.getindex(p::HetaParameters, i::Integer)
  i <= length(p.tunable) && return p.tunable[i]
  i -= length(p.tunable)
  i <= length(p.derived) && return p.derived[i]
  return p.discrete[i - length(p.derived)]
end

function Base.setindex!(p::HetaParameters, value, i::Integer)
  if i <= length(p.tunable)
    p.tunable[i] = value
    _heta_reinitialize_parameters!(p)
  else
    i -= length(p.tunable)
    if i <= length(p.derived)
      p.derived[i] = value
    else
      p.discrete[i - length(p.derived)] = value
    end
  end
  return value
end

SII.parameter_values(p::HetaParameters) = p
SII.parameter_values(p::HetaParameters, i::Integer) = p[i]

SciMLStructures.isscimlstructure(::HetaParameters) = true
SciMLStructures.ismutablescimlstructure(::HetaParameters) = true

SciMLStructures.hasportion(::SciMLStructures.Tunable, ::HetaParameters) = true
SciMLStructures.hasportion(::SciMLStructures.Constants, ::HetaParameters) = true
SciMLStructures.hasportion(::SciMLStructures.Discrete, ::HetaParameters) = true
SciMLStructures.hasportion(::SciMLStructures.AbstractPortion, ::HetaParameters) = false

function SciMLStructures.canonicalize(::SciMLStructures.Tunable, p::HetaParameters)
  repack = values -> SciMLStructures.replace(SciMLStructures.Tunable(), p, values)
  return p.tunable, repack, true
end

function SciMLStructures.replace(
  ::SciMLStructures.Tunable,
  p::HetaParameters,
  values::AbstractVector,
)
  derived, discrete = _heta_reinitialize_parameters(p, values)
  return HetaParameters(values, derived, discrete, p.initialize_parameters!)
end

function SciMLStructures.replace!(::SciMLStructures.Tunable, p::HetaParameters, values)
  copyto!(p.tunable, values)
  _heta_reinitialize_parameters!(p)
  return nothing
end

function SciMLStructures.canonicalize(::SciMLStructures.Constants, p::HetaParameters)
  repack = values -> SciMLStructures.replace(SciMLStructures.Constants(), p, values)
  return p.derived, repack, true
end

SciMLStructures.replace(::SciMLStructures.Constants, p::HetaParameters, values) =
  HetaParameters(p.tunable, values, p.discrete, p.initialize_parameters!)

function SciMLStructures.replace!(::SciMLStructures.Constants, p::HetaParameters, values)
  copyto!(p.derived, values)
  return nothing
end

function SciMLStructures.canonicalize(::SciMLStructures.Discrete, p::HetaParameters)
  repack = values -> SciMLStructures.replace(SciMLStructures.Discrete(), p, values)
  return p.discrete, repack, true
end

SciMLStructures.replace(::SciMLStructures.Discrete, p::HetaParameters, values) =
  HetaParameters(p.tunable, p.derived, values, p.initialize_parameters!)

function SciMLStructures.replace!(::SciMLStructures.Discrete, p::HetaParameters, values)
  copyto!(p.discrete, values)
  return nothing
end
