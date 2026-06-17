#=
  default run
=#
using HetaSimulator, Plots

model = load_jl_model("./model.jl")

### default simulations

Scenario(model, (0, 100)) |> sim |> plot
