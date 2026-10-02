using HetaImporter
using Test
using OrdinaryDiffEqTsit5
import SciMLBase
import SymbolicIndexingInterface as SII
import SciMLStructures

@testset "ODEProblem and symbolic results" begin
  system = HetaImporter.build_ode_system(_parse_fresh_heta("0-hello-world").models[:mm])
  problem = ODEProblem(system, (0.0, 10.0))
  u0 = problem.u0(problem.p, 0.0)
  @test u0 == [10.0, 0.0]
  @test problem.p.tunable == [0.1, 2.5]
  @test problem.p.derived == [1.0]
  @test isempty(problem.p.discrete)
  @test ODEProblem(system, (0.0, 10.0); p=[0.2, 3.0]).p.tunable == [0.2, 3.0]
  @test_throws DimensionMismatch ODEProblem(system, (0.0, 10.0); p=[0.2])
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); u0=[1.0, 0.0])
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); callback=identity)

  solution = solve(problem, Tsit5(); save_everystep=false)
  @test SciMLBase.successful_retcode(solution)
  @test solution.u[end][1] < u0[1]
  @test sum(solution.u[end]) ≈ sum(u0)
  @test first(solution[:S]) == 10.0
  @test first(solution[[:S_amt_, :S]]) == [10.0, 10.0]
  @test problem.f.observed((:S, :P), u0, problem.p, 0.0) == (10.0, 0.0)
  @test getp(problem.f, :Vmax)(solution) == 0.1

  for symbol in (:not_in_model, :Vmax, :t, :(S + P))
    @test_throws ArgumentError problem.f.observed(symbol, u0, problem.p, 0.0)
  end
  @test_throws ArgumentError solution[[:Vmax, :S]]
end

# A constant state and an observable depending on a parameter that events can change.
function _event_system(; time_events=Any[], events=Any[])
  model = HetaImporter.parse_dynms_model(Dict(
    "id" => "event_test",
    "constants" => [Dict("id" => "k", "value" => 1.0)],
    "dynamic" => [Dict("id" => "x", "initial" => 1.0, "derivative" => 0.0)],
    "static" => [
      Dict("id" => "derived", "initial" => ["Multiply", 2.0, "k"]),
      Dict("id" => "p", "initial" => "k"),
    ],
    "assignments" => [Dict("id" => "y", "rhs" => ["Divide", "x", "p"])],
    "timeEvents" => time_events,
    "events" => events,
  ))
  return HetaImporter.build_ode_system(model)
end

@testset "parameter recomputation and event history" begin
  event = Dict(
    "id" => "change_parameter",
    "trigger" => Dict("start" => 0.5),
    "actions" => [Dict("state" => "p", "rhs" => 2.0)],
  )
  system = _event_system(; time_events=[event])
  problem = ODEProblem(system, (0.0, 1.0))
  @test problem.p.derived == [2.0]
  @test problem.p.discrete == [1.0]

  solution = solve(problem, Tsit5(); save_everystep=false)
  @test SII.parameter_timeseries(solution, 1) == [0.0, 0.5]
  @test getp(problem.f, :p)(solution) == [1.0, 2.0]
  @test solution(0.25; idxs=:y) == 1.0
  @test solution(0.75; idxs=:y) == 0.5
  @test last(solution[:y]) == 0.5

  # Repacking tunables must reset event values and preserve the new numeric type.
  problem.p.discrete[1] = 100.0
  tunable, repack, _ = SciMLStructures.canonicalize(SciMLStructures.Tunable(), problem.p)
  @test tunable == [1.0]
  rebuilt = repack(BigFloat[3.0])
  @test rebuilt.derived == BigFloat[6.0] && eltype(rebuilt.derived) == BigFloat
  @test rebuilt.discrete == BigFloat[3.0] && eltype(rebuilt.discrete) == BigFloat
  @test problem.p.discrete == [100.0]

  SciMLStructures.replace!(SciMLStructures.Tunable(), problem.p, [2.0])
  @test problem.p.derived == [4.0]
  @test problem.p.discrete == [2.0]
  constants, _, _ = SciMLStructures.canonicalize(SciMLStructures.Constants(), problem.p)
  @test constants == [4.0]
  restored = SciMLStructures.replace(SciMLStructures.Discrete(), problem.p, [7.0])
  @test restored.discrete == [7.0] && restored.derived == [4.0]
end

@testset "time event schedule" begin
  event = Dict{String,Any}(
    "id" => "periodic",
    "trigger" => Dict("start" => 0.0, "period" => 0.25, "stop" => 0.5, "atStart" => false),
    "actions" => [Dict("state" => "x", "rhs" => ["Add", "x", 1.0])],
  )
  system = _event_system(; time_events=[event])
  for (start_time, expected) in ((0.0, 2.0), (0.25, 2.0), (0.125, 1.0), (0.75, 1.0))
    problem = ODEProblem(system, (start_time, 1.0))
    @test init(problem, Tsit5()).u[1] == expected
  end
  solution = solve(ODEProblem(system, (0.0, 1.0)), Tsit5(); save_everystep=false)
  @test last(solution[:x]) == 4.0  # one affect each at 0.0, 0.25, and 0.5
  @test HetaImporter._heta_time_event_occurs_at(
    (start=0.0, period=0.1, stop=0.5), 0.3,
  )

  event["active"] = false
  inactive = ODEProblem(_event_system(; time_events=[event]), (0.0, 1.0))
  @test last(solve(inactive, Tsit5())[:x]) == 1.0

  event["active"] = true
  event["trigger"] = Dict("start" => "k", "period" => 0.25, "stop" => 0.5)
  delayed = ODEProblem(_event_system(; time_events=[event]), (0.0, 1.0); p=[0.25])
  @test last(solve(delayed, Tsit5())[:x]) == 3.0
end

@testset "conditional events" begin
  for (type, detection, condition) in (
    ("crossing", "root", ["Subtract", "t", 0.5]),
    ("conditional", "step", ["Greater", "t", 0.5]),
  )
    event = Dict(
      "id" => "change_state",
      "trigger" => Dict("type" => type, "detection" => detection, "rhs" => condition),
      "actions" => [Dict("state" => "x", "rhs" => 5.0)],
    )
    problem = ODEProblem(_event_system(; events=[event]), (0.0, 1.0))
    @test last(solve(problem, Tsit5())[:x]) == 5.0

    for (at_start, threshold, expected) in ((true, 0.0, 5.0), (false, 0.0, 1.0), (true, 2.0, 1.0))
      event["trigger"] = Dict(
        "type" => type, "detection" => detection, "atStart" => at_start,
        "rhs" => [type == "crossing" ? "Subtract" : "Greater", "x", threshold],
      )
      problem = ODEProblem(_event_system(; events=[event]), (0.0, 1.0))
      @test init(problem, Tsit5()).u[1] == expected
    end
  end

  stop = Dict(
    "id" => "stop",
    "stopSimulation" => true,
    "trigger" => Dict(
      "type" => "conditional", "detection" => "step", "atStart" => true,
      "rhs" => ["Greater", "x", 0.0],
    ),
  )
  solution = solve(ODEProblem(_event_system(; events=[stop]), (0.0, 1.0)), Tsit5())
  @test last(solution.t) == 0.0
end
