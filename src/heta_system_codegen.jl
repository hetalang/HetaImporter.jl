function _heta_symbols!(symbols::Set{Symbol}, value)
  if value isa Symbol
    push!(symbols, value)
  elseif value isa Expr
    first_argument = value.head === :call ? 2 : 1
    for i in first_argument:length(value.args)
      _heta_symbols!(symbols, value.args[i])
    end
  elseif value isa Tuple || value isa AbstractArray
    foreach(Base.Fix1(_heta_symbols!, symbols), value)
  end
  return symbols
end

function _heta_required_assignments(
  assignment_rules::OrderedDict{Symbol,DynMSExpr},
  roots,
)
  needed = Set{Symbol}()
  foreach(root -> _heta_symbols!(needed, root), roots)
  required = Symbol[]

  for (id, rhs) in Iterators.reverse(assignment_rules)
    if id in needed
      push!(required, id)
      _heta_symbols!(needed, rhs)
    end
  end

  return reverse!(required)
end

function _add_heta_assignment_bindings!(
  statements,
  dynms::DynMSModel,
  roots,
)
  for id in _heta_required_assignments(dynms.assignment_rules, roots)
    push!(statements, Expr(:(=), id, dynms.assignment_rules[id]))
  end
  return statements
end

function _heta_index_maps(dynms::DynMSModel)
  state_index = Dict(id => i for (i, id) in enumerate(keys(dynms.states)))
  parameter_index = Dict{Symbol,Int}()
  discrete_index = Dict{Symbol,Int}()

  for (i, id) in enumerate(keys(dynms.parameters.tunable))
    parameter_index[id] = i
  end
  offset = length(parameter_index)
  for (i, id) in enumerate(keys(dynms.parameters.discrete))
    parameter_index[id] = offset + i
    discrete_index[id] = i
  end
  return state_index, parameter_index, discrete_index
end

function _add_heta_tunable_bindings!(statements, dynms::DynMSModel; p=:__p__)
  for (i, id) in enumerate(keys(dynms.parameters.tunable))
    push!(statements, :($id = $p.tunable[$i]))
  end
  return statements
end

function _add_heta_parameter_bindings!(statements, dynms::DynMSModel; p=:__p__)
  _add_heta_tunable_bindings!(statements, dynms; p)
  for (i, id) in enumerate(keys(dynms.parameters.discrete))
    push!(statements, :($id = $p.discrete[$i]))
  end
  return statements
end

function _add_heta_state_bindings!(statements, dynms::DynMSModel; u=:__u__)
  for (i, id) in enumerate(keys(dynms.states))
    push!(statements, :($id = $u[$i]))
  end
  return statements
end

function _heta_initialize_discrete_function(dynms::DynMSModel; name=dynms.id)
  statements = []
  for (i, id) in enumerate(keys(dynms.parameters.tunable))
    push!(statements, :($id = __tunable__[$i]))
  end
  for (i, (id, initial)) in enumerate(dynms.parameters.discrete)
    push!(statements, Expr(:(=), id, initial))
    push!(statements, :(__discrete__[$i] = $id))
  end
  push!(statements, :(return nothing))
  return _dynms_function(
    Symbol(name, "_initialize_discrete_!"),
    [:__discrete__, :__tunable__],
    statements,
  )
end

function _heta_u0_function(dynms::DynMSModel; name=dynms.id)
  statements = []
  _add_heta_parameter_bindings!(statements, dynms)
  push!(statements, :(
    __u0__ = Vector{eltype(__p__.tunable)}(undef, $(length(dynms.states)))
  ))
  for (i, (id, state)) in enumerate(dynms.states)
    push!(statements, Expr(:(=), id, state.initial))
    push!(statements, :(__u0__[$i] = $id))
  end
  push!(statements, :(return __u0__))
  return _dynms_function(Symbol(name, "_u0_func_"), [:__p__, :t], statements)
end

function _heta_ode_function(dynms::DynMSModel; name=dynms.id)
  statements = []
  _add_heta_parameter_bindings!(statements, dynms)
  _add_heta_state_bindings!(statements, dynms)
  _add_heta_assignment_bindings!(
    statements,
    dynms,
    (state.equation for state in values(dynms.states)),
  )
  for (i, state) in enumerate(values(dynms.states))
    push!(statements, :(__du__[$i] = $(state.equation)))
  end
  push!(statements, :(return nothing))
  return _dynms_function(
    Symbol(name, "_ode_func_"),
    [:__du__, :__u__, :__p__, :t],
    statements,
  )
end

function _heta_schedule_function(
  dynms::DynMSModel,
  event::DynMSTimeEvent;
  name=dynms.id,
)
  statements = []
  _add_heta_tunable_bindings!(statements, dynms)

  push!(statements, :(
    return (
      start=$(event.start),
      period=$(event.period),
      stop=$(event.stop),
    )
  ))
  return _dynms_function(
    Symbol(name, "_", event_id(event), "_schedule_func_"),
    [:__p__],
    statements,
  )
end

function _heta_condition_function(
  dynms::DynMSModel,
  event::Union{DynMSContinuousEvent,DynMSDiscreteEvent,DynMSStopEvent};
  name=dynms.id,
)
  statements = [:(__p__ = __integrator__.p)]
  _add_heta_parameter_bindings!(statements, dynms)
  _add_heta_state_bindings!(statements, dynms)
  _add_heta_assignment_bindings!(
    statements,
    dynms,
    (event.condition,),
  )
  push!(statements, :(return $(event.condition)))
  return _dynms_function(
    Symbol(name, "_", event_id(event), "_condition_func_"),
    [:__u__, :t, :__integrator__],
    statements,
  )
