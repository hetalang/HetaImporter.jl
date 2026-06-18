using HetaImporter
using Test


@time platform_old = load_platform(joinpath(@__DIR__, "models", "onecomp_model"); load_format = :julia, rm_out=false);
@time platform_new = load_platform(joinpath(@__DIR__, "models", "onecomp_model"); load_format = :dynms, rm_out=false);