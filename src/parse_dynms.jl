const DynMSExpr = Union{Expr,Symbol,Float64}
const DynMSVal = Union{Symbol, Float64}

abstract type AbstractDynMSEvent end

struct DynMSState
  initial::DynMSExpr
  equation::DynMSExpr
  is_algebraic::Bool
end

is_algebraic(state::DynMSState) = state.is_algebraic

struct DynMSTimeEvent <: AbstractDynMSEvent
  id::Symbol
  start::DynMSVal
  period::Union{DynMSVal, Nothing}
  stop::Union{DynMSVal, Nothing}
  state_affects::OrderedDict{Symbol,DynMSExpr}
  discrete_affects::OrderedDict{Symbol,DynMSExpr}
  initial_affect::Bool
  is_active::Bool
end

struct DynMSContinuousEvent <: AbstractDynMSEvent
  id::Symbol
  condition::Union{Expr,Symbol}
  state_affects::OrderedDict{Symbol,DynMSExpr}
  discrete_affects::OrderedDict{Symbol,DynMSExpr}
  initial_affect::Bool
  is_active::Bool
end

struct DynMSDiscreteEvent <: AbstractDynMSEvent
  id::Symbol  
  condition::Union{Expr,Symbol}
  state_affects::OrderedDict{Symbol,DynMSExpr}
  discrete_affects::OrderedDict{Symbol,DynMSExpr}
  initial_affect::Bool
  is_active::Bool
end

struct DynMSStopEvent <: AbstractDynMSEvent
  id::Symbol
  condition::Union{Expr,Symbol}
  initial_affect::Bool
  is_active::Bool
end

event_id(event::AbstractDynMSEvent) = event.id
is_active(event::AbstractDynMSEvent) = event.is_active
has_initial_affect(event::AbstractDynMSEvent) = event.initial_affect

struct DynMSParameters
  tunable::OrderedDict{Symbol,Float64}
  derived::OrderedDict{Symbol,DynMSExpr}
  discrete::OrderedDict{Symbol,DynMSExpr}
end

struct DynMSModel
  id::Symbol
  parameters::DynMSParameters
  assignment_rules::OrderedDict{Symbol,DynMSExpr}
  states::OrderedDict{Symbol,DynMSState}
  time_events::OrderedDict{Symbol,DynMSTimeEvent}
  continuous_events::OrderedDict{Symbol,DynMSContinuousEvent}
  discrete_events::OrderedDict{Symbol,DynMSDiscreteEvent}
  stop_events::OrderedDict{Symbol,DynMSStopEvent}
  observables::Vector{Symbol}
end

has_algebraic(model::DynMSModel) = any(is_algebraic, values(model.states))

merge_events(model::DynMSModel) = merge(model.time_events, model.continuous_events, model.discrete_events, model.stop_events)

struct DynMSScenario
  id::Symbol
  model::Symbol
  tspan::Tuple{Float64, Float64}
  saveat::Union{Nothing,Vector{Float64}}
  parameters::Union{Nothing,Dict{Symbol,Float64}}
  events_active::Union{Nothing,Dict{Symbol,Bool}}
  events_save::Union{Nothing,Dict{Symbol,Tuple{Bool, Bool}}}
end

struct DynMSModelSet
  models::OrderedDict{Symbol,DynMSModel}
  scenarios::OrderedDict{Symbol,DynMSScenario}
  version::String
end

struct DynMSJuliaFunction
  name::Symbol
  args::Vector{Symbol}
  body::Expr
end

struct DynMSJuliaTimeEventCode
  id::Symbol
  schedule_func::DynMSJuliaFunction
  affect_func::DynMSJuliaFunction
  initial_affect::Bool
end

struct DynMSJuliaConditionalEventCode
  id::Symbol
  condition_func::DynMSJuliaFunction
  affect_func::DynMSJuliaFunction
  initial_affect::Bool
end

struct DynMSJuliaStopEventCode
  id::Symbol
  condition_func::DynMSJuliaFunction
  initial_affect::Bool
end

function _dynms_function_source(io::IO, func::DynMSJuliaFunction)
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

function _dynms_expr_source(ex)
  clean_ex = Base.remove_linenums!(deepcopy(ex))
  return sprint(io -> Base.show_unquoted(io, clean_ex, 0, 0))
