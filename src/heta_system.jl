"""
    HetaODESystem

Native Julia representation of a parsed Heta ODE model. `dynms` retains the
semantic model for inspection and `generated_code` contains the fixed,
uncompiled Julia functions generated once by [`build_ode_system`](@ref).
Functions are generated for all events, including those inactive by default;
event activation is resolved separately for each `ODEProblem`.

`parameter_index` indexes the complete flattened parameter container (tunables,
derived, then discretes). `discrete_index` indexes only the discrete portion and
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
  n_derived = length(dynms.parameters.derived)
  n_discrete = length(dynms.parameters.discrete)
  n_time = length(code.time_events)
  n_continuous = length(code.continuous_events)
  n_discrete_events = length(code.discrete_events)
  n_stop = length(code.stop_events)
  n_events = n_time + n_continuous + n_discrete_events + n_stop

  println(io, "HetaODESystem `$(system.name)`")
  println(io, "  States:     ", length(dynms.states))
  println(io, "  Parameters: ", n_tunable + n_derived + n_discrete,
    " (", n_tunable, " tunable, ", n_derived, " derived, ",
    n_discrete, " discrete)")
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
    import_heta(heta_dir, model_id::Symbol=:nameless; write_to_file=false,
                filename=nothing, build_dir=nothing, nanmath=false, kwargs...)

Compile a Heta project to DynMS and delegate to [`import_dynms`](@ref) to
construct a native [`HetaODESystem`](@ref). Remaining keyword arguments are forwarded to
[`build_dynms_file`](@ref). The selected model defaults to `:nameless` and must exist.

By default, compiler output is stored in a temporary directory that is removed
after import, including on failure. Set `build_dir` to retain compiler output
in a specific directory. 

Set `nanmath=true` to use NaNMath for powers, square roots, and logarithms
throughout the converted model. See [`import_dynms`](@ref).
"""
function import_heta(
  heta_dir::AbstractString,
  model_id::Symbol=:nameless;
  nanmath::Bool=false,
  write_to_file::Bool=false,
  filename::Union{AbstractString,Nothing}=nothing,
  build_dir::Union{AbstractString,Nothing}=nothing,
  kwargs...,
)

  if isnothing(build_dir)
    return mktempdir() do temporary_build_dir
      import_heta(heta_dir, model_id; build_dir=temporary_build_dir,
        nanmath, write_to_file, filename, kwargs...)
    end
  end
  dynms_filepath = build_dynms_file(heta_dir; build_dir, kwargs...)
  return import_dynms(dynms_filepath, model_id; nanmath, write_to_file, filename)
end

"""
    import_dynms(dynms_filepath, model_id::Symbol=:nameless; write_to_file=false,
                 filename=nothing, nanmath=false)

Parse and validate a DynMS JSON file, convert it to a model set, and build the
selected model as a native [`HetaODESystem`](@ref). The selected model defaults
to `:nameless` and must exist.
When `write_to_file=true`, generated
Julia source is also written to `filename`.

With `nanmath=true`, powers, square roots, and `log`, `log10`, and `log2`
calls use NaNMath in all model expressions, including initialization and events.
The converted expressions are also visible through the inspection functions.
"""
function import_dynms(
  dynms_filepath::AbstractString,
  model_id::Symbol=:nameless;
  nanmath::Bool=false,
  write_to_file::Bool=false,
  filename::Union{AbstractString,Nothing}=nothing,
)
  data = parse_dynms(dynms_filepath)
  validate_dynms(data)
  model_set = convert_dynms(data; nanmath)
  return build_ode_system(model_set; model_id, write_to_file, filename)
end

"""
    import_heta_all(heta_dir; write_to_file=false, output_dir=".", nanmath=false, kwargs...)

Compile a Heta project and return every model as an
`OrderedDict{Symbol,<:HetaODESystem}` keyed by model ID. Remaining keyword
arguments are forwarded to [`build_dynms_file`](@ref).

When `write_to_file=true`, readable generated code is written to
`<output_dir>/<model_id>_ode.jl` for each system.
The `nanmath` option applies to every model; see [`import_dynms`](@ref).
"""
function import_heta_all(
  heta_dir::AbstractString;
  nanmath::Bool=false,
  write_to_file::Bool=false,
  output_dir::AbstractString=".",
  kwargs...,
)
  dynms_filepath = build_dynms_file(heta_dir; kwargs...)
  data = parse_dynms(dynms_filepath)
  validate_dynms(data)
  model_set = convert_dynms(data; nanmath)
  return OrderedDict(
    id => build_ode_system(
      model;
      write_to_file,
      filename=write_to_file ? joinpath(output_dir, "$(id)_ode.jl") : nothing,
    )
    for (id, model) in model_set.models
  )
end
