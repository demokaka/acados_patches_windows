%% ACADOS OCP TEMPLATE -- LINEAR MPC / SIMULINK / WINDOWS-MSVC
%
% Purpose
% -------
% A reusable starting point for building an acados OCP in MATLAB.
%
% Recommended workflow:
%
%   1) define/load the model
%   2) choose horizon and sampling
%   3) define the cost
%   4) define constraints
%   5) choose numerical solver options
%   6) configure Simulink ports
%   7) configure code generation
%   8) create/reuse the solver
%   9) build/reuse the Simulink S-function
%
% The concrete example below uses get_qube_servo_model(), but the structure
% is intended to be copied for other systems as well.

%% ========================================================================
%  0. MATLAB SETUP
%  ========================================================================

clear;
clc;
close all;

import casadi.*

% Optional sanity check:
% check_acados_requirements();

% If a rebuild fails on Windows because an old MEX/DLL is still loaded:
% clear mex
% clear classes


%% ========================================================================
%  1. MODEL
%  ========================================================================
%
% This is the MAIN model-specific part to replace for another system.
%
% The model should normally contain at least:
%
%   model.x              state vector
%   model.u              input vector
%
% and one dynamics representation, for example:
%
%   model.f_expl_expr    explicit continuous-time dynamics xdot = f(x,u)
%
% or
%
%   model.f_impl_expr    implicit dynamics
%
% or
%
%   model.disc_dyn_expr  discrete dynamics x(k+1) = f_d(x(k),u(k))

model = get_qube_servo_model();

nx = length(model.x);
nu = length(model.u);

fprintf('Model: %s\n', model.name);
fprintf('nx = %d, nu = %d\n', nx, nu);


%% ========================================================================
%  2. MPC HORIZON AND BASIC DESIGN PARAMETERS
%  ========================================================================

N  = 50;      % number of shooting intervals
Tf = 1.0;     % prediction horizon [s]

Ts = Tf / N;  % for a uniform grid: first shooting interval / controller period

fprintf('Prediction horizon Tf = %.4f s\n', Tf);
fprintf('N = %d, nominal Ts = %.6f s\n', N, Ts);

% Explicit solver name:
%
% Using a fixed readable name avoids the newer automatic hash suffix.
% The JSON/hash reuse mechanism still detects formulation changes.
solver_name = model.name;

% Code generation folder
codegen_dir = fullfile(pwd, 'generated_solver');

% IMPORTANT:
% acados currently expects only a filename here, not a full path.
json_name = 'my_ocp.json';


%% ========================================================================
%  3. REFERENCES AND MPC WEIGHTS
%  ========================================================================
%
% LINEAR_LS cost:
%
%   y = Vx*x + Vu*u
%
%   l(x,u) = 1/2 * (y-yref)' * W * (y-yref)
%
% A very common MPC choice is:
%
%   y    = [x; u]
%   yref = [xref; uref]
%   W    = blkdiag(Q,R)
%
% Then:
%
%   Vx = [I; 0]
%   Vu = [0; I]

% ---- nominal references --------------------------------------------------
x_ref = zeros(nx, 1);
u_ref = zeros(nu, 1);

% ---- QUBE example weights ------------------------------------------------
%
% Replace these for another model.
%
% Q weights state tracking.
% R weights input effort.
% P weights terminal state error.

Q = diag([1e4, 1]);
R = 1;
P = 1e1 * Q;

% Generic alternatives:
%
% Q = eye(nx);
% R = 1e-2 * eye(nu);
% P = Q;
%
% If nx/nu are different from the QUBE dimensions, update Q/R above.


%% ========================================================================
%  4. OPTIONAL CONSTRAINT DESIGN DATA
%  ========================================================================
%
% Keep constraint DATA here.
% The actual acados constraint declarations are in Section 8.
%
% acados indices are ZERO-BASED.
%
% MATLAB:
%   first state  -> index 0
%   second state -> index 1
%   ...
%
% This is one of the most important details to remember.

% ---- initial state -------------------------------------------------------
%
% This is only the default value used when the solver is created.
% In closed-loop Simulink MPC, lbx_0 and ubx_0 will normally both be fed
% with the measured state x_meas at every controller step.

x0_default = zeros(nx, 1);


% ---- input bounds --------------------------------------------------------
%
% Set true only after replacing the EXAMPLE limits with your real actuator
% limits.

USE_INPUT_BOUNDS = false;