end

"""
    parse_dynms(dynms_filepath::AbstractString)

Parse a DynMS JSON file into a dictionary without validation or conversion.
Use [`import_dynms`](@ref) to construct a `HetaODESystem` from a file.
"""
parse_dynms(dynms_filepath::AbstractString) = JSON.parsefile(dynms_filepath)

"""
    validate_dynms(dynms_dict::AbstractDict)

Check the supported format version, JSON schema, and semantic consistency of
an already-parsed DynMS dictionary. Return `nothing` on success.
"""
function validate_dynms(dynms_dict::AbstractDict)
  dynms_version = string(get(dynms_dict, "dynms", ""))
  dynms_version in DYNMS_SUPPORTED_VERSIONS ||
    throw(ArgumentError(
      "Unsupported DynMS format version: $dynms_version. " *
      "Supported versions are: $(join(DYNMS_SUPPORTED_VERSIONS, ", ")).",
    ))

  validate_schema_dynms(dynms_dict, dynms_version)
  validate_semantic_dynms(dynms_dict, dynms_version)
  
  return nothing
end

"""
    validate_schema_dynms(dynms_dict::AbstractDict, dynms_version::AbstractString)

Validate a DynMS JSON dictionary against the schema for its DynMS format
version.
"""
function validate_schema_dynms(dynms_dict::AbstractDict, dynms_version::AbstractString)
  schema = DYNMS_SCHEMAS[dynms_version]
  validation_issue = JSONSchema.validate(schema, dynms_dict)
  isnothing(validation_issue) || throw(ArgumentError(
    "DynMS format version $dynms_version does not conform to its JSON Schema:\n" *
    sprint(show, validation_issue),
  ))
  return nothing
end

"""
    validate_semantic_dynms(dynms_dict::AbstractDict, dynms_version::AbstractString)

Validate semantic consistency of a DynMS JSON dictionary.

`dynms_version` identifies the document format and is available for future
format-specific validation. The schema validator verifies that the version is
supported before this function is called.
"""
function validate_semantic_dynms(dynms_dict::AbstractDict, dynms_version::AbstractString)
  return nothing
end

"""
    convert_dynms(data::AbstractDict; nanmath::Bool=false)

Convert an already-parsed, validated DynMS JSON dictionary into a `DynMSModelSet`.

Use [`parse_dynms`](@ref) to read a file and [`validate_dynms`](@ref) before
conversion. The returned specification contains model definitions, Julia expression trees for
mathematical expressions, event definitions, and metadata from the DynMS
generator.

Set `nanmath=true` to convert powers, square roots, and logarithms to
NaNMath calls. This option applies to every model expression.
"""
function convert_dynms(data::AbstractDict; nanmath::Bool=false)
  dynms_version = string(get(data, "dynms", ""))

  dynms_models = OrderedDict{Symbol,DynMSModel}()
  for model in get(data, "models", Any[])
    isempty_dynms_model(model) && continue
    dynms_model = convert_dynms_model(model; nanmath)
    dynms_models[dynms_model.id] = dynms_model
  end
 
  isempty(dynms_models) && 
    throw(ArgumentError("No non-empty models found in the provided DynMS JSON."))
  
  scenarios = OrderedDict{Symbol,DynMSScenario}()
  for scenario in get(data, "scenarios", Any[])
    parsed = convert_dynms_scenario(scenario)
    scenarios[parsed.id] = parsed
  end

  return DynMSModelSet(dynms_models, scenarios, dynms_version)
end

