using HetaImporter
using Test
using OrdinaryDiffEqTsit5

@testset "Partial parameter overrides" begin
  system = import_heta(_dynms_model_dir("0-hello-world"), :mm)
  reference = solve(ODEProblem(system, (0.0, 1.0); p=[3.0, 2.5]), Tsit5())
  for overrides in (Dict(:Vmax => 3.0), [:Vmax => 3.0])
    problem = ODEProblem(system, (0.0, 1.0); p=overrides)
    @test problem.p.tunable == [3.0, 2.5]
    @test problem.p.derived == [1.0]
    @test isempty(problem.p.discrete)
    @test problem.u0(problem.p, 0.0) == [10.0, 0.0]
    solution = solve(problem, Tsit5())
    @test SciMLBase.successful_retcode(solution)
  end
  @test collect(values(parameters(system).tunable)) == [0.1, 2.5]
  @test ODEProblem(system, (0.0, 1.0); p=[:Km => 7, :Vmax => 3]).p.tunable == [3, 7]
  @test ODEProblem(system, (0.0, 1.0); p=[3.0, 7.0]).p.tunable == [3.0, 7.0]
  for overrides in (Dict(:unknown => 1.0), [:default_comp => 1.0], [:S => 1.0],
                    Dict("Vmax" => 1.0), ["Vmax" => 1.0],
                    [:Vmax => 1.0, :Vmax => 2.0], Dict(:Vmax => "bad"),
                    Any[:Vmax => 1.0, 2.0], (Vmax=1.0,))
    @test_throws ArgumentError ODEProblem(system, (0.0, 1.0); p=overrides)
  end
  @test_throws DimensionMismatch ODEProblem(system, (0.0, 1.0); p=[1.0])
  @test_throws DimensionMismatch ODEProblem(system, (0.0, 1.0); p=[])
end

@testset "ODEProblem and symbolic results" begin
  system = import_heta(_dynms_model_dir("0-hello-world"), :mm)
  problem = ODEProblem(system, (0.0, 10.0))
  @test ODEProblem(system, (0, 10)).tspan === (0.0, 10.0)
  @test ODEProblem(system, (0.0f0, 10.0f0)).tspan === (0.0f0, 10.0f0)
  u0 = problem.u0(problem.p, 0.0)
  @test u0 == [10.0, 0.0]
  @test problem.p.tunable == [0.1, 2.5]
  @test problem.p.derived == [1.0]
  @test isempty(problem.p.discrete)
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); u0=[1.0, 0.0])
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); callback=identity)
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); callback=nothing)

  solution = solve(problem, Tsit5(); saveat=1.0)
  @test size(solution) == (2, 11)
  @test SciMLBase.successful_retcode(solution)
  @test last(solution[:S]) ≈ 9.206648
  @test first(solution[[:S_amt_, :S]]) == [10.0, 10.0]
  @test solution.ps[:default_comp] == 1.0
  @test solution.ps[[:Vmax, :Km]] == [0.1, 2.5]
end

@testset "Time events and activation overrides" begin
  system = import_heta(_dynms_model_dir("11-time-switcher"))
  problem = ODEProblem(system, (0, 30); p=[0.01, 0.01, 5.5])
  solution = solve(problem, Tsit5())
  @test SciMLBase.successful_retcode(solution)
  @test 5.5 in solution.t
  @test 29.5 in solution.t
  @test last(solution[:s2]) ≈ 4.0

  @test length(problem.kwargs[:callback].discrete_callbacks) == 2

  # sw1 is inactive in the model; enabling it adds dosing callbacks.
  enabled = ODEProblem(system, (0, 30); events_active=Dict(:sw1 => true))
  @test length(enabled.kwargs[:callback].discrete_callbacks) == 3
  enabled_solution = solve(enabled, Tsit5())
  @test SciMLBase.successful_retcode(enabled_solution)
  @test last(enabled_solution[:a0]) > 0.0
  @test last(enabled_solution[:comp1]) ≈ 6.0

  # sw2 is active by default; disabling it removes its callback and effects.
  disabled = ODEProblem(system, (0, 30); events_active=[:sw2 => false])
  @test length(disabled.kwargs[:callback].discrete_callbacks) == 1
  disabled_solution = solve(disabled, Tsit5())
  @test SciMLBase.successful_retcode(disabled_solution)
  @test last(disabled_solution[:s2]) == 0.0
  @test !events(system).time[:sw1].is_active
  @test events(system).time[:sw2].is_active
end
