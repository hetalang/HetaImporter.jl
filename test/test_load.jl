@test chomp(read(`$(HetaImporter.heta_exe_path) -v`, String)) == HetaImporter.HETA_COMPILER_VERSION
@test_throws AssertionError("The model was build with Heta compiler v0.0.1, which is not supported.\nThis HetaSimulator release includes Heta compiler v$(HetaImporter.HETA_COMPILER_VERSION). Please re-compile the model with HetaSimulator load_platform().") load_jlplatform(joinpath(@__DIR__, "models", "wrong_jlmodel.jl"))

platform = load_platform(joinpath(@__DIR__, "models", "onecomp_model"));
model = platform.models[:nameless];

@test isa(model, Model)
@test isa(platform, Platform)