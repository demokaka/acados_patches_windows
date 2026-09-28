% qube_servo_sim_solver.m

%% clear everything
clear; clc; close all;

%%
Ts = 0.02;
model = get_qube_servo_model();

%%
sim = AcadosSim();
sim.name = 'qube_servo_plant'; % not "qube_servo_plant"; 
                               % this will be the name of generated code 
sim.model = model;

% integration time: 
sim.solver_options.Tsim = Ts;  % for matlab, use solver_options.Tsim

% integrator type:
sim.solver_options.integrator_type = 'ERK'; % explicit Runge-Kutta
sim.solver_options.num_stages = 4; % RK4
sim.solver_options.num_steps = 2;  % perform on 2 subintervals; e.g. RK4 applied for 2 steps of 0.01s

%% codegen options
sim.code_gen_options.code_export_directory = fullfile(pwd,'generated_code_qube_servo_sim');
sim.code_gen_options.json_file = 'qube_servo_sim.json';

%% Debug types before generation

fprintf('\n--- Type check ---\n');

disp(model.name)
disp(class(model.name))

disp(sim.name)
disp(class(sim.name))

disp(sim.code_gen_options.code_export_directory)
disp(class(sim.code_gen_options.code_export_directory))

%% code reuse
solver_opts = struct();

solver_opts.generate = false;
solver_opts.build = false;
solver_opts.compile_mex_wrapper = false;
solver_opts.check_reuse_possible = true;

%%
sim_solver = AcadosSimSolver(sim, solver_opts);

%% test
x = [0;
     0];

u = 1.0;

x_next = sim_solver.simulate(x, u);
disp("x = " + num2str(x))
disp("u = " + num2str(u))
disp("x_next = " + num2str(x_next))