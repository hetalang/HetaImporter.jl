# default paths and model file names
const JULIA_MODEL_DIR = "julia"
const JULIA_MODEL_NAME = "model.jl"
const DYNMS_MODEL_DIR = "dynms"
const DYNMS_MODEL_NAME = "output.dynms.json"

"""
    build_dynms_file(heta_dir; build_dir, kwargs...)

Build a Heta platform and write a DynMS JSON file to
`joinpath(build_dir, DYNMS_MODEL_DIR, DYNMS_MODEL_NAME)`.

The returned value is the generated DynMS JSON file path.

Arguments:

- `heta_dir` : path to a Heta source directory containing a platform declaration file
- `build_dir` : directory path where generated files are written. Default is `joinpath(heta_dir, "dist")`
- `spaceFilter` : filter for namespaces in the Heta model. Can be a string, a vector of symbols, or `nothing`. Default is `nothing`
- kwargs : other arguments supported by `heta_build`

"""
function build_dynms_file(
  heta_dir::AbstractString;
  build_dir::AbstractString = joinpath(abspath(heta_dir), "dist"),
  spaceFilter::Union{String,Vector{Symbol},Nothing} = nothing,
  kwargs...
)
  build_dir = abspath(build_dir)
  spaceFilter = _normalize_space_filter(spaceFilter)
  dynms_path, export_format = get_model_path_and_export_format(build_dir, spaceFilter, Val(:dynms))

  build_retcode = heta_build(heta_dir; dist_dir=build_dir, export_format, kwargs...)
  build_retcode == 0 ||
    error("heta_build failed while generating DynMS JSON with exit code $build_retcode.")
  isfile(dynms_path) ||
    error("heta_build did not generate DynMS JSON at '$dynms_path'.")

  return dynms_path
end

"""
    build_julia_file(heta_dir; build_dir, ir_format=:julia, kwargs...)

Build a Heta platform and write a Julia source file to
`joinpath(build_dir, JULIA_MODEL_DIR, JULIA_MODEL_NAME)`.

When `ir_format == :julia`, heta-compiler writes Julia code directly. When
`ir_format == :dynms`, heta-compiler writes DynMS JSON first; HetaImporter then
converts that DynMS IR to readable Julia source.

The returned value is the generated Julia file path. 

Arguments:

- `heta_dir` : path to a Heta source directory containing a platform declaration file
- `ir_format` : format of the intermediate representation of the model. Default is `:julia`
- `build_dir` : directory path where generated files are written. Default is `joinpath(heta_dir, "dist")`
- `spaceFilter` : filter for namespaces in the Heta model. Can be a string, a vector of symbols, or `nothing`. Default is `nothing`
- kwargs : other arguments supported by `heta_build`

"""
function build_julia_file(
  heta_dir::AbstractString;
  ir_format::Symbol = :julia,
  build_dir::AbstractString = joinpath(abspath(heta_dir), "dist"),
  spaceFilter::Union{String,Vector{Symbol},Nothing} = nothing,
  kwargs...
)
  build_dir = abspath(build_dir)
  julia_path = joinpath(build_dir, JULIA_MODEL_DIR, JULIA_MODEL_NAME)
  return _build_julia_file(heta_dir, julia_path; ir_format, build_dir, spaceFilter, kwargs...)
end

function _build_julia_file(
  heta_dir::AbstractString,
  julia_path::AbstractString;
  ir_format::Symbol,
  build_dir::AbstractString,
  spaceFilter::Union{String,Vector{Symbol},Nothing},
  kwargs...
)
  ir_format in (:julia, :dynms) ||
    throw(ArgumentError("Unsupported IR format: $ir_format. Supported formats are: :julia, :dynms"))

  spaceFilter = _normalize_space_filter(spaceFilter)
  model_path, export_format = get_model_path_and_export_format(build_dir, spaceFilter, Val(ir_format))

  build_retcode = heta_build(heta_dir; dist_dir=build_dir, export_format, kwargs...)
  build_retcode == 1 &&
    throw("Compilation errors. Likely there is an error in the Heta model. Please check the log file for details.")

  _write_julia_file(model_path, julia_path, Val(ir_format))
  return julia_path
end

function _write_julia_file(model_path::AbstractString, julia_path::AbstractString, ::Val{:julia})
  dir = dirname(julia_path)
  !isempty(dir) && mkpath(dir)
  abspath(model_path) == abspath(julia_path) || cp(model_path, julia_path; force=true)
  return julia_path
end

function _write_julia_file(model_path::AbstractString, julia_path::AbstractString, ::Val{:dynms})
  return write_dynms_julia(model_path, julia_path)
end

function _normalize_space_filter(spaceFilter::Union{String,Vector{Symbol},Nothing})
  if spaceFilter isa Vector{Symbol}
    return "^(" * join(spaceFilter, "|") * ")\$"
  end
  return spaceFilter
end

function get_model_path_and_export_format(build_dir::AbstractString, spaceFilter, ::Val{:julia})
  filepath = JULIA_MODEL_DIR
  export_format = _export_format("julia", filepath, spaceFilter)
  model_path = joinpath(build_dir, filepath, JULIA_MODEL_NAME)
  return (model_path, export_format)
end

function get_model_path_and_export_format(build_dir::AbstractString, spaceFilter, ::Val{:dynms})
  filepath = DYNMS_MODEL_DIR
  export_format = _export_format("dynms", filepath, spaceFilter)
  model_path = joinpath(build_dir, filepath, DYNMS_MODEL_NAME)
  return (model_path, export_format)
end

function _export_format(format::String, filepath::String, spaceFilter)
  if isnothing(spaceFilter)
    return "{format:$format, filepath:$filepath}"
  else
    return "{format:$format, filepath:$filepath, spaceFilter:'$spaceFilter'}"
  end
end
