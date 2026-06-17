using HetaImporter
using Test

@testset "HetaImporter.jl" begin
    @testset "DynMS parser tests" begin
        include("dynms_tests/test_hello_world_model.jl")
        include("dynms_tests/test_time_switcher_model.jl")
        include("dynms_tests/test_c_switcher_model.jl")
        include("dynms_tests/test_d_switcher_model.jl")
    end
    @testset "Heta-compiler tests" begin include("test_load.jl") end
end
