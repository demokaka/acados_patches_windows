from pathlib import Path
from dataclasses import fields
from acados_template import AcadosOcp, AcadosOcpSolver, ocp_get_default_cmake_builder, AcadosOcpSimulinkOptions

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
    model = export_qube_servo_model(kt=kt, km=km, Rm=Rm, Jeq=Jeq)

    nx = model.x.rows()
    nu = model.u.rows()

    Ts = 0.02
    Npred = 50
    Tf = Npred * Ts

    x_ref = np.array([0.5,0.0])
    u_ref = np.array([0.0])
    y_ref = np.concatenate((x_ref,u_ref))

    Qc = np.diag([1e4, 1.0])
    Rc = np.diag([1.0])
    P = 10.0 * Qc

    # OCP
    ocp = AcadosOcp()
    ocp.name = "qube_servo_mpc"
    ocp.model = model

    ocp.solver_options.N_horizon = Npred
    ocp.solver_options.tf = Tf

    # cost
    Vx = np.vstack((np.eye(nx), np.zeros((nu,nx))))
    Vu = np.vstack((np.zeros((nx,nu)), np.eye(nu)))

    # initial cost
    ocp.cost.cost_type_0 = "LINEAR_LS"
    ocp.cost.Vx_0 = Vx
    ocp.cost.Vu_0 = Vu
    ocp.cost.W_0 = 2.0 *  np.block([[Qc, np.zeros((nx,nu))],[np.zeros((nu,nx)), Rc]])
    ocp.cost.yref_0 = y_ref

    # path cost
    ocp.cost.cost_type = "LINEAR_LS"
    ocp.cost.Vx = Vx
    ocp.cost.Vu = Vu
    ocp.cost.W = 2.0 *  np.block([[Qc, np.zeros((nx,nu))],[np.zeros((nu,nx)), Rc]])
    ocp.cost.yref = y_ref

    # terminal cost
    ocp.cost.cost_type_0 = "LINEAR_LS"
    ocp.cost.Vx_e = np.eye(nx)
    ocp.cost.W_e= 2.0 *  P
    ocp.cost.yref_e = x_ref


    # Constraints
    # initial state
    x0 = np.array([0.0, 0.0])
    ocp.constraints.x0 = x0

    # input bounds
    vmax = 10
    vmin = -10

    ocp.constraints.idxbu = 0
    ocp.constraints.lbu = vmin
    ocp.constraints.ubu = vmax

    # solver options
    ocp.solver_options.nlp_solver_type = 'SQP'; # 'SQP'; 'SQP_RTI'
    ocp.solver_options.qp_solver = 'PARTIAL_CONDENSING_HPIPM'
    ocp.solver_options.integrator_type = 'ERK'
    ocp.solver_options.hessian_approx = 'GAUSS_NEWTON'

    # OCP internal integrator
    ocp.solver_options.sim_method_num_stages = 4
    ocp.solver_options.sim_method_num_steps = 1

    # codegen options
    script_dir = Path(__file__).resolve().parent

    codegen_dir = script_dir / "generated_code_qube_servo_ocp"
    ocp.code_gen_options.code_export_directory = str(codegen_dir)
    ocp.code_gen_options.json_file = "qube_servo_ocp.json"

    # cmake builder required for MSVC
    builder = ocp_get_default_cmake_builder()

    builder.generator = "Visual Studio 17 2022"
    builder.host = "x64"

    # 
    simulink_opts = AcadosOcpSimulinkOptions()
    # ------------------------------------------------
    # Disable all inputs first
    # ------------------------------------------------

    for f in fields(simulink_opts.inputs):
        setattr(simulink_opts.inputs, f.name, 0)

    # ------------------------------------------------
    # Disable all outputs first
    # ------------------------------------------------

    for f in fields(simulink_opts.outputs):
        setattr(simulink_opts.outputs, f.name, 0)

    # inputs
    simulink_opts.inputs.lbx_0 = 1
    simulink_opts.inputs.ubx_0 = 1
    
    simulink_opts.inputs.y_ref_0 = 1
    simulink_opts.inputs.y_ref = 1
    simulink_opts.inputs.y_ref_e = 1

    # outputs
    simulink_opts.outputs.u0 = 1
    simulink_opts.outputs.solver_status = 1
    simulink_opts.outputs.CPU_time = 1
    simulink_opts.outputs.sqp_iter = 1

    # block settings
    simulink_opts.samplingtime = "t0"
    simulink_opts.show_port_info = 1
    simulink_opts.generate_simulink_block = 1


    ocp.simulink_opts = simulink_opts
    # generate and build
    ocp_solver = AcadosOcpSolver(ocp,
                                 generate=False,    # by default, in python is True
                                 build=False,       # by default, in python is True
                                 check_reuse_possible=True, 
                                 cmake_builder=builder)
    return ocp_solver

if __name__=="__main__":
    ocp_solver = main()

    x_meas = np.array([
        0.0,
        0.0,
    ])

    # stage-0 equality:
    #
    # lbx_0 = ubx_0 = measured state

    ocp_solver.set(
        0,
        "lbx",
        x_meas,
    )

    ocp_solver.set(
        0,
        "ubx",
        x_meas,
    )

    status = ocp_solver.solve()

    print("status =", status)

    if status != 0:
        ocp_solver.print_statistics()

    u0 = ocp_solver.get(
        0,
        "u",
    )

    print("u0 =", u0)
