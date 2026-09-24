"""
ACADOS OCP TEMPLATE -- LINEAR MPC / PYTHON / WINDOWS-MSVC

Reusable Python counterpart of the MATLAB OCP template.

The main structure is deliberately the same:

    1. model
    2. horizon
    3. references / weights
    4. constraints
    5. Simulink options (optional)
    6. formulate OCP
    7. solver options
    8. code generation
    9. create/reuse solver
   10. runtime updates / closed-loop use

IMPORTANT
---------
Replace export_qube_servo_model() with your actual Python model-export
function. The MATLAB function get_qube_servo_model() cannot be called
directly from normal Python.
"""

from __future__ import annotations

import os
import numpy as np
from scipy.linalg import block_diag

from acados_template import (
    AcadosOcp,
    AcadosOcpSolver,
    AcadosOcpSimulinkOptions,
    ocp_get_default_cmake_builder,
)

# --------------------------------------------------------------------------
# Replace this import with your actual model module.
# --------------------------------------------------------------------------
from qube_servo_model import export_qube_servo_model


# ==========================================================================
# 0. USER SWITCHES
# ==========================================================================

GENERATE_SIMULINK_FILES = False
USE_CMAKE = True

USE_INPUT_BOUNDS = False
USE_STATE_BOUNDS = False
USE_TERMINAL_STATE_BOUNDS = False
USE_GENERAL_LINEAR_CONSTRAINT = False
USE_TERMINAL_LINEAR_CONSTRAINT = False
USE_NONLINEAR_CONSTRAINT = False


# ==========================================================================
# 1. MODEL
# ==========================================================================

model = export_qube_servo_model()

nx = model.x.rows()
nu = model.u.rows()
np_ = model.p.rows()

print(f"Model: {model.name}")
print(f"nx = {nx}, nu = {nu}, np = {np_}")


# ==========================================================================
# 2. MPC HORIZON
# ==========================================================================

N = 50
Tf = 1.0
Ts = Tf / N

solver_name = model.name

codegen_dir = os.path.abspath("generated_solver")
json_name = "my_ocp.json"


# ==========================================================================
# 3. REFERENCES AND WEIGHTS
# ==========================================================================

x_ref = np.zeros(nx)
u_ref = np.zeros(nu)

# QUBE example.
# Replace if your model dimensions differ.
Q = np.diag([1e4, 1.0])
R = np.eye(nu)
P = 1e1 * Q

ny = nx + nu

Vx = np.vstack(
    (
        np.eye(nx),
        np.zeros((nu, nx)),
    )
)

Vu = np.vstack(
    (
        np.zeros((nx, nu)),
        np.eye(nu),
    )
)

y_ref = np.concatenate((x_ref, u_ref))


# ==========================================================================
# 4. CONSTRAINT DESIGN DATA
# ==========================================================================
#
# IMPORTANT:
# acados indices are ZERO-BASED in Python as well.

x0_default = np.zeros(nx)

# ---- input bounds --------------------------------------------------------

u_min = -np.ones(nu)
u_max = np.ones(nu)

# ---- path state bounds ---------------------------------------------------

state_bound_idx = np.array([0], dtype=np.int64)
x_min = np.array([-np.pi / 2])
x_max = np.array([ np.pi / 2])

# ---- terminal bounds -----------------------------------------------------

terminal_state_bound_idx = np.array([0], dtype=np.int64)
x_min_e = np.array([-np.pi / 2])
x_max_e = np.array([ np.pi / 2])

# ---- general linear constraints -----------------------------------------
#
#     lg <= C x + D u <= ug

C_general = np.zeros((1, nx))
D_general = np.zeros((1, nu))
lg_general = np.array([-np.inf])
ug_general = np.array([ np.inf])

# ---- terminal linear constraints ----------------------------------------
#
#     lg_e <= C_e x_N <= ug_e

C_general_e = np.zeros((1, nx))
lg_general_e = np.array([-np.inf])
ug_general_e = np.array([ np.inf])


# ==========================================================================
# 5. CREATE OCP
# ==========================================================================

ocp = AcadosOcp()

# Readable name instead of automatic hash suffix.
ocp.name = solver_name

ocp.model = model

ocp.solver_options.N_horizon = N
ocp.solver_options.tf = Tf


# ==========================================================================
# 6. COST
# ==========================================================================

# --------------------------------------------------------------------------
# 6.1 initial stage k=0
# --------------------------------------------------------------------------

ocp.cost.cost_type_0 = "LINEAR_LS"

ocp.cost.Vx_0 = Vx
ocp.cost.Vu_0 = Vu
ocp.cost.W_0 = block_diag(Q, R)
ocp.cost.yref_0 = y_ref


