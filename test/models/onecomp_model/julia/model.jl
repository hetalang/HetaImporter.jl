#=
    This code was generated from DynMS JSON by HetaImporter 1.0.0-DEV
=#

(function()

### MODEL nameless ###

### create default constants
nameless_constants_num_ = NamedTuple{(:F, :dose, :kabs, :kel, :time_start, :time_end, :time_inj, :dose_inj)}((0.97, 10.0, 0.01, 0.0012, 100.0, 100.1, 0.1, 1.0))

### create static ids
nameless_statics_id_ = (:switch, :gut, :Vd)

### create default observables
nameless_records_output_ = NamedTuple{(:a0, :c1, :switch, :gut, :Vd, :r_inj, :r_abs, :r_el, :c1_amt_)}((true, true, false, false, false, false, false, false, false))

### create default events
nameless_events_active_ = NamedTuple{(:sw, :sw_end)}((false, false))

### vector of non-steady-state
nameless_dynamic_nonss_ = NamedTuple{(:a0, :c1_amt_)}((true, true))

### initialization of ODE variables and Records
function nameless_init_func_!(__u0__, __p0__, __constants__)
  t = 0.0
  (F, dose, kabs, kel, time_start, time_end, time_inj, dose_inj) = __constants__
  a0 = F * dose
  c1_amt_ = 0.0 * 5.0
  switch = 0.0
  gut = 1.0
  Vd = 5.0
  __u0__[1] = a0
  __u0__[2] = c1_amt_
  __p0__[1] = switch
  __p0__[2] = gut
  __p0__[3] = Vd
  return nothing
end

### calculate RHS of ODE
function nameless_ode_func_(__du__, __u__, __p__, t)
  (switch, gut, Vd) = __p__.x[1]
  (F, dose, kabs, kel, time_start, time_end, time_inj, dose_inj) = __p__.x[2]
  (a0, c1_amt_) = __u__
  r_inj = (switch * dose_inj) / time_inj
  r_abs = kabs * a0
  c1 = c1_amt_ / Vd
  r_el = kel * c1 * Vd
  __du__[1] = r_inj + -r_abs
  __du__[2] = r_abs + -r_el
  return nothing
end

### output function
function nameless_saving_generator_(__outputIds__::Vector{Symbol})
  __wrongIds__ = setdiff(__outputIds__, Symbol[:switch, :gut, :Vd, :r_inj, :r_abs, :c1, :r_el, :a0, :c1_amt_])
  !isempty(__wrongIds__) && throw("The following outputs have not been found in the model: $(__wrongIds__)")

  __out_expr__ = Expr(:block)
  for (__i__, __obs__) in enumerate(__outputIds__)
    push!(__out_expr__.args, :(__out__[$__i__] = $__obs__))
  end

  return @eval function(__out__, __u__, t, __integrator__)
    (switch, gut, Vd) = __integrator__.p.x[1]
    (F, dose, kabs, kel, time_start, time_end, time_inj, dose_inj) = __integrator__.p.x[2]
    (a0, c1_amt_) = __u__
    r_inj = (switch * dose_inj) / time_inj
    r_abs = kabs * a0
    c1 = c1_amt_ / Vd
    r_el = kel * c1 * Vd

    $(__out_expr__)
    return nothing
  end
end

### TIME EVENTS ###
function nameless_sw_tstops_func_(__constants__, __times__)
  (F, dose, kabs, kel, time_start, time_end, time_inj, dose_inj) = __constants__
  return [time_start]
end

function nameless_sw_affect_func_(__integrator__)
  t = __integrator__.t
  (switch, gut, Vd) = __integrator__.p.x[1]
  (F, dose, kabs, kel, time_start, time_end, time_inj, dose_inj) = __integrator__.p.x[2]
  (a0, c1_amt_) = __integrator__.u
  r_inj = (switch * dose_inj) / time_inj
  r_abs = kabs * a0
  c1 = c1_amt_ / Vd
  r_el = kel * c1 * Vd
  __integrator__.p[1] = 1.0
  return nothing
end

function nameless_sw_end_tstops_func_(__constants__, __times__)
  (F, dose, kabs, kel, time_start, time_end, time_inj, dose_inj) = __constants__
  return [time_end]
end

function nameless_sw_end_affect_func_(__integrator__)
  t = __integrator__.t
  (switch, gut, Vd) = __integrator__.p.x[1]
  (F, dose, kabs, kel, time_start, time_end, time_inj, dose_inj) = __integrator__.p.x[2]
  (a0, c1_amt_) = __integrator__.u
  r_inj = (switch * dose_inj) / time_inj
  r_abs = kabs * a0
  c1 = c1_amt_ / Vd
  r_el = kel * c1 * Vd
  __integrator__.p[1] = 0.0
  return nothing
end

### D EVENTS ###
### C EVENTS ###
### STOP EVENTS ###
### event tuples
nameless_time_events_ = NamedTuple{(:sw, :sw_end)}((
  (nameless_sw_tstops_func_, nameless_sw_affect_func_, false),
  (nameless_sw_end_tstops_func_, nameless_sw_end_affect_func_, false),
))

nameless_discrete_events_ = NamedTuple{()}(())

nameless_continuous_events_ = NamedTuple{()}(())

nameless_stop_events_ = NamedTuple{()}(())

### MODELS ###

nameless_model_ = (
  nameless_init_func_!,
  nameless_ode_func_,
  nameless_time_events_,
  nameless_discrete_events_,
  nameless_continuous_events_,
  nameless_stop_events_,
  nameless_saving_generator_,
  nameless_constants_num_,
  nameless_statics_id_,
  nameless_events_active_,
  nameless_records_output_,
  nameless_dynamic_nonss_
)

### OUTPUT ###

return (
  (
    nameless = nameless_model_,
  ),
  (),
  "0.12.0"
)

end)()