"""
    convert_dynms_scenario(scenario::AbstractDict)

Convert a DynMS scenario dictionary into a `DynMSScenario`. The required
`tspan` must contain two numeric values. Omitted or null optional settings
become `nothing`; explicitly empty vectors and dictionaries are preserved.
"""
function convert_dynms_scenario(scenario::AbstractDict)
  tspan = get(scenario, "tspan", nothing)
  saveat = get(scenario, "saveat", nothing)
  parameters = get(scenario, "parameters", nothing)
  events_active = get(scenario, "eventsActive", nothing)
  events_save = get(scenario, "eventsSave", nothing)

  tspan isa AbstractVector && length(tspan) == 2 &&
    all(value -> value isa Real && !(value isa Bool), tspan) ||
    throw(ArgumentError(
      "DynMS scenario '$(scenario["id"])' requires a tspan array with two numeric values.",
    ))
  tspan = (Float64(tspan[1]), Float64(tspan[2]))

  converted_events_save = isnothing(events_save) ? nothing : Dict{Symbol,Tuple{Bool,Bool}}()
  if !isnothing(events_save)
    for (id, positions) in events_save
      length(positions) == 2 || throw(ArgumentError(
        "DynMS scenario '$(scenario["id"])' eventsSave entry '$id' must contain two values.",
      ))
      converted_events_save[Symbol(id)] = (Bool(positions[1]), Bool(positions[2]))
    end
  end

  return DynMSScenario(
    Symbol(scenario["id"]),
    Symbol(scenario["model"]),
    tspan,
    isnothing(saveat) ? nothing : Float64[Float64(value) for value in saveat],
    isnothing(parameters) ? nothing : Dict{Symbol,Float64}(
      Symbol(id) => Float64(value) for (id, value) in parameters
    ),
    isnothing(events_active) ? nothing : Dict{Symbol,Bool}(
      Symbol(id) => Bool(value) for (id, value) in events_active
    ),
    converted_events_save,
  )
end

"""
    convert_dynms_model(model::AbstractDict; nanmath::Bool=false)

Convert one validated DynMS model dictionary into a `DynMSModel`.

This is mainly useful when working with a model entry extracted from an
already-validated DynMS document. To import a file as a system, use
[`import_dynms`](@ref); for a Heta project, use [`import_heta`](@ref).
The `nanmath` option has the same meaning as in [`convert_dynms`](@ref).
"""
convert_dynms_model(model::AbstractDict; nanmath::Bool=false) = _convert_dynms_model(model; nanmath)

function isempty_dynms_model(model::AbstractDict)
  return all(isempty(get(model, key, Any[])) for key in (
    "constants", "dynamic", "static", "assignments", "timeEvents", "events"
  ))
end

function _convert_dynms_model(model::AbstractDict; nanmath::Bool=false)

  assignment_rules = _convert_dynms_assignments(model; nanmath)
  states = _convert_dynms_states(model; nanmath)
  time_events = _convert_dynms_time_events(model; nanmath)
  continuous_events = _convert_dynms_continuous_events(model; nanmath)
  discrete_events = _convert_dynms_discrete_events(model; nanmath)
  stop_events = _convert_dynms_stop_events(model; nanmath)
  parameters = _convert_dynms_parameters(
    model, time_events, continuous_events, discrete_events; nanmath,
  )
  observables = _convert_dynms_observables(model)

  return DynMSModel(
    Symbol(model["id"]),
    parameters,
    assignment_rules,
    states,
    time_events,
    continuous_events,
    discrete_events,
    stop_events,
    observables
  )
end

function _convert_dynms_parameters(model::AbstractDict, event_groups...; nanmath::Bool=false)
  affected = Set{Symbol}()
  for event in Iterators.flatten(values(group) for group in event_groups)
    union!(affected, keys(event.discrete_affects))
  end
  derived = OrderedDict{Symbol,DynMSExpr}()
  discrete = OrderedDict{Symbol,DynMSExpr}()
  for state in _dynms_static_defs(model)
    id = Symbol(string(state["id"]))
    initial = _convert_dynms_numeric_expr(
      get(state, "initial", 0.0), "static state '$id' initial value"; nanmath,
    )
    (id in affected ? discrete : derived)[id] = initial
  end
  return DynMSParameters(
    _convert_dynms_tunable(model),
    derived,
    discrete,
  )
end

function _convert_dynms_tunable(model::AbstractDict)
  tunable = OrderedDict{Symbol,Float64}()
  for constant in get(model, "constants", Any[])
    tunable[Symbol(string(constant["id"]))] = Float64(constant["value"])
  end
  return tunable
end

function _dynms_dynamic_defs(model::AbstractDict)
  return get(model, "dynamic", Any[])
end

function _dynms_static_defs(model::AbstractDict)
  return get(model, "static", Any[])
end

function _dynms_time_event_defs(model::AbstractDict)
  return get(model, "timeEvents", Any[])
end

function _dynms_event_defs(model::AbstractDict)
  return get(model, "events", Any[])
end

