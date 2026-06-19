@testset "DynMS parser: time switcher" begin
  dynms_path = joinpath(@__DIR__, "..", "models", "dynms", "11-time-switcher", "dist", "dynms", "output.dynms.json")
  spec = parse_dynms_spec(dynms_path)
  model = spec.models[:nameless]

  @test collect(keys(model.constants)) == [:kabs, :kel, :sw2_start]
  @test collect(keys(model.states)) == [:a0, :s1_amt_]
  @test collect(keys(model.statics)) == [:s2_amt_, :comp0, :comp1]
  @test model.observables == [:s1, :s2, :comp0, :comp1]

  @test collect(keys(model.time_events)) == [:sw0, :sw1, :sw2]
  @test isempty(model.continuous_events)
  @test isempty(model.discrete_events)
  @test isempty(model.stop_events)

  sw0 = model.time_events[:sw0]
  @test sw0.start == 40.0
  @test isnothing(sw0.period)
  @test isnothing(sw0.stop)
  @test sw0.is_active
  @test !sw0.initial_affect
  @test isempty(sw0.state_affects)
  @test isempty(sw0.discrete_affects)

  sw1 = model.time_events[:sw1]
  @test sw1.start == 0.0
  @test sw1.period == 12.0
  @test sw1.stop == 60.0
  @test sw1.initial_affect
  @test !sw1.is_active
  @test collect(keys(sw1.state_affects)) == [:a0]
  @test sw1.state_affects[:a0] == :(a0 + 10.0)
  @test collect(keys(sw1.discrete_affects)) == [:comp1]
  @test sw1.discrete_affects[:comp1] == 6.0

  sw2 = model.time_events[:sw2]
  @test sw2.start == :sw2_start
  @test sw2.period == 24.0
  @test isnothing(sw2.stop)
  @test collect(keys(sw2.state_affects)) == [:s1_amt_]
  @test collect(keys(sw2.discrete_affects)) == [:s2_amt_]
end
