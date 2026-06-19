@testset "DynMS parser: hello world" begin
  spec = _parse_fresh_dynms_spec("0-hello-world")

  @test spec.version == HetaImporter.HETA_COMPILER_VERSION
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
