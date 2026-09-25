using HetaImporter
using Test
using OrdinaryDiffEqTsit5
import SciMLBase
import SymbolicIndexingInterface as SII
import SciMLStructures

if !isdefined(@__MODULE__, :_parse_fresh_heta)
  const JULIA_BACKEND_TEST_MODELS = joinpath(@__DIR__, "..", "models", "dynms")
  function _parse_fresh_heta(model_name::AbstractString)
    return mktempdir() do build_dir
      parse_heta(joinpath(JULIA_BACKEND_TEST_MODELS, model_name); build_dir)
    end
  end
end

@testset "HetaODESystem ODEProblem interface" begin
  model = _parse_fresh_heta("0-hello-world").models[:mm]
  problem = ODEProblem(build_ode_system(model), (0.0, 10.0))
  u0 = problem.u0(problem.p, first(problem.tspan))

  @test u0 == [10.0, 0.0]
  @test problem.p isa HetaParameters
  @test problem.p.tunable == [0.1, 2.5]
  @test problem.p.discrete == [1.0]

  du = similar(u0)
  problem.f(du, u0, problem.p, 0.0)
  @test du[1] < 0
  @test du[2] > 0
  @test sum(du) ≈ 0.0

  observed = problem.f.observed
  @test observed(:S, u0, problem.p, 0.0) ≈ 10.0
  @test observed([:S, :P], u0, problem.p, 0.0) ≈ [10.0, 0.0]
  @test observed((:S, :P), u0, problem.p, 0.0) == (10.0, 0.0)
  @test observed(:S) === observed(:S)
  @test_throws ArgumentError observed(:not_in_model)

  @test SII.variable_symbols(problem.f) == [:S_amt_, :P_amt_]
  @test SII.parameter_symbols(problem.f) == [:Vmax, :Km, :default_comp]
  @test SII.is_parameter(problem.f, :Vmax)
  @test SII.is_parameter(problem.f, :default_comp)
  @test SII.parameter_index(problem.f, :Vmax) == 1
  @test SII.parameter_index(problem.f, :default_comp) == 3
  @test SII.is_observed(problem.f, :S)
  @test SII.observed(problem.f, :S)(u0, problem.p, 0.0) ≈ 10.0
  @test SII.timeseries_parameter_index(problem.f, :default_comp) ==
    SII.ParameterTimeseriesIndex(1, 1)

  tunable, repack, aliases = SciMLStructures.canonicalize(
    SciMLStructures.Tunable(),
    problem.p,
  )
  @test aliases
  @test tunable == [0.1, 2.5]
  @test repack([0.2, 3.0]).tunable == [0.2, 3.0]

  initialize_discrete! = function (discrete, tunable)
    discrete[1] = 2 * tunable[1]
    discrete[2] = discrete[1] + tunable[2]
    return nothing
  end
  parameters = HetaParameters([2.0, 3.0], 2, initialize_discrete!)
  @test parameters.discrete == [4.0, 7.0]

  # Runtime event values belong to one solve. Repacking a new optimization point
  # must initialize a fresh discrete vector rather than retaining those values.
  parameters.discrete .= 100.0
  rebuilt = SciMLStructures.replace(
    SciMLStructures.Tunable(),
    parameters,
    BigFloat[5.0, 7.0],
  )
  @test rebuilt.tunable == BigFloat[5.0, 7.0]
  @test rebuilt.discrete == BigFloat[10.0, 17.0]
  @test eltype(rebuilt.discrete) == BigFloat
  @test parameters.discrete == [100.0, 100.0]

  SciMLStructures.replace!(SciMLStructures.Tunable(), parameters, [4.0, 1.0])
  @test parameters.discrete == [8.0, 9.0]

  restored = SciMLStructures.replace(
    SciMLStructures.Discrete(),
    parameters,
    [11.0, 12.0],
  )
  @test restored.discrete == [11.0, 12.0]

  time_model = _parse_fresh_heta("11-time-switcher").models[:nameless]
  time_problem = ODEProblem(build_ode_system(time_model), (0.0, 50.0))
  @test haskey(time_problem.kwargs, :callback)
  @test !haskey(time_problem.kwargs, :tstops)

  time_code = time_problem.f.sys.generated_code.time_events
  sw0_schedule = HetaImporter._heta_runtime_function(time_code[:sw0].schedule_func)
  sw2_schedule = HetaImporter._heta_runtime_function(time_code[:sw2].schedule_func)
  fake_integrator(t, p=time_problem.p) = (
    t=t,
    tdir=one(t),
    p=p,
    sol=(prob=(tspan=(zero(t), convert(typeof(t), 50)),),),
  )

  @test HetaImporter._heta_next_time(sw0_schedule, fake_integrator(0.0f0)) === 40.0f0
  @test HetaImporter._heta_next_time(sw0_schedule, fake_integrator(40.0f0)) === nothing
  @test HetaImporter._heta_next_time(sw2_schedule, fake_integrator(0.0f0)) === 5.0f0
  @test HetaImporter._heta_next_time(sw2_schedule, fake_integrator(5.0f0)) === 29.0f0
  @test HetaImporter._heta_next_time(sw2_schedule, fake_integrator(29.0f0)) === nothing

  updated_parameters = copy(time_problem.p)
  updated_parameters.tunable[3] = 7.0
  @test HetaImporter._heta_next_time(
    sw2_schedule,
    fake_integrator(0.0f0, updated_parameters),
  ) === 7.0f0

  bounded_schedule = _ -> (start=0, period=12, stop=24)
  @test HetaImporter._heta_next_time(
    bounded_schedule,
    fake_integrator(0.0f0),
  ) === 12.0f0
  @test HetaImporter._heta_next_time(
    bounded_schedule,
    fake_integrator(12.0f0),
  ) === 24.0f0
  @test HetaImporter._heta_next_time(
    bounded_schedule,
    fake_integrator(24.0f0),
  ) === nothing
  bounded = HetaImporter._heta_time_event_schedule(
    bounded_schedule,
    fake_integrator(0.0f0),
  )
  @test HetaImporter._heta_time_event_occurs_at(bounded, 0.0f0)
  @test HetaImporter._heta_time_event_occurs_at(bounded, 12.0f0)
  @test !HetaImporter._heta_time_event_occurs_at(bounded, 6.0f0)
  @test bounded.start isa Float32
  @test bounded.period isa Float32
  @test bounded.stop isa Float32

  time_solution = solve(time_problem, Tsit5(); save_everystep=false)
  @test SciMLBase.successful_retcode(time_solution)
  @test time_solution.u[end][2] > 0

  continuous_model = _parse_fresh_heta("9-c-switcher").models[:nameless]
  continuous_problem = ODEProblem(
    build_ode_system(continuous_model),
    (0.0, 10.0),
  )
  @test haskey(continuous_problem.kwargs, :callback)

  discrete_model = _parse_fresh_heta("16-d-switcher").models[:nameless]
  discrete_problem = ODEProblem(
    build_ode_system(discrete_model),
    (0.0, 10.0),
  )
  @test haskey(discrete_problem.kwargs, :callback)
