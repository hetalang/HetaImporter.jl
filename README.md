# HetaImporter

[![Build Status](https://github.com/hetalang/HetaImporter.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/hetalang/HetaImporter.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://hetalang.github.io/HetaImporter.jl/dev/)

HetaImporter.jl is a Julia package for importing [Heta](https://hetalang.github.io/) models into Julia. Internally HetaImporter uses [Heta-compiler](https://hetalang.github.io/hetacompiler/), a CLI tool that converts Systems Biology/QSP models written in the Heta modeling language into various formats suitable for simulation, calibration, and analysis (e.g., SBML, SimBiology, mrgsolve, and Julia code).

The package supports two ways to use Heta models from Julia:

- `HetaImporter.build_julia_file`: call heta-compiler's Julia exporter to generate Julia source file `model.jl`.
- `import_heta`: call heta-compiler's DynMS exporter, parse the resulting JSON, and construct a native `HetaODESystem`, which can be passed to `SciMLBase.ODEProblem`.

The generated Julia file is intended to be loaded by simulation and parameter estimation packages such as [HetaSimulator](https://github.com/hetalang/HetaSimulator.jl).
