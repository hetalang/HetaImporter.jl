"""
    HetaODESystem

Native Julia representation of a parsed Heta ODE model. `dynms` retains the
semantic model for inspection and `generated_code` contains the fixed,
uncompiled Julia functions generated once by [`build_ode_system`](@ref).

`parameter_index` indexes the complete flattened parameter container (tunables
followed by discretes). `discrete_index` indexes only the discrete portion and
is also used as its parameter-timeseries index.
"""
struct HetaODESystem{GC}
  name::Symbol
  dynms::DynMSModel
  state_index::Dict{Symbol,Int}
  parameter_index::Dict{Symbol,Int}
  discrete_index::Dict{Symbol,Int}
  generated_code::GC
end

function Base.show(io::IO, system::HetaODESystem)
  return print(io, "HetaODESystem(", repr(system.name), ")")
end

function Base.show(io::IO, ::MIME"text/plain", system::HetaODESystem)
  get(io, :compact, false) && return show(io, system)

  dynms = system.dynms
  code = system.generated_code
  n_tunable = length(dynms.parameters.tunable)
  n_discrete = length(dynms.parameters.discrete)
  n_time = length(code.time_events)
  n_continuous = length(code.continuous_events)
  n_discrete_events = length(code.discrete_events)
  n_stop = length(code.stop_events)
  n_events = n_time + n_continuous + n_discrete_events + n_stop

  println(io, "HetaODESystem `$(system.name)`")
  println(io, "  States:     ", length(dynms.states))
  println(io, "  Parameters: ", n_tunable + n_discrete,
    " (", n_tunable, " tunable, ", n_discrete, " discrete)")
  println(io, "  Observed:   ", length(dynms.assignment_rules))
  print(io, "  Events:     ", n_events,
    " (", n_time, " time, ", n_continuous, " continuous, ",
    n_discrete_events, " discrete, ", n_stop, " stop)")
  return nothing
end

"""
    build_ode_system(model; write_to_file=false, filename=nothing)
    build_ode_system(model_set; model_id, kwargs...)

Lower a parsed DynMS model to a native [`HetaODESystem`](@ref).

When `write_to_file=true`, readable Julia source for the resulting system is
also written to `filename`.
"""
build_ode_system(model::DynMSModel; kwargs...) =
  _build_ode_system(model; kwargs...)

function build_ode_system(
  model_set::DynMSModelSet;
  model_id::Union{Symbol,Nothing}=nothing,
  kwargs...,
)
  if model_id === nothing
    length(model_set.models) == 1 || throw(ArgumentError(
      "model_id must be provided when Heta contains more than one model",
    ))
    model_id = first(keys(model_set.models))
  end
  haskey(model_set.models, model_id) || throw(ArgumentError(
    "model_id $model_id not found in model_set",
  ))
  return build_ode_system(model_set.models[model_id]; kwargs...)
end

"""
    import_heta(heta_dir; model_id=nothing, write_to_file=false,
                filename=nothing, kwargs...)

Compile a Heta project, parse it, and lower the selected model to a
native [`HetaODESystem`](@ref). Remaining keyword arguments are forwarded to
[`parse_heta`](@ref).
"""
function import_heta(
  heta_dir::AbstractString;
  model_id::Union{Symbol,Nothing}=nothing,
  write_to_file::Bool=false,
  filename::Union{AbstractString,Nothing}=nothing,
  kwargs...,
)
  model_set = parse_heta(heta_dir; kwargs...)
  return build_ode_system(
    model_set;
    model_id,
    write_to_file,
    filename,
  )
end

"""
    import_heta_all(heta_dir; write_to_file=false, output_dir=".", kwargs...)

Compile a Heta project and return every model as an
`OrderedDict{Symbol,<:HetaODESystem}` keyed by model ID. Remaining keyword
arguments are forwarded to [`parse_heta`](@ref).

When `write_to_file=true`, readable generated code is written to
`<output_dir>/<model_id>_ode.jl` for each system.
"""
function import_heta_all(
  heta_dir::AbstractString;
  write_to_file::Bool=false,
  output_dir::AbstractString=".",
  kwargs...,
)
  model_set = parse_heta(heta_dir; kwargs...)
  return OrderedDict(
    id => build_ode_system(
      model;
      write_to_file,
      filename=write_to_file ? joinpath(output_dir, "$(id)_ode.jl") : nothing,
    )
    for (id, model) in model_set.models
  )
end
