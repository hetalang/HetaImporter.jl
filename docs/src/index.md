# HetaImporter.jl

HetaImporter.jl is a Julia package for importing [Heta](https://hetalang.github.io/) models into Julia. Internally HetaImporter uses [Heta-compiler](https://hetalang.github.io/hetacompiler/), a CLI tool that converts Systems Biology/QSP models written in the Heta modeling language into various formats suiatble for simulation, calibration, and analysis (e.g., SBML, SimBiology, mrgsolve, and Julia code).

The package supports three ways to use Heta models from Julia:

- `ir_format = :julia`: call heta-compiler's Julia exporter to generate Julia source file `model.jl`.
- `ir_format = :dynms`: call heta-compiler's DynMS exporter, parse `output.dynms.json`, and generate readable Julia source from the DynMS intermediate representation.
- Parse DynMS and construct a native `HetaODESystem`, which can be passed to
  `SciMLBase.ODEProblem`.

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
dynms_path = build_dynms_file(
  "path/to/heta/platform";
  build_dir = "path/to/build"
)

spec = parse_dynms(dynms_path)
model = spec.models[:my_model]
```

The parsed `DynMSModelSet` is a representation of the DynMS content (states, assignment rules, events, etc) in the form of Julia expressions `Expr`.

It can be lowered to a native `HetaODESystem`. The system retains the
inspectable equations and defaults while storing the generated function
expressions used to construct an `ODEProblem`:

```julia
using SciMLBase

system = build_ode_system(spec; model_id=:my_model)
problem = ODEProblem(system, (0.0, 100.0))

equations(system)
initial_conditions(system)
parameters(system)
observed(system)
events(system)
```

To compile and import a Heta platform in one call, use `import_heta`. Generated
Julia expressions can optionally be written for inspection without being
generated a second time:

```julia
system = import_heta(
  "path/to/heta/platform";
  model_id=:my_model,
  write_to_file=true,
  filename="my_model_ode.jl",
)
```

To import every model from a platform, use `import_heta_all`. It always returns
an ordered dictionary keyed by model ID:

```julia
systems = import_heta_all("path/to/heta/platform")
system = systems[:my_model]
```

## Pages

- [API](@ref)
