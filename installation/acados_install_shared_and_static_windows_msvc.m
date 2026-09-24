function acados_install_shared_and_static_windows_msvc(varargin)
% acados_install_shared_and_static_windows_msvc([CmakeConfigString])
% Install acados on Windows/MSVC as both shared and static libraries.
%
% This function intentionally follows the structure of the upstream
% acados_install_shared_and_static_windows.m. The blocks marked
% "WINDOWS/MSVC PATCH" contain the local adjustments required by the
% Visual Studio/MSVC workflow.
%
% CmakeConfigString
%   Optional extra CMake configuration string.
%
% Default:
%   -DCMAKE_POLICY_VERSION_MINIMUM=3.5
%
% Typical usage:
%
%   acados_install_shared_and_static_windows_msvc( ...
%       ['-DACADOS_WITH_QPOASES=ON ', ...
%        '-DACADOS_WITH_DAQP=OFF ', ...
%        '-DACADOS_WITH_QPDUNES=ON ', ...
%        '-DACADOS_WITH_OSQP=ON ', ...
%        '-DACADOS_WITH_HPMPC=OFF ', ...
%        '-DACADOS_WITH_CLARABEL=OFF ', ...
%        '-DACADOS_WITH_QORE=OFF ', ...
%        '-DACADOS_WITH_OOQP=OFF ', ...
%        '-DCMAKE_POLICY_VERSION_MINIMUM=3.5'])
%
% Installation layout after this function:
%
%   <acados>\bin
%       shared DLLs
%       import .lib files from the shared build
%
%   <acados>\lib
%       static .lib files from the second build
%
% The import libraries from the shared build are intentionally moved to
% bin before the static build is installed. This keeps the static libraries
% in lib while preserving the import libraries needed by the DLL-based
% MATLAB/MEX workflow.


    switch nargin
        case 0
            cmakeConfigString = '-DCMAKE_POLICY_VERSION_MINIMUM=3.5';
        case 1
            cmakeConfigString = varargin{1};
        otherwise
            error('function called with %d parameters, was expecting max 1', nargin);
    end


    %% Guard against conflicting user option
    if contains(cmakeConfigString, '-DBUILD_SHARED_LIBS')
        error(['BUILD_SHARED_LIBS must not be provided in CmakeConfigString. ', ...
               'This wrapper performs both the shared and static builds itself.']);
    end


    %% Shared installation
    disp(' ');
    disp('============================================================');
    disp('Installing acados with shared libraries (MSVC)');
    disp('============================================================');

    acados_install_windows_msvc( ...
        ['-DBUILD_SHARED_LIBS=ON ', cmakeConfigString]);


    acados_root_dir = getenv('ACADOS_INSTALL_DIR');

    if isempty(acados_root_dir)
        error('ACADOS_INSTALL_DIR is empty after shared installation.');
    end

    acados_bin_path = fullfile(acados_root_dir, 'bin');
    acados_lib_path = fullfile(acados_root_dir, 'lib');


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH:
    % The MSVC installer uses <acados>\build_msvc rather than the upstream
    % MinGW-oriented <acados>\build directory.
    %
    % Some optional solver subprojects (notably qpOASES and qpDUNES in the
    % current workflow) build their DLLs successfully but do not always
    % install them into <acados>\bin. Search the build tree recursively
    % instead of depending on a fixed Visual Studio Release subdirectory.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    acados_build_path = fullfile(acados_root_dir, 'build_msvc');

    optional_solver_dlls = { ...
        'qpOASES_e.dll', ...
        'qpdunes.dll' ...
    };

    for i = 1:numel(optional_solver_dlls)
        copy_optional_solver_dll( ...
            acados_build_path, ...
            acados_bin_path, ...
            optional_solver_dlls{i});
    end
    % END PATCH
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


    %% Preserve shared-build import libraries
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % WINDOWS/MSVC PATCH / clarification:
    %
    % On Windows, a shared library normally consists of:
    %
    %   foo.dll  -> runtime library
    %   foo.lib  -> import library used by the linker
    %
    % CMake installs the .lib import libraries into <acados>\lib. We move
    % them to <acados>\bin before installing the static build, because the
    % static build will populate <acados>\lib with static libraries having
    % many of the same filenames.
    %
    % The upstream shared+static Windows installer uses the same strategy.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    fprintf('Moving shared-build import libraries from lib to bin\n');

    shared_import_libs = dir(fullfile(acados_lib_path, '*.lib'));

    if isempty(shared_import_libs)
        warning(['No .lib import libraries were found in:\n  %s\n', ...
                 'The shared installation may not have completed as expected.'], ...
                 acados_lib_path);
    else
        for i = 1:numel(shared_import_libs)
            src = fullfile(shared_import_libs(i).folder, shared_import_libs(i).name);
            dst = fullfile(acados_bin_path, shared_import_libs(i).name);

            fprintf('  %s -> bin\n', shared_import_libs(i).name);

            [status, message] = movefile(src, dst, 'f');

            if ~status
                error('Failed to move %s to bin:\n%s', src, message);
            end
        end
    end


    %% Static installation
    disp(' ');
    disp('============================================================');
    disp('Installing acados with static libraries (MSVC)');
    disp('============================================================');

    acados_install_windows_msvc( ...
        ['-DBUILD_SHARED_LIBS=OFF ', cmakeConfigString]);


    fprintf('\n');
    fprintf('Shared + static MSVC installation completed successfully.\n');
    fprintf('Shared runtime/import libraries:\n  %s\n', acados_bin_path);
    fprintf('Static libraries:\n  %s\n', acados_lib_path);

end


function copy_optional_solver_dll(build_root, bin_dir, dll_name)
% Search recursively for an optional solver DLL and copy it to acados/bin.
%
% Visual Studio is a multi-configuration generator, so exact build-tree
% locations may vary between dependencies and CMake versions. Recursive
% discovery is more robust than hard-coding paths such as:
%
%   build_msvc\external\<solver>\lib\Release\...

    if ~exist(build_root, 'dir')
        warning('MSVC build directory does not exist: %s', build_root);
        return;
    end

    matches = dir(fullfile(build_root, '**', dll_name));

    if isempty(matches)
        fprintf('Optional DLL not found in build tree: %s\n', dll_name);
        return;
    end

    % Prefer an artifact from a Release directory when several matches exist.
    selected = 1;

    for k = 1:numel(matches)
        candidate = fullfile(matches(k).folder, matches(k).name);

        if contains(lower(candidate), [filesep, 'release', filesep])
            selected = k;
            break;
        end
    end

    src = fullfile(matches(selected).folder, matches(selected).name);
    dst = fullfile(bin_dir, dll_name);

    fprintf('Copying optional solver DLL:\n');
    fprintf('  %s\n', src);
    fprintf('  -> %s\n', dst);

    [status, message] = copyfile(src, dst, 'f');

    if ~status
        error('Failed to copy %s:\n%s', dll_name, message);
    end
end
