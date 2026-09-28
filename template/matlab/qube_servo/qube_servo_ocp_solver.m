% - qube_servo_ocp_solver.m


%%
clear; clc; close all;


%%
Ts = 0.002;
Npred = 50;
Tf = Npred * Ts;

Qc = diag([1e4, 1e3]);
Rc = 1;
P = 10*Qc;

x_ref = [0.5, 0]';
u_ref = 0.0;
y_ref = [x_ref;
         u_ref];

model = get_qube_servo_model();

%%
ocp = AcadosOcp();
ocp.model = model;
ocp.name = 'qube_servo_mpc';

ocp.solver_options.N_horizon = Npred; % prediction steps
ocp.solver_options.tf = Tf;

nx = length(model.x);
nu = length(model.u);

%% cost functions
Vx = [eye(nx);zeros(nu,nx)];
Vu = [zeros(nx,nu); eye(nu)];

% ================================================================
% Continuous-time cost weights
%
% J = integral (
%       ex' Qc ex + eu' Rc eu
%     ) dt
%     + ex_N' P ex_N
% ================================================================

% initial cost
ocp.cost.cost_type_0 = 'LINEAR_LS';
ocp.cost.Vx_0 = Vx;
ocp.cost.Vu_0 = Vu;
ocp.cost.W_0 = 2 * blkdiag(Qc, Rc);
ocp.cost.yref_0 = y_ref;

% path cost
ocp.cost.cost_type = 'LINEAR_LS';
ocp.cost.Vx = Vx;
ocp.cost.Vu = Vu;
ocp.cost.W = 2 * blkdiag(Qc, Rc);
ocp.cost.yref = y_ref;

% terminal cost
ocp.cost.cost_type_e = 'LINEAR_LS';
ocp.cost.Vx_e = eye(nx);
ocp.cost.W_e = 2 * P;
ocp.cost.yref_e = x_ref;

%% constraints
% ================================================================
% Initial condition
% ================================================================

x0 = [0.0;
      0.0];

ocp.constraints.x0 = x0;

% input bounds
vmax = 10;
vmin = -10;

ocp.constraints.idxbu = 0;
ocp.constraints.lbu = vmin;
ocp.constraints.ubu = vmax;


%% solver options
ocp.solver_options.nlp_solver_type = 'SQP'; % 'SQP'; 'SQP_RTI'
ocp.solver_options.qp_solver = 'PARTIAL_CONDENSING_HPIPM';
ocp.solver_options.integrator_type = 'ERK';
ocp.solver_options.hessian_approx = 'GAUSS_NEWTON';

% OCP internal integrator
ocp.solver_options.sim_method_num_stages = 4;
ocp.solver_options.sim_method_num_steps = 1;

%% codegen options
ocp.code_gen_options.code_export_directory = fullfile(pwd,'generated_code_qube_servo_ocp');
ocp.code_gen_options.json_file = 'qube_servo_ocp.json';


%% code reuse
solver_opts = struct();

solver_opts.generate = false;
solver_opts.build = false;
solver_opts.compile_mex_wrapper = false;
solver_opts.check_reuse_possible = true;

%% create simulink
simulink_opts = AcadosOcpSimulinkOptions();

% turn every inputs off first
input_names = properties(simulink_opts.inputs);
for i=1:length(input_names)
    simulink_opts.inputs.(input_names{i}) = 0;
end

% turn every outputs off first
output_names = properties(simulink_opts.outputs);
for i=1:length(output_names)
    simulink_opts.outputs.(output_names{i}) = 0;
end

% inputs:
simulink_opts.inputs.lbx_0 = 1;
simulink_opts.inputs.ubx_0 = 1;

simulink_opts.inputs.y_ref_0 = 1;
simulink_opts.inputs.y_ref   = 1;
simulink_opts.inputs.y_ref_e = 1;

% outputs

simulink_opts.outputs.u0 = 1;
simulink_opts.outputs.solver_status = 1;
simulink_opts.outputs.CPU_time = 1;

% block settings

simulink_opts.samplingtime = 't0';
simulink_opts.show_port_info = 1;
simulink_opts.generate_simulink_block = 1;


ocp.simulink_opts = simulink_opts;
%%
ocp_solver = AcadosOcpSolver(ocp, solver_opts);




%% test
x_meas = [0.0;
          0.0];

ocp_solver.set( ...
    'constr_x0', ...
    x_meas);

ocp_solver.solve();

status = ocp_solver.get('status');

disp(['status = ', num2str(status)]);

u0 = ocp_solver.get('u', 0);

disp('u0 =');
disp(u0);