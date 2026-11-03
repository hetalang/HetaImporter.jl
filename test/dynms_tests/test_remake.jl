using HetaImporter
using SciMLBase
using OrdinaryDiffEqTsit5
using Test
import SciMLStructures as SS
import SymbolicIndexingInterface as SII

@testset "Remake hello-world parameters" begin
  sys = import_heta(_dynms_model_dir("0-hello-world"), :mm)
  prob = ODEProblem(sys, (0.0, 10.0); p=[:Km => 7.0])
  reference = solve(ODEProblem(sys, prob.tspan; p=[0.2, 7.0]), Tsit5(); saveat=1.0)

  for updates in (Dict(:Vmax => 0.2), [:Vmax => 0.2])
    changed = remake(prob; p=updates)
    @test changed.p.tunable == [0.2, 7.0]  # Retain the current Km, not its model default.
    @test changed.p.tunable !== prob.p.tunable
    sol = solve(changed, Tsit5(); saveat=1.0)
    @test SciMLBase.successful_retcode(sol)
    @test sol.u ≈ reference.u
  end
  @test prob.p.tunable == [0.1, 7.0]
  @test remake(prob; p=Dict{Symbol,Float64}()).p.tunable == prob.p.tunable
  @test remake(prob; p=[:Vmax => 0.2], use_defaults=true).p.tunable == [0.2, 2.5]

  packed = SS.replace(SS.Tunable(), prob.p, [0.3, 4.0])
  @test remake(prob; p=packed).p === packed
  @test_throws ArgumentError remake(prob; p=[:default_comp => 2.0])
  @test_throws ArgumentError remake(prob; u0=[:S_amt_ => 1.0])
end

@testset "Update time-switcher parameters" begin
  sys = import_heta(_dynms_model_dir("11-time-switcher"))
  prob = ODEProblem(sys, (0.0, 10.0))
  original_p = prob.p
  buffers = (prob.p.tunable, prob.p.derived, prob.p.discrete)

  # Remake resets derived/discrete values without changing the source storage.
  prob.p.derived .= 99.0
  prob.p.discrete .= 99.0
  changed = remake(prob; p=[:sw2_start => 5.5])
  @test changed.p.derived == [1.0]
  @test changed.p.discrete == [0.0, 5.2]
  @test prob.p.discrete == [99.0, 99.0]
  @test changed.p.discrete !== prob.p.discrete
  @test_throws ArgumentError remake(prob; p=[:comp1 => 6.0])

  set_rates! = SII.setp(sys, [:kel, :sw2_start])
  for update! in (
    p -> SS.replace!(SS.Tunable(), p.p, [0.01, 0.03, 5.5]),
    p -> set_rates!(p, [0.03, 5.5]),
  )
    prob.p.tunable .= [0.01, 0.01, 5.0]
    prob.p.derived .= 99.0
    prob.p.discrete .= 99.0
    update!(prob)
    @test prob.p.tunable == [0.01, 0.03, 5.5]
    @test prob.p.derived == [1.0]
    @test prob.p.discrete == [0.0, 5.2]
    @test prob.p === original_p
  end
  @test_throws DimensionMismatch SS.replace!(SS.Tunable(), prob.p, [0.1])
  @test prob.p.tunable == [0.01, 0.03, 5.5]
  sol = solve(prob, Tsit5())
  @test SciMLBase.successful_retcode(sol)
  @test 5.5 in sol.t
  @test last(sol[:s2]) ≈ 2.0
end