function _convert_dynms_assignments(model::AbstractDict; nanmath::Bool=false)
  assignment_rules = OrderedDict{Symbol,DynMSExpr}()
  for assignment in get(model, "assignments", Any[])
    id = Symbol(string(assignment["id"]))
    assignment_rules[id] = _convert_dynms_numeric_expr(assignment["rhs"], "assignment '$id'"; nanmath)
  end
  return assignment_rules
end

function _convert_dynms_states(model::AbstractDict; nanmath::Bool=false)
  states = OrderedDict{Symbol,DynMSState}()
  for state in _dynms_dynamic_defs(model)
    id = string(state["id"])
    haskey(state, "derivative") ||
      throw(ArgumentError("DynMS dynamic state '$id' does not include a derivative."))

    states[Symbol(id)] = DynMSState(
      _convert_dynms_numeric_expr(get(state, "initial", 0.0), "dynamic state '$id' initial value"; nanmath),
      _convert_dynms_numeric_expr(state["derivative"], "dynamic state '$id' derivative"; nanmath),
      Bool(get(state, "algebraic", false))
    )
  end
  return states
end

function _convert_dynms_time_events(model::AbstractDict; nanmath::Bool=false)
  events = OrderedDict{Symbol,DynMSTimeEvent}()
  for event in _dynms_time_event_defs(model)
    parsed = _convert_dynms_time_event(model, event; nanmath)
    events[parsed.id] = parsed
  end
  return events
end

function _convert_dynms_continuous_events(model::AbstractDict; nanmath::Bool=false)
  events = OrderedDict{Symbol,DynMSContinuousEvent}()
  for event in _dynms_event_defs(model)
    _dynms_event_kind(event) == :continuous || continue
    parsed = _convert_dynms_continuous_event(model, event; nanmath)
    events[parsed.id] = parsed
  end
  return events
end

function _convert_dynms_discrete_events(model::AbstractDict; nanmath::Bool=false)
  events = OrderedDict{Symbol,DynMSDiscreteEvent}()
  for event in _dynms_event_defs(model)
    _dynms_event_kind(event) == :discrete || continue
    parsed = _convert_dynms_discrete_event(model, event; nanmath)
    events[parsed.id] = parsed
  end
  return events
end

function _convert_dynms_stop_events(model::AbstractDict; nanmath::Bool=false)
  events = OrderedDict{Symbol,DynMSStopEvent}()
  for event in _dynms_event_defs(model)
    _dynms_event_kind(event) == :stop || continue
    parsed = _convert_dynms_stop_event(event; nanmath)
    events[parsed.id] = parsed
  end
  return events
end

function _convert_dynms_observables(model::AbstractDict)
  return Symbol[Symbol(string(obs["symbol"])) for obs in get(model, "observables", Any[])]
end

function _convert_dynms_time_event(model::AbstractDict, event; nanmath::Bool=false)
  trigger = event["trigger"]
  state_affects, discrete_affects = _convert_dynms_event_affects(model, event; nanmath)
  return DynMSTimeEvent(
    Symbol(string(event["id"])),
    _convert_dynms_value(get(trigger, "start", 0.0); nanmath),
    _convert_dynms_optional_value(get(trigger, "period", nothing); nanmath),
    _convert_dynms_optional_value(get(trigger, "stop", nothing); nanmath),
    state_affects,
    discrete_affects,
    Bool(get(trigger, "atStart", false)),
    Bool(get(event, "active", true))
  )
end

function _convert_dynms_continuous_event(model::AbstractDict, event; nanmath::Bool=false)
  state_affects, discrete_affects = _convert_dynms_event_affects(model, event; nanmath)
  return DynMSContinuousEvent(
    Symbol(string(event["id"])),
    _convert_dynms_condition(event["trigger"]["rhs"]; nanmath),
    state_affects,
    discrete_affects,
    Bool(get(event["trigger"], "atStart", false)),
    Bool(get(event, "active", true))
  )
end

function _convert_dynms_discrete_event(model::AbstractDict, event; nanmath::Bool=false)
  state_affects, discrete_affects = _convert_dynms_event_affects(model, event; nanmath)
  return DynMSDiscreteEvent(
    Symbol(string(event["id"])),
    _convert_dynms_condition(event["trigger"]["rhs"]; nanmath),
    state_affects,
    discrete_affects,
    Bool(get(event["trigger"], "atStart", false)),
    Bool(get(event, "active", true))
  )
