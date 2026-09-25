using HetaImporter
using Test
using SciMLBase
using LinearAlgebra
import SymbolicIndexingInterface as SII

if !isdefined(@__MODULE__, :HETA_SYSTEM_TEST_MODELS)
  const HETA_SYSTEM_TEST_MODELS = joinpath(@__DIR__, "..", "models", "dynms")
end

@testset "numeric DynMS expression fields" begin
  static_model = Dict{String,Any}(
    "id" => "numeric_fields",
    "static" => [Dict("id" => "p", "initial" => true)],
  )
  @test_throws ArgumentError HetaImporter.parse_dynms_model(static_model)
  static_model["static"][1]["initial"] = "True"
  @test_throws ArgumentError HetaImporter.parse_dynms_model(static_model)

  static_model["static"][1]["initial"] = 1.0
  static_model["assignments"] = [Dict("id" => "flag", "rhs" => true)]
  @test_throws ArgumentError HetaImporter.parse_dynms_model(static_model)
  delete!(static_model, "assignments")

  dynamic_model = Dict{String,Any}(
    "id" => "numeric_fields",
    "dynamic" => [Dict("id" => "x", "initial" => false, "derivative" => 0.0)],
  )
  @test_throws ArgumentError HetaImporter.parse_dynms_model(dynamic_model)
  dynamic_model["dynamic"][1]["initial"] = 0.0
  dynamic_model["dynamic"][1]["derivative"] = false
  @test_throws ArgumentError HetaImporter.parse_dynms_model(dynamic_model)

  static_model["timeEvents"] = [Dict(
    "id" => "change",
    "trigger" => Dict("start" => 0.0),
    "actions" => [Dict("state" => "p", "rhs" => true)],
  )]
  @test_throws ArgumentError HetaImporter.parse_dynms_model(static_model)
end
if !isdefined(@__MODULE__, :_parse_fresh_heta)
  function _parse_fresh_heta(model_name::AbstractString)
    return mktempdir() do build_dir
      HetaImporter.parse_heta(joinpath(HETA_SYSTEM_TEST_MODELS, model_name); build_dir)
    end
  end
end

