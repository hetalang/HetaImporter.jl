const DYNMS_TEST_MODELS_DIR = joinpath(@__DIR__, "..", "models", "dynms")

struct TestParameterPartition{C}
  x::Tuple{Vector{Float64},C}
end

TestParameterPartition(p0::AbstractVector, constants) =
  TestParameterPartition((Float64.(p0), constants))

Base.getindex(p::TestParameterPartition, i::Integer) = p.x[1][i]
Base.getindex(p::TestParameterPartition, idxs::AbstractVector) = p.x[1][Int.(idxs)]

function Base.setindex!(p::TestParameterPartition, value, i::Integer)
  p.x[1][i] = value
  return p
end

function Base.setindex!(p::TestParameterPartition, values, idxs::AbstractVector)
  isempty(idxs) && return p
  p.x[1][Int.(idxs)] .= values
  return p
end

mutable struct TestIntegrator{U,P,T}
  u::U
  p::P
  t::T
end

function _include_generated_julia(julia_path::AbstractString)
  mod = Module(gensym(:GeneratedDynMSModel))
  return Base.invokelatest(Base.include, mod, julia_path)
end

function _build_generated_args(model_name::AbstractString, ir_format::Symbol)
  heta_dir = joinpath(DYNMS_TEST_MODELS_DIR, model_name)
  build_dir = mktempdir()
  julia_path = build_julia_file(heta_dir; ir_format, build_dir)
  return julia_path, _include_generated_julia(julia_path)
end

function _init_model_u0_p0(model)
  constants = model[8]
  u0 = zeros(length(model[12]))
  p0 = zeros(length(model[9]))
  init_func = model[1]
  Base.invokelatest(init_func, u0, p0, constants)
  return constants, u0, p0
end

function _parameter_partition(p0::AbstractVector, constants)
  return TestParameterPartition(copy(p0), constants)
end

function _integrator(u::AbstractVector, p0::AbstractVector, constants, t)
  return TestIntegrator(copy(u), _parameter_partition(p0, constants), t)
end

function _ode_values(model, u0, p0, constants, t)
  du = zeros(length(u0))
  ode_func = model[2]
  Base.invokelatest(ode_func, du, copy(u0), _parameter_partition(p0, constants), t)
  return du
end

function _saved_values(model, output_ids::Vector{Symbol}, u0, p0, constants, t)
  out = zeros(length(output_ids))
  saving_func = model[7]
  saving = Base.invokelatest(saving_func, output_ids)
  integrator = _integrator(u0, p0, constants, t)
  Base.invokelatest(saving, out, copy(u0), t, integrator)
  return out
end

function _default_output_ids(model)
  records_output = model[11]
  return Symbol[id for (id, enabled) in pairs(records_output) if enabled]
end

function _condition_value(condition_func, u0, p0, constants, t)
  integrator = _integrator(u0, p0, constants, t)
  return Base.invokelatest(condition_func, copy(u0), t, integrator)
end

function _affected_values(affect_func, u0, p0, constants, t)
  integrator = _integrator(u0, p0, constants, t)
  Base.invokelatest(affect_func, integrator)
  return copy(integrator.u), copy(integrator.p.x[1])
end

function _test_time_event(old_event, new_event, old_state, new_state; times)
  # The old Julia backend uses the third time-event tuple field differently
  # from the DynMS codegen path. Active flags are compared through model[10].
  old_tstops = Base.invokelatest(old_event[1], old_state.constants, times)
  new_tstops = Base.invokelatest(new_event[1], new_state.constants, times)
  @test isapprox(collect(new_tstops), collect(old_tstops))

  old_u, old_p = _affected_values(
    old_event[2], old_state.u0, old_state.p0, old_state.constants, times[1]
  )
  new_u, new_p = _affected_values(
    new_event[2], new_state.u0, new_state.p0, new_state.constants, times[1]
  )
  @test isapprox(new_u, old_u)
  @test isapprox(new_p, old_p)
end

function _test_discrete_event(old_event, new_event, old_state, new_state; t=0.0)
  old_at_start = old_event[3]
  new_at_start = new_event[3]
  @test old_at_start == new_at_start

  old_value = _condition_value(old_event[1], old_state.u0, old_state.p0, old_state.constants, t)
  new_value = _condition_value(new_event[1], new_state.u0, new_state.p0, new_state.constants, t)
  @test new_value == old_value

  old_u, old_p = _affected_values(
    old_event[2], old_state.u0, old_state.p0, old_state.constants, t
  )
  new_u, new_p = _affected_values(
    new_event[2], new_state.u0, new_state.p0, new_state.constants, t
  )
  @test isapprox(new_u, old_u)
  @test isapprox(new_p, old_p)
