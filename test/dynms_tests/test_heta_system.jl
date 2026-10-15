using HetaImporter
using Test
using LinearAlgebra

@testset "native model import" begin
  mktempdir() do directory
    filename = joinpath(directory, "mm_ode.jl")
    system = import_heta(
      _dynms_model_dir("0-hello-world");
      build_dir=joinpath(directory, "build"),
      log_level="error",
      write_to_file=true,
      filename,
    )
    @test system isa HetaODESystem
    @test system.generated_code.mass_matrix === I
    @test collect(keys(equations(system))) == [:S_amt_, :P_amt_]
    @test haskey(initial_conditions(system), :S_amt_)
    @test parameters(system).tunable[:Vmax] == 0.1
    @test haskey(observed(system), :S)
    @test isempty(events(system).time)
    @test isfile(filename)

    dynms_path = joinpath(directory, "build", "dynms", "output.dynms.json")
    data = HetaImporter.parse_dynms(dynms_path)
    @test data isa AbstractDict
    @test HetaImporter.validate_dynms(data) === nothing
    @test HetaImporter.convert_dynms(data) isa HetaImporter.DynMSModelSet
    imported = import_dynms(dynms_path; model_id=:mm)
    @test imported isa HetaODESystem
    @test equations(imported) == equations(system)
    @test_throws ArgumentError import_dynms(dynms_path; model_id=:missing)

    invalid_path = joinpath(directory, "invalid.json")
    write(invalid_path, "{\"dynms\":\"unsupported\",\"models\":[]}")
    @test HetaImporter.parse_dynms(invalid_path)["dynms"] == "unsupported"
    @test_throws ArgumentError import_dynms(invalid_path)
    write(invalid_path, "{\"dynms\":\"0.2.2\",\"models\":false}")
    @test HetaImporter.parse_dynms(invalid_path)["models"] === false
    @test_throws ArgumentError import_dynms(invalid_path)

    systems = import_heta_all(
      _dynms_model_dir("0-hello-world");
      build_dir=joinpath(directory, "build"),
      log_level="error",
    )
    @test collect(keys(systems)) == [:mm]
    @test systems[:mm] isa HetaODESystem
  end
end

@testset "algebraic states" begin
  model = HetaImporter.convert_dynms_model(Dict(
    "id" => "algebraic",
    "dynamic" => [
      Dict("id" => "x", "initial" => 0.0, "derivative" => 0.0, "algebraic" => true),
      Dict("id" => "y", "initial" => 1.0, "derivative" => 0.0),
    ],
  ))
  @test HetaImporter.build_ode_system(model).generated_code.mass_matrix ==
    Diagonal([0.0, 1.0])
end

@testset "numeric expression validation" begin
  for (field, definitions) in (
    "static" => [Dict("id" => "p", "initial" => true)],
    "dynamic" => [Dict("id" => "x", "initial" => 0.0, "derivative" => false)],
  )
    @test_throws ArgumentError HetaImporter.convert_dynms_model(Dict(
      "id" => "invalid", field => definitions,
    ))
  end
end

@testset "assignment dependencies" begin
  rules = HetaImporter.OrderedDict{Symbol,HetaImporter.DynMSExpr}(
    :A => :(x + 1),
    :B => :(y + 1),
    :C => :(2 * A),
  )
  @test HetaImporter._heta_required_assignments(rules, (:C,)) == [:A, :C]
  @test HetaImporter._heta_required_assignments(rules, (:(B + C),)) == [:A, :B, :C]
end
