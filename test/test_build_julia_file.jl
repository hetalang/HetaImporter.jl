# This test file is related to HetaSimulator and will be removed in future versions.
using HetaImporter
using Test

@testset "heta-compiler Julia export" begin
  heta_dir = joinpath(@__DIR__, "models", "dynms", "0-hello-world")
  mktempdir() do build_dir
    @test_throws ArgumentError HetaImporter.build_julia_file(heta_dir; ir_format=:dynms, build_dir)

    julia_path = HetaImporter.build_julia_file(heta_dir; build_dir)
    @test julia_path == joinpath(build_dir, "julia", "model.jl")
    @test isfile(julia_path)
  end
end
