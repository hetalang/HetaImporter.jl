using HetaImporter, OrdinaryDiffEqTsit5

sys = import_heta("test/models/dynms/11-time-switcher") #::MTK.System / HetaODESystem

eq = equations(sys)
ps = parameters(sys)
obs = observed(sys) # rules
ic = initial_conditions(sys)

prob = ODEProblem(sys, (0., 100.))
sol = solve(prob, Tsit5())

sol[:s1_amt_]
sol[:s2]
sol(12.6)
sol(12.9; idxs=[:s1_amt_, :vel])
