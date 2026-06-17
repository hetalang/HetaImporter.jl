
"""
    heta_version()

Displays heta-compiler version

"""
function heta_version()
  run_build = run(ignorestatus(`$heta_exe_path -v`))
  return run_build.exitcode
end

"""
    heta_help(command::Union{String, Nothing}=nothing)

Displays help for heta-compiler CLI

Arguments:

- `command`: command to display. Default is `nothing` to display general help

"""
function heta_help(command::Union{String, Nothing}=nothing)
    run_build = run(ignorestatus(`$heta_exe_path help $command`))
    return run_build.exitcode
end

"""
    heta_init(dir::String; force::Bool=false, silent::Bool=false)

Creates template files for Heta-based platform in the specified directory `dir`

See `heta compiler` docs for details:
<https://hetalang.github.io/hetacompiler/cli-references.html#heta-init-command>

Arguments:

- `dir`: path to the directory where to create template files
- `force`: if `true` replace files and directories
- `silent`: if `true` use default options without prompt

"""
function heta_init(dir::String; force::Bool=false, silent::Bool=false)
    options_array = String[]
    force && push!(options_array, "--force")
    silent && push!(options_array, "--silent")

    run_build = run(ignorestatus(`$heta_exe_path init $options_array $dir`))
    return run_build.exitcode
end

"""
    heta_build(
      target_dir::AbstractString;
      declaration::String = "platform",
      units_check::Bool = false,
      log_mode::String = "error",
      log_path::String = "build.log",
      log_level::String = "info",
      debug::Bool = false,
      dist_dir::String = "dist",
      meta_dir::String = "meta",
      source::String = "index.heta",
      type::String = "heta",
      export_format::Union{String, Nothing} = nothing,
    )

Builds the models from Heta-based platform

See `heta compiler` docs for details:
<https://hetalang.github.io/hetacompiler/cli-references.html#running-heta-build-with-options>

Arguments:

- `target_dir` : path to the directory where Heta platform is located
- `declaration` : filepath to the platform declaration file. Default is `"platform"`
- `units_check` : if set to `true` units will be checked for the consistency
- `log_mode` : log mode. Default is `"error"`
- `log_path` : path to the log file. Default is `"build.log"`
- `log_level` : log level to display. Default is `"info"`
- `debug` : turn on debug mode. Default is `false`
- `dist_dir` : directory path, where to write distributives to. Default is `"dist"`
- `meta_dir` : meta directory path. Default is `"meta"`
- `source` : path to the main heta module. Default is `"index.heta"`
- `type` : type of the source file. Default is `"heta"`
- `export_format` : export the model to the specified format: `julia,dynms`,`{format:SBML,version:L3V1}`
"""
function heta_build(
  target_dir::AbstractString;
  declaration::String = "platform",
  units_check::Bool = false,
  log_mode::String = "error",
  log_path::String = "build.log",
  log_level::String = "info",
  debug::Bool = false,
  dist_dir::String = "dist",
  meta_dir::String = "meta",
  source::String = "index.heta",
  type::String = "heta",
  export_format::Union{String, Nothing} = nothing,
)

  # convert to absolute path
  _target_dir = abspath(target_dir)

  # cmd options supported by heta-compiler
  options_array = String[]

  declaration != "platform" && push!(options_array, "--declaration", declaration)
  units_check && push!(options_array, "--units-check")
  log_mode != "error" && push!(options_array, "--log-mode", log_mode)
  log_path != "build.log" && push!(options_array, "--log-path", log_path)
  log_level != "info" && push!(options_array, "--log-level", log_level)
  debug && push!(options_array, "--debug")
  dist_dir != "dist" && push!(options_array, "--dist-dir", dist_dir)
  meta_dir != "meta" && push!(options_array, "--meta-dir", meta_dir)
  source != "index.heta" && push!(options_array, "--source", source)
  type != "heta" && push!(options_array, "--type", type)
  push!(options_array, "--skip-updates")
  !isnothing(export_format) && push!(options_array, "--export", export_format)

  run_build = run(ignorestatus(`$heta_exe_path build $options_array $_target_dir`))

  return run_build.exitcode
end