# --------------------------------------------------------------------------
# 6.2 path cost
# --------------------------------------------------------------------------

ocp.cost.cost_type = "LINEAR_LS"

ocp.cost.Vx = Vx
ocp.cost.Vu = Vu
ocp.cost.W = block_diag(Q, R)
ocp.cost.yref = y_ref


# --------------------------------------------------------------------------
# 6.3 terminal cost
# --------------------------------------------------------------------------

ocp.cost.cost_type_e = "LINEAR_LS"

ocp.cost.Vx_e = np.eye(nx)
ocp.cost.W_e = P
ocp.cost.yref_e = x_ref


# Other useful cost types:
#
#   "NONLINEAR_LS"
#   "EXTERNAL"
#   "CONVEX_OVER_NONLINEAR"


# ==========================================================================
# 7. CONSTRAINTS
# ==========================================================================

# --------------------------------------------------------------------------
# 7.1 Initial-state equality
# --------------------------------------------------------------------------
#
#     x_0 = x_measured
#
# This defines the structure. At runtime, update x0 numerically with:
#
#     solver.set(0, "lbx", x_meas)
#     solver.set(0, "ubx", x_meas)
#
# or use an appropriate convenience method if available in your version.

ocp.constraints.x0 = x0_default


# --------------------------------------------------------------------------
# 7.2 Input bounds
# --------------------------------------------------------------------------

if USE_INPUT_BOUNDS:
    ocp.constraints.idxbu = np.arange(nu, dtype=np.int64)
    ocp.constraints.lbu = u_min
    ocp.constraints.ubu = u_max


# --------------------------------------------------------------------------
# 7.3 Path state bounds
# --------------------------------------------------------------------------

if USE_STATE_BOUNDS:
    ocp.constraints.idxbx = state_bound_idx
    ocp.constraints.lbx = x_min
    ocp.constraints.ubx = x_max


# --------------------------------------------------------------------------
# 7.4 Terminal state bounds
# --------------------------------------------------------------------------

if USE_TERMINAL_STATE_BOUNDS:
    ocp.constraints.idxbx_e = terminal_state_bound_idx
    ocp.constraints.lbx_e = x_min_e
    ocp.constraints.ubx_e = x_max_e


# --------------------------------------------------------------------------
# 7.5 General linear constraints
# --------------------------------------------------------------------------
#
#     lg <= C*x + D*u <= ug

if USE_GENERAL_LINEAR_CONSTRAINT:
    ocp.constraints.C = C_general
    ocp.constraints.D = D_general
    ocp.constraints.lg = lg_general
    ocp.constraints.ug = ug_general


# --------------------------------------------------------------------------
# 7.6 Terminal general linear constraints
# --------------------------------------------------------------------------

if USE_TERMINAL_LINEAR_CONSTRAINT:
    ocp.constraints.C_e = C_general_e
    ocp.constraints.lg_e = lg_general_e
    ocp.constraints.ug_e = ug_general_e


# --------------------------------------------------------------------------
# 7.7 Nonlinear constraints
# --------------------------------------------------------------------------
#
# BGH form:
#
#     lh <= h(x,u) <= uh

if USE_NONLINEAR_CONSTRAINT:
    h_expr = model.x[0] ** 2

    ocp.model.con_h_expr = h_expr

    ocp.constraints.lh = np.array([0.0])
    ocp.constraints.uh = np.array([1.0])


# --------------------------------------------------------------------------
# 7.8 Soft constraints example
# --------------------------------------------------------------------------
#
# Example for softening the FIRST state-bound constraint:
#
# ocp.constraints.idxsbx = np.array([0], dtype=np.int64)
# ocp.constraints.lsbx = np.zeros(1)
# ocp.constraints.usbx = np.zeros(1)
#
# ocp.cost.zl = 1e3 * np.ones(1)
# ocp.cost.zu = 1e3 * np.ones(1)
# ocp.cost.Zl = 1e4 * np.ones(1)
# ocp.cost.Zu = 1e4 * np.ones(1)


# ==========================================================================
# 8. NUMERICAL SOLVER
# ==========================================================================

ocp.solver_options.nlp_solver_type = "SQP"

# Later for real-time MPC:
# ocp.solver_options.nlp_solver_type = "SQP_RTI"

ocp.solver_options.qp_solver = "PARTIAL_CONDENSING_HPIPM"

# Alternatives if compiled:
#
# "FULL_CONDENSING_HPIPM"
# "FULL_CONDENSING_QPOASES"
# "FULL_CONDENSING_DAQP"
# "PARTIAL_CONDENSING_OSQP"
# "PARTIAL_CONDENSING_QPDUNES"
# "PARTIAL_CONDENSING_CLARABEL"

