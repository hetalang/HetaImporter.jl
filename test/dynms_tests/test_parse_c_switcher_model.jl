@testset "DynMS parser: continuous switcher" begin
  dynms_path = joinpath(@__DIR__, "..", "models", "dynms", "9-c-switcher", "dist", "dynms", "output.dynms.json")
  spec = parse_dynms_spec(dynms_path)
  model = spec.models[:nameless]

  @test collect(keys(model.constants)) == [:k1]
  @test collect(keys(model.states)) == [:x1_amt_, :x2_amt_]
  @test collect(keys(model.statics)) == [:comp1, :p1, :x3_amt_]
  @test collect(keys(model.assignment_rules)) == [:x2, :x1, :r1, :x3, :cond1]
  @test model.observables == [:x1, :x2, :p1, :x3]

  @test isempty(model.time_events)
  @test collect(keys(model.continuous_events)) == [:sw1]
  @test isempty(model.discrete_events)
  @test isempty(model.stop_events)

  sw1 = model.continuous_events[:sw1]
  @test sw1.condition == :cond1
  @test sw1.is_active
  @test !sw1.initial_affect
  @test collect(keys(sw1.state_affects)) == [:x1_amt_]
  @test sw1.state_affects[:x1_amt_] == :((x1 + 10.0) * comp1)
  @test collect(keys(sw1.discrete_affects)) == [:p1]
  @test sw1.discrete_affects[:p1] == :(x1 * 2.0)
end
