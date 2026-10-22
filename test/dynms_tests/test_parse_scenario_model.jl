@testset "DynMS parser: scenario model" begin
  sys = import_heta(_dynms_model_dir("21-scenario"))
  parsed = scenarios(sys)

  @test collect(keys(parsed)) == [:scn1, :scn2, :scn3]
  @test parsed == sys.scenarios
  for (id, scenario) in parsed
    @test scenario.id == id
    @test scenario.model == nameof(sys) == :nameless
    @test isnothing(scenario.events_active)
    @test isnothing(scenario.events_save)
  end

  @test parsed[:scn1].tspan == (0.0, 200.0)
  @test parsed[:scn3].tspan == (0.0, 12.0)
  for id in (:scn1, :scn3)
    @test isnothing(parsed[id].parameters)
    @test isnothing(parsed[id].saveat)
    @test isnothing(parsed[id].observables)
  end

  @test parsed[:scn2].tspan == (0.0, 12.0)
  @test parsed[:scn2].parameters == Dict(:k1 => 0.001, :xxx => 2.0)
  @test parsed[:scn2].saveat == [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
  @test parsed[:scn2].observables == [:x1, :x2]
end
