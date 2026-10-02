Base.nameof(system::HetaODESystem) = system.name

function Base.getproperty(system::HetaODESystem, symbol::Symbol)
  symbol in fieldnames(typeof(system)) && return getfield(system, symbol)
  dynms = getfield(system, :dynms)
  if symbol === :t || haskey(dynms.states, symbol) ||
      haskey(dynms.parameters.tunable, symbol) ||
      haskey(dynms.parameters.derived, symbol) ||
      haskey(dynms.parameters.discrete, symbol) ||
      haskey(dynms.assignment_rules, symbol)
    # SciMLBase uses `getproperty(fn.sys, sym)` to translate Symbol queries
    # before dispatching to the generic observed interface. A QuoteNode keeps
    # the identity while avoiding recursive Symbol dispatch.
    return QuoteNode(symbol)
  end
  return getfield(system, symbol)
end

"""Return the state derivative expressions of `system`, keyed by state name."""
function equations(system::HetaODESystem)
  return OrderedDict{Symbol,Any}(
    id => state.equation for (id, state) in system.dynms.states
  )
end

"""Return the state initial-condition expressions of `system`."""
function initial_conditions(system::HetaODESystem)
  return OrderedDict{Symbol,Any}(
    id => state.initial for (id, state) in system.dynms.states
  )
end

"""Return the tunable defaults and derived/discrete initialization expressions."""
parameters(system::HetaODESystem) = (
  tunable=copy(system.dynms.parameters.tunable),
  derived=copy(system.dynms.parameters.derived),
  discrete=copy(system.dynms.parameters.discrete),
)

"""Return the assignment-rule expressions available as observed variables."""
observed(system::HetaODESystem) = copy(system.dynms.assignment_rules)

"""Return the time, continuous, discrete, and stop event definitions."""
events(system::HetaODESystem) = (
  time=copy(system.dynms.time_events),
  continuous=copy(system.dynms.continuous_events),
  discrete=copy(system.dynms.discrete_events),
  stop=copy(system.dynms.stop_events),
)

SII.is_variable(system::HetaODESystem, symbol) = haskey(system.state_index, symbol)
SII.variable_index(system::HetaODESystem, symbol) = get(system.state_index, symbol, nothing)
SII.variable_symbols(system::HetaODESystem) = collect(keys(system.dynms.states))

SII.is_parameter(system::HetaODESystem, symbol) = haskey(system.parameter_index, symbol)
SII.parameter_index(system::HetaODESystem, symbol) = get(system.parameter_index, symbol, nothing)
SII.parameter_symbols(system::HetaODESystem) = vcat(
  collect(keys(system.dynms.parameters.tunable)),
  collect(keys(system.dynms.parameters.derived)),
  collect(keys(system.dynms.parameters.discrete)),
)

SII.is_timeseries_parameter(system::HetaODESystem, symbol) =
  haskey(system.discrete_index, symbol)
function SII.timeseries_parameter_index(system::HetaODESystem, symbol)
  index = get(system.discrete_index, symbol, nothing)
  return isnothing(index) ? nothing : SII.ParameterTimeseriesIndex(1, index)
end

function _heta_depends_on_discrete(system::HetaODESystem, symbol::Symbol, visited)
  haskey(system.discrete_index, symbol) && return true
  symbol in visited && return false
  rhs = get(system.dynms.assignment_rules, symbol, nothing)
  rhs === nothing && return false
  push!(visited, symbol)
  dependencies = _heta_expr_walk!(Set{Symbol}(), rhs)
  return any(dependency ->
    _heta_depends_on_discrete(system, dependency, visited), dependencies)
end

function SII.get_all_timeseries_indexes(system::HetaODESystem, symbol)
  symbol isa QuoteNode && return SII.get_all_timeseries_indexes(system, symbol.value)
  if symbol isa Union{Tuple,AbstractArray}
    return mapreduce(
      item -> SII.get_all_timeseries_indexes(system, item),
      union,
      symbol;
      init=Set{Any}(),
    )
  elseif symbol isa Symbol
    if haskey(system.state_index, symbol) || symbol === :t
      return Set{Any}((SII.ContinuousTimeseries(),))
    elseif haskey(system.discrete_index, symbol)
      return Set{Any}((1,))
    elseif haskey(system.dynms.assignment_rules, symbol)
      indexes = Set{Any}((SII.ContinuousTimeseries(),))
      _heta_depends_on_discrete(system, symbol, Set{Symbol}()) && push!(indexes, 1)
      return indexes
    end
  end
  return Set{Any}()
