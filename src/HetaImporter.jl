module HetaImporter

using JSON
using MathJSON
using RuntimeGeneratedFunctions
using DataStructures
using LinearAlgebra
using Pkg, Pkg.Artifacts
import Base: SHA1

RuntimeGeneratedFunctions.init(@__MODULE__)

# heta-compiler supported version
const HETA_COMPILER_VERSION = "0.12.0"

function heta_compiler_load()
    artifact_info = artifact_meta("heta_app", joinpath(@__DIR__, "..", "Artifacts.toml"))
    
    isnothing(artifact_info) && throw("Your arch/OS is not supported by heta-compiler. Please, report this issue to Heta development team.")
    
    return artifact_path(SHA1(artifact_info["git-tree-sha1"]))
end
  
const heta_path = heta_compiler_load()
const heta_exe_name = Sys.iswindows() ? "heta-compiler.exe" : "heta-compiler" 
const heta_exe_path = heta_path === nothing ? heta_exe_name : joinpath(heta_path, heta_exe_name)

include("heta_cli.jl")
include("build_julia_file.jl")
include("parse_dynms.jl")
include("dynms_julia_codegen.jl")

export heta_version, heta_help, heta_init, heta_build
export build_julia_file
export parse_dynms_spec, parse_dynms_model
export write_dynms_julia 

end
