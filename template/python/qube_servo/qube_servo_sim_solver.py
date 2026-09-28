from pathlib import Path
from acados_template import AcadosSim, AcadosSimSolver, sim_get_default_cmake_builder

from get_qube_servo_model import export_qube_servo_model
import numpy as np

# Resistance
Rm = 7.5
# Current-torque (N-m/A)
kt = 0.042
# Back-emf constant (V-s/rad)
km = 0.042
# Rotor inertia (kg-m^2)
Jr = 1.4e-6
# Hub mass (kg)
mh = 0.0106 # 9 g
# Hub radius (m)
rh = 22.2/1000/2 # diameter 22.2 mm
# Hub inertia (kg-m^2)
Jh = 0.5*mh*rh**2
# Disc mass (kg)
md = 0.053
# Disc radius (m)
rd = 49.5/1000/2 # diameter = 49.5 mm
# Disc moment of inertia (kg-m^2)
Jd = 0.5*md*rd**2
# Equivalent moment of inertia (kg-m^2)
Jeq = Jr + Jh + Jd

def main():
    Ts = 0.02

    model = export_qube_servo_model(kt=kt, km=km, Rm=Rm, Jeq=Jeq)

    #
    sim = AcadosSim()
    sim.model = model
    sim.name = 'qube_servo_plant'

    # integration time
    sim.solver_options.T = Ts # for python, use solver_options.T

    # integrator type
    sim.solver_options.num_stages = 4
    sim.solver_options.num_steps = 2

    # codegen options
    script_dir = Path(__file__).resolve().parent

    codegen_dir = script_dir / "generated_code_qube_servo_sim"
    sim.code_gen_options.code_export_directory = str(codegen_dir)
    sim.code_gen_options.json_file = "qube_servo_sim.json"

    # cmake builder required for MSVC
    builder = sim_get_default_cmake_builder()

    builder.generator = "Visual Studio 17 2022"
    builder.host = "x64"

    # generate and build
    sim_solver = AcadosSimSolver(sim,
                                 generate=False,    # by default, in python is True
                                 build=False,       # by default, in python is True
                                 check_reuse_possible=True, 
                                 cmake_builder=builder)
    return sim_solver


if __name__=="__main__":
    sim_solver = main()

    x = np.array([
        0.0,
        0.0,
    ])

    u = np.array([
        1.0,
    ])

    x_next = sim_solver.simulate(
        x=x,
        u=u,
    )

    print("x      =", x)
    print("u      =", u)
    print("x_next =", x_next)