end

function _convert_dynms_stop_event(event; nanmath::Bool=false)
  return DynMSStopEvent(
    Symbol(string(event["id"])),
    _convert_dynms_condition(event["trigger"]["rhs"]; nanmath),
    Bool(get(event["trigger"], "atStart", false)),
    Bool(get(event, "active", true))
  )
end

function _convert_dynms_event_affects(model::AbstractDict, event; nanmath::Bool=false)
  dynamic_state_ids = Set(string(state["id"]) for state in _dynms_dynamic_defs(model))
  discrete_ids = Set(string(state["id"]) for state in _dynms_static_defs(model))
  state_affects = OrderedDict{Symbol,DynMSExpr}()
  discrete_affects = OrderedDict{Symbol,DynMSExpr}()

  for action in get(event, "actions", Any[])
    state_id = string(action["state"])
    target = Symbol(state_id)
    rhs = _convert_dynms_numeric_expr(action["rhs"], "event $(event["id"]) update to '$state_id'"; nanmath)

    if state_id in dynamic_state_ids
      state_affects[target] = rhs
    elseif state_id in discrete_ids
      discrete_affects[target] = rhs
    else
      throw(ArgumentError("DynMS event $(event["id"]) updates unknown state '$state_id'."))
    end
  end

  return state_affects, discrete_affects
end

function _dynms_event_kind(event)
  trigger = event["trigger"]
  trigger_type = string(trigger["type"])

  trigger_type == "time" && return :time

  haskey(trigger, "detection") ||
    throw(ArgumentError("DynMS event $(event["id"]) has trigger type '$trigger_type' but does not include an explicit detection type."))

  detection_type = string(trigger["detection"])
  terminate_simulation = Bool(get(event, "stopSimulation", false))

  # Temporary backend limitation: stopSimulation is currently represented as a
  # separate StopEvent and is supported only for step-detected conditional events.
  if terminate_simulation
    trigger_type == "conditional" && detection_type == "step" && return :stop
    throw(ArgumentError(
      "DynMS event $(event["id"]) has an argument `stopSimulation` set to true, which is currently supported only for " *
      "trigger type 'conditional' with detection 'step'. Got type='$trigger_type', detection='$detection_type'."
    ))
  end

  trigger_type == "crossing" && detection_type == "root" && return :continuous
  trigger_type == "conditional" && detection_type == "step" && return :discrete

  throw(ArgumentError("Unsupported DynMS event trigger type/detection combination: type='$trigger_type', detection='$detection_type'."))
end

function _convert_dynms_optional_value(value; nanmath::Bool=false)
  isnothing(value) && return nothing
  return _convert_dynms_value(value; nanmath)
end

function _convert_dynms_value(value; nanmath::Bool=false)
  parsed = _convert_dynms_expr(value; nanmath)
  parsed isa Float64 && return parsed
  parsed isa Symbol && return parsed
  throw(ArgumentError("DynMS time-event value must be numeric or symbolic, got: $parsed"))
end

function _convert_dynms_condition(expr; nanmath::Bool=false)
  parsed = _convert_dynms_expr(expr; nanmath)
  parsed isa Union{Expr,Symbol} && return parsed
  throw(ArgumentError("DynMS event condition must parse to Expr or Symbol, got: $parsed"))
end

function _convert_dynms_numeric_expr(expr, context; nanmath::Bool=false)
  parsed = _convert_dynms_expr(expr; nanmath)
  parsed isa Bool &&
    throw(ArgumentError("DynMS $context must be numeric, got Boolean: $parsed"))
  return parsed::DynMSExpr
end

function _convert_dynms_expr(expr; nanmath::Bool=false)
  payload = _dynms_expr_payload(expr)
  payload isa Bool && return payload
  payload isa Number && return Float64(payload)

  try
    mathjson_expr = parse(MathJSON.MathJSONFormat, JSON.json(payload))
    return _dynms_mathjson_to_julia(mathjson_expr; nanmath)
  catch err
    @warn "MathJSON.jl failed to parse DynMS expression; using fallback parser." expr exception=(err, catch_backtrace())
    return _dynms_raw_expr_to_julia(payload; nanmath)
  end
end

