@testset "DynMS parser: hello world" begin
  dynms_path = joinpath(@__DIR__, "..", "models", "dynms", "0-hello-world", "dist", "dynms", "output.dynms.json")
  spec = parse_dynms_spec(dynms_path)

  @test spec.version == "0.11.1"
  @test collect(keys(spec.models)) == [:mm]

  model = spec.models[:mm]
  @test model.id == :mm
  @test collect(keys(model.constants)) == [:Vmax, :Km]
  @test collect(values(model.constants)) == [0.1, 2.5]
  @test collect(keys(model.statics)) == [:default_comp]
  @test model.statics[:default_comp] == 1.0
  @test collect(keys(model.assignment_rules)) == [:P, :S, :r1]
  @test collect(keys(model.states)) == [:S_amt_, :P_amt_]
  @test model.states[:S_amt_].initial == :(10.0 * 1.0)
  @test model.states[:S_amt_].equation == :(-r1)
  @test model.states[:P_amt_].equation == :r1
  @test !model.states[:S_amt_].is_algebraic
  @test model.observables == [:S, :P]

  @test isempty(model.time_events)
  @test isempty(model.continuous_events)
  @test isempty(model.discrete_events)
  @test isempty(model.stop_events)
end