end

function SciMLBase.create_parameter_timeseries_collection(
  ::HetaODESystem, p::HetaParameters, tspan,
)
  isempty(p.discrete) && return nothing
  values = [copy(p.discrete)]
  times = [first(tspan)]
  buffer = SciMLBase.DiffEqArray(values, times)
  return SII.ParameterTimeseriesCollection((buffer,), copy(p))
end

function SciMLBase.get_saveable_values(
  ::HetaODESystem, p::HetaParameters, timeseries_idx,
)
  timeseries_idx == 1 || return nothing
  return copy(p.discrete)
end

function SII.with_updated_parameter_timeseries_values(
  ::HetaODESystem, p::HetaParameters, updates::Pair...,
)
  for (timeseries_idx, values) in updates
    timeseries_idx == 1 || throw(ArgumentError(
      "Unknown Heta parameter timeseries index: $timeseries_idx",
    ))
    copyto!(p.discrete, values)
  end
  return p
end

SII.is_independent_variable(::HetaODESystem, symbol) = symbol === :t
SII.independent_variable_symbols(::HetaODESystem) = [:t]
SII.is_time_dependent(::HetaODESystem) = true
SII.constant_structure(::HetaODESystem) = true

function SII.default_values(system::HetaODESystem)
  defaults = Dict{Symbol,Any}()
  merge!(defaults, system.dynms.parameters.tunable)
  merge!(defaults, system.dynms.parameters.derived)
  merge!(defaults, system.dynms.parameters.discrete)
  for (id, state) in system.dynms.states
    defaults[id] = state.initial
  end
  return defaults
end

SII.all_variable_symbols(system::HetaODESystem) = vcat(
  SII.variable_symbols(system),
  collect(keys(system.dynms.assignment_rules)),
)
SII.all_symbols(system::HetaODESystem) = vcat(
  SII.all_variable_symbols(system),
  SII.parameter_symbols(system),
  [:t],
)

function SII.is_observed(system::HetaODESystem, symbol)
  symbol isa QuoteNode && return SII.is_observed(system, symbol.value)
  symbol isa Symbol && return haskey(system.dynms.assignment_rules, symbol)
  symbol isa Union{Tuple,AbstractArray} || return false
  return all(item ->
    SII.is_variable(system, item) ||
    SII.is_observed(system, item), symbol)
end
SII.supports_tuple_observed(::HetaODESystem) = true

function _heta_observed_result(system::HetaODESystem, symbol, roots)
  symbol isa QuoteNode && (symbol = symbol.value)
  if symbol isa Symbol
    if haskey(system.dynms.assignment_rules, symbol)
      push!(roots, symbol)
      return symbol
    elseif haskey(system.state_index, symbol)
      return symbol
    end
    throw(ArgumentError("Unknown symbol in HetaODESystem $(system.name): $symbol"))
  elseif symbol isa Tuple
    return Expr(:tuple, (_heta_observed_result(system, item, roots) for item in symbol)...)
  elseif symbol isa AbstractArray
    return Expr(:vect, (_heta_observed_result(system, item, roots) for item in symbol)...)
  end
  throw(ArgumentError("Unsupported observed request: $symbol"))
end

function _heta_observed_function(system::HetaODESystem, symbol)
  roots = Any[]
  result = _heta_observed_result(system, symbol, roots)
  statements = []
  _add_heta_parameter_bindings!(statements, system.dynms)
  _add_heta_state_bindings!(statements, system.dynms)
  _add_heta_assignment_bindings!(
    statements,
    system.dynms,
    roots,
  )
  push!(statements, :(return $result))
  return _dynms_function(
    Symbol(system.name, "_observed_func_"),
    [:__u__, :__p__, :t],
    statements,
  )
end

function _heta_runtime_function(func::DynMSJuliaFunction)
  lambda = Expr(:->, Expr(:tuple, func.args...), func.body)
  return RuntimeGeneratedFunctions.RuntimeGeneratedFunction(
    @__MODULE__, @__MODULE__, lambda,
  )
end