end

@testset "native event initial affects" begin
  base_model = _parse_fresh_heta("0-hello-world").models[:mm]
  empty_affects = HetaImporter.OrderedDict{Symbol,HetaImporter.DynMSExpr}()
  initial_affect = HetaImporter.OrderedDict{Symbol,HetaImporter.DynMSExpr}(
    :P_amt_ => 20.0,
  )

  function model_with_events(; time_events=base_model.time_events,
      continuous_events=base_model.continuous_events,
      discrete_events=base_model.discrete_events,
      stop_events=base_model.stop_events)
    return HetaImporter.DynMSModel(
      base_model.id,
      base_model.parameters,
      base_model.assignment_rules,
      base_model.states,
      time_events,
      continuous_events,
      discrete_events,
      stop_events,
      base_model.observables,
    )
  end

  time_event = HetaImporter.DynMSTimeEvent(
    :time_at_start,
    0.0,
    nothing,
    nothing,
    initial_affect,
    empty_affects,
    true,
    true,
  )
  time_events = HetaImporter.OrderedDict(:time_at_start => time_event)
  time_problem = ODEProblem(
    build_ode_system(model_with_events(; time_events)),
    (0.0, 0.1),
  )
  time_integrator = init(time_problem, Tsit5())
  @test time_integrator.u[2] == 20.0

  future_time_event = HetaImporter.DynMSTimeEvent(
    :time_after_start,
    0.05,
    nothing,
    nothing,
    initial_affect,
    empty_affects,
    true,
    true,
  )
  future_time_events = HetaImporter.OrderedDict(
    :time_after_start => future_time_event,
  )
  future_time_problem = ODEProblem(
    build_ode_system(model_with_events(; time_events=future_time_events)),
    (0.0, 0.1),
  )
  future_time_integrator = init(future_time_problem, Tsit5())
  @test future_time_integrator.u[2] == 0.0

  continuous_event = HetaImporter.DynMSContinuousEvent(
    :continuous_at_start,
    :S_amt_,
    initial_affect,
    empty_affects,
    true,
    true,
  )
  continuous_events = HetaImporter.OrderedDict(
    :continuous_at_start => continuous_event,
  )
  continuous_problem = ODEProblem(
    build_ode_system(model_with_events(; continuous_events)),
    (0.0, 0.1),
  )
  continuous_integrator = init(continuous_problem, Tsit5())
  @test continuous_integrator.u[2] == 20.0

  discrete_event = HetaImporter.DynMSDiscreteEvent(
    :discrete_at_start,
    :(S_amt_ > 0),
    initial_affect,
    empty_affects,
    true,
    true,
  )
  discrete_events = HetaImporter.OrderedDict(
    :discrete_at_start => discrete_event,
  )
  discrete_problem = ODEProblem(
    build_ode_system(model_with_events(; discrete_events)),
    (0.0, 0.1),
  )
  discrete_integrator = init(discrete_problem, Tsit5())
  @test discrete_integrator.u[2] == 20.0

  inactive_event = HetaImporter.DynMSDiscreteEvent(
    :inactive_at_start,
    :(S_amt_ < 0),
    initial_affect,
    empty_affects,
    true,
    true,
  )
  inactive_events = HetaImporter.OrderedDict(
    :inactive_at_start => inactive_event,
  )
  inactive_problem = ODEProblem(
    build_ode_system(model_with_events(; discrete_events=inactive_events)),
    (0.0, 0.1),
  )
  inactive_integrator = init(inactive_problem, Tsit5())
  @test inactive_integrator.u[2] == 0.0

  stop_event = HetaImporter.DynMSStopEvent(
    :stop_at_start,
    :(S_amt_ > 0),
    true,
    true,
  )
  stop_events = HetaImporter.OrderedDict(:stop_at_start => stop_event)
  stop_problem = ODEProblem(
    build_ode_system(model_with_events(; stop_events)),
    (0.0, 1.0),
  )
  stop_solution = solve(stop_problem, Tsit5())
  @test last(stop_solution.t) == first(stop_problem.tspan)
end
