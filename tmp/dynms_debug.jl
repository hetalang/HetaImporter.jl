#=
    This code was generated from DynMS JSON by HetaImporter.
    HetaImporter loads DynMS with RuntimeGeneratedFunctions in memory;
    this file is emitted for debugging and review.
=#

(function()

### MODEL mm

mm_init_func_! = ((__u0__, __p0__, __constants__)->begin
        t = 0.0
        Vmax = __constants__[1]
        Km = __constants__[2]
        default_comp = 1
        S_amt_ = 10 * 1
        P_amt_ = 0 * 1
        P = P_amt_ / default_comp
        S = S_amt_ / default_comp
        r1 = ((Vmax * S) / (Km + S)) * default_comp
        __u0__[1] = S_amt_
        __u0__[2] = P_amt_
        __p0__[1] = default_comp
        return nothing
    end)

mm_ode_func_ = ((__du__, __u__, __p__, t)->begin
        __statics__ = __p__.x[1]
        __constants__ = __p__.x[2]
        Vmax = __constants__[1]
        Km = __constants__[2]
        S_amt_ = __u__[1]
        P_amt_ = __u__[2]
        default_comp = __statics__[1]
        P = P_amt_ / default_comp
        S = S_amt_ / default_comp
        r1 = ((Vmax * S) / (Km + S)) * default_comp
        __du__[1] = -r1
        __du__[2] = r1
        return nothing
    end)

mm_saving_generator_ = ((__outputIds__,)->begin
        __wrongIds__ = setdiff(__outputIds__, [:default_comp, :S, :P, :r1])
        !(isempty(__wrongIds__)) && throw("The following observables have not been found in the model's Records: $(__wrongIds__)")
        function saving!(__out__, __u__, t, __integrator__)
            __statics__ = __integrator__.p.x[1]
            __constants__ = __integrator__.p.x[2]
            Vmax = __constants__[1]
            Km = __constants__[2]
            S_amt_ = __u__[1]
            P_amt_ = __u__[2]
            default_comp = __statics__[1]
            P = P_amt_ / default_comp
            S = S_amt_ / default_comp
            r1 = ((Vmax * S) / (Km + S)) * default_comp
            begin
                for (__record_i__, __record_id__) = enumerate(__outputIds__)
                    if __record_id__ == :default_comp
                        __out__[__record_i__] = default_comp
                    else
                        if __record_id__ == :S
                            __out__[__record_i__] = S
                        else
                            if __record_id__ == :P
                                __out__[__record_i__] = P
                            else
                                if __record_id__ == :r1
                                    __out__[__record_i__] = r1
                                else
                                    throw("Observable :$(__record_id__) has not been found in the model's Records.")
                                end
                            end
                        end
                    end
                end
            end
            return nothing
        end
        return saving!
    end)

mm_constants_num_ = (Vmax = 0.1, Km = 2.5)
mm_statics_id_ = (:default_comp,)
mm_records_output_ = (default_comp = false, S = true, P = true, r1 = false)
mm_events_active_ = NamedTuple()
mm_dynamic_nonss_ = (S = true, P = true)

mm_time_events_ = NamedTuple{()}((
))
mm_conditional_events_ = NamedTuple{()}((
))
mm_crossing_events_ = NamedTuple{()}((
))
mm_stop_events_ = NamedTuple{()}((
))
mm_model_ = (
  mm_init_func_!,
  mm_ode_func_,
  mm_time_events_,
  mm_conditional_events_,
  mm_crossing_events_,
  mm_stop_events_,
  mm_saving_generator_,
  mm_constants_num_,
  mm_statics_id_,
  mm_events_active_,
  mm_records_output_,
  mm_dynamic_nonss_
)

return (
  (
    mm = mm_model_,
  ),
  (),
  "0.11.1"
)

end)()
