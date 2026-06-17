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
include("structs.jl")
include("load_platform.jl")
include("parse_dynms.jl")
include("load_dynms_platform.jl")

export heta_version, heta_help, heta_init, heta_build
export Platform, Model
export load_platform, load_model, load_jl_platform, load_jl_model, load_jlplatform, load_jlmodel
export load_dynms_platform, load_dynms_model, parse_dynms_platform, parse_dynms_model
export write_dynms_julia 

end
