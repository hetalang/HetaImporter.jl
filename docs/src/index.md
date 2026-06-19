# HetaImporter.jl

HetaImporter.jl is a Julia package for importing [Heta](https://hetalang.github.io/) models into Julia. Internally HetaImporter uses [Heta-compiler](https://hetalang.github.io/hetacompiler/), a CLI tool that converts Systems Biology/QSP models written in the Heta modeling language into various formats suiatble for simulation, calibration, and analysis (e.g., SBML, SimBiology, mrgsolve, and Julia code).

The package supports two ways for converting Heta models into Julia code:

- `ir_format = :julia`: call heta-compiler's Julia exporter to generate Julia source file `model.jl`.
- `ir_format = :dynms`: call heta-compiler's DynMS exporter, parse `output.dynms.json`, and generate readable Julia source from the DynMS intermediate representation.

The generated Julia file is intended to be loaded by simulation and parameters estimation packages such as [HetaSimulator](https://github.com/hetalang/HetaSimulator.jl).

## Quick Start

```julia
using HetaImporter

julia_path = build_julia_file(
  "path/to/heta/platform";
  ir_format = :dynms,
  build_dir = "path/to/build"
)
```

The returned `julia_path` points to:

```julia
joinpath(build_dir, HetaImporter.JULIA_MODEL_DIR, HetaImporter.JULIA_MODEL_NAME)
```

To use heta-compiler's Julia exporter directly:

```julia
julia_path = build_julia_file(
  "path/to/heta/platform";
  ir_format = :julia,
  build_dir = "path/to/build"
)
```

## DynMS Parser

DynMS JSON can also be parsed directly:

```julia
spec = parse_dynms_spec("path/to/output.dynms.json")
model = spec.models[:my_model]
```

The parsed `DynMSSpec` is a representation of the DynMS content (states, assignment rules, events, etc) in the form of Julia expressions `Expr`.

## Pages

- [API](@ref)
