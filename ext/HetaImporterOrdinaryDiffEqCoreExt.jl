module HetaImporterOrdinaryDiffEqCoreExt

using HetaImporter
import OrdinaryDiffEqCore
import SciMLBase

function HetaImporter._heta_reset_event_dt!(integrator::OrdinaryDiffEqCore.ODEIntegrator)
  # Initial events precede the solver's own step-size initialization.
  # Fixed-step solves must retain the user's requested step size.
  if integrator.opts.adaptive && integrator.t != first(integrator.sol.prob.tspan)
    SciMLBase.auto_dt_reset!(integrator)
  end
  return nothing
end

end