end

function _test_continuous_event(old_event, new_event, old_state, new_state; t=0.0)
  old_at_start = old_event[3]
  new_at_start = new_event[3]
  @test old_at_start == new_at_start

  old_value = _condition_value(old_event[1], old_state.u0, old_state.p0, old_state.constants, t)
  new_value = _condition_value(new_event[1], new_state.u0, new_state.p0, new_state.constants, t)
  @test isapprox(new_value, old_value)

  old_u, old_p = _affected_values(
    old_event[2], old_state.u0, old_state.p0, old_state.constants, t
  )
  new_u, new_p = _affected_values(
    new_event[2], new_state.u0, new_state.p0, new_state.constants, t
  )
  @test isapprox(new_u, old_u)
  @test isapprox(new_p, old_p)
end

function _test_stop_event(old_event, new_event, old_state, new_state; t=0.0)
  old_at_start = old_event[2]
  new_at_start = new_event[2]
  @test old_at_start == new_at_start

  old_value = _condition_value(old_event[1], old_state.u0, old_state.p0, old_state.constants, t)
  new_value = _condition_value(new_event[1], new_state.u0, new_state.p0, new_state.constants, t)
  @test new_value == old_value
end

function _test_event_dict(old_events, new_events, old_state, new_state, tester; kwargs...)
  @test Tuple(keys(new_events)) == Tuple(keys(old_events))
  for id in keys(old_events)
    @test haskey(new_events, id)
    tester(old_events[id], new_events[id], old_state, new_state; kwargs...)
  end
end

function _test_dynms_codegen_model(
  model_name::AbstractString;
  model_id::Symbol
)
  old_julia_path, old_args = _build_generated_args(model_name, :julia)
  new_julia_path, new_args = _build_generated_args(model_name, :dynms)

  @test isfile(old_julia_path)
  @test isfile(new_julia_path)
  @test old_args[3] == new_args[3]
  @test haskey(old_args[1], model_id)
  @test haskey(new_args[1], model_id)

  old_model = old_args[1][model_id]
  new_model = new_args[1][model_id]

  old_constants, old_u0, old_p0 = _init_model_u0_p0(old_model)
  new_constants, new_u0, new_p0 = _init_model_u0_p0(new_model)
  old_state = (; constants = old_constants, u0 = old_u0, p0 = old_p0)
  new_state = (; constants = new_constants, u0 = new_u0, p0 = new_p0)

  @test new_constants == old_constants
  @test isapprox(new_u0, old_u0)
  @test isapprox(new_p0, old_p0)

  old_du0 = _ode_values(old_model, old_u0, old_p0, old_constants, 0.0)
  new_du0 = _ode_values(new_model, new_u0, new_p0, new_constants, 0.0)
  @test isapprox(new_du0, old_du0)

  old_output_ids = _default_output_ids(old_model)
  new_output_ids = _default_output_ids(new_model)
  @test Tuple(new_output_ids) == Tuple(old_output_ids)

  old_saved = _saved_values(old_model, old_output_ids, old_u0, old_p0, old_constants, 0.0)
  new_saved = _saved_values(new_model, new_output_ids, new_u0, new_p0, new_constants, 0.0)
  @test isapprox(new_saved, old_saved)

  old_events_active = old_model[10]
  new_events_active = new_model[10]
  @test new_events_active == old_events_active

  _test_event_dict(old_model[3], new_model[3], old_state, new_state, _test_time_event; times=(0.0, 100.0))
  _test_event_dict(old_model[4], new_model[4], old_state, new_state, _test_discrete_event; t=0.0)
  _test_event_dict(old_model[5], new_model[5], old_state, new_state, _test_continuous_event; t=0.0)
  _test_event_dict(old_model[6], new_model[6], old_state, new_state, _test_stop_event; t=0.0)

  old_is_algebraic = old_model[12]
  new_is_algebraic = new_model[12]
  @test values(new_is_algebraic) == values(old_is_algebraic)

  return nothing
end
