@test chomp(read(`$(HetaImporter.heta_exe_path) -v`, String)) == HetaImporter.HETA_COMPILER_VERSION
@test_throws AssertionError("The model was build with Heta compiler v0.0.1, which is not supported.\nThis HetaSimulator release includes Heta compiler v$(HetaImporter.HETA_COMPILER_VERSION). Please re-compile the model with HetaSimulator load_platform().") load_jl_platform(joinpath(@__DIR__, "models", "wrong_jlmodel.jl"))

dynms_path = joinpath(@__DIR__, "models", "dynms", "0-hello-world", "dist", "dynms", "output.dynms.json")
dynms_platform = load_dynms_platform(dynms_path)
dynms_model = dynms_platform.models[:mm]
dynms_u0 = zeros(dynms_model.nstates)
dynms_p0 = zeros(dynms_model.nstatics)
dynms_model.init_func(dynms_u0, dynms_p0, dynms_model.constants)
dynms_du = zeros(dynms_model.nstates)
dynms_model.ode_func(dynms_du, dynms_u0, (x = (dynms_p0, dynms_model.constants),), 0.0)
dynms_out = zeros(2)
dynms_saving = dynms_model.saving_generator([:S, :P])
dynms_saving(dynms_out, dynms_u0, 0.0, (p = (x = (dynms_p0, dynms_model.constants),),))
dynms_extra_out = zeros(3)
dynms_extra_saving = dynms_model.saving_generator([:S_amt_, :default_comp, :r1])
dynms_extra_saving(dynms_extra_out, dynms_u0, 0.0, (p = (x = (dynms_p0, dynms_model.constants),),))
dynms_debug_julia = tempname() * ".jl"
saved_dynms_platform = load_dynms_platform(dynms_path; save_julia=dynms_debug_julia)
saved_dynms_args = Base.include(Main, dynms_debug_julia)
saved_dynms_extra_out = zeros(3)
saved_dynms_model = saved_dynms_args[1].mm
saved_dynms_extra_saving = saved_dynms_model[7]([:S_amt_, :default_comp, :r1])
saved_dynms_extra_saving(saved_dynms_extra_out, dynms_u0, 0.0, (p = (x = (dynms_p0, dynms_model.constants),),))
dynms_dist_dir = mktempdir()
loaded_dynms_with_dist = HetaImporter._load_platform(dynms_path, Val(:dynms); rm_out=false, dist_dir=dynms_dist_dir)
loaded_dynms_debug_julia = joinpath(dynms_dist_dir, HetaImporter.JULIA_MODEL_DIR, HetaImporter.JULIA_MODEL_NAME)

@test isa(dynms_platform, Platform)
@test isa(saved_dynms_platform, Platform)
@test isa(loaded_dynms_with_dist, Platform)
@test isfile(dynms_debug_julia)
@test isfile(loaded_dynms_debug_julia)
@test collect(keys(saved_dynms_args[1])) == [:mm]
@test HetaImporter.observables(dynms_model) == [:S, :P]
@test Set(HetaImporter.records(dynms_model)) == Set([:default_comp, :P, :S, :r1, :S_amt_, :P_amt_])
@test dynms_u0 == [10.0, 0.0]
@test dynms_p0 == [1.0]
@test dynms_du == [-0.08, 0.08]
@test dynms_out == [10.0, 0.0]
@test dynms_extra_out == [10.0, 1.0, 0.08]
@test saved_dynms_extra_out == [10.0, 1.0, 0.08]

platform = load_platform(joinpath(@__DIR__, "models", "onecomp_model"));
model = platform.models[:nameless];

@test isa(model, Model)
@test isa(platform, Platform)