SII.observed(system::HetaODESystem, symbol) =
  _heta_runtime_function(_heta_observed_function(system, symbol))

function _heta_observed_interface(system::HetaODESystem)
  cache = Dict{Any,Any}()
  function lookup(symbol)
    key = symbol isa AbstractArray ? (:array, Tuple(symbol)) : symbol
    # Return the cached function if the key is present.
    # Otherwise, call SII.observed to build the function, store it, and return it
    return get!(cache, key) do
      SII.observed(system, symbol)
    end
  end
  observed(symbol, u, p, t) = lookup(symbol)(u, p, t)
  return observed
end

function _heta_parameters(system::HetaODESystem, tunable::AbstractVector)
  expected = length(system.dynms.parameters.tunable)
  length(tunable) == expected || throw(DimensionMismatch(
    "Expected $expected tunable parameters for HetaODESystem $(system.name), " *
    "got $(length(tunable)).",
  ))
  initialize_parameters! = _heta_runtime_function(
    system.generated_code.initialize_parameters_func,
  )
  return HetaParameters(
    tunable,
    length(system.dynms.parameters.derived),
    length(system.dynms.parameters.discrete),
    initialize_parameters!,
  )
end

function _heta_default_parameters(system::HetaODESystem)
  tunable = collect(values(system.dynms.parameters.tunable))
  return _heta_parameters(system, tunable)
end

function _heta_problem_parameters(system::HetaODESystem, p)
  (isnothing(p) || p isa SciMLBase.NullParameters) &&
    return _heta_default_parameters(system)
  p isa AbstractVector || throw(ArgumentError(
    "p must be an AbstractVector containing the tunable parameters for " *
    "HetaODESystem $(system.name), got $(typeof(p)).",
  ))
  return _heta_parameters(system, p)
end

function _heta_time_event_schedule(schedule_func, integrator)
  schedule = schedule_func(integrator.p)
  time_type = typeof(integrator.t)
  return (
    start=convert(time_type, schedule.start),
    period=isnothing(schedule.period) ? nothing :
      convert(time_type, schedule.period),
    stop=isnothing(schedule.stop) ? nothing : convert(time_type, schedule.stop),
  )
end

function _heta_time_event_occurs_at(schedule, time)
  time < schedule.start && return false
  schedule.stop !== nothing && time > schedule.stop && return false
  schedule.period === nothing && return time == schedule.start

  period = schedule.period
  period > zero(period) || throw(ArgumentError(
    "Time-event period must be positive, got $period.",
  ))
  range_stop = isnothing(schedule.stop) ? time : schedule.stop
  return time in (schedule.start:period:range_stop)
end

function _heta_next_time(schedule_func, integrator)
  integrator.tdir > 0 || throw(ArgumentError(
    "Native Heta time events currently support only forward integration.",
  ))
  schedule = _heta_time_event_schedule(schedule_func, integrator)
  time = integrator.t
  final_time = convert(typeof(time), last(integrator.sol.prob.tspan))

  if schedule.period === nothing
    next_time = schedule.start
    return time < next_time <= final_time ? next_time : nothing
  end

  period = schedule.period
  period > zero(period) || throw(ArgumentError(
    "Time-event period must be positive, got $period.",
  ))
  if time < schedule.start
    next_time = schedule.start
  else
    # Count periods (occurrences) till the next event
    occurrence = floor(Int, (time - schedule.start) / period) + 1
    next_time = schedule.start + occurrence * period
    # Ensure the next time is not equal to the current time (floating point rounding)
    if next_time <= time
      next_time = schedule.start + (occurrence + 1) * period
    end
  end

  schedule.stop !== nothing && next_time > schedule.stop && return nothing
  return next_time <= final_time ? convert(typeof(time), next_time) : nothing
end

function _heta_event_initialize(
  initial_affect,
  is_active;
  after_affect! = integrator -> nothing,
)
  return function (callback, u, t, integrator)
    if initial_affect && is_active(callback.condition(u, t, integrator))
      callback.affect!(integrator)
      after_affect!(integrator)
      SciMLBase.derivative_discontinuity!(integrator, true)
    else
      SciMLBase.derivative_discontinuity!(integrator, false)
    end
    return nothing
  end
end

# if saves_discrete is true applies affect and saves the discrete state
function _heta_event_affect(affect!, saves_discrete)
  saves_discrete || return affect!
  return function (integrator)
    affect!(integrator)
    SciMLBase.save_discretes!(integrator, 1)
  end