% EXAMPLE ONLY:
u_min = -1.0 * ones(nu, 1);
u_max =  1.0 * ones(nu, 1);


% ---- path state bounds ---------------------------------------------------
%
% Example:
% if x(1) is an angle and you want
%
%      -pi/2 <= x(1) <= pi/2
%
% use:
%
%   state_bound_idx = 0;
%   x_min = -pi/2;
%   x_max =  pi/2;

USE_STATE_BOUNDS = false;

state_bound_idx = 0;     % zero-based state indices
x_min = -pi/2;
x_max =  pi/2;


% ---- terminal state bounds ----------------------------------------------
%
% These apply only at shooting node N.

USE_TERMINAL_STATE_BOUNDS = false;

terminal_state_bound_idx = 0;
x_min_e = -pi/2;
x_max_e =  pi/2;


% ---- general linear / polytopic constraints -----------------------------
%
% acados represents:
%
%       lg <= C*x + D*u <= ug
%
% This is useful when a constraint couples multiple states and/or inputs.
%
% Example:
%
%       -2 <= x1 + 0.5*u1 <= 2
%
% with nx=2, nu=1:
%
%   C_general = [1, 0];
%   D_general = 0.5;
%   lg_general = -2;
%   ug_general =  2;

USE_GENERAL_LINEAR_CONSTRAINT = false;

C_general = zeros(1, nx);
D_general = zeros(1, nu);
lg_general = -inf;
ug_general =  inf;


% ---- terminal general linear constraints --------------------------------
%
% At the terminal node there is no u_N, therefore:
%
%       lg_e <= C_e*x_N <= ug_e

USE_TERMINAL_LINEAR_CONSTRAINT = false;

C_general_e = zeros(1, nx);
lg_general_e = -inf;
ug_general_e =  inf;


% ---- nonlinear constraints ----------------------------------------------
%
% acados BGH nonlinear constraints have the form:
%
%       lh <= h(x,u) <= uh
%
% Define the CasADi expression in:
%
%       ocp.model.con_h_expr
%
% Example:
%
%   h = model.x(1)^2 + model.x(2)^2;
%   ocp.model.con_h_expr = h;
%   ocp.constraints.lh = 0;
%   ocp.constraints.uh = 4;
%
% Similar expressions exist for:
%
%   ocp.model.con_h_expr_0     stage 0
%   ocp.model.con_h_expr       path stages
%   ocp.model.con_h_expr_e     terminal stage
%
% and the corresponding bounds:
%
%   lh_0, uh_0
%   lh,   uh
%   lh_e, uh_e

USE_NONLINEAR_CONSTRAINT = false;


% ---- soft constraints ----------------------------------------------------
%
% Soft constraints introduce slacks instead of declaring the problem
% infeasible immediately.
%
% Typical use:
%   - safety/comfort limits that may occasionally be violated,
%   - but should incur a large penalty.
%
% Example for softening path state bounds:
%
%   ocp.constraints.idxsbx = [0];
%   ocp.constraints.lsbx   = zeros(1,1);
%   ocp.constraints.usbx   = zeros(1,1);
%
%   ocp.cost.zl = 1e3 * ones(1,1);    % linear lower-slack penalty
%   ocp.cost.zu = 1e3 * ones(1,1);    % linear upper-slack penalty
%   ocp.cost.Zl = 1e4 * ones(1,1);    % quadratic lower-slack penalty
%   ocp.cost.Zu = 1e4 * ones(1,1);    % quadratic upper-slack penalty
%
% IMPORTANT:
% idxsbx indexes the list of state-bound constraints, not necessarily the
% original state index itself.
%
% Other available soft-constraint groups include:
%
%   idxsbu / lsbu / usbu       soft input bounds
%   idxsg  / lsg  / usg        soft general linear constraints
%   idxsh  / lsh  / ush        soft nonlinear constraints
%
% Terminal versions use the "_e" suffix.


%% ========================================================================
%  5. SIMULINK INTERFACE
%  ========================================================================
%
% A clean rule for MPC:
%
%   runtime data  -> Simulink input ports
%   fixed design  -> compiled into the OCP
%
% For a simple tracking MPC, the most useful runtime inputs are:
%
%   measured state:
%       lbx_0
%       ubx_0
%
%   reference:
%       y_ref_0
%       y_ref
%       y_ref_e
%
% We disable every port first, then explicitly enable only the ports wanted.
% This keeps the generated Simulink block clean.

