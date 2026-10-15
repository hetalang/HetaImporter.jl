using HetaImporter
using Test
using OrdinaryDiffEqTsit5

@testset "ODEProblem and symbolic results" begin
  system = import_heta(_dynms_model_dir("0-hello-world"), :mm)
  problem = ODEProblem(system, (0.0, 10.0))
  u0 = problem.u0(problem.p, 0.0)
  @test u0 == [10.0, 0.0]
  @test problem.p.tunable == [0.1, 2.5]
  @test problem.p.derived == [1.0]
  @test isempty(problem.p.discrete)
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); u0=[1.0, 0.0])
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); callback=identity)

  solution = solve(problem, Tsit5(); saveat=1.0)
  @test size(solution) == (2, 11)
  @test SciMLBase.successful_retcode(solution)
  @test last(solution[:S]) ≈ 9.206648
  @test first(solution[[:S_amt_, :S]]) == [10.0, 10.0]
  @test solution.ps[:default_comp] == 1.0
  @test solution.ps[[:Vmax, :Km]] == [0.1, 2.5]
end