@testset "native HetaODESystem lowering" begin
  spec = _parse_fresh_heta("0-hello-world")
  model = spec.models[:mm]
  system = build_ode_system(model)

  @test system isa HetaODESystem
  @test system.name == :mm
  @test repr(system) == "HetaODESystem(:mm)"
  system_display = sprint(show, MIME"text/plain"(), system)
  @test occursin("HetaODESystem `mm`", system_display)
  @test occursin("States:     2", system_display)
  @test occursin("Parameters: 3 (2 tunable, 1 discrete)", system_display)
  @test occursin("Observed:   3", system_display)
  @test occursin("Events:     0", system_display)
  @test !occursin("generated_code", system_display)
  @test !HetaImporter.has_algebraic(model)
  @test system.generated_code.mass_matrix === I

  algebraic_states = copy(model.states)
  algebraic_id = first(keys(algebraic_states))
  algebraic_state = algebraic_states[algebraic_id]
  algebraic_states[algebraic_id] = HetaImporter.DynMSState(
    algebraic_state.initial,
    algebraic_state.equation,
    true,
  )
  algebraic_model = HetaImporter.DynMSModel(
    model.id,
    model.parameters,
    model.assignment_rules,
    algebraic_states,
    model.time_events,
    model.continuous_events,
    model.discrete_events,
    model.stop_events,
    model.observables,
  )
  algebraic_mass_matrix = build_ode_system(algebraic_model).generated_code.mass_matrix
  @test HetaImporter.has_algebraic(algebraic_model)
  @test algebraic_mass_matrix isa Diagonal{Float64}
  @test diag(algebraic_mass_matrix)[1] == 0.0
  @test system.dynms === model
  @test system.state_index == Dict(:S_amt_ => 1, :P_amt_ => 2)
  @test system.parameter_index == Dict(:Vmax => 1, :Km => 2, :default_comp => 3)
  @test system.discrete_index == Dict(:default_comp => 1)
  @test SII.variable_symbols(system) == [:S_amt_, :P_amt_]
  @test SII.parameter_symbols(system) == [:Vmax, :Km, :default_comp]
  @test system.generated_code.ode_func isa HetaImporter.DynMSJuliaFunction
  @test system.generated_code.initialize_discrete_func isa
    HetaImporter.DynMSJuliaFunction
  @test system.generated_code.u0_func isa HetaImporter.DynMSJuliaFunction
  @test :assignment_dependencies ∉ fieldnames(typeof(system))
  @test haskey(observed(system), :S)
  @test equations(system)[:S_amt_] == model.states[:S_amt_].equation
  @test initial_conditions(system)[:S_amt_] == model.states[:S_amt_].initial
  @test parameters(system).tunable == model.parameters.tunable

  problem = ODEProblem(system, (0.0, 10.0))
  u0 = problem.u0(problem.p, 0.0)
  du = similar(u0)
  problem.f(du, u0, problem.p, 0.0)

  @test u0 == [10.0, 0.0]
  @test du[1] < 0
  @test du[2] > 0
  @test sum(du) ≈ 0.0

  tunable = [0.2, 3.0]
  custom_problem = ODEProblem(system, (0.0, 10.0); p=tunable)
  @test custom_problem.p isa HetaParameters
  @test custom_problem.p.tunable === tunable
  @test custom_problem.p.discrete == [1.0]
  @test ODEProblem(system, (0.0, 10.0); p=nothing).p.tunable == [0.1, 2.5]
  @test ODEProblem(
    system,
    (0.0, 10.0);
    p=SciMLBase.NullParameters(),
  ).p.tunable == [0.1, 2.5]
  @test_throws DimensionMismatch ODEProblem(system, (0.0, 10.0); p=[0.2])
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); p=(0.2, 3.0))
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); callback=identity)
  @test_throws ArgumentError ODEProblem(system, (0.0, 10.0); u0=[1.0, 0.0])

  mktempdir() do directory
    filename = joinpath(directory, "mm_heta_system.jl")
    written = build_ode_system(model; write_to_file=true, filename)
    @test written isa HetaODESystem
    @test isfile(filename)

    source = read(filename, String)
    @test occursin(string(written.generated_code.ode_func.name), source)
    @test occursin(string(written.generated_code.u0_func.name), source)
  end

  time_model = _parse_fresh_heta("11-time-switcher").models[:nameless]
  time_system = build_ode_system(time_model)
  time_display = sprint(show, MIME"text/plain"(), time_system)
  @test occursin("Events:     2 (2 time", time_display)
  @test length(time_system.generated_code.time_events) ==
    count(HetaImporter.is_active, values(time_model.time_events))
  @test all(
    event -> event.schedule_func isa HetaImporter.DynMSJuliaFunction,
    values(time_system.generated_code.time_events),
  )
  for event in values(time_system.generated_code.time_events)
    schedule_source = string(event.schedule_func.body)
    @test occursin("__p__.tunable", schedule_source)
    @test !occursin("__p__.discrete", schedule_source)
  end

  discrete_model = _parse_fresh_heta("16-d-switcher").models[:nameless]
  discrete_system = build_ode_system(discrete_model)
  @test !isempty(discrete_system.generated_code.discrete_events)
  @test all(
    event -> event.condition_func isa HetaImporter.DynMSJuliaFunction,
    values(discrete_system.generated_code.discrete_events),
  )

  mktempdir() do directory
    output_dir = joinpath(directory, "generated")
    systems = import_heta_all(
      joinpath(HETA_SYSTEM_TEST_MODELS, "0-hello-world");
      build_dir=joinpath(directory, "build"),
      write_to_file=true,
      output_dir,
    )
    @test systems isa HetaImporter.OrderedDict
    @test collect(keys(systems)) == [:mm]
    @test systems[:mm] isa HetaODESystem
    @test isfile(joinpath(output_dir, "mm_ode.jl"))
  end
end

@testset "ordered assignment selection" begin
  rules = HetaImporter.OrderedDict{Symbol,HetaImporter.DynMSExpr}(
    :A => :(x + 1),
    :B => :(y + 1),
    :C => :(2 * A),
  )

  required = collect(HetaImporter._heta_required_assignments(rules, (:C,)))
  @test required == [:A, :C]

  required = collect(HetaImporter._heta_required_assignments(rules, (:(B + C),)))
  @test required == [:A, :B, :C]
end