function _dynms_expr_payload(expr)
  if expr isa AbstractDict && haskey(expr, "expr")
    format = string(get(expr, "format", "math-json"))
    format == "math-json" ||
      throw(ArgumentError("Unsupported DynMS expression format '$format'. Only 'math-json' is supported."))
    return expr["expr"]
  end

  return expr
end

function _dynms_mathjson_to_julia(expr::MathJSON.NumberExpr; nanmath::Bool=false)
  return Float64(expr.value)
end

function _dynms_mathjson_to_julia(expr::MathJSON.SymbolExpr; nanmath::Bool=false)
  return _dynms_symbol_to_julia(expr.name)
end

function _dynms_mathjson_to_julia(expr::MathJSON.StringExpr; nanmath::Bool=false)
  throw(ArgumentError("Unsupported DynMS MathJSON string literal: $(expr.value)"))
end

function _dynms_mathjson_to_julia(expr::MathJSON.FunctionExpr; nanmath::Bool=false)
  args = Any[_dynms_mathjson_to_julia(arg; nanmath) for arg in expr.arguments]
  return _dynms_operator_to_julia(expr.operator, args; nanmath)
end

function _dynms_raw_expr_to_julia(payload; nanmath::Bool=false)
  if payload isa Bool
    return payload
  elseif payload isa Number
    return Float64(payload)
  elseif payload isa AbstractString
    return _dynms_symbol_to_julia(payload)
  elseif payload isa AbstractVector
    isempty(payload) && throw(ArgumentError("DynMS MathJSON expression cannot be an empty array."))
    operator = Symbol(payload[1])
    args = Any[_dynms_raw_expr_to_julia(arg; nanmath) for arg in payload[2:end]]
    return _dynms_operator_to_julia(operator, args; nanmath)
  elseif payload isa AbstractDict
    haskey(payload, "num") && return _dynms_parse_mathjson_number(payload["num"])
    haskey(payload, "sym") && return _dynms_symbol_to_julia(string(payload["sym"]))
    haskey(payload, "str") && throw(ArgumentError("Unsupported DynMS MathJSON string literal: $(payload["str"])"))
    haskey(payload, "fn") && return _dynms_raw_expr_to_julia(payload["fn"]; nanmath)
  end

  throw(ArgumentError("Unsupported DynMS expression: $payload"))
end

function _dynms_parse_mathjson_number(x)
  x isa Number && return Float64(x)
  s = string(x)
  s == "Infinity" && return Inf
  s == "+Infinity" && return Inf
  s == "-Infinity" && return -Inf
  s == "NaN" && return NaN
  return parse(Float64, s)
end

function _dynms_symbol_to_julia(name::AbstractString)
  name == "pi" && return :pi
  name == "Pi" && return :pi
  name == "e" && return :(Base.MathConstants.e)
  name == "ExponentialE" && return :(Base.MathConstants.e)
  name == "True" && return true
  name == "False" && return false

  return Symbol(name)
end