end

function _heta_callbacks(system::HetaODESystem, tspan)
  code = system.generated_code
  callbacks = Any[]

  for (id, event) in code.time_events
    schedule_func = _heta_runtime_function(event.schedule_func)
    affect! = _heta_event_affect(
      _heta_runtime_function(event.affect_func),
      !isempty(system.dynms.time_events[id].discrete_affects),
    )
    time_choice = integrator -> _heta_next_time(schedule_func, integrator)
    time_type = promote_type(typeof(first(tspan)), typeof(last(tspan)))
    initialize = function (callback, u, t, integrator)
      schedule = _heta_time_event_schedule(schedule_func, integrator)
      occurs_at_start = _heta_time_event_occurs_at(schedule, t)
      occurs_at_start && affect!(integrator)
      SciMLBase.derivative_discontinuity!(integrator, occurs_at_start)
      return nothing
    end
    push!(callbacks, DiffEqCallbacks.IterativeCallback(
      time_choice,
      affect!,
      time_type;
      initial_affect=false,
      initialize,
    ))
  end

  for (id, event) in code.continuous_events
    # Initial affect is applied if event.initial_affect is true and condition is nonnegative at the initial time
    initialize = _heta_event_initialize(event.initial_affect, value -> value >= zero(value))
    push!(callbacks, SciMLBase.ContinuousCallback(
      _heta_runtime_function(event.condition_func),
      _heta_event_affect(
        _heta_runtime_function(event.affect_func),
        !isempty(system.dynms.continuous_events[id].discrete_affects),
      ),
      ; initialize,
    ))
  end

  for (id, event) in code.discrete_events
    # Initial affect is applied if event.initial_affect is true and condition is satisfied at the initial time
    initialize = _heta_event_initialize(event.initial_affect, identity)
    push!(callbacks, SciMLBase.DiscreteCallback(
      _heta_runtime_function(event.condition_func),
      _heta_event_affect(
        _heta_runtime_function(event.affect_func),
        !isempty(system.dynms.discrete_events[id].discrete_affects),
      ),
      ; initialize,
    ))
  end

  for event in values(code.stop_events)
    condition = _heta_runtime_function(event.condition_func)
    affect! = integrator -> SciMLBase.terminate!(integrator)
    # terminate! empties tstops. During initialization the solver still needs one
    # stop to determine its initial dt, so retain the current time until solve!.
    initialize = _heta_event_initialize(
      event.initial_affect,
      identity;
      after_affect! = integrator -> SciMLBase.add_tstop!(integrator, integrator.t),
    )
    push!(callbacks, SciMLBase.DiscreteCallback(condition, affect!; initialize))
  end

  callback = isempty(callbacks) ? nothing : SciMLBase.CallbackSet(callbacks...)
  return callback
end

function SciMLBase.ODEFunction(system::HetaODESystem; kwargs...)
  return SciMLBase.ODEFunction{true}(
    _heta_runtime_function(system.generated_code.ode_func);
    mass_matrix=system.generated_code.mass_matrix,
    observed=_heta_observed_interface(system),
    sys=system,
    kwargs...,
  )
end

function SciMLBase.ODEProblem(
  system::HetaODESystem,
  tspan::Tuple;
  p=SciMLBase.NullParameters(),
  callback=nothing,
  kwargs...,
)
  callback === nothing || throw(ArgumentError(
    "External callbacks are not supported for HetaODESystem. " *
    "Define callbacks in the Heta model.",
  ))
  haskey(kwargs, :u0) && throw(ArgumentError(
    "u0 is defined by HetaODESystem and cannot be supplied to ODEProblem.",
  ))

  parameters = _heta_problem_parameters(system, p)
  initial_state = _heta_runtime_function(system.generated_code.u0_func)
  ode_function = SciMLBase.ODEFunction(system)
  heta_callback = _heta_callbacks(system, tspan)

  if isnothing(heta_callback)
    return SciMLBase.ODEProblem(ode_function, initial_state, tspan, parameters; kwargs...)
  end
  return SciMLBase.ODEProblem(
    ode_function,
    initial_state,
    tspan,
    parameters;
    callback=heta_callback,
    kwargs...,
  )
end
