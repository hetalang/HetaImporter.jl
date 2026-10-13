module HetaImporter

using JSON
using JSONSchema
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
import SymbolicIndexingInterface: getp


RuntimeGeneratedFunctions.init(@__MODULE__)

# heta-compiler supported version
const HETA_COMPILER_VERSION = "0.12.3"
const DYNMS_SUPPORTED_VERSIONS = ("0.2.1","0.2.2")
const ARTIFACTS_TOML = joinpath(@__DIR__, "..", "Artifacts.toml")

function heta_compiler_load()
    artifact_info = artifact_meta("heta_app", ARTIFACTS_TOML)
    
    isnothing(artifact_info) && error("Your arch/OS is not supported by heta-compiler.")
    
    return artifact_path(SHA1(artifact_info["git-tree-sha1"]))
end

function dynms_schemas_load()
    schemas = Dict{String, JSONSchema.Schema}()
    for dynms_version in DYNMS_SUPPORTED_VERSIONS
        artifact_name = "dynms_schema_$dynms_version"
        artifact_info = artifact_meta(artifact_name, ARTIFACTS_TOML)
        isnothing(artifact_info) && error(
            "DynMS schema artifact '$artifact_name' for format version $dynms_version is not available.",
        )

        schema_path = joinpath(
            artifact_path(SHA1(artifact_info["git-tree-sha1"])),
            "dynms.schema.json",
        )
        isfile(schema_path) || error(
            "DynMS schema for format version $dynms_version is missing from artifact " *
            "'$artifact_name'. Run `Pkg.instantiate()` to install package artifacts.",
        )
        schemas[dynms_version] = JSONSchema.Schema(
            JSON.parsefile(schema_path);
            parent_dir = dirname(schema_path),
        )
    end
    return schemas
end
  
const heta_path = heta_compiler_load()
const heta_exe_name = Sys.iswindows() ? "heta-compiler.exe" : "heta-compiler" 
const heta_exe_path = heta_path === nothing ? heta_exe_name : joinpath(heta_path, heta_exe_name)
const DYNMS_SCHEMAS = dynms_schemas_load()

include("heta_cli.jl")
include("build_julia_file.jl")
include("parse_heta.jl")
include("heta_parameters.jl")
include("heta_system.jl")
include("heta_system_codegen.jl")
include("heta_system_runtime.jl")

export heta_version, heta_help, heta_init, heta_build
export import_heta, import_heta_all
export load_dynms, build_dynms_file
export HetaODESystem, HetaParameters
export getp
export write_generated_code
export equations, initial_conditions, parameters, observed, events

end
