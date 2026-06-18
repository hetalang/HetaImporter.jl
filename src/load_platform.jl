# default paths and model file names
const JULIA_MODEL_DIR = "julia"
const JULIA_MODEL_NAME = "model.jl"
const DYNMS_MODEL_DIR = "dynms"
const DYNMS_MODEL_NAME = "output.dynms.json"

"""
    load_platform(  
      target_dir::AbstractString;
      rm_out::Bool = true,
      load_format::Symbol = :julia,
      spaceFilter::Union{String, Vector{Symbol}, Nothing} = nothing,
      kwargs...
    )

Converts heta model to Julia and outputs `Platform` type.

See `heta comiler` docs for details:
https://hetalang.github.io/#/heta-compiler/cli-references?id=running-build-with-cli-options

Arguments:

- `target_dir` : path to a Heta platform directory
- `rm_out` : should the file with the intermediate representation of the model be removed after loading. Default is `true`
- `load_format` : format of the intermediate representation of the model. Default is `:julia`
- `spaceFilter` : filter for namespaces in the Heta model. Can be a string, a vector of symbols, or `nothing`. Default is `nothing`
- kwargs : other arguments supported by `heta_build`
"""
function load_platform(
  target_dir::AbstractString;
  rm_out::Bool = true,
  load_format::Symbol = :julia,
  spaceFilter::Union{String, Vector{Symbol}, Nothing} = nothing,
  kwargs...
)

  load_format in (:julia, :dynms) || 
    throw(ArgumentError("Unsupported load format: $load_format. Supported formats are: :julia, :dynms"))

  if spaceFilter isa Vector{Symbol}
    spaceFilter = "^(" * join(spaceFilter, "|") * ")\$"
  end

  dist_dir = rm_out ? mktempdir() : abspath(target_dir)

  model_path, export_format = get_model_path_and_export_format(dist_dir, spaceFilter, Val(load_format))

  # check the retcode (0 - success, 1 - failure) 
  build_retcode = heta_build(target_dir; dist_dir, export_format , kwargs...)
  build_retcode == 1 && throw("Compilation errors. Likely there is an error in the Heta model. Please check the log file for details.")

  # load model to Main
  platform = _load_platform(model_path, Val(load_format); rm_out, dist_dir) 
    
  return platform
end

function _load_platform(model_path::AbstractString, ::Val{:julia}; rm_out::Bool=true, dist_dir::AbstractString="")
  platform = load_jl_platform(model_path)
  _cleanup_dist_dir(rm_out, dist_dir)
  return platform
end

function _load_platform(model_path::AbstractString, ::Val{:dynms}; rm_out::Bool=true, dist_dir::AbstractString="")
  save_julia = rm_out ? nothing : joinpath(dist_dir, JULIA_MODEL_DIR, JULIA_MODEL_NAME)
  platform = load_dynms_platform(model_path; save_julia)
  _cleanup_dist_dir(rm_out, dist_dir)
  return platform
end

function _cleanup_dist_dir(rm_out::Bool, dist_dir::AbstractString)
  rm_out && !isempty(dist_dir) && rm(dist_dir; force=true, recursive=true)
  return nothing
end

function get_model_path_and_export_format(dist_dir::AbstractString, spaceFilter, ::Val{:julia})
  filepath = JULIA_MODEL_DIR
  export_format = _export_format("julia", filepath, spaceFilter)
  model_path = joinpath(dist_dir, filepath, JULIA_MODEL_NAME)
  return (model_path, export_format)
end

function get_model_path_and_export_format(dist_dir::AbstractString, spaceFilter, ::Val{:dynms})
  filepath = DYNMS_MODEL_DIR
  export_format = _export_format("dynms", filepath, spaceFilter)
  model_path = joinpath(dist_dir, filepath, DYNMS_MODEL_NAME)
  return (model_path, export_format)
end

function _export_format(format::String, filepath::String, spaceFilter)
  if isnothing(spaceFilter)
    return "{format:$format, filepath:$filepath}"
  else
    return "{format:$format, filepath:$filepath, spaceFilter:'$spaceFilter'}"
  end
end

"""
    load_jl_platform(  
      model_jl::AbstractString
    )

Loads prebuild julia model as part of `Platform`

Arguments:

- `model_jl` : path to Julia model file
"""
function load_jl_platform(
  model_jl::AbstractString
)
  # include and CAPTURE the returned tuple (models, tasks, version)
  args = Base.invokelatest(() -> Base.include(Main, model_jl))

  # version check
  version = args[3]
  @assert version == HETA_COMPILER_VERSION "The model was build with Heta compiler v$version, which is not supported.\n"*
  "This HetaSimulator release includes Heta compiler v$HETA_COMPILER_VERSION. Please re-compile the model with HetaSimulator load_platform()."

  # build the Platform using the returned tuple
  platform = Base.invokelatest(Platform, args...)
  return platform
end

# tmp solution to add model only
"""
    load_jl_model(  
      model_jl::AbstractString
    )

Loads prebuild julia model without `Platform`

Arguments:

- `model_jl` : path to Julia model file
"""
function load_jl_model(model_jl::AbstractString)
  platform = load_jl_platform(model_jl)
  
  first_model = [values(platform.models)...][1]

  return first_model
end

@deprecate load_jlplatform(model_jl::AbstractString) load_jl_platform(model_jl)
@deprecate load_jlmodel(model_jl::AbstractString) load_jl_model(model_jl)
