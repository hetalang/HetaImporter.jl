using HetaImporter
using Test
using LinearAlgebra

@testset "native model import" begin
  mktempdir() do directory
    filename = joinpath(directory, "mm_ode.jl")
    system = import_heta(
      _dynms_model_dir("0-hello-world");
      build_dir=joinpath(directory, "build"),
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

    systems = import_heta_all(
      _dynms_model_dir("0-hello-world");
      build_dir=joinpath(directory, "build"),
    )
    @test collect(keys(systems)) == [:mm]
    @test systems[:mm] isa HetaODESystem
  end
end

@testset "algebraic states" begin
  model = HetaImporter.parse_dynms_model(Dict(
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
    @test_throws ArgumentError HetaImporter.parse_dynms_model(Dict(
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
