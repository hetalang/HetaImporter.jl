@testset "DynMS parser: hello world" begin
  sys = import_heta(_dynms_model_dir("0-hello-world"), :mm)
  model = sys.dynms

  @test model.id == :mm
  @test collect(keys(model.parameters.tunable)) == [:Vmax, :Km]
  @test collect(values(model.parameters.tunable)) == [0.1, 2.5]
  @test collect(keys(model.parameters.derived)) == [:default_comp]
  @test isempty(model.parameters.discrete)
  @test model.parameters.derived[:default_comp] == 1.0
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

  @test HetaImporter._convert_dynms_expr(["Ln", "S"]; nanmath=true) == :(NaNMath.log(S))
  @test HetaImporter._convert_dynms_expr(["Power", "S", "P"]; nanmath=true) == :(NaNMath.pow(S, P))
end
