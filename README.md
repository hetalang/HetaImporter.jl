# HetaImporter

[![Build Status](https://github.com/hetalang/HetaImporter.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/hetalang/HetaImporter.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://hetalang.github.io/HetaImporter.jl/dev/)

HetaImporter.jl is a Julia package for importing [Heta](https://hetalang.github.io/) models into Julia. Internally HetaImporter uses [Heta-compiler](https://hetalang.github.io/hetacompiler/), a CLI tool that converts Systems Biology/QSP models written in the Heta modeling language into various formats suitable for simulation, calibration, and analysis (e.g., SBML, SimBiology, mrgsolve, and Julia code).

The package supports two ways to use Heta models from Julia:

- `HetaImporter.build_julia_file()`: call heta-compiler's Julia exporter to generate Julia source file `model.jl`.
- `import_heta()`: call heta-compiler's DynMS exporter, parse the resulting JSON, and construct a native `HetaODESystem`, which can be passed to `SciMLBase.ODEProblem`.

The generated Julia file is intended to be loaded by simulation and parameter estimation packages such as [HetaSimulator](https://github.com/hetalang/HetaSimulator.jl).

## Current interface

Get a `HetaODESystem` when the Heta project contains exactly one model.
```julia
system = import_heta("path/to/heta-project")
```

Get model `:my_model` as `HetaODESystem` from a Heta project.
```julia
system = import_heta("path/to/heta-project"; model_id=:my_model)
```

Import a DynMS JSON file directly as `HetaODESystem`.
```julia
system = import_dynms("path/to/output.dynms.json"; model_id=:my_model)
```

The processing stages can also be called separately:
```julia
data = HetaImporter.parse_dynms("path/to/output.dynms.json") # unvalidated dictionary
# For a Heta project, first create the file with build_dynms_file("path/to/heta-project").
HetaImporter.validate_dynms(data)
model_set = HetaImporter.convert_dynms(data) # DynMSModelSet
model = HetaImporter.convert_dynms_model(data["models"][1]) # DynMSModel
```

`build_dynms_file` compiles a Heta project and returns the DynMS file path;
`parse_dynms` reads that file into an unvalidated dictionary. Dictionary conversion uses
`convert_dynms` and `convert_dynms_model` instead of `parse_dynms` and
`parse_dynms_model`. The former `load_dynms` pipeline is replaced by the
explicit stages above, or `import_dynms` when a system is needed.

Get all models as `OrderedDict{Symbol,HetaODESystem}` from a Heta project.
```julia
systems = import_heta_all("path/to/heta-project")
```

Compile a Heta project to a Julia source file and get its path.
```julia
julia_file = HetaImporter.build_julia_file("path/to/heta-project")
```

Compile a Heta project to a DynMS JSON file and get its path.
```julia
dynms_file = build_dynms_file("path/to/heta-project")
```

## Version maintenance

Support for a heta-compiler release and its DynMS format is defined in four
places that must be kept in sync:

- `src/HetaImporter.jl`: `HETA_COMPILER_VERSION` and
  `DYNMS_SUPPORTED_VERSIONS` define the runtime compatibility contract.
- `artifacts/generate_artifacts.jl`: `HETA_COMPILER_RELEASE` selects the
  compiler binaries, and `DYNMS_SCHEMAS` maps each supported DynMS version to
  its schema archive.

After changing the artifact sources, regenerate `Artifacts.toml` from the
repository root:

```powershell
julia --project=artifacts artifacts\generate_artifacts.jl
```
