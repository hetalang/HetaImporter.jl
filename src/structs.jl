################################## Platform ###########################################
"""
    struct Platform{M,C}
      models::Dict{Symbol,M}     # dictionary storing Models
      scenarios::Dict{Symbol,C} # dictionary storing Scenarios
    end

The main storage representing a modeling platform.
Typically HetaSimulator works with one platform object which can include several models and scenarios.

Usually a `Platform` is created based on Heta formatted files using [`load_platform`]{@ref}.

To get the platform content use methods: `models(platform)`, `scenarios(platform).
"""
struct Platform{M,C}
  models::OrderedDict{Symbol,M}
  scenarios::OrderedDict{Symbol,C}
end

function Platform(
    models::NamedTuple,
    scenarios::Tuple,
    version::String
)
    print("Loading platform... ")
    model_pairs = [pair[1] => Model(pair[2]...) for pair in pairs(models)]
    
    platform = Platform(
        OrderedDict{Symbol,Model}(model_pairs),
        OrderedDict{Symbol,Any}()
    )
    println("OK!")

    return platform
end

models(p::Platform) = p.models
scenarios(p::Platform) = p.scenarios

function Base.show(io::IO, mime::MIME"text/plain", p::Platform)
  models_names = join(keys(p.models), ", ")
  scn_names = join(keys(p.scenarios), ", ")

  measurements_count = 0
  for (x, y) in scenarios(p)
    measurements_count += length(measurements(y))
  end

  println(io, "Platform with $(length(models(p))) model(s), $(length(scenarios(p))) scenario(s), $measurements_count measurement(s)")
  println(io, "   Models: $models_names")
  println(io, "   Scenarios: $scn_names")
end

################################## Model ###########################################

abstract type AbstractModel end

"""
    struct Model{IF,OF,EV,SG,EA, MM} <: AbstractModel
      init_func::IF
      ode_func::OF
      events::EV
      saving_generator::SG
      records_output::AbstractVector{Pair{Symbol,Bool}}
      constants::NamedTuple
      statics::NamedTuple
      events_active::EA
      mass_matrix::MM
    end

Structure storing core properties of ODE model.
This represent the content of one namespace from a Heta platform.

To get list of model content use methods: constants(model), records(model), switchers(model).

To get the default model options use methods: 
`events_active(model)`, `events_save(model)`, `observables(model)`.
These values can be rewritten by a [`Scenario`]{@ref}.
"""
struct Model{IF,OF,EV,SG,EA, MM} <: AbstractModel
  init_func::IF
  ode_func::OF
  events::EV # IDEA: use (:TimeEvent, ...) instead of TimeEvent(...)
  saving_generator::SG
  records_output::AbstractVector{Pair{Symbol,Bool}}
  constants::NamedTuple
  nstatics::Int
  nstates::Int
  events_active::EA
  mass_matrix::MM
end

