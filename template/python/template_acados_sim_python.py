"""
ACADOS SIM TEMPLATE -- STANDALONE INTEGRATOR / PYTHON / WINDOWS-MSVC

AcadosSim advances the model one integration interval:

    x_next = Phi(x, u, p)

Use it to:
    - validate model dynamics,
    - simulate a plant,
    - inspect sensitivities,
    - generate an integrator S-function for Simulink.

IMPORTANT
---------
Replace export_qube_servo_model() with your real Python model-export function.
"""

from __future__ import annotations

import os
import numpy as np

from acados_template import (
    AcadosSim,
    AcadosSimSolver,
    sim_get_default_cmake_builder,
)

from qube_servo_model import export_qube_servo_model


# ==========================================================================
# 0. USER SWITCHES
# ==========================================================================

USE_CMAKE = True
GENERATE_SIMULINK_FILES = False


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
# 2. SIMULATION STEP
# ==========================================================================

Tsim = 0.02


# ==========================================================================
# 3. CREATE SIM OBJECT
# ==========================================================================

sim = AcadosSim()

sim.name = f"{model.name}_sim"
sim.model = model


# ==========================================================================
# 4. INTEGRATOR OPTIONS
# ==========================================================================
#
# IMPORTANT:
#
# Python:
#     sim.solver_options.T
#
# MATLAB:
#     sim.solver_options.Tsim

sim.solver_options.T = Tsim


# --------------------------------------------------------------------------
# 4.1 Integrator type
# --------------------------------------------------------------------------

sim.solver_options.integrator_type = "ERK"

# Alternatives:
#
# "IRK"
# "GNSF"


# --------------------------------------------------------------------------
# 4.2 Integration accuracy
# --------------------------------------------------------------------------

sim.solver_options.num_stages = 4
sim.solver_options.num_steps = 1


# --------------------------------------------------------------------------
# 4.3 IRK-specific options
# --------------------------------------------------------------------------
#
# sim.solver_options.newton_iter = 3
# sim.solver_options.newton_tol = 0.0
# sim.solver_options.collocation_type = "GAUSS_RADAU_IIA"
#
# Alternative:
# sim.solver_options.collocation_type = "GAUSS_LEGENDRE"


# ==========================================================================
# 5. SENSITIVITIES
# ==========================================================================

sim.solver_options.sens_forw = True

# Optional:
#
# sim.solver_options.sens_adj = False
# sim.solver_options.sens_algebraic = False
# sim.solver_options.sens_hess = False


# ==========================================================================
# 6. PARAMETERS
# ==========================================================================

if np_ > 0:
    sim.parameter_values = np.zeros(np_)


# ==========================================================================
# 7. OPTIONAL SIMULINK FILE GENERATION
# ==========================================================================
#
# In current Python acados, setting simulink_opts to a non-None object/dict
# requests MATLAB-related integrator S-function templates.
#
# The generated MEX is still compiled from MATLAB.

if GENERATE_SIMULINK_FILES:
    sim.simulink_opts = {}


# ==========================================================================
# 8. CODE GENERATION
# ==========================================================================

codegen_dir = os.path.abspath("generated_sim")
json_name = "my_sim.json"

sim.code_gen_options.code_export_directory = codegen_dir
sim.code_gen_options.json_file = json_name


# ==========================================================================
# 9. CMAKE BUILDER
# ==========================================================================

cmake_builder = None

if USE_CMAKE:
    cmake_builder = sim_get_default_cmake_builder()

    if os.name == "nt":
        cmake_builder.generator = "Visual Studio 17 2022"
        cmake_builder.host = "x64"


# ==========================================================================
# 10. CREATE OR REUSE INTEGRATOR
# ==========================================================================
#
# If JSON/hash matches:
#     reuse existing generated solver
#
# If formulation changed:
#     acados automatically forces generate=True and build=True

sim_solver = AcadosSimSolver(
    sim,
    generate=False,
    build=False,
    check_reuse_possible=True,
    cmake_builder=cmake_builder,
)


# ==========================================================================
# 11. TEST ONE STEP
# ==========================================================================

x0 = np.zeros(nx)
u0 = np.zeros(nu)

x1 = sim_solver.simulate(
    x=x0,
    u=u0,
)

print("x0 =", x0)
print("u0 =", u0)
print("x1 =", x1)


# ==========================================================================
# 12. LOW-LEVEL API
# ==========================================================================
#
# Equivalent:
#
# sim_solver.set("x", x0)
# sim_solver.set("u", u0)
#
# if np_ > 0:
#     p0 = np.zeros(np_)
#     sim_solver.set("p", p0)
#
# status = sim_solver.solve()
# x1 = sim_solver.get("x")
#
# NOTE:
# Check the exact get-field names supported by your acados version.
# The high-level simulate(...) helper is usually the simplest choice.


# ==========================================================================
# 13. FORWARD SENSITIVITIES
# ==========================================================================
#
# With sens_forw=True:

S_forw = sim_solver.get("S_forw")

print("S_forw =")
print(S_forw)

# Conceptually:
#
#     S_forw = [ d x_next / d x    d x_next / d u ]


# ==========================================================================
# 14. IRK INITIAL GUESS
# ==========================================================================
#
# For IRK:
#
# if sim.solver_options.integrator_type == "IRK":
#     sim_solver.set("xdot", np.zeros(nx))
#
# If algebraic states z exist:
#     sim_solver.set("z", z_guess)


# ==========================================================================
# 15. OPEN-LOOP SIMULATION LOOP
# ==========================================================================
#
# Nsim = 200
#
# X = np.zeros((Nsim + 1, nx))
# U = np.zeros((Nsim, nu))
#
# X[0] = x0
#
# for k in range(Nsim):
#
#     U[k] = np.zeros(nu)
#
#     X[k + 1] = sim_solver.simulate(
#         x=X[k],
#         u=U[k],
#     )
#
# t = np.arange(Nsim + 1) * Tsim


# ==========================================================================
# 16. WHEN DOES CODE NEED REGENERATION?
# ==========================================================================
#
# Runtime changes -- no regeneration:
#
#   x
#   u
#   p
#   IRK guesses
#
# Structural changes -- regenerate:
#
#   model equations
#   dimensions
#   integrator type
#   T
#   num_stages / num_steps
#   sensitivity structure
#
# The build-directory used by the acados installation itself (for example
# <acados>/build_msvc) is unrelated to the generated solver's local CMake
# build directory.
