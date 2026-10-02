using HetaImporter
using Test

const DYNMS_TEST_MODELS_DIR = joinpath(@__DIR__, "models", "dynms")

_dynms_model_dir(model_name::AbstractString) = joinpath(DYNMS_TEST_MODELS_DIR, model_name)

function _parse_fresh_heta(model_name::AbstractString)
  return mktempdir() do build_dir
        HetaImporter.parse_heta(_dynms_model_dir(model_name); build_dir)
  end
end

@testset "HetaImporter.jl" begin

    @testset "Heta compiler CLI tests" begin
        @test heta_version() == HetaImporter.HETA_COMPILER_VERSION
    end

    @testset "DynMS parser tests" begin
        include("dynms_tests/test_parse_hello_world_model.jl")
        include("dynms_tests/test_parse_time_switcher_model.jl")
        include("dynms_tests/test_parse_c_switcher_model.jl")
        include("dynms_tests/test_parse_d_switcher_model.jl")
    end
    include("test_build_julia_file.jl")
    include("dynms_tests/test_heta_system.jl")
    include("dynms_tests/test_julia_backend.jl")
end
