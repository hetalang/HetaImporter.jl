using HetaImporter
using Test

@testset "compiler Julia export" begin
  heta_dir = joinpath(@__DIR__, "models", "dynms", "0-hello-world")
  mktempdir() do build_dir
    @test_throws ArgumentError HetaImporter.build_julia_file(heta_dir; ir_format=:dynms, build_dir)
    @test_throws ArgumentError HetaImporter.build_julia_file(heta_dir; ir_format=:unsupported, build_dir)

    for options in ((;), (; ir_format=:julia, spaceFilter=[:mm]))
      julia_path = HetaImporter.build_julia_file(heta_dir; build_dir, options...)
      @test julia_path == joinpath(build_dir, "julia", "model.jl")
      @test isfile(julia_path)
      model_module = Module(gensym(:CompilerJuliaModel))
      platform = Base.invokelatest(Base.include, model_module, julia_path)
      @test haskey(platform[1], :mm)
      model = platform[1][:mm]
      u0 = zeros(length(model[12]))
      statics = zeros(length(model[9]))
      Base.invokelatest(model[1], u0, statics, model[8])
      @test u0 == [10.0, 0.0]
    end
  end
end
