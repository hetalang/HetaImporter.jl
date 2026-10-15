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
HetaImporter.build_dynms_file
HetaImporter.build_julia_file
```

## Advanced: DynMS Parsing, Validation, and Conversion

`build_dynms_file` compiles a Heta project and returns a DynMS file path.
`parse_dynms` reads a DynMS file into an unvalidated dictionary. Pass it to
`validate_dynms` before `convert_dynms` creates a `DynMSModelSet`.
`convert_dynms_model` converts one validated model dictionary to a `DynMSModel`.
For a complete file-to-system pipeline, use `import_heta` or `import_dynms`.

```@docs
HetaImporter.parse_dynms
HetaImporter.validate_dynms
HetaImporter.convert_dynms
HetaImporter.convert_dynms_model
```

## Heta Import and ODE Construction

```@docs
import_heta
import_heta_all
import_dynms
HetaODESystem
HetaParameters
HetaImporter.build_ode_system
write_generated_code
equations
initial_conditions
parameters
observed
events
```