function _dynms_operator_to_julia(operator::Symbol, args::Vector{Any}; nanmath::Bool=false)
  if nanmath
    operator == :Power && return :(NaNMath.pow($(args[1]), $(args[2])))
    operator == :Square && return :(NaNMath.pow($(only(args)), 2))
    operator == :Root && return length(args) == 1 ?
      :(NaNMath.sqrt($(only(args)))) : :(NaNMath.pow($(args[1]), 1 / $(args[2])))
    operator == :Sqrt && return :(NaNMath.sqrt($(only(args))))
    (operator == :Ln || (operator == :Log && length(args) == 1)) &&
      return :(NaNMath.log($(only(args))))
    operator in (:Log10, :Lg) && return :(NaNMath.log10($(only(args))))
    operator in (:Log2, :Lb) && return :(NaNMath.log2($(only(args))))
  end

  operator == :Add && return _dynms_call(:+, args; empty=0.0)
  operator == :Multiply && return _dynms_call(:*, args; empty=1.0)
  operator == :Negate && return :(-$(only(args)))
  operator == :Subtract && return length(args) == 1 ? :(-$(only(args))) : _dynms_call(:-, args)
  operator == :Divide && return length(args) == 1 ? :(inv($(only(args)))) : _dynms_call(:/, args)
  operator == :Power && return :($(args[1]) ^ $(args[2]))

  operator == :Abs && return :(abs($(only(args))))
  operator == :Sqrt && return :(sqrt($(only(args))))
  operator == :Exp && return :(exp($(only(args))))
  operator == :Ln && return :(log($(only(args))))
  operator == :Log && return length(args) == 1 ? :(log($(only(args)))) : :(log($(args[2]), $(args[1])))
  operator == :Log10 && return :(log10($(only(args))))
  operator == :Lg && return :(log10($(only(args))))
  operator == :Lb && return :(log2($(only(args))))
  operator == :Log2 && return :(log2($(only(args))))

  operator == :Sin && return :(sin($(only(args))))
  operator == :Cos && return :(cos($(only(args))))
  operator == :Tan && return :(tan($(only(args))))
  operator == :Cot && return :(cot($(only(args))))
  operator == :Sec && return :(sec($(only(args))))
  operator == :Csc && return :(csc($(only(args))))
  operator == :Arcsin && return :(asin($(only(args))))
  operator == :Arccos && return :(acos($(only(args))))
  operator == :Arctan && return Expr(:call, :atan, args...)
  operator == :Arccot && return :(acot($(only(args))))
  operator == :Arcsec && return :(asec($(only(args))))
  operator == :Arccsc && return :(acsc($(only(args))))

  operator == :Min && return Expr(:call, :min, args...)
  operator == :Max && return Expr(:call, :max, args...)
  operator == :Floor && return :(floor($(only(args))))
  operator == :Ceil && return :(ceil($(only(args))))
  operator == :Round && return :(round($(only(args))))
  operator == :Mod && return :(mod($(args[1]), $(args[2])))
  operator == :Sign && return :(sign($(only(args))))
  operator == :Square && return :($(only(args)) ^ 2)
  operator == :Root && return length(args) == 1 ? :(sqrt($(only(args)))) : :($(args[1]) ^ (1 / $(args[2])))
  operator == :Factorial && return :(factorial(round(Int, $(only(args)))))

  operator == :Less && return _dynms_pairwise_comparison(Symbol("<"), args)
  operator == :LessEqual && return _dynms_pairwise_comparison(Symbol("<="), args)
  operator == :Greater && return _dynms_pairwise_comparison(Symbol(">"), args)
  operator == :GreaterEqual && return _dynms_pairwise_comparison(Symbol(">="), args)
  operator == :Equal && return _dynms_pairwise_comparison(Symbol("=="), args)
  operator == :NotEqual && return :(!$(_dynms_pairwise_comparison(Symbol("=="), args)))
  operator == :And && return _dynms_short_circuit(Symbol("&&"), args; empty=true)
  operator == :Or && return _dynms_short_circuit(Symbol("||"), args; empty=false)
  operator == :Not && return :(!Bool($(only(args))))
  operator == :Xor && return isempty(args) ? false : Expr(:call, :xor, args...)

  operator == :If && return :($(args[1]) ? $(args[2]) : $(args[3]))
  operator == :Which && return _dynms_which(args)

  throw(ArgumentError("Unsupported DynMS MathJSON operator '$operator'."))
end

function _dynms_which(args::Vector{Any})
  isempty(args) && throw(ArgumentError("Which requires at least one argument."))
  n = length(args)
  has_default = isodd(n)
  expr = has_default ? args[end] : :(throw(ArgumentError("No matching Which branch and no default value provided.")))
  pairs_n = has_default ? n - 1 : n
  for i in (pairs_n - 1):-2:1
    expr = :($(args[i]) ? $(args[i + 1]) : $expr)
  end
  return expr
end

function _dynms_call(op::Symbol, args::Vector{Any}; empty=nothing)
  isempty(args) && return empty
  length(args) == 1 && return only(args)
  return Expr(:call, op, args...)
end

function _dynms_pairwise_comparison(op::Symbol, args::Vector{Any})
  length(args) <= 1 && return true
  comparisons = Any[Expr(:call, op, args[i], args[i + 1]) for i in 1:(length(args) - 1)]
  return _dynms_short_circuit(Symbol("&&"), comparisons; empty=true)
end

function _dynms_short_circuit(op::Symbol, args::Vector{Any}; empty)
  isempty(args) && return empty
  ex = args[1]
  for arg in args[2:end]
    ex = Expr(op, ex, arg)
  end
  return ex
end
