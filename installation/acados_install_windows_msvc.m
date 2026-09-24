function acados_install_windows_msvc(varargin)
% acados_install_windows_msvc([CmakeConfigString])
% Install acados on Windows using Visual Studio 2022 / MSVC.
%
% This function intentionally follows the structure of the upstream
% acados_install_windows.m as closely as possible. The upstream installer is
% written for MinGW; the blocks marked "WINDOWS/MSVC PATCH" are the local
% changes required for the MSVC workflow.
%
% CmakeConfigString
%   Optional extra CMake configuration string.
%
% Default:
%   -DBUILD_SHARED_LIBS=OFF
%   -DACADOS_WITH_OSQP=OFF
%   -DCMAKE_POLICY_VERSION_MINIMUM=3.5
%
% Typical usage:
%
%   acados_install_windows_msvc()
%
% or, for example:
%
%   acados_install_windows_msvc([ ...
%       '-DBUILD_SHARED_LIBS=OFF ', ...
%       '-DACADOS_WITH_QPOASES=ON ', ...
%       '-DACADOS_WITH_OSQP=ON ', ...
%       '-DACADOS_WITH_QPDUNES=ON ', ...
%       '-DACADOS_WITH_DAQP=ON' ...
%   ])
%
% Notes
% -----
% 1. This is a single acados build/install pass. If your higher-level
%    installation workflow intentionally performs both a shared and a static
%    build, call this function separately for each configuration.
%
% 2. BLASFEO is forced to GENERIC for native MSVC compatibility.
%
% 3. Visual Studio is a multi-configuration generator, therefore Release is
%    selected with "--config Release" during build/install rather than with
%    CMAKE_BUILD_TYPE.
%
% 4. The MSVC runtime is requested as MultiThreadedDLL (/MD), matching the
%    normal MATLAB MEX runtime. CMP0091 is explicitly enabled so modern CMake
%    honors CMAKE_MSVC_RUNTIME_LIBRARY.
%
% 5. No installation path is hard-coded. ACADOS_INSTALL_DIR is derived from
%    the location of this file, exactly as in the upstream Windows installer.


    switch nargin
        case 0
            cmakeConfigString = [ ...
                '-DBUILD_SHARED_LIBS=OFF ', ...
                '-DACADOS_WITH_OSQP=OFF ', ...
                '-DCMAKE_POLICY_VERSION_MINIMUM=3.5' ...
            ];
        case 1
            cmakeConfigString = varargin{1};
        otherwise
            error('function called with %d parameters, was expecting max 1', nargin);
    end


    %% Derive acados root path
    % Upstream logic: this file lives in
    % <acados>\interfaces\acados_matlab_octave.
    fullPath = mfilename('fullpath');

    [folderPath, ~, ~] = fileparts(fullPath);
    [folderPath, ~, ~] = fileparts(folderPath);
    [acadosPath, ~, ~] = fileparts(folderPath);

    % Use forward slashes in CMake command-line paths.
    acadosPath = strrep(acadosPath, '\', '/');


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH:
    % Use a dedicated build directory instead of the upstream "build".
    %
    % This prevents CMake generator conflicts if the same acados checkout
    % has previously been configured with MinGW.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    acadosBuildPath = fullfile(acadosPath, 'build_msvc');


    %% Environment
    fprintf('Setting up environment for MSVC build\n');

    origEnvPath = getenv('PATH');
    origDir = pwd;

    % Always restore the caller's directory and PATH, also if an error occurs.
    cleanupObj = onCleanup(@() restore_environment(origDir, origEnvPath)); %#ok<NASGU>

    setenv('ACADOS_INSTALL_DIR', acadosPath);


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH:
    % The upstream MinGW installer prepends
    %     <mex compiler location>\bin
    % to PATH so that gcc/mingw32-make are found.
    %
    % Do NOT do that for Visual Studio. CMake's Visual Studio generator
    % locates MSVC through the installed Visual Studio toolchain.
    %
    % We only inspect MATLAB's selected C compiler here as a useful sanity
    % check because the generated MEX interfaces are also expected to use
    % Microsoft Visual C++ in this workflow.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    cCompilerConfig = mex.getCompilerConfigurations('C', 'Selected');

    if isempty(cCompilerConfig)
        warning(['No MATLAB C compiler is currently selected. ', ...
                 'Run "mex -setup C" before compiling acados MEX interfaces.']);
    else
        fprintf('MATLAB selected C compiler: %s\n', cCompilerConfig.Name);

        if ~contains(lower(cCompilerConfig.Name), 'microsoft')
            warning(['The selected MATLAB C compiler does not appear to be MSVC. ', ...
                     'For this workflow, run "mex -setup C" and select ', ...
                     'Microsoft Visual C++ 2022.']);
        end
    end


    %% Create build directory
    fprintf('Creating build dir in %s\n', acadosBuildPath);

    if ~exist(acadosBuildPath, 'dir')
        mkdir(acadosBuildPath);
    end

    cd(acadosBuildPath);

    fprintf('ACADOS_INSTALL_DIR is %s\n', acadosPath);


    %% Configure acados with CMake
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH:
    %
    % Upstream Windows installer:
    %   cmake.exe -G "MinGW Makefiles" ...
    %
    % MSVC version:
    %   - Visual Studio 17 2022 generator
    %   - x64 architecture
    %   - BLASFEO_TARGET=GENERIC
    %   - HPIPM_TARGET=GENERIC (explicit, although GENERIC is already the
    %     current acados default)
    %   - /MD runtime through CMAKE_MSVC_RUNTIME_LIBRARY
    %   - dynamic ACADOS_INSTALL_DIR; no user-specific hard-coded path
    %
    % CMAKE_BUILD_TYPE is deliberately NOT set: Visual Studio is a
    % multi-configuration generator and Release is chosen at build time.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    cmake_cmd = sprintf([ ...
        'cmake -G "Visual Studio 17 2022" -A x64 ', ...
        '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW ', ...
        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL ', ...
        '-DBLASFEO_TARGET=GENERIC ', ...
        '-DHPIPM_TARGET=GENERIC ', ...
        '-DACADOS_INSTALL_DIR="%s" ', ...
        '%s ..' ...
    ], acadosPath, cmakeConfigString);

    fprintf('Executing CMake configuration\n');
    disp(cmake_cmd);

    status = system(cmake_cmd);

    if status ~= 0
        error('cmake command failed. Command was:\n%s\n', cmake_cmd);
    end


    %% Compile
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH:
    % Visual Studio projects are built through "cmake --build".
    % "--config Release" selects the Release configuration.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    fprintf('Compiling and installing using MSVC\n');

    n_jobs = 4;
    compile_command = sprintf( ...
        'cmake --build . --parallel %d --config Release', ...
        n_jobs);

    status = system(compile_command);

    if status ~= 0
        envPath = getenv('PATH');
        error('Compilation of acados failed %s\n%s\n%s\n%s\n\n', ...
            'Compile command was:', compile_command, ...
            'Environment path was: ', envPath);
    end


    %% Install
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH:
    % Equivalent of the upstream "mingw32-make.exe install".
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    install_command = 'cmake --install . --config Release';

    status = system(install_command);

    if status ~= 0
        envPath = getenv('PATH');
        error('Installation of acados failed %s\n%s\n%s\n%s\n\n', ...
            'Install command was:', install_command, ...
            'Environment path was: ', envPath);
    end


    %% MATLAB interface / CasADi
    addpath(fullfile(acadosPath, 'interfaces', 'acados_matlab_octave'));


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH:
    % Prefer the custom MSVC environment helper when it is present.
    % Fall back to the upstream Windows environment script otherwise.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    msvc_env_script = fullfile( ...
        acadosPath, ...
        'interfaces', ...
        'acados_matlab_octave', ...
        'acados_env_variables_windows_msvc.m');

    if exist(msvc_env_script, 'file')
        run(msvc_env_script);
    else
        fprintf(['acados_env_variables_windows_msvc.m was not found; ', ...
                 'using upstream acados_env_variables_windows.m instead.\n']);
        run(fullfile( ...
            acadosPath, ...
            'interfaces', ...
            'acados_matlab_octave', ...
            'acados_env_variables_windows.m'));
    end


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH / USER WORKFLOW:
    % Upstream calls:
    %
    %     check_acados_requirements(true)
    %
    % which automatically downloads CasADi when it is not found.
    %
    % Here "false" keeps the upstream check but does not force a download:
    % if CasADi is already available nothing happens; otherwise MATLAB asks
    % before downloading it. This works better when CasADi is managed
    % separately.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    check_acados_requirements(false);


    %% Template renderer
    % This part intentionally mirrors the current upstream installer.
    fprintf('Installing the template renderer...\n');

    acados_root_dir = getenv('ACADOS_INSTALL_DIR');
    t_renderer_location = fullfile(acados_root_dir, 'bin', 't_renderer.exe');

    if ~exist(t_renderer_location, 'file')
        set_up_t_renderer(t_renderer_location);
    end


    fprintf('\nacados was installed successfully with MSVC!\n');
    fprintf('Installation directory:\n  %s\n', acadosPath);
    fprintf('Build directory:\n  %s\n', acadosBuildPath);

end


function restore_environment(origDir, origEnvPath)
% Restore MATLAB process state even when installation throws an error.

    try
        cd(origDir);
    catch
    end

    try
        setenv('PATH', origEnvPath);
    catch
    end
end