GENERATE_SIMULINK_INTERFACE = true;

if GENERATE_SIMULINK_INTERFACE

    simulink_opts = AcadosOcpSimulinkOptions();

    % ---- disable all inputs first ---------------------------------------
    input_names = properties(simulink_opts.inputs);
    for k = 1:numel(input_names)
        simulink_opts.inputs.(input_names{k}) = 0;
    end

    % ---- runtime initial state ------------------------------------------
    %
    % Feed x_meas to BOTH lbx_0 and ubx_0.
    %
    % This implements:
    %
    %        x_0 = x_meas
    %
    simulink_opts.inputs.lbx_0 = 1;
    simulink_opts.inputs.ubx_0 = 1;

    % ---- runtime reference trajectory ----------------------------------
    simulink_opts.inputs.y_ref_0 = 1;
    simulink_opts.inputs.y_ref   = 1;
    simulink_opts.inputs.y_ref_e = 1;

    % ---- optional runtime-varying constraints ---------------------------
    %
    % Enable only if you want these bounds to change online.
    %
    % simulink_opts.inputs.lbu   = 1;
    % simulink_opts.inputs.ubu   = 1;
    % simulink_opts.inputs.lbx   = 1;
    % simulink_opts.inputs.ubx   = 1;
    % simulink_opts.inputs.lbx_e = 1;
    % simulink_opts.inputs.ubx_e = 1;
    % simulink_opts.inputs.lg    = 1;
    % simulink_opts.inputs.ug    = 1;
    % simulink_opts.inputs.lh    = 1;
    % simulink_opts.inputs.uh    = 1;

    % ---- optional runtime parameters -----------------------------------
    %
    % If model.p is nonempty:
    %
    % simulink_opts.inputs.parameter_traj = 1;

    % ---- optional warm-start/reset inputs -------------------------------
    %
    % simulink_opts.inputs.reset_solver = 1;
    % simulink_opts.inputs.x_init       = 1;
    % simulink_opts.inputs.u_init       = 1;
    % simulink_opts.inputs.pi_init      = 1;

    % ---- disable all outputs first --------------------------------------
    output_names = properties(simulink_opts.outputs);
    for k = 1:numel(output_names)
        simulink_opts.outputs.(output_names{k}) = 0;
    end

    % ---- desired outputs ------------------------------------------------
    simulink_opts.outputs.u0            = 1;
    simulink_opts.outputs.solver_status = 1;
    simulink_opts.outputs.CPU_time      = 1;

    % Helpful during debugging / experiments:
    simulink_opts.outputs.sqp_iter      = 1;
    simulink_opts.outputs.KKT_residual  = 1;

    % Optional:
    %
    % simulink_opts.outputs.x1          = 1;
    % simulink_opts.outputs.xtraj       = 1;
    % simulink_opts.outputs.utraj       = 1;
    % simulink_opts.outputs.cost_value  = 1;
    % simulink_opts.outputs.CPU_time_qp = 1;
    % simulink_opts.outputs.CPU_time_sim = 1;

    % Sampling time:
    %
    % 't0' -> use first shooting interval.
    % '-1' -> inherit sampling time from Simulink.
    simulink_opts.samplingtime = 't0';

    % Create the small helper .slx containing the masked acados block.
    %
    % Useful the first time.
    % Once you have copied the block into your own model, setting this to 0
    % avoids recreating the helper model after every structural rebuild.
    simulink_opts.generate_simulink_block = 1;

    % Show labels on generated block ports.
    simulink_opts.show_port_info = 1;

else
    simulink_opts = [];
end


%% ========================================================================
%  6. CREATE THE OCP OBJECT
%  ========================================================================

ocp = AcadosOcp();

ocp.name  = solver_name;
ocp.model = model;

% Number of shooting intervals
ocp.solver_options.N_horizon = N;

% Total prediction horizon
ocp.solver_options.tf = Tf;


%% ========================================================================
%  7. COST
%  ========================================================================
%
% For y = [x;u]:
%
%   ny = nx + nu
%
%   Vx = [I;
%         0]
%
%   Vu = [0;
%         I]

ny = nx + nu;

Vx = [eye(nx);
      zeros(nu, nx)];

Vu = [zeros(nx, nu);
      eye(nu)];

y_ref = [x_ref;
         u_ref];


% -------------------------------------------------------------------------
% 7.1 Initial stage cost, k = 0
% -------------------------------------------------------------------------
%
% Keeping this explicit is useful while learning.
%
% Alternatively, cost_type_0 can be left empty and acados can inherit/copy
% path-cost information where supported.

ocp.cost.cost_type_0 = 'LINEAR_LS';

ocp.cost.Vx_0 = Vx;
ocp.cost.Vu_0 = Vu;
ocp.cost.W_0 = blkdiag(Q, R);
ocp.cost.yref_0 = y_ref;


% -------------------------------------------------------------------------
% 7.2 Path stage cost, k = 1,...,N-1
% -------------------------------------------------------------------------

ocp.cost.cost_type = 'LINEAR_LS';

ocp.cost.Vx = Vx;
ocp.cost.Vu = Vu;
ocp.cost.W = blkdiag(Q, R);
ocp.cost.yref = y_ref;


% -------------------------------------------------------------------------
% 7.3 Terminal cost, k = N
% -------------------------------------------------------------------------
%
% No control u_N exists at the terminal node.

ocp.cost.cost_type_e = 'LINEAR_LS';

ocp.cost.Vx_e = eye(nx);
ocp.cost.W_e = P;
ocp.cost.yref_e = x_ref;


% -------------------------------------------------------------------------
% OTHER COST TYPES YOU MAY USE LATER
% -------------------------------------------------------------------------
%
% 'NONLINEAR_LS'
%   Define nonlinear output maps using:
%
%       ocp.model.cost_y_expr
%       ocp.model.cost_y_expr_0
%       ocp.model.cost_y_expr_e
%
% 'EXTERNAL'
%   Define an arbitrary scalar cost expression.
%
% 'CONVEX_OVER_NONLINEAR'
%   Useful for certain structured nonlinear convex costs.
%
% For basic linear MPC, LINEAR_LS is the cleanest starting point.


%% ========================================================================
%  8. CONSTRAINTS
%  ========================================================================


% -------------------------------------------------------------------------
% 8.1 Initial-state equality
% -------------------------------------------------------------------------
%
% This is the standard closed-loop MPC condition:
%
%       x_0 = x_measured
%
% Setting x0 once creates the correct stage-0 bound structure.
%
% In Simulink the numerical values can then be updated at every sampling
% instant by feeding the same x_meas to lbx_0 and ubx_0.

ocp.constraints.x0 = x0_default;


% Manual equivalent, useful if only SOME initial states should be fixed:
%
% ocp.constraints.idxbx_0  = [0; 1];      % zero-based state indices
% ocp.constraints.idxbxe_0 = [0; 1];      % equality subset
% ocp.constraints.lbx_0    = [0; 0];
% ocp.constraints.ubx_0    = [0; 0];


% -------------------------------------------------------------------------
% 8.2 Input box constraints
% -------------------------------------------------------------------------
%
%       u_min <= u_k <= u_max
%
% applied for k = 0,...,N-1.

if USE_INPUT_BOUNDS
    ocp.constraints.idxbu = (0:nu-1)';
    ocp.constraints.lbu = u_min(:);
    ocp.constraints.ubu = u_max(:);
end


% -------------------------------------------------------------------------
% 8.3 Path state box constraints
% -------------------------------------------------------------------------
%
%       x_min <= selected states <= x_max
%
% These normally apply to intermediate/path nodes.
%
% idxbx uses ZERO-BASED state indices.

if USE_STATE_BOUNDS
    ocp.constraints.idxbx = state_bound_idx(:);
    ocp.constraints.lbx = x_min(:);
    ocp.constraints.ubx = x_max(:);
end


% -------------------------------------------------------------------------
% 8.4 Terminal state box constraints
% -------------------------------------------------------------------------
%
% Bounds specifically at node N.

if USE_TERMINAL_STATE_BOUNDS
    ocp.constraints.idxbx_e = terminal_state_bound_idx(:);
    ocp.constraints.lbx_e = x_min_e(:);
    ocp.constraints.ubx_e = x_max_e(:);
end


% -------------------------------------------------------------------------
% 8.5 General linear / polytopic constraints
% -------------------------------------------------------------------------
%
%       lg <= C*x + D*u <= ug

if USE_GENERAL_LINEAR_CONSTRAINT
    ocp.constraints.C  = C_general;
    ocp.constraints.D  = D_general;
    ocp.constraints.lg = lg_general(:);
    ocp.constraints.ug = ug_general(:);
end


% -------------------------------------------------------------------------
% 8.6 Terminal general linear constraints
% -------------------------------------------------------------------------
%
%       lg_e <= C_e*x_N <= ug_e

if USE_TERMINAL_LINEAR_CONSTRAINT
    ocp.constraints.C_e  = C_general_e;
    ocp.constraints.lg_e = lg_general_e(:);
    ocp.constraints.ug_e = ug_general_e(:);
end


% -------------------------------------------------------------------------
% 8.7 Nonlinear constraints
% -------------------------------------------------------------------------
%
% Example only. Replace h(x,u) and limits with the actual constraint.
%
% BGH form:
%
%       lh <= h(x,u) <= uh

if USE_NONLINEAR_CONSTRAINT

    % EXAMPLE:
    h_expr = ocp.model.x(1)^2;

    ocp.model.con_h_expr = h_expr;

    ocp.constraints.lh = 0;
    ocp.constraints.uh = 1;

    % Terminal nonlinear constraint example:
    %
    % h_e = ocp.model.x(1)^2;
    % ocp.model.con_h_expr_e = h_e;
    % ocp.constraints.lh_e = 0;
    % ocp.constraints.uh_e = 1;
end


% -------------------------------------------------------------------------
% 8.8 Soft constraints
% -------------------------------------------------------------------------
%
% Leave hard constraints as the default while learning.
%
% Example for softening the FIRST state-bound constraint:
%
% ns_soft = 1;
%
% ocp.constraints.idxsbx = 0;       % index within idxbx list
% ocp.constraints.lsbx = zeros(ns_soft,1);
% ocp.constraints.usbx = zeros(ns_soft,1);
%
% ocp.cost.zl = 1e3 * ones(ns_soft,1);
% ocp.cost.zu = 1e3 * ones(ns_soft,1);
% ocp.cost.Zl = 1e4 * ones(ns_soft,1);
% ocp.cost.Zu = 1e4 * ones(ns_soft,1);


%% ========================================================================
%  9. NUMERICAL SOLVER OPTIONS
%  ========================================================================


% -------------------------------------------------------------------------
% 9.1 NLP method
% -------------------------------------------------------------------------
%
% 'SQP'
%   Full sequential quadratic programming iterations.
%   Very good for learning/debugging and difficult nonlinear problems.
%
% 'SQP_RTI'
%   Real-time iteration: typically one SQP step per controller sample.
%   Important later for real-time embedded MPC.

ocp.solver_options.nlp_solver_type = 'SQP';


% -------------------------------------------------------------------------
% 9.2 QP solver
% -------------------------------------------------------------------------
%
% Good default:
ocp.solver_options.qp_solver = 'PARTIAL_CONDENSING_HPIPM';

% Alternatives, provided they are compiled in your acados installation:
%
% ocp.solver_options.qp_solver = 'FULL_CONDENSING_HPIPM';
% ocp.solver_options.qp_solver = 'FULL_CONDENSING_QPOASES';
% ocp.solver_options.qp_solver = 'FULL_CONDENSING_DAQP';
% ocp.solver_options.qp_solver = 'PARTIAL_CONDENSING_OSQP';
% ocp.solver_options.qp_solver = 'PARTIAL_CONDENSING_QPDUNES';
% ocp.solver_options.qp_solver = 'PARTIAL_CONDENSING_CLARABEL';


% -------------------------------------------------------------------------
% 9.3 Integrator / dynamics transcription
% -------------------------------------------------------------------------
%
% ERK:
%   explicit Runge-Kutta, suitable for explicit ODEs.
%
% IRK:
%   implicit Runge-Kutta, useful for stiff/implicit systems.
%
% DISCRETE:
%   use when model.disc_dyn_expr already gives x_{k+1}=f_d(x_k,u_k).

ocp.solver_options.integrator_type = 'ERK';

% Optional ERK/IRK integration accuracy settings:
%
% ocp.solver_options.sim_method_num_stages = 4;
% ocp.solver_options.sim_method_num_steps  = 1;


% -------------------------------------------------------------------------
% 9.4 Hessian approximation
% -------------------------------------------------------------------------
%
% GAUSS_NEWTON:
%   natural default with least-squares costs.
%
% EXACT:
%   exact second derivatives; more expensive.

ocp.solver_options.hessian_approx = 'GAUSS_NEWTON';


% -------------------------------------------------------------------------
% 9.5 Optional SQP tolerances and limits
% -------------------------------------------------------------------------
%
% Leave defaults first. Tighten only when there is a reason.
%
% ocp.solver_options.nlp_solver_max_iter = 20;
% ocp.solver_options.nlp_solver_tol_stat = 1e-6;
% ocp.solver_options.nlp_solver_tol_eq   = 1e-6;
% ocp.solver_options.nlp_solver_tol_ineq = 1e-6;
% ocp.solver_options.nlp_solver_tol_comp = 1e-6;
%
% ocp.solver_options.qp_solver_iter_max = 100;
%
% Print level:
% ocp.solver_options.print_level = 1;


% -------------------------------------------------------------------------
% 9.6 Partial-condensing option
% -------------------------------------------------------------------------
%
% If desired:
%
% ocp.solver_options.qp_solver_cond_N = 10;
%
% Interpretation:
% reduce the N-stage QP to a smaller partially condensed QP.
%
% Do not tune this until the basic controller is working.


%% ========================================================================
%  10. CODE GENERATION
%  ========================================================================

ocp.code_gen_options.code_export_directory = codegen_dir;

% Filename only -- do not pass the full path here.
ocp.code_gen_options.json_file = json_name;

% Attach Simulink configuration.
ocp.simulink_opts = simulink_opts;


%% ========================================================================
%  11. CREATE OR REUSE THE OCP SOLVER
%  ========================================================================
%
% Development workflow:
%
%   Always construct the CURRENT OCP in MATLAB.
%
% Then ask acados to reuse generated code:
%
%   unchanged formulation -> reuse
%   changed formulation   -> regenerate/rebuild automatically
%
% This is preferable to loading the old OCP from JSON during active
% development, because the MATLAB source remains the source of truth.

opts.generate = false;
opts.build = false;
opts.compile_mex_wrapper = false;

% Compare current formulation with stored JSON/hash.
opts.check_reuse_possible = true;

ocp_solver = AcadosOcpSolver(ocp, opts);


%% ========================================================================
%  12. BUILD OR REUSE THE SIMULINK S-FUNCTION
%  ========================================================================

if GENERATE_SIMULINK_INTERFACE

    sfun_mex = fullfile( ...
        codegen_dir, ...
        ['acados_solver_sfunction_' ocp.name '.' mexext]);

    % If acados detected a structural OCP change, it internally switches
    % generation back on. In that case the S-function must also be rebuilt.
    ocp_was_regenerated = ocp_solver.solver_creation_opts.generate;

    if ocp_was_regenerated || ~isfile(sfun_mex)

        disp('Building Simulink S-function...');

        old_dir = pwd;
        cleanup_cd = onCleanup(@() cd(old_dir));

        cd(codegen_dir);
        make_sfun;

        clear cleanup_cd;

    else
        disp('Simulink S-function already up to date. Reusing it.');
    end

    % Make the generated S-function visible to Simulink.
    addpath(codegen_dir);
end


%% ========================================================================
%  13. WHAT CHANGES AT RUNTIME?
%  ========================================================================
%
% Do NOT regenerate code for ordinary MPC runtime data.
%
% Typical runtime quantities:
%
%   measured x0
%   reference trajectory
%   model parameters p
%   warm-start values
%
% In MATLAB these can be updated through ocp_solver.set(...).
% In Simulink they should normally enter through the corresponding ports.
%
% Structural changes that DO require regeneration include:
%
%   changing nx / nu
%   changing model equations
%   changing N
%   changing integrator type
%   changing solver type
%   changing the structure/dimension of costs or constraints
%   changing Simulink port configuration
%
% Numerical reference values and measured states are runtime data and should
% not require regeneration.


%% ========================================================================
%  14. SIMULINK SIGNAL MEANING FOR THIS TEMPLATE
%  ========================================================================
%
% Recommended connections:
%
%   measured state x_meas
%          | \
%          |  \
%          v   v
%       lbx_0 ubx_0
%
% Therefore:
%
%       lbx_0 = x_meas
%       ubx_0 = x_meas
%
% which gives:
%
%       x_0 = x_meas
%
%
% Tracking reference:
%
%   y_ref_0 = [x_ref(0); u_ref(0)]
%
%   y_ref   = concatenated stage references for stages 1,...,N-1
%
%   y_ref_e = terminal x_ref(N)
%
%
% Controller output:
%
%   u0
%
% is the first optimal control input and is the value normally applied to
% the plant.
%
%
% CPU_time is reported by acados in SECONDS.
%
% Example:
%
%   CPU_time = 0.0004
%
% means:
%
%   0.4 ms = 400 us