end

function _heta_affect_function(
  dynms::DynMSModel,
  event;
  name=dynms.id,
)
  roots = Iterators.flatten((
    values(event.state_affects),
    values(event.discrete_affects),
  ))
  statements = [
    :(t = __integrator__.t),
    :(__u__ = __integrator__.u),
    :(__p__ = __integrator__.p),
  ]
  _add_heta_parameter_bindings!(statements, dynms)
  _add_heta_state_bindings!(statements, dynms)
  _add_heta_assignment_bindings!(statements, dynms, roots)

  state_index = Dict(id => i for (i, id) in enumerate(keys(dynms.states)))
  discrete_index = Dict(
    id => i for (i, id) in enumerate(keys(dynms.parameters.discrete))
  )
  for (id, rhs) in event.state_affects
    push!(statements, :(__integrator__.u[$(state_index[id])] = $rhs))
  end
  for (id, rhs) in event.discrete_affects
    push!(statements, :(__integrator__.p.discrete[$(discrete_index[id])] = $rhs))
  end
  push!(statements, :(return nothing))
  return _dynms_function(
    Symbol(name, "_", event_id(event), "_affect_func_"),
    [:__integrator__],
    statements,
  )
end

function _heta_time_event_codes(dynms; name=dynms.id)
  result = OrderedDict{Symbol,DynMSJuliaTimeEventCode}()
  for (id, event) in dynms.time_events
    is_active(event) || continue
    result[id] = DynMSJuliaTimeEventCode(
      id,
      _heta_schedule_function(dynms, event; name),
      _heta_affect_function(dynms, event; name),
      has_initial_affect(event),
    )
  end
  return result
end

function _heta_conditional_event_codes(dynms, events; name=dynms.id)
  result = OrderedDict{Symbol,DynMSJuliaConditionalEventCode}()
  for (id, event) in events
    is_active(event) || continue
    result[id] = DynMSJuliaConditionalEventCode(
      id,
      _heta_condition_function(dynms, event; name),
      _heta_affect_function(dynms, event; name),
      has_initial_affect(event),
    )
  end
  return result
end

function _heta_stop_event_codes(dynms; name=dynms.id)
  result = OrderedDict{Symbol,DynMSJuliaStopEventCode}()
  for (id, event) in dynms.stop_events
    is_active(event) || continue
    result[id] = DynMSJuliaStopEventCode(
      id,
      _heta_condition_function(dynms, event; name),
      has_initial_affect(event),
    )
  end
  return result
end

function _generate_ode_code(dynms::DynMSModel; name=dynms.id)
  return (
    initialize_discrete_func=_heta_initialize_discrete_function(dynms; name),
    u0_func=_heta_u0_function(dynms; name),
    ode_func=_heta_ode_function(dynms; name),
    time_events=_heta_time_event_codes(dynms; name),
    continuous_events=_heta_conditional_event_codes(
      dynms, dynms.continuous_events; name,
    ),
    discrete_events=_heta_conditional_event_codes(
      dynms, dynms.discrete_events; name,
    ),
    stop_events=_heta_stop_event_codes(dynms; name),
    mass_matrix=has_algebraic(dynms) ? Diagonal(Float64[
      !is_algebraic(state) for state in values(dynms.states)
    ]) : I,
  )
end

function _write_heta_event_functions(io, event_codes)
  for event in values(event_codes)
    if event isa DynMSJuliaTimeEventCode
      _dynms_function_source(io, event.schedule_func)
      _dynms_function_source(io, event.affect_func)
    elseif event isa DynMSJuliaConditionalEventCode
      _dynms_function_source(io, event.condition_func)
      _dynms_function_source(io, event.affect_func)
    elseif event isa DynMSJuliaStopEventCode
      _dynms_function_source(io, event.condition_func)
    end
  end
  return nothing
end

function _heta_generated_code_source(system::HetaODESystem)
  io = IOBuffer()
  println(io, "# Generated by HetaImporter.jl for HetaODESystem $(system.name)")
  println(io, "using LinearAlgebra")
  println(io)
  code = system.generated_code
  _dynms_function_source(io, code.initialize_discrete_func)
  _dynms_function_source(io, code.u0_func)
  _dynms_function_source(io, code.ode_func)
  _write_heta_event_functions(io, code.time_events)
  _write_heta_event_functions(io, code.continuous_events)
  _write_heta_event_functions(io, code.discrete_events)
  _write_heta_event_functions(io, code.stop_events)
  println(io, "mass_matrix = ", repr(code.mass_matrix))
  return String(take!(io))
end

"""
    write_generated_code(system, filename)

Write the fixed native Julia functions stored in `system.generated_code` to a
readable source file. No code is regenerated.
"""
function write_generated_code(system::HetaODESystem, filename::AbstractString)
  path = abspath(filename)
  mkpath(dirname(path))
  open(path, "w") do io
    write(io, _heta_generated_code_source(system))
  end
  return path
end

function _build_ode_system(
  dynms::DynMSModel,
  ;
  name::Symbol=dynms.id,
  write_to_file::Bool=false,
  filename::Union{AbstractString,Nothing}=nothing,
)
  state_index, parameter_index, discrete_index = _heta_index_maps(dynms)
  generated_code = _generate_ode_code(dynms; name)
  system = HetaODESystem(
    name,
    dynms,
    state_index,
    parameter_index,
    discrete_index,
    generated_code,
  )

  if write_to_file
    output = isnothing(filename) ? "$(name)_ode.jl" : filename
    write_generated_code(system, output)
  end
  return system
end