ocp.solver_options.integrator_type = "ERK"
ocp.solver_options.hessian_approx = "GAUSS_NEWTON"

# Optional:
#
# ocp.solver_options.sim_method_num_stages = 4
# ocp.solver_options.sim_method_num_steps = 1
#
# ocp.solver_options.nlp_solver_max_iter = 20
# ocp.solver_options.nlp_solver_tol_stat = 1e-6
# ocp.solver_options.nlp_solver_tol_eq = 1e-6
# ocp.solver_options.nlp_solver_tol_ineq = 1e-6
# ocp.solver_options.nlp_solver_tol_comp = 1e-6
#
# ocp.solver_options.qp_solver_cond_N = 10


# ==========================================================================
# 9. OPTIONAL SIMULINK FILE GENERATION
# ==========================================================================
#
# Python can generate the MATLAB/Simulink source files, but MATLAB still
# compiles the generated S-function MEX.

if GENERATE_SIMULINK_FILES:

    simulink_opts = AcadosOcpSimulinkOptions()

    # Disable all ports first.
    for name in vars(simulink_opts.inputs):
        setattr(simulink_opts.inputs, name, 0)

    for name in vars(simulink_opts.outputs):
        setattr(simulink_opts.outputs, name, 0)

    # Runtime measured state.
    simulink_opts.inputs.lbx_0 = 1
    simulink_opts.inputs.ubx_0 = 1

    # Runtime references.
    simulink_opts.inputs.y_ref_0 = 1
    simulink_opts.inputs.y_ref = 1
    simulink_opts.inputs.y_ref_e = 1

    # Outputs.
    simulink_opts.outputs.u0 = 1
    simulink_opts.outputs.solver_status = 1
    simulink_opts.outputs.CPU_time = 1
    simulink_opts.outputs.sqp_iter = 1
    simulink_opts.outputs.KKT_residual = 1

    simulink_opts.samplingtime = "t0"
    simulink_opts.generate_simulink_block = 1

    ocp.simulink_opts = simulink_opts


# ==========================================================================
# 10. CODE GENERATION
# ==========================================================================

ocp.code_gen_options.code_export_directory = codegen_dir

# Filename only.
ocp.code_gen_options.json_file = json_name


# ==========================================================================
# 11. CMAKE BUILDER
# ==========================================================================
#
# On Windows, CMake + Visual Studio is recommended.
#
# Your local acados patch changes the Python defaults to VS 2022 / x64,
# but it is also fine to state them explicitly here.

cmake_builder = None

if USE_CMAKE:
    cmake_builder = ocp_get_default_cmake_builder()

    if os.name == "nt":
        cmake_builder.generator = "Visual Studio 17 2022"
        cmake_builder.host = "x64"


# ==========================================================================
# 12. CREATE OR REUSE SOLVER
# ==========================================================================
#
# Current Python acados supports the same idea as MATLAB:
#
#   generate=False
#   build=False
#   check_reuse_possible=True
#
# If the formulation differs from the stored JSON/hash, acados forces
# generate/build back to True.

solver = AcadosOcpSolver(
    ocp,
    generate=False,
    build=False,
    check_reuse_possible=True,
    cmake_builder=cmake_builder,
)


# ==========================================================================
# 13. RUNTIME MPC UPDATE EXAMPLE
# ==========================================================================
#
# Runtime values should NOT require regeneration.

x_meas = np.zeros(nx)

# Enforce x0 = x_meas.
solver.set(0, "lbx", x_meas)
solver.set(0, "ubx", x_meas)

# Reference example.
#
# Stage 0:
solver.set(0, "yref", y_ref)

# Path stages:
for k in range(1, N):
    solver.set(k, "yref", y_ref)

# Terminal:
solver.set(N, "yref", x_ref)


# ==========================================================================
# 14. SOLVE
# ==========================================================================

status = solver.solve()

u0 = solver.get(0, "u")

print(f"solver status = {status}")
print(f"u0 = {u0}")

solver.print_statistics()


# ==========================================================================
# 15. CLOSED-LOOP STRUCTURE
# ==========================================================================
#
# Typical loop:
#
# for k in range(Nsim):
#
#     x_meas = measure_state()
#
#     solver.set(0, "lbx", x_meas)
#     solver.set(0, "ubx", x_meas)
#
#     update references / parameters
#
#     status = solver.solve()
#     u = solver.get(0, "u")
#
#     apply_control(u)
#
#
# Runtime changes:
#   x0, yref, p, warm starts
#
# Structural changes:
#   model, dimensions, N, cost structure, constraint structure,
#   integrator, QP/NLP solver, Simulink port structure
