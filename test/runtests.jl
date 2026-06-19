using HetaImporter
using Test

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
    @testset "DynMS Julia codegen tests" begin
        include("dynms_tests/codegen_test_helpers.jl")
        @testset "DynMS Julia codegen: hello world" begin
            _test_dynms_codegen_model("0-hello-world"; model_id = :mm)
        end
        @testset "DynMS Julia codegen: time switcher" begin
            _test_dynms_codegen_model("11-time-switcher"; model_id = :nameless)
        end
        @testset "DynMS Julia codegen: continuous switcher" begin
            _test_dynms_codegen_model("9-c-switcher"; model_id = :nameless)
        end
        @testset "DynMS Julia codegen: discrete switcher" begin
            _test_dynms_codegen_model("16-d-switcher"; model_id = :nameless)
        end 

    end
end
