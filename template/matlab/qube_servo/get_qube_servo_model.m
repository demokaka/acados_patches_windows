% - get qube servo model
% File: get_qube_servo_model.m

function model = get_qube_servo_model()
    import casadi.*

    qube3_param;
    a = kt*km /(Rm*Jeq);
    b = kt / (Rm*Jeq);

    % state
    theta = SX.sym("theta");
    omega = SX.sym("omega");
    
    x = vertcat(theta, omega);
    % or we can use matlab syntax: x = [theta;omega];

    % input
    vm = SX.sym('vm');

    u  = vertcat(vm);
    
    % state derivatives
    theta_dot = SX.sym('theta_dot');
    omega_dot = SX.sym('omega_dot');
    
    xdot = vertcat(theta_dot, omega_dot);

    % dynamics
    f_expl = vertcat(omega, -a * omega + b * vm);
    f_impl = xdot - f_expl;

    % model
    model = AcadosModel();
    model.name = 'qube_servo'; % not model.name = "qube_servo";
    model.x = x;
    model.xdot = xdot;
    model.u = u;
    model.f_expl_expr = f_expl;
    model.f_impl_expr = f_impl;

end

