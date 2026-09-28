interface_dir = fileparts(which('acados_env_variables_windows_msvc_s'));

acados_dir = fullfile(interface_dir, '..', '..');

matlab_interface_dir = fullfile( ...
    acados_dir, ...
    'interfaces', ...
    'acados_matlab_octave');

addpath(matlab_interface_dir);
addpath(fullfile(acados_dir, 'external', 'jsonlab'));

% Set acados root
setenv('ACADOS_INSTALL_DIR', acados_dir);

% Add runtime DLLs to Windows PATH
acados_bin = fullfile(acados_dir, 'bin');

if ~contains(getenv('PATH'), acados_bin, 'IgnoreCase', true)
    setenv('PATH', [acados_bin pathsep getenv('PATH')]);
end

setenv('ENV_RUN', 'true');