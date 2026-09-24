%% ACADOS SIM TEMPLATE -- STANDALONE INTEGRATOR / SIMULINK / WINDOWS-MSVC
%
% Purpose
% -------
% Reusable template for creating an AcadosSim solver in MATLAB.
%
% AcadosSim is NOT an MPC controller. It is a numerical integrator:
%
%       x_{k+1} = Phi(x_k, u_k, p_k)
%
% Typical uses:
%
%   1) validate the dynamics independently of the OCP,
%   2) simulate the plant in MATLAB,
%   3) use an acados integrator S-function as the plant in Simulink,
%   4) compare ERK / IRK / GNSF integration,
%   5) inspect forward/adjoint sensitivities.
%
% Recommended organization:
%
%   1. model
%   2. simulation step
%   3. integrator options
%   4. sensitivities
%   5. code generation
%   6. create/reuse solver
%   7. build/reuse Simulink S-function
%   8. test one simulation step
%   9. optional simulation loop

%% ========================================================================
%  0. MATLAB SETUP
%  ========================================================================

clear;
clc;
close all;

import casadi.*

% Optional:
% check_acados_requirements();


%% ========================================================================
%  1. MODEL
%  ========================================================================
%
% Replace this function for another plant.

model = get_qube_servo_model();

nx = length(model.x);
nu = length(model.u);
np = length(model.p);

fprintf('Model: %s\n', model.name);
fprintf('nx = %d, nu = %d, np = %d\n', nx, nu, np);


%% ========================================================================
%  2. SIMULATION STEP
%  ========================================================================
%
% AcadosSim advances the model by ONE integration interval:
%
%       x_next = Phi(x, u, p)
%
% For controller/plant simulation, this is normally the sampling period.

Tsim = 0.02;     % [s], example: 50 Hz


%% ========================================================================
%  3. CREATE SIM OBJECT
%  ========================================================================

sim = AcadosSim();

% Use a readable fixed name instead of the automatic hash suffix.
sim.name = [model.name '_sim'];

sim.model = model;


%% ========================================================================
%  4. INTEGRATOR OPTIONS
%  ========================================================================
%
% MATLAB AcadosSim uses:
%
%       sim.solver_options.Tsim
%
% NOTE:
% Python AcadosSim uses:
%
%       sim.solver_options.T
%
% Do not mix the two APIs.

sim.solver_options.Tsim = Tsim;


% -------------------------------------------------------------------------
% 4.1 Integrator type
% -------------------------------------------------------------------------
%
% ERK
%   Explicit Runge-Kutta.
%   Good default for explicit ODEs xdot = f(x,u).
%
% IRK
%   Implicit Runge-Kutta.
%   Useful for implicit/stiff dynamics.
%
% GNSF
%   Generalized nonlinear static feedback structure.
%
% DISCRETE is an OCP transcription option; standalone AcadosSim currently
% focuses on ERK / IRK / GNSF.

sim.solver_options.integrator_type = 'ERK';


% -------------------------------------------------------------------------
% 4.2 Integration accuracy
% -------------------------------------------------------------------------

sim.solver_options.num_stages = 4;
sim.solver_options.num_steps  = 1;

% Interpretation:
%
% num_stages
%   stages inside each Runge-Kutta step.
%
% num_steps
%   number of integration substeps inside Tsim.
%
% Example:
%
% Tsim = 0.02
% num_steps = 2
%
% means two integration steps of approximately 0.01 s each.


% -------------------------------------------------------------------------
% 4.3 IRK-specific options
% -------------------------------------------------------------------------
%
% These matter primarily for IRK:
%
% sim.solver_options.newton_iter = 3;
% sim.solver_options.newton_tol  = 0.0;
% sim.solver_options.jac_reuse   = 0;
%
% Collocation:
%
% sim.solver_options.collocation_type = 'GAUSS_LEGENDRE';
%
% Alternative:
% sim.solver_options.collocation_type = 'GAUSS_RADAU_IIA';


%% ========================================================================
%  5. SENSITIVITIES
%  ========================================================================
%
% AcadosSim can return sensitivities of x_next with respect to x, u, etc.
%
% Useful for:
%   - linearization,
%   - MPC derivatives,
%   - validation,
%   - sensitivity studies.

sim.solver_options.sens_forw = true;

% Optional:
% sim.solver_options.sens_adj       = false;
% sim.solver_options.sens_algebraic = false;
% sim.solver_options.sens_hess      = false;

% If the model has parameters and you want forward sensitivities wrt p:
% sim.solver_options.sens_forw_p = true;


%% ========================================================================
%  6. PARAMETER INITIAL VALUES
%  ========================================================================
%
% If model.p is empty, leave this empty.
%
% If np > 0:
%
%     sim.parameter_values = zeros(np, 1);
%
% Runtime values can later be changed through:
%
%     sim_solver.set('p', p_value);

if np > 0
    sim.parameter_values = zeros(np, 1);
end


%% ========================================================================
%  7. OPTIONAL SIMULINK GENERATION
%  ========================================================================
%
% Standalone AcadosSim generates an integrator S-function template.
%
% Its normal ports are:
%
%   inputs:
%       x0
%       u        (if nu > 0)
%       p        (if np > 0)
%
%   output:
%       x1
%
% In a controller-in-the-loop model:
%
%         +------------------+       +------------------+
% x ---->|   acados OCP      | u --->|   acados SIM     |----> x_next
% ^      |   controller      |       |   plant          |       |
% |      +------------------+       +------------------+       |
% +-------------------------------------------------------------+
%
% On real QUBE hardware, the physical plant replaces the SIM block.

GENERATE_SIMULINK_INTERFACE = true;


%% ========================================================================
%  8. CODE GENERATION
%  ========================================================================

codegen_dir = fullfile(pwd, 'generated_sim');
json_name   = 'my_sim.json';

sim.code_gen_options.code_export_directory = codegen_dir;

% Filename only.
sim.code_gen_options.json_file = json_name;


%% ========================================================================
%  9. CREATE OR REUSE SIM SOLVER
%  ========================================================================
%
% Development workflow:
%
%   always formulate the CURRENT sim object in MATLAB,
%   then ask acados to reuse generated code.
%
% unchanged model/options  -> reuse
% changed model/options    -> regenerate/rebuild
%
% This requires the JSON/reuse fixes that we added to your local MATLAB
% interface.

opts.generate = false;
opts.build = false;
opts.compile_mex_wrapper = false;
opts.check_reuse_possible = true;

sim_solver = AcadosSimSolver(sim, opts);


%% ========================================================================
%  10. BUILD OR REUSE SIMULINK S-FUNCTION
%  ========================================================================

if GENERATE_SIMULINK_INTERFACE

    sfun_mex = fullfile( ...
        codegen_dir, ...
        ['acados_sim_solver_sfunction_' sim.name '.' mexext]);

    sim_was_regenerated = sim_solver.solver_creation_opts.generate;

    if sim_was_regenerated || ~isfile(sfun_mex)

        disp('Building AcadosSim Simulink S-function...');

        old_dir = pwd;
        cleanup_cd = onCleanup(@() cd(old_dir));

        cd(codegen_dir);

        % Generated function name is:
        %
        %   make_sfun_sim_<sim.name>
        %
        make_sfun_sim_fun = str2func( ...
            ['make_sfun_sim_' sim.name]);

        make_sfun_sim_fun();

        clear cleanup_cd;

    else
        disp('AcadosSim S-function already up to date. Reusing it.');
    end

    addpath(codegen_dir);
end


%% ========================================================================
%  11. TEST ONE SIMULATION STEP
%  ========================================================================
%
% Replace these values with a meaningful state and input for your system.

x0 = zeros(nx, 1);
u0 = zeros(nu, 1);

% Option A: high-level helper
%
% For ERK this is usually sufficient.

x1 = sim_solver.simulate(x0, u0);

fprintf('\nOne-step simulation:\n');
disp('x0 =');
disp(x0);

disp('u0 =');
disp(u0);

disp('x1 =');
disp(x1);


%% ========================================================================
%  12. LOW-LEVEL SET / SOLVE / GET API
%  ========================================================================
%
% Equivalent style:
%
% sim_solver.set('x', x0);
% sim_solver.set('u', u0);
%
% if np > 0
%     p0 = zeros(np,1);
%     sim_solver.set('p', p0);
% end
%
% status = sim_solver.solve();
%
% x1 = sim_solver.get('xn');
%
% Forward sensitivities:
%
% S_forw = sim_solver.get('S_forw');
%
% Typical S_forw structure:
%
%     [ dx_next/dx   dx_next/du ]


%% ========================================================================
%  13. IRK INITIAL GUESSES
%  ========================================================================
%
% For IRK, you may provide initial guesses:
%
% if strcmp(sim.solver_options.integrator_type, 'IRK')
%     sim_solver.set('xdot', zeros(nx,1));
%
%     % If algebraic states z exist:
%     % sim_solver.set('z', zeros(nz,1));
% end


%% ========================================================================
%  14. OPTIONAL OPEN-LOOP SIMULATION LOOP
%  ========================================================================
%
% Example:
%
% Nsim = 200;
% X = zeros(nx, Nsim+1);
% U = zeros(nu, Nsim);
%
% X(:,1) = x0;
%
% for k = 1:Nsim
%
%     % Example input:
%     U(:,k) = zeros(nu,1);
%
%     X(:,k+1) = sim_solver.simulate( ...
%         X(:,k), ...
%         U(:,k));
% end
%
% t = (0:Nsim) * Tsim;
%
% figure;
% plot(t, X');
% grid on;
% xlabel('time [s]');
% ylabel('states');


%% ========================================================================
%  15. WHEN DOES SIM REQUIRE REGENERATION?
%  ========================================================================
%
% Runtime changes -- NO regeneration:
%
%   x
%   u
%   p
%   IRK initial guesses
%
% Structural changes -- regenerate:
%
%   model equations
%   nx / nu / np
%   integrator type
%   Tsim
%   number of stages/steps
%   enabled sensitivity structure
%
% In normal simulation:
%
%       state/input values change every step,
%       generated solver structure does not.
