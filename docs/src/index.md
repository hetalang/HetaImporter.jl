# HetaImporter.jl

HetaImporter.jl is a Julia package for importing [Heta](https://hetalang.github.io/) models into Julia. Internally HetaImporter uses [Heta-compiler](https://hetalang.github.io/hetacompiler/), a CLI tool that converts Systems Biology/QSP models written in the Heta modeling language into various formats suitable for simulation, calibration, and analysis (e.g., SBML, SimBiology, mrgsolve, and Julia code).

The package supports two ways to use Heta models from Julia:

- `HetaImporter.build_julia_file`: call heta-compiler's Julia exporter to generate Julia source file `model.jl`.
- [`import_heta`](@ref): call heta-compiler's DynMS exporter, parse the resulting JSON, and construct a native [`HetaODESystem`](@ref), which can be passed to `SciMLBase.ODEProblem`.

The generated Julia file is intended to be loaded by simulation and parameter estimation packages such as [HetaSimulator](https://github.com/hetalang/HetaSimulator.jl). The native system can be used directly with SciML solvers.

## Quick Start

### Generate Julia source code

```julia
using HetaImporter

build_dir = "path/to/build"
julia_path = HetaImporter.build_julia_file(
  "path/to/heta/platform";
  build_dir,
)
```

The returned `julia_path` points to the generated source file:

```julia
joinpath(build_dir, "julia", "model.jl")
```

`HetaImporter.build_julia_file` uses the compiler's Julia exporter. Its only supported `ir_format` is `:julia`, which is also the default. If `build_dir` is omitted, files are written under the platform's `dist` directory.

### Import Heta as `HetaODESystem`

Pass the directory containing the Heta platform declaration (`platform.yml` or `platform.json`). The optional second positional argument, `model_id`, selects a model by its namespace ID and defaults to `:nameless`.

```julia
using HetaImporter
using SciMLBase

sys = import_heta("path/to/heta/platform", :my_model)
problem = ODEProblem(sys, (0.0, 100.0))
```

The problem uses the initial conditions and parameter defaults from the Heta model. Active model events are attached automatically as callbacks.

Override event activation for a particular problem using `events_active`:

```julia
problem = ODEProblem(sys, (0.0, 100.0);
    events_active=Dict(:dosing => false, :rescue_dose => true))
# A vector of pairs is also supported:
problem = ODEProblem(sys, (0.0, 100.0); events_active=[:dosing => false])
```

Keys must be `Symbol`s naming existing model events, and values must be `Bool`s.
Unspecified events retain their DynMS `active` defaults; `nothing` (the default)
or an empty collection uses all defaults. Unknown names and duplicate names in
a pair vector are rejected. These overrides apply to time, continuous, discrete,
and stop events, including events inactive in the model. The system defaults are not mutated, so the same
system can be reused for different scenarios. 

Control saving before and after events with `events_save`:

```julia
problem = ODEProblem(sys, (0.0, 100.0);
    events_save=Dict(:dosing => (false, true)))
# A vector of pairs is also supported:
problem = ODEProblem(sys, (0.0, 100.0);
    events_save=[:dosing => (false, false)], saveat=[0.0, 50.0, 100.0])
```

Each value is a `(save_before, save_after)` tuple of `Bool`s, passed to the
event callback's `save_positions`. Unspecified events use `(true, true)`;
`nothing` or an empty collection uses all defaults. Keys must name existing
events, and duplicate names in a pair vector are rejected. 

Override selected tunable parameters with a dictionary or a vector of pairs:

```julia
problem = ODEProblem(sys, (0.0, 100.0); p=Dict(:Vmax => 0.2))
problem = ODEProblem(sys, (0.0, 100.0); p=[:Vmax => 0.2, :Km => 3.0])
```

Keys must be `Symbol`s naming tunable parameters. Unspecified tunables retain
their model defaults; overrides are applied before computing derived parameters,
discrete initial values, and initial states. The system defaults are not mutated.
Unknown names, derived/discrete parameter names, and duplicate names in a pair
vector are rejected. Any `AbstractDict` is supported. An empty dictionary or
typed empty pair vector (`Pair{Symbol,Float64}[]`) uses all defaults.

A numeric vector remains a full positional replacement and must contain every
tunable in the order returned by `keys(parameters(sys).tunable)`.

To solve the problem, load a solver package separately. For example, with `OrdinaryDiffEqTsit5` installed:

```julia
using OrdinaryDiffEqTsit5

sol = solve(problem, Tsit5(); saveat=1.0)
```

States and assignment rules can be retrieved by name. For a model with a state named `x` and an assignment rule named `y`:

```julia
sol.t                  # saved simulation times
sol[:x]                # state values at saved times
sol[:y]                # observed values computed at saved times
sol[[:x, :y]]          # both quantities at each saved time
sol(50.0; idxs=:y)     # observed value at a particular time
```

Use the names returned by `equations(sys)` and `observed(sys)` for these queries. Access parameters with `sol.ps[:Vmax]`, or import [`getp`](https://docs.sciml.ai/SymbolicIndexingInterface/stable/api/#SymbolicIndexingInterface.getp) explicitly with `using SymbolicIndexingInterface: getp`.

### Import multiple models

[`import_heta_all`](@ref) returns an ordered dictionary of systems keyed by model ID:

```julia
systems = import_heta_all("path/to/heta/platform")
collect(keys(systems))
sys = systems[:my_model]
```

Both import functions accept `build_dir` for the compiler output directory and `spaceFilter` for selecting namespaces before import. For example, `spaceFilter=[:my_model]` restricts compilation to that namespace.

`import_heta` uses a temporary compiler output directory by default and removes
it after import, including on failure. Set `build_dir` explicitly to retain
compiler output. This does not change the destination of generated Julia source
requested with `write_to_file` and `filename`.

### Inspect the model and generated functions

The system retains expressions and event definitions for inspection:

```julia
equations(sys)           # state derivatives, keyed by state name
initial_conditions(sys)  # state initial-condition expressions
parameters(sys)          # tunable defaults and derived/discrete expressions
observed(sys)            # assignment-rule expressions
events(sys)              # time, continuous, discrete, and stop events
scenarios(sys)           # simulation regimens referencing this model
```

To save the generated native functions for inspection, use [`write_generated_code`](@ref):

```julia
write_generated_code(sys, "my_model_ode.jl")
```

The same file can be written during import:

```julia
sys = import_heta(
  "path/to/heta/platform", :my_model;
  write_to_file=true,
  filename="my_model_ode.jl",
)
```

## Pages

- [API](@ref)
