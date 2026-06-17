
"""
    load_dynms_platform(dynms_json::AbstractString; save_julia=nothing)

Load a DynMS JSON file and return a `Platform`.

The DynMS expressions are compiled to Julia functions at load time using
RuntimeGeneratedFunctions.jl. If `save_julia` is a path, a readable Julia source
file is written for debugging.
"""
function load_dynms_platform(dynms_json::AbstractString; backend=:julia, save_julia=nothing)
  return load_dynms_platform(parse_dynms_platform(dynms_json); save_julia)
end

function load_dynms_platform(dynms_platform::DynMSPlatform; save_julia=nothing)
  platform_data = _platform_tuple(dynms_platform)
  !isnothing(save_julia) && write_dynms_julia(platform_data, save_julia)
  return Platform(platform_data...)
end

"""
    load_dynms_model(dynms_json::AbstractString; kwargs...)

Load the first non-empty model from a DynMS JSON file.
"""
function load_dynms_model(dynms_json::AbstractString; kwargs...)
  platform = load_dynms_platform(dynms_json; kwargs...)
  return [values(platform.models)...][1]
end


# Convert DynMSPlatform to the tuple returned by generated `model.jl` file.
function _platform_tuple(dynms::DynMSPlatform)
  models_nt = (; (
    model.id => _dynms_model_tuple(model)
    for model in values(dynms.models)
  )...)

  return (models_nt, (), dynms.version)
end


"""
    write_dynms_julia(dynms_json, julia_path)

Write readable Julia code generated from DynMS JSON. This is intended for
debugging and review; `load_dynms_platform` compiles the same function bodies
in memory and does not include the written file.
"""
function write_dynms_julia(dynms_json::AbstractString, julia_path::AbstractString)
  
  return write_dynms_julia(parse_dynms_platform(dynms_json), julia_path)
end

function write_dynms_julia(data::AbstractDict, julia_path::AbstractString)
  return write_dynms_julia(parse_dynms_platform(data), julia_path)
end

function write_dynms_julia(dynms::DynMSPlatform, julia_path::AbstractString)
  return write_dynms_julia(_platform_tuple(dynms), julia_path)
end

function write_dynms_julia(dynms::DynMSPlatform, platform_data::Tuple, julia_path::AbstractString)
  dir = dirname(julia_path)
  !isempty(dir) && mkpath(dir)
  open(julia_path, "w") do io
    print(io, _dynms_platform_source(dynms, platform_data))
  end
  return julia_path
end

function _dynms_model_tuple(dynms::DynMSModel)
  
  constants_num = NamedTuple(dynms.constants)
  statics_id = Tuple(keys(dynms.statics))
  records_output = (; (obs => true for obs in dynms.observables)...)
  events_active = (; (k => is_active(v) for (k, v) in merge_events(dynms))...)
  dynamic_nonss = (; (k => !is_algebraic(v) for (k, v) in dynms.states)...)

  return (
    _dynms_runtime_function(_dynms_init_function(dynms)),
    _dynms_runtime_function(_dynms_ode_function(dynms)),
    _dynms_events_namedtuple(dynms, dynms.time_events),
    _dynms_events_namedtuple(dynms, dynms.continuous_events),
    _dynms_events_namedtuple(dynms, dynms.discrete_events),
    _dynms_events_namedtuple(dynms, dynms.stop_events),
    _dynms_saving_generator(dynms),
    constants_num,
    statics_id,
    events_active,
    records_output,
    dynamic_nonss
  )
end

function _dynms_namedtuple(ids::AbstractVector, values)
  return NamedTuple{Tuple(Symbol.(ids))}(Tuple(values))
end

function _dynms_runtime_function(func::DynMSFunction)
  return RuntimeGeneratedFunctions.RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, _dynms_lambda(func))
end

function _dynms_runtime_function(ex::Expr)
  return RuntimeGeneratedFunctions.RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex)
end

function _dynms_lambda(func::DynMSFunction)
  return _dynms_lambda(func.args, func.body)
end

function _dynms_lambda(args::Vector{Symbol}, body)
  return Expr(:->, Expr(:tuple, args...), body)
end

function _dynms_function(name::Symbol, args::Vector{Symbol}, stmts)
  return DynMSFunction(name, args, Expr(:block, stmts...))
end

function _dynms_init_function(dynms::DynMSModel)
  stmts = [:(t = 0.0)]
  _add_dynms_constant_bindings!(stmts, dynms)

  for (id, state) in dynms.states
    push!(stmts, Expr(:(=), id, state.initial))
  end
  for (id, static_initial) in dynms.statics
    push!(stmts, Expr(:(=), id, static_initial))
  end

  for (i, id) in enumerate(keys(dynms.states))
    push!(stmts, :(__u0__[$i] = $id))
  end
  for (i, id) in enumerate(keys(dynms.statics))
    push!(stmts, :(__p0__[$i] = $id))
  end

  push!(stmts, :(return nothing))
  return _dynms_function(Symbol(dynms.id, "_init_func_!"), [:__u0__, :__p0__, :__constants__], stmts)
end

function _dynms_ode_function(dynms::DynMSModel)
  stmts = []
  _add_dynms_header_bindings!(stmts, dynms; integrator_p=false)
  _add_dynms_assignment_bindings!(stmts, dynms)

  for (i, state) in enumerate(values(dynms.states))
    push!(stmts, :(__du__[$i] = $(state.equation)))
  end

  push!(stmts, :(return nothing))
  return _dynms_function(Symbol(dynms.id, "_ode_func_"), [:__du__, :__u__, :__p__, :t], stmts)
end

function _dynms_saving_generator(dynms::DynMSModel)
  record_ids = dynms.observables
  cache = Dict{Tuple{Vararg{Symbol}},Any}()

  function saving_generator(__outputIds__::Vector{Symbol})
    wrong_ids = setdiff(__outputIds__, record_ids)
    !isempty(wrong_ids) && throw("The following observables have not been found in the model's Records: $(wrong_ids)")

    output_key = Tuple(__outputIds__)
    return get!(cache, output_key) do
      _dynms_runtime_function(_dynms_saving_function(dynms, __outputIds__))
    end
  end
end

function _dynms_saving_function(dynms::DynMSModel, output_ids::Vector{Symbol})
  stmts = []
  _add_dynms_header_bindings!(stmts, dynms; integrator_p=true)
  _add_dynms_assignment_bindings!(stmts, dynms)

  for (i, obs) in enumerate(output_ids)
    push!(stmts, :(__out__[$i] = $obs))
  end

  push!(stmts, :(return nothing))
  return _dynms_function(Symbol(dynms.id, "_saving_func_"), [:__out__, :__u__, :t, :__integrator__], stmts)
end

_dynms_events_namedtuple(dynms::DynMSModel, events_dict) =
  (; (k => _dynms_event_tuple(dynms, v) for (k, v) in events_dict)...)


function _dynms_event_tuple(dynms::DynMSModel, event::DynMSTimeEvent)
  tstops_function = _dynms_runtime_function(_dynms_tstops_function(dynms, event))
  affect! = _dynms_runtime_function(_dynms_affect_function(dynms, event))
  at_start = has_initial_affect(event)

  return (tstops_function, affect!, at_start)
end

function _dynms_event_tuple(dynms::DynMSModel, event::Union{DynMSContinuousEvent, DynMSDiscreteEvent})
  condition = _dynms_runtime_function(_dynms_condition_function(dynms, event))
  affect! = _dynms_runtime_function(_dynms_affect_function(dynms, event))
  at_start = has_initial_affect(event)

  return (condition, affect!, at_start)
end

function _dynms_event_tuple(dynms::DynMSModel, event::DynMSStopEvent)
  condition = _dynms_runtime_function(_dynms_condition_function(dynms, event))
  at_start = has_initial_affect(event)

  return (condition, at_start)
end

function _dynms_tstops_function(dynms::DynMSModel, event::DynMSTimeEvent)

  stmts = []
  _add_dynms_constant_bindings!(stmts, dynms)

  if isnothing(event.period)
    push!(stmts, :(return [$(event.start)]))
  elseif isnothing(event.stop)
    push!(stmts, :(return collect(range($(event.start), __times__[2]; step=$(event.period)))))
  else
    push!(stmts, :(return collect(range($(event.start), $(event.stop); step=$(event.period)))))
  end

  return _dynms_function(
    Symbol(dynms.id, "_", event_id(event), "_tstops_func_"),
    [:__constants__, :__times__],
    stmts
  )
end

function _dynms_condition_function(dynms::DynMSModel, event::Union{DynMSContinuousEvent, DynMSDiscreteEvent})
  stmts = []
  _add_dynms_header_bindings!(stmts, dynms; integrator_p=true)
  _add_dynms_assignment_bindings!(stmts, dynms)
 
  push!(stmts, :(return $(event.condition)))
  return _dynms_function(
    Symbol(dynms.id, "_", event_id(event), "_condition_func_"),
    [:__u__, :t, :__integrator__],
    stmts
  )
end

function _dynms_affect_function(dynms::DynMSModel, event)
  stmts = [:(t = __integrator__.t)]
  _add_dynms_header_bindings!(stmts, dynms; integrator_p=true, integrator_u=true)
  _add_dynms_assignment_bindings!(stmts, dynms)

  state_index = Dict(id => i for (i, id) in enumerate(keys(dynms.states)))
  static_index = Dict(id => i for (i, id) in enumerate(keys(dynms.statics)))

  for (id, rhs_expr) in event.state_affects
    idx = state_index[id]
    push!(stmts, :(__integrator__.u[$idx] = $rhs_expr))
  end
  for (id, rhs_expr) in event.discrete_affects
    idx = static_index[id]
    push!(stmts, :(__integrator__.p[$idx] = $rhs_expr))
  end

  push!(stmts, :(return nothing))
  return _dynms_function(
    Symbol(dynms.id, "_", event_id(event), "_affect_func_"),
    [:__integrator__],
    stmts
  )
end

_add_dynms_constant_bindings!(stmts, dynms::DynMSModel) =
  push!(stmts, :( $(Expr(:tuple, keys(dynms.constants)...)) = __constants__ ))

function _add_dynms_header_bindings!(stmts, dynms::DynMSModel; integrator_p::Bool=false, integrator_u::Bool=false)
  if integrator_p
    push!(stmts, :( $(Expr(:tuple, keys(dynms.statics)...)) = __integrator__.p.x[1] ))
    push!(stmts, :( $(Expr(:tuple, keys(dynms.constants)...)) = __integrator__.p.x[2] ))
  else
    push!(stmts, :( $(Expr(:tuple, keys(dynms.statics)...)) = __p__.x[1] ))
    push!(stmts, :( $(Expr(:tuple, keys(dynms.constants)...)) = __p__.x[2] ))
  end
  if integrator_u
    push!(stmts, :( $(Expr(:tuple, keys(dynms.states)...)) = __integrator__.u ))
  else
    push!(stmts, :( $(Expr(:tuple, keys(dynms.states)...)) = __u__ ))
  end

  return nothing
end

function _add_dynms_assignment_bindings!(stmts, dynms::DynMSModel)
  for (r,rule) in dynms.assignment_rules
    push!(stmts, Expr(:(=), r, rule))
  end
  return nothing
end

######################### DynMS source Julia code generation #########################


function _dynms_platform_source(dynms::DynMSPlatform, dynms_tuple::Tuple)
  io = IOBuffer()
  println(io, "#=")
  println(io, "    This code was generated from DynMS JSON by HetaImporter $(pkgversion(@__MODULE__))")
  println(io, "=#")
  println(io)
  println(io, "(function()")
  println(io)

  for model in values(dynms.models)
    _dynms_model_source(io, model, dynms_tuple)
  end

  println(io, "return (")
  println(io, "  (")
  for model in values(dynms.models)
    println(io, "    $(model.id) = $(model.id)_model_,")
  end
  println(io, "  ),")
  println(io, "  (),")
  println(io, "  ", repr(dynms.version))
  println(io, ")")
  println(io)
  println(io, "end)()")

  return String(take!(io))
end

function _dynms_model_source(io::IO, dynms::DynMSModel, dynms_tuple::Tuple)

end