function Model(
    init_func::Function,
    ode_func::Function,
    time_events::NamedTuple,
    d_events::NamedTuple,
    c_events::NamedTuple,
    stop_events::NamedTuple,
    saving_generator::Function,
    constants_num::NamedTuple,
    statics_ids::Tuple,
    events_active::NamedTuple,
    records_output::NamedTuple,
    ss_vars::NamedTuple
)
    events = Pair[]
    ## FIXME : remove event name from heta-compiler
    for (name,event_tuple) in pairs(time_events) # time events
        evt = name => TimeEvent(event_tuple[1], event_tuple[2], event_tuple[3])
        push!(events, evt)
    end
    for (name,event_tuple) in pairs(d_events) # d events
        evt = name => DEvent(event_tuple[1], event_tuple[2], event_tuple[3])
        push!(events, evt)
    end
    for (name,event_tuple) in pairs(c_events) # c events
        evt = name => CEvent(event_tuple[1], event_tuple[2], event_tuple[3])
        push!(events, evt)
    end
    for (name,event_tuple) in pairs(stop_events) # stop events
        evt = name => StopEvent(event_tuple[1], event_tuple[2])
        push!(events, evt)
    end

    #observable_pairs = filter((p) -> p[2], pairs(records_output)) # from records_output
    #observables = Symbol[p[1] for p in observable_pairs]
    records_output_ = collect(Pair{Symbol,Bool}, pairs(records_output))
    events_active_ = collect(Pair{Symbol,Bool}, pairs(events_active))

    # DAE problems
    ss_ids = values(ss_vars)
    isdae = false in ss_ids
    mass_matrix = isdae ? Diagonal([Bool(s) for s in ss_ids]) : I

    ### fake run, disabled because it slows model loading down
    #=
    _u0, _p0 = init_func(constants_num)
    constants = LVector(constants_num)
    _params = Params(constants, _p0)
    prob = ODEProblem(ode_func, _u0, (0.,1.), _params)

    # check if default alg can solve the prob
    integrator = init(prob, DEFAULT_ALG)
    step!(integrator)
    ret = check_error(integrator)
    ret != :Success && @warn "Default algorithm returned $ret status. Consider using a different algorithm."
    =#
    model = Model(
        init_func,            # init_func
        ode_func,             # ode_func
        NamedTuple(events),   # events :: Changed to NamedTuple
        saving_generator,     # saving_generator
        records_output_,       
        constants_num,        # constants :: Changed to NamedTuple
        length(statics_ids),  # statics_num
        length(ss_vars),      # ss_vars_num
        NamedTuple(events_active_), # events_active :: Changed to NamedTuple
        mass_matrix
    )

    return model
end

constants(m::Model) = [keys(m.constants)...] # ids of constants
records(m::Model) = first.(m.records_output) # ids of records
switchers(m::Model) = [keys(m.events)...]    # ids of events
events_active(m::Model) = collect(Pair{Symbol, Bool}, pairs(m.events_active))
events_save(m::Model) = [first(x) => (false,false) for x in pairs(m.events)]
observables(m::Model) = begin                # ids of active observables
  only_true = filter((p) -> last(p), m.records_output)
  first.(only_true)
end

# auxilary function to display first n components of Vector or Tuple
function print_lim(x::Union{Vector, Tuple}, n::Int)
  first_n = ["$y" for y in first(x, n)]
  if length(x) > n
    push!(first_n, "...")
  elseif length(x) == 0
    return "-"
  end
  return join(first_n, ", ")
end

function print_lim(::Nothing, n::Int)
  return "-"
end

function print_lim(x::NamedTuple, n::Int)
  x_keys = keys(x)
  if length(x) > n
    string_array = ["$(x_keys[i])=$(x[i])" for i in 1:n]
    push!(string_array, "...")
  else
    string_array = ["$(x_keys[i])=$(x[i])" for i in 1:length(x)]
  end

  return "(" * join(string_array, ", ") * ")"
end

function Base.show(io::IO, mime::MIME"text/plain", m::AbstractModel)
  const_str = print_lim(constants(m), 10)
  record_str = print_lim(records(m), 10)
  switchers_str = print_lim(switchers(m), 10)

  println(io, "Model contains $(length(m.constants)) constant(s), $(length(m.records_output)) record(s), $(length(m.events)) switcher(s).")
  println(io, "   Constants (model-level parameters): $const_str")
  println(io, "   Records (observables): $record_str")
  println(io, "   Switchers (events): $switchers_str")
end

################################## Events ##############################################
abstract type AbstractEvent end

struct TimeEvent{F1,F2} <: AbstractEvent
  condition_func::F1
  affect_func::F2
  atStart::Bool
end

struct CEvent{F1,F2} <: AbstractEvent
  condition_func::F1
  affect_func::F2
  atStart::Bool
end

struct DEvent{F1,F2} <: AbstractEvent
  condition_func::F1
  affect_func::F2
  atStart::Bool
end

struct StopEvent{F1} <: AbstractEvent
  condition_func::F1
  atStart::Bool
end