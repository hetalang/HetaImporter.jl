using HetaImporter
using Test

@testset "HetaImporter.jl" begin
    @testset "Heta-compiler tests" begin include("test_load.jl") end
end
