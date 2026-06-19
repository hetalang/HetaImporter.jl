@testset "DynMS parser: discrete switcher" begin
  spec = _parse_fresh_dynms_spec("16-d-switcher")
  model = spec.models[:nameless]

  @test collect(keys(model.constants)) == [:k1]
  @test collect(keys(model.states)) == [:S1_amt_, :x1]
  @test collect(keys(model.statics)) == [:comp1, :S2_amt_, :x2]
  @test model.observables == [:S1, :S2, :x1, :x2]

  @test isempty(model.time_events)
  @test isempty(model.continuous_events)
  @test collect(keys(model.discrete_events)) == [:sw1, :sw2]
  @test isempty(model.stop_events)

  sw1 = model.discrete_events[:sw1]
  @test sw1.condition == :(S1 < 6.0)
  @test sw1.is_active
  @test collect(keys(sw1.state_affects)) == [:S1_amt_, :x1]
  @test sw1.state_affects[:S1_amt_] == :((S1 + 10.0) * comp1)
  @test sw1.state_affects[:x1] == :(x1 + 100.0)
  @test collect(keys(sw1.discrete_affects)) == [:S2_amt_, :x2]
  @test sw1.discrete_affects[:S2_amt_] == :((S2 + 10.0) * comp1)
  @test sw1.discrete_affects[:x2] == :(x2 + 100.0)

  sw2 = model.discrete_events[:sw2]
  @test sw2.condition == :(S1 < 10.0 && t > 400000.0)
  @test isempty(sw2.state_affects)
  @test isempty(sw2.discrete_affects)
end
