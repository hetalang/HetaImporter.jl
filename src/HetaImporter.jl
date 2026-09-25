module HetaImporter

using JSON
using MathJSON
using RuntimeGeneratedFunctions
using DataStructures
using DiffEqCallbacks
using LinearAlgebra
using Pkg, Pkg.Artifacts
import Base: SHA1
using SciMLBase
using SciMLStructures
import SymbolicIndexingInterface as SII


RuntimeGeneratedFunctions.init(@__MODULE__)

# heta-compiler supported version
const HETA_COMPILER_VERSION = "0.12.1"
const DYNMS_VERSION = "0.2.0"
const DYNMS_SUPPORTED_VERSIONS = (DYNMS_VERSION,)

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
include("parse_heta.jl")
include("heta_parameters.jl")
include("old_format_codegen.jl")
include("heta_system.jl")
include("heta_system_codegen.jl")
include("heta_system_runtime.jl")

export heta_version, heta_help, heta_init, heta_build
export build_dynms_file, build_julia_file
export parse_heta, parse_dynms, parse_dynms_model, import_heta, import_heta_all
export HetaODESystem, HetaParameters, build_ode_system
export write_dynms_julia, write_generated_code
export equations, initial_conditions, parameters, observed, events

end
