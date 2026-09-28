from acados_template import AcadosModel
from casadi import SX, vertcat


def export_qube_servo_model(kt, km, Rm, Jeq):
    # parameters
    a = kt*km/(Rm*Jeq)
    b = kt/(Rm*Jeq)

    # states
    theta =  SX.sym('theta')
    omega = SX.sym('omega')

    x = vertcat(theta, omega)

    # input
    vm = SX.sym('vm')

    u = vertcat(vm)

    # state derivatives
    theta_dot = SX.sym('theta_dot')
    omega_dot = SX.sym('omega_dot')

    xdot = vertcat(theta_dot,omega_dot)

    # dynamics
    f_expl = vertcat(omega, -a*omega + b*vm)

    f_impl = xdot - f_expl

    # acados model
    model = AcadosModel()

    model.name = 'qube_servo'
    model.x = x
    model.xdot = xdot
    model.u = u

    model.f_expl_expr = f_expl
    model.f_impl_expr = f_impl

    return model
