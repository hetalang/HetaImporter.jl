"""
    HetaParameters(tunable, ndiscrete, initialize_discrete!)

Runtime parameter storage used by the native Julia backend. `tunable` contains
the flat values exposed to optimizers and `discrete` contains the initialized
values that callbacks may mutate during integration.

`initialize_discrete!(discrete, tunable)` is generated with the model. It is
called by the constructor and whenever the `Tunable` portion is replaced, so a
new optimization point always starts with discrete values consistent with its
tunables. Replacing only the `Discrete` portion does not call it, because that
operation is used to restore values saved during a simulation.
"""
struct HetaParameters{
  T<:AbstractVector,
  D<:AbstractVector,
  F,
}
  tunable::T
  discrete::D
  initialize_discrete!::F
end

function HetaParameters(
  tunable::AbstractVector,
  ndiscrete::Integer,
  initialize_discrete!,
)
  ndiscrete >= 0 || throw(ArgumentError("ndiscrete must be non-negative"))
  discrete = Vector{eltype(tunable)}(undef, ndiscrete)
  initialize_discrete!(discrete, tunable)
  return HetaParameters(tunable, discrete, initialize_discrete!)
end

function _heta_reinitialize_discrete(p::HetaParameters, tunable::AbstractVector)
  discrete = Vector{eltype(tunable)}(undef, length(p.discrete))
  p.initialize_discrete!(discrete, tunable)
  return discrete
end

function _heta_reinitialize_discrete!(p::HetaParameters)
  p.initialize_discrete!(p.discrete, p.tunable)
  return p
end

Base.copy(p::HetaParameters) = HetaParameters(
  copy(p.tunable),
  copy(p.discrete),
  p.initialize_discrete!,
)
Base.length(p::HetaParameters) = length(p.tunable) + length(p.discrete)

function Base.getindex(p::HetaParameters, i::Integer)
  i <= length(p.tunable) && return p.tunable[i]
  return p.discrete[i - length(p.tunable)]
end

function Base.setindex!(p::HetaParameters, value, i::Integer)
  if i <= length(p.tunable)
    p.tunable[i] = value
    _heta_reinitialize_discrete!(p)
  else
    p.discrete[i - length(p.tunable)] = value
  end
  return value
end

SII.parameter_values(p::HetaParameters) = p

SciMLStructures.isscimlstructure(::HetaParameters) = true
SciMLStructures.ismutablescimlstructure(::HetaParameters) = true

SciMLStructures.hasportion(::SciMLStructures.Tunable, ::HetaParameters) = true
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
  discrete = _heta_reinitialize_discrete(p, values)
  return HetaParameters(values, discrete, p.initialize_discrete!)
end

function SciMLStructures.replace!(::SciMLStructures.Tunable, p::HetaParameters, values)
  copyto!(p.tunable, values)
  _heta_reinitialize_discrete!(p)
  return nothing
end

function SciMLStructures.canonicalize(::SciMLStructures.Discrete, p::HetaParameters)
  repack = values -> SciMLStructures.replace(SciMLStructures.Discrete(), p, values)
  return p.discrete, repack, true
end

SciMLStructures.replace(::SciMLStructures.Discrete, p::HetaParameters, values) =
  HetaParameters(p.tunable, values, p.initialize_discrete!)

function SciMLStructures.replace!(::SciMLStructures.Discrete, p::HetaParameters, values)
  copyto!(p.discrete, values)
  return nothing
end