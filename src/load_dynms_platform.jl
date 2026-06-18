
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
  platform_code = _dynms_platform_code(dynms_platform)
  !isnothing(save_julia) && write_dynms_julia(platform_code, save_julia)
  platform_data = _platform_tuple(platform_code)
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


struct DynMSTimeEventCode
  id::Symbol
  tstops_func::DynMSFunction
  affect_func::DynMSFunction
  initial_affect::Bool
end

struct DynMSConditionalEventCode
  id::Symbol
  condition_func::DynMSFunction
  affect_func::DynMSFunction
  initial_affect::Bool
end

struct DynMSStopEventCode
  id::Symbol
  condition_func::DynMSFunction
  initial_affect::Bool
end

struct DynMSSavingGeneratorCode
  name::Symbol
  dynms::DynMSModel
  output_ids::Vector{Symbol}
end

struct DynMSModelCode
  id::Symbol
  init_func::DynMSFunction
  ode_func::DynMSFunction
  time_events::OrderedDict{Symbol,DynMSTimeEventCode}
  continuous_events::OrderedDict{Symbol,DynMSConditionalEventCode}
  discrete_events::OrderedDict{Symbol,DynMSConditionalEventCode}
  stop_events::OrderedDict{Symbol,DynMSStopEventCode}
  saving_generator::DynMSSavingGeneratorCode
  constants_num::NamedTuple
  statics_id::Tuple
  events_active::NamedTuple
  records_output::NamedTuple
  dynamic_nonss::NamedTuple
end

struct DynMSPlatformCode
  models::OrderedDict{Symbol,DynMSModelCode}
  version::String
end


# Convert DynMSPlatform to the generated function definitions used by backends.
function _dynms_platform_code(dynms::DynMSPlatform)
  model_codes = OrderedDict{Symbol,DynMSModelCode}()
  for model in values(dynms.models)
    model_codes[model.id] = _dynms_model_code(model)
  end
  return DynMSPlatformCode(model_codes, dynms.version)
end

function _dynms_model_code(dynms::DynMSModel)
  constants_num = NamedTuple(dynms.constants)
  statics_id = Tuple(keys(dynms.statics))
  output_ids = _dynms_output_ids(dynms)
  record_ids = _dynms_record_ids(dynms, output_ids)
  default_observables = Set(dynms.observables)
  records_output = (; (id => (id in default_observables) for id in record_ids)...)
  events_active = (; (k => is_active(v) for (k, v) in merge_events(dynms))...)
  dynamic_nonss = (; (k => !is_algebraic(v) for (k, v) in dynms.states)...)

  return DynMSModelCode(
    dynms.id,
    _dynms_init_function(dynms),
    _dynms_ode_function(dynms),
    _dynms_time_event_codes(dynms),
    _dynms_continuous_event_codes(dynms),
    _dynms_discrete_event_codes(dynms),
    _dynms_stop_event_codes(dynms),
    DynMSSavingGeneratorCode(Symbol(dynms.id, "_saving_generator_"), dynms, output_ids),
    constants_num,
    statics_id,
    events_active,
    records_output,
    dynamic_nonss
  )
end

function _dynms_output_ids(dynms::DynMSModel)
  ids = Symbol[]
  append!(ids, keys(dynms.statics))
  append!(ids, keys(dynms.assignment_rules))
  append!(ids, keys(dynms.states))
  return unique(ids)
end

function _dynms_record_ids(dynms::DynMSModel, output_ids::Vector{Symbol})
  missing_observables = setdiff(dynms.observables, output_ids)
  isempty(missing_observables) ||
    throw(ArgumentError("DynMS observables must refer to statics, assignment rules, or states. Unknown observables: $(missing_observables)"))

  ids = Symbol[]
  append!(ids, dynms.observables)
  append!(ids, output_ids)
  return unique(ids)
end

function _dynms_time_event_codes(dynms::DynMSModel)
  event_codes = OrderedDict{Symbol,DynMSTimeEventCode}()
  for (id, event) in dynms.time_events
    event_codes[id] = DynMSTimeEventCode(
      id,
      _dynms_tstops_function(dynms, event),
      _dynms_affect_function(dynms, event),
      has_initial_affect(event)
    )
  end
  return event_codes
end

function _dynms_continuous_event_codes(dynms::DynMSModel)
  event_codes = OrderedDict{Symbol,DynMSConditionalEventCode}()
  for (id, event) in dynms.continuous_events
    event_codes[id] = DynMSConditionalEventCode(
      id,
      _dynms_condition_function(dynms, event),
      _dynms_affect_function(dynms, event),
      has_initial_affect(event)
    )
  end
  return event_codes
end

function _dynms_discrete_event_codes(dynms::DynMSModel)
  event_codes = OrderedDict{Symbol,DynMSConditionalEventCode}()
  for (id, event) in dynms.discrete_events
    event_codes[id] = DynMSConditionalEventCode(
      id,
      _dynms_condition_function(dynms, event),
      _dynms_affect_function(dynms, event),
      has_initial_affect(event)
    )
  end
  return event_codes
end

function _dynms_stop_event_codes(dynms::DynMSModel)
  event_codes = OrderedDict{Symbol,DynMSStopEventCode}()
  for (id, event) in dynms.stop_events
    event_codes[id] = DynMSStopEventCode(
      id,
      _dynms_condition_function(dynms, event),
      has_initial_affect(event)
    )
  end
  return event_codes
end


# Convert DynMS code definitions to the tuple returned by generated `model.jl` file.
_platform_tuple(dynms::DynMSPlatform) = _platform_tuple(_dynms_platform_code(dynms))

function _platform_tuple(platform_code::DynMSPlatformCode)
  models_nt = (; (
    model.id => _dynms_model_tuple(model)
    for model in values(platform_code.models)
  )...)

  return (models_nt, (), platform_code.version)
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
  return write_dynms_julia(_dynms_platform_code(dynms), julia_path)
end

function write_dynms_julia(platform_code::DynMSPlatformCode, julia_path::AbstractString)
  dir = dirname(julia_path)
  !isempty(dir) && mkpath(dir)
  open(julia_path, "w") do io
    print(io, _dynms_platform_source(platform_code))
  end
  return julia_path
end

function _dynms_model_tuple(model_code::DynMSModelCode)
  return (
    _dynms_runtime_function(model_code.init_func),
    _dynms_runtime_function(model_code.ode_func),
    _dynms_events_namedtuple(model_code.time_events),
    _dynms_events_namedtuple(model_code.discrete_events),
    _dynms_events_namedtuple(model_code.continuous_events),
    _dynms_events_namedtuple(model_code.stop_events),
    _dynms_saving_generator(model_code.saving_generator),
    model_code.constants_num,
    model_code.statics_id,
    model_code.events_active,
    model_code.records_output,
    model_code.dynamic_nonss
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

_dynms_saving_generator(dynms::DynMSModel) =
  _dynms_saving_generator(DynMSSavingGeneratorCode(Symbol(dynms.id, "_saving_generator_"), dynms, _dynms_output_ids(dynms)))

function _dynms_saving_generator(generator_code::DynMSSavingGeneratorCode)
  dynms = generator_code.dynms
  output_ids = generator_code.output_ids
  cache = Dict{Tuple{Vararg{Symbol}},Any}()

  function saving_generator(__outputIds__::Vector{Symbol})
    wrong_ids = setdiff(__outputIds__, output_ids)
    !isempty(wrong_ids) && throw("The following outputs have not been found in the model: $(wrong_ids)")

    output_key = Tuple(__outputIds__)
    # is the function already generated for this set of outputs?
    if haskey(cache, output_key)
      return cache[output_key]
    else
      value = _dynms_runtime_function(_dynms_saving_function(dynms, __outputIds__))
      cache[output_key] = value
      return value
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

_dynms_events_namedtuple(events_dict) =
  (; (k => _dynms_event_tuple(v) for (k, v) in events_dict)...)


function _dynms_event_tuple(event_code::DynMSTimeEventCode)
  return (
    _dynms_runtime_function(event_code.tstops_func),
    _dynms_runtime_function(event_code.affect_func),
    event_code.initial_affect
  )
end

function _dynms_event_tuple(event_code::DynMSConditionalEventCode)
  return (
    _dynms_runtime_function(event_code.condition_func),
    _dynms_runtime_function(event_code.affect_func),
    event_code.initial_affect
  )
end

function _dynms_event_tuple(event_code::DynMSStopEventCode)
  return (
    _dynms_runtime_function(event_code.condition_func),
    event_code.initial_affect
  )
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

function _dynms_condition_function(dynms::DynMSModel, event::Union{DynMSContinuousEvent,DynMSDiscreteEvent,DynMSStopEvent})
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


function _dynms_platform_source(platform_code::DynMSPlatformCode)
  io = IOBuffer()
  println(io, "#=")
  println(io, "    This code was generated from DynMS JSON by HetaImporter $(pkgversion(@__MODULE__))")
  println(io, "=#")
  println(io)
  println(io, "(function()")
  println(io)

  for model_code in values(platform_code.models)
    _dynms_model_source(io, model_code)
  end

  println(io, "### OUTPUT ###")
  println(io)
  println(io, "return (")
  println(io, "  (")
  for model_code in values(platform_code.models)
    println(io, "    $(model_code.id) = $(model_code.id)_model_,")
  end
  println(io, "  ),")
  println(io, "  (),")
  println(io, "  ", repr(platform_code.version))
  println(io, ")")
  println(io)
  println(io, "end)()")

  return String(take!(io))
end

function _dynms_model_source(io::IO, model_code::DynMSModelCode)
  model_id = model_code.id
  constants_name = Symbol(model_id, "_constants_num_")
  statics_name = Symbol(model_id, "_statics_id_")
  records_name = Symbol(model_id, "_records_output_")
  events_active_name = Symbol(model_id, "_events_active_")
  dynamic_nonss_name = Symbol(model_id, "_dynamic_nonss_")
  time_events_name = Symbol(model_id, "_time_events_")
  discrete_events_name = Symbol(model_id, "_discrete_events_")
  continuous_events_name = Symbol(model_id, "_continuous_events_")
  stop_events_name = Symbol(model_id, "_stop_events_")

  println(io, "### MODEL $(model_id) ###")
  println(io)
  println(io, "### create default constants")
  println(io, "$(constants_name) = $(_dynms_namedtuple_literal(model_code.constants_num))")
  println(io)
  println(io, "### create static ids")
  println(io, "$(statics_name) = $(repr(model_code.statics_id))")
  println(io)
  println(io, "### create default observables")
  println(io, "$(records_name) = $(_dynms_namedtuple_literal(model_code.records_output))")
  println(io)
  println(io, "### create default events")
  println(io, "$(events_active_name) = $(_dynms_namedtuple_literal(model_code.events_active))")
  println(io)
  println(io, "### vector of non-steady-state")
  println(io, "$(dynamic_nonss_name) = $(_dynms_namedtuple_literal(model_code.dynamic_nonss))")
  println(io)

  println(io, "### initialization of ODE variables and Records")
  _dynms_function_source(io, model_code.init_func)

  println(io, "### calculate RHS of ODE")
  _dynms_function_source(io, model_code.ode_func)

  println(io, "### output function")
  _dynms_saving_generator_source(io, model_code.saving_generator)

  println(io, "### TIME EVENTS ###")
  for event_code in values(model_code.time_events)
    _dynms_function_source(io, event_code.tstops_func)
    _dynms_function_source(io, event_code.affect_func)
  end

  println(io, "### D EVENTS ###")
  for event_code in values(model_code.discrete_events)
    _dynms_function_source(io, event_code.condition_func)
    _dynms_function_source(io, event_code.affect_func)
  end

  println(io, "### C EVENTS ###")
  for event_code in values(model_code.continuous_events)
    _dynms_function_source(io, event_code.condition_func)
    _dynms_function_source(io, event_code.affect_func)
  end

  println(io, "### STOP EVENTS ###")
  for event_code in values(model_code.stop_events)
    _dynms_function_source(io, event_code.condition_func)
  end

  println(io, "### event tuples")
  _dynms_event_namedtuple_source(io, time_events_name, model_code.time_events)
  _dynms_event_namedtuple_source(io, discrete_events_name, model_code.discrete_events)
  _dynms_event_namedtuple_source(io, continuous_events_name, model_code.continuous_events)
  _dynms_event_namedtuple_source(io, stop_events_name, model_code.stop_events)

  println(io, "### MODELS ###")
  println(io)
  println(io, "$(model_id)_model_ = (")
  println(io, "  $(model_code.init_func.name),")
  println(io, "  $(model_code.ode_func.name),")
  println(io, "  $(time_events_name),")
  println(io, "  $(discrete_events_name),")
  println(io, "  $(continuous_events_name),")
  println(io, "  $(stop_events_name),")
  println(io, "  $(model_code.saving_generator.name),")
  println(io, "  $(constants_name),")
  println(io, "  $(statics_name),")
  println(io, "  $(events_active_name),")
  println(io, "  $(records_name),")
  println(io, "  $(dynamic_nonss_name)")
  println(io, ")")
  println(io)

  return nothing
end

function _dynms_function_source(io::IO, func::DynMSFunction)
  println(io, "function $(func.name)($(join(func.args, ", ")))")
  for stmt in func.body.args
    _dynms_statement_source(io, stmt, 2)
  end
  println(io, "end")
  println(io)
  return nothing
end

function _dynms_statement_source(io::IO, stmt, indent::Int)
  stmt isa LineNumberNode && return nothing
  stmt_string = _dynms_expr_source(stmt)
  prefix = " "^indent
  for line in split(stmt_string, '\n')
    println(io, prefix, line)
  end
  return nothing
end

function _dynms_saving_generator_source(io::IO, generator_code::DynMSSavingGeneratorCode)
  dynms = generator_code.dynms
  stmts = []
  _add_dynms_header_bindings!(stmts, dynms; integrator_p=true)
  _add_dynms_assignment_bindings!(stmts, dynms)

  println(io, "function $(generator_code.name)(__outputIds__::Vector{Symbol})")
  println(io, "  __wrongIds__ = setdiff(__outputIds__, $(_dynms_symbol_vector_source(generator_code.output_ids)))")
  println(io, "  !isempty(__wrongIds__) && throw(\"The following outputs have not been found in the model: \$(__wrongIds__)\")")
  println(io)
  println(io, "  __out_expr__ = Expr(:block)")
  println(io, "  for (__i__, __obs__) in enumerate(__outputIds__)")
  println(io, "    push!(__out_expr__.args, :(__out__[\$__i__] = \$__obs__))")
  println(io, "  end")
  println(io)
  println(io, "  return @eval function(__out__, __u__, t, __integrator__)")
  for stmt in stmts
    _dynms_statement_source(io, stmt, 4)
  end
  println(io)
  println(io, "    \$(__out_expr__)")
  println(io, "    return nothing")
  println(io, "  end")
  println(io, "end")
  println(io)
  return nothing
end

function _dynms_event_namedtuple_source(io::IO, name::Symbol, event_codes)
  if isempty(event_codes)
    println(io, "$(name) = NamedTuple{()}(())")
    println(io)
    return nothing
  end

  println(io, "$(name) = NamedTuple{$(repr(Tuple(keys(event_codes))))}((")
  for event_code in values(event_codes)
    println(io, "  $(_dynms_event_value_source(event_code)),")
  end
  println(io, "))")
  println(io)
  return nothing
end

function _dynms_event_value_source(event_code::DynMSTimeEventCode)
  return "($(event_code.tstops_func.name), $(event_code.affect_func.name), $(repr(event_code.initial_affect)))"
end

function _dynms_event_value_source(event_code::DynMSConditionalEventCode)
  return "($(event_code.condition_func.name), $(event_code.affect_func.name), $(repr(event_code.initial_affect)))"
end

function _dynms_event_value_source(event_code::DynMSStopEventCode)
  return "($(event_code.condition_func.name), $(repr(event_code.initial_affect)))"
end

function _dynms_namedtuple_literal(nt::NamedTuple)
  return "NamedTuple{$(repr(Tuple(keys(nt))))}($(repr(Tuple(values(nt)))))"
end

function _dynms_symbol_vector_source(ids::Vector{Symbol})
  isempty(ids) && return "Symbol[]"
  return "Symbol[" * join((repr(id) for id in ids), ", ") * "]"
end

function _dynms_expr_source(ex)
  clean_ex = Base.remove_linenums!(deepcopy(ex))
  return sprint(io -> Base.show_unquoted(io, clean_ex, 0, 0))
end
