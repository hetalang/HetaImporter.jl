# API

## Heta Compiler CLI

```@docs
heta_version
heta_help
heta_init
heta_build
```

## Julia File Generation

```@docs
build_dynms_file
build_julia_file
write_dynms_julia
```

## Advanced: Heta Parsing

```@docs
HetaImporter.parse_heta
```

## Advanced: DynMS Parsing

```@docs
HetaImporter.parse_dynms
HetaImporter.parse_dynms_model
```

## Heta Import and ODE Construction

```@docs
import_heta
import_heta_all
HetaODESystem
HetaParameters
build_ode_system
write_generated_code
equations
initial_conditions
parameters
observed
events
```
