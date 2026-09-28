function configure_quarc_acados(model_name, codegen_dir)
%CONFIGURE_QUARC_ACADOS
% Configure a Simulink/QUARC model to compile an acados S-function.
%
% Automatically reads the generated make_sfun*.m and configures:
%
%   CustomInclude
%   CustomSource
%   CustomLibrary
%
% Usage:
%
%   configure_quarc_acados( ...
%       'qube3_dc_mpc_acados', ...
%       ocp.code_gen_options.code_export_directory);
%
% Works with MATLAB-generated:
%       make_sfun.m
%
% and Python-generated:
%       make_sfun_<ocp_name>.m

    codegen_dir = char(codegen_dir);

    if ~isfolder(codegen_dir)
        error('Code generation directory does not exist:\n%s', ...
              codegen_dir);
    end

    load_system(model_name);


    %% ============================================================
    % 1. Find generated make_sfun file
    % ============================================================

    candidates = [ ...
        dir(fullfile(codegen_dir, 'make_sfun.m')); ...
        dir(fullfile(codegen_dir, 'make_sfun_*.m')) ...
    ];

    % Do not use the SIM S-function build script
    keep = ~contains({candidates.name}, 'make_sfun_sim');

    candidates = candidates(keep);

    % Remove duplicate filenames
    if ~isempty(candidates)
        [~, idx] = unique({candidates.name}, 'stable');
        candidates = candidates(idx);
    end

    if isempty(candidates)

        error(['Could not find an OCP make_sfun script in:\n%s\n' ...
               'Generate the solver with simulink_opts enabled first.'], ...
               codegen_dir);

    end

    % MATLAB interface normally gives make_sfun.m.
    % Prefer it if present.
    names = {candidates.name};

    idx = find(strcmp(names, 'make_sfun.m'), 1);

    if isempty(idx)

        if numel(candidates) ~= 1
            fprintf('\nFound several make_sfun files:\n');

            for i = 1:numel(candidates)
                fprintf('  %s\n', candidates(i).name);
            end

            error('Cannot determine which OCP make_sfun file to use.');
        end

        idx = 1;
    end

    make_sfun_file = fullfile( ...
        candidates(idx).folder, ...
        candidates(idx).name);

    fprintf('\nUsing:\n  %s\n', make_sfun_file);

    txt = fileread(make_sfun_file);


    %% ============================================================
    % 2. Read acados include root from make_sfun
    % ============================================================

    token = regexp( ...
        txt, ...
        'INC_PATH\s*=\s*''([^'']+)''', ...
        'tokens', ...
        'once');

    if isempty(token)
        error('Could not extract INC_PATH from %s.', make_sfun_file);
    end

    inc_path = token{1};


    %% ============================================================
    % 3. Include directories
    % ============================================================

    include_dirs = { ...
        inc_path, ...
        fullfile(inc_path, 'acados'), ...
        fullfile(inc_path, 'blasfeo', 'include'), ...
        fullfile(inc_path, 'hpipm', 'include'), ...
        codegen_dir ...
    };

    include_dirs = include_dirs( ...
        cellfun(@isfolder, include_dirs));

    include_dirs = unique(include_dirs, 'stable');


    %% ============================================================
    % 4. Extract exact source files used by make_sfun
    % ============================================================

    source_block = regexp( ...
        txt, ...
        '(?s)SOURCES\s*=\s*\{(.*?)\};', ...
        'tokens', ...
        'once');

    if isempty(source_block)
        error('Could not extract SOURCES from %s.', make_sfun_file);
    end

    source_tokens = regexp( ...
        source_block{1}, ...
        '''([^'']+\.c)''', ...
        'tokens');

    source_files = {};

    for i = 1:numel(source_tokens)

        relative_file = source_tokens{i}{1};

        [~, name, ext] = fileparts(relative_file);

        filename = [name ext];


        % IMPORTANT:
        %
        % Simulink/QUARC already compiles the S-function wrapper
        % automatically because it is the source of the S-function block.
        %
        % Adding it again to CustomSource would compile it twice.

        if startsWith(filename, 'acados_solver_sfunction_')
            continue;
        end

        if startsWith(filename, 'acados_sim_solver_sfunction_')
            continue;
        end


        absolute_file = fullfile(codegen_dir, relative_file);

        if isfile(absolute_file)

            source_files{end+1} = absolute_file; %#ok<AGROW>

        else

            warning('Generated source not found:\n%s', ...
                    absolute_file);

        end

    end

    source_files = unique(source_files, 'stable');


    %% ============================================================
    % 5. Extract library directory
    % ============================================================

    token = regexp( ...
        txt, ...
        'LIB_PATH\s*=.*?fullfile\(''([^'']+)''\)', ...
        'tokens', ...
        'once');

    if isempty(token)
        error('Could not extract LIB_PATH from %s.', make_sfun_file);
    end

    lib_path = token{1};

    if ~isfolder(lib_path)
        error('acados library directory does not exist:\n%s', ...
              lib_path);
    end


    %% ============================================================
    % 6. Find all libraries required by this acados installation
    % ============================================================

    % Core acados libraries
    library_names = { ...
        'acados', ...
        'hpipm', ...
        'blasfeo' ...
    };


    %% ------------------------------------------------------------
    % Read optional dependencies from link_libs.json
    %
    % This file is generated when acados itself is compiled.
    %
    % Example contents:
    %
    %   "qpoases": "-lqpOASES_e"
    %   "qpdunes": "-lqpdunes"
    %   "osqp":    "-losqp"
    %
    % ------------------------------------------------------------

    link_json = fullfile(lib_path, 'link_libs.json');

    if isfile(link_json)

        fprintf('\nReading:\n  %s\n', link_json);

        link_info = jsondecode(fileread(link_json));

        field_names = fieldnames(link_info);

        for i = 1:numel(field_names)

            value = link_info.(field_names{i});

            if isempty(value)
                continue;
            end

            if isstring(value)
                value = char(value);
            end

            if ~ischar(value)
                continue;
            end


            % Extract all "-lxxx" occurrences
            %
            % Example:
            %
            %   -lqpOASES_e  -> qpOASES_e
            %   -lqpdunes    -> qpdunes
            %   -losqp       -> osqp

            tokens = regexp( ...
                value, ...
                '-l([A-Za-z0-9_\-]+)', ...
                'tokens');

            for j = 1:numel(tokens)

                library_names{end+1} = ...
                    tokens{j}{1}; %#ok<AGROW>

            end

        end

    else

        warning(['link_libs.json was not found:\n%s\n' ...
                 'Only the core acados libraries will be used.'], ...
                 link_json);

    end


    %% ------------------------------------------------------------
    % Remove duplicate library names
    % ------------------------------------------------------------

    library_names = unique( ...
        library_names, ...
        'stable');


    %% ------------------------------------------------------------
    % Convert names into actual Windows .lib files
    % ------------------------------------------------------------

    library_files = {};

    fprintf('\nDetected libraries:\n');

    for i = 1:numel(library_names)

        candidate = fullfile( ...
            lib_path, ...
            [library_names{i}, '.lib']);

        if isfile(candidate)

            fprintf('  [OK] %s\n', candidate);

            library_files{end+1} = candidate; %#ok<AGROW>

        else

            fprintf('  [MISSING] %s\n', candidate);

        end

    end


    %% ------------------------------------------------------------
    % Remove duplicates
    % ------------------------------------------------------------

    library_files = unique( ...
        library_files, ...
        'stable');


    %% ============================================================
    % 7. Convert to Simulink strings
    % ============================================================

    custom_include = quote_and_join(include_dirs);
    custom_source  = quote_and_join(source_files);
    custom_library = quote_and_join(library_files);


    %% ============================================================
    % 8. Apply to model
    % ============================================================

    set_param(model_name, ...
        'CustomInclude', custom_include);

    set_param(model_name, ...
        'CustomSource', custom_source);

    set_param(model_name, ...
        'CustomLibrary', custom_library);
    
    %% ============================================================
    % Deploy runtime DLLs needed by QUARC
    % ============================================================

    deploy_runtime_dlls(lib_path, library_names);

    %% ============================================================
    % 9. Summary
    % ============================================================

    fprintf('\n========================================\n');
    fprintf('acados / QUARC configuration\n');
    fprintf('========================================\n');

    fprintf('\nInclude directories:\n');
    for i = 1:numel(include_dirs)
        fprintf('  [OK] %s\n', include_dirs{i});
    end

    fprintf('\nAdditional source files:\n');
    for i = 1:numel(source_files)
        fprintf('  [OK] %s\n', source_files{i});
    end

    fprintf('\nLibraries:\n');
    for i = 1:numel(library_files)
        fprintf('  [OK] %s\n', library_files{i});
    end

    fprintf('\nConfiguration complete for:\n  %s\n\n', ...
            model_name);

end


function result = quote_and_join(paths)

    if isempty(paths)
        result = '';
        return;
    end

    quoted = cellfun( ...
        @(p) ['"' p '"'], ...
        paths, ...
        'UniformOutput', false);

    result = strjoin(quoted, ' ');

end

function deploy_runtime_dlls(lib_path, library_names)
%DEPLOY_RUNTIME_DLLS
% Copy dynamic acados dependencies to the local QUARC Win64 spool.
%
% Example:
%   osqp.lib is an import library
%   -> osqp.dll is required at runtime
%
% Static libraries simply have no corresponding DLL and are ignored.

    %% ------------------------------------------------------------
    % Infer acados installation root
    %
    % lib_path:
    %   <acados_root>\lib
    %
    % therefore:
    %   acados_root = parent(lib_path)
    % ------------------------------------------------------------

    acados_root = fileparts(lib_path);

    bin_path = fullfile( ...
        acados_root, ...
        'bin');


    if ~isfolder(bin_path)

        fprintf('\nNo acados bin directory found:\n');
        fprintf('  %s\n', bin_path);

        return;
    end


    %% ------------------------------------------------------------
    % QUARC local Win64 spool
    % ------------------------------------------------------------

    program_data = getenv('ProgramData');

    if isempty(program_data)

        warning('Could not determine Windows ProgramData directory.');
        return;

    end

    quarc_spool = fullfile( ...
        program_data, ...
        'QUARC', ...
        'spool', ...
        'win64');


    if ~isfolder(quarc_spool)

        fprintf('\nCreating QUARC spool directory:\n');
        fprintf('  %s\n', quarc_spool);

        mkdir(quarc_spool);
    end


    %% ------------------------------------------------------------
    % Check corresponding DLL for every linked library
    % ------------------------------------------------------------

    fprintf('\nRuntime DLL deployment:\n');

    dll_count = 0;

    for i = 1:numel(library_names)

        dll_name = [library_names{i}, '.dll'];

        source = fullfile( ...
            bin_path, ...
            dll_name);

        if ~isfile(source)
            % Probably a genuinely static library.
            continue;
        end


        destination = fullfile( ...
            quarc_spool, ...
            dll_name);


        copyfile( ...
            source, ...
            destination, ...
            'f');


        fprintf('  [COPIED] %s\n', dll_name);

        dll_count = dll_count + 1;

    end


    if dll_count == 0

        fprintf('  No runtime DLLs required/found.\n');

    else

        fprintf('\nRuntime DLLs deployed to:\n');
        fprintf('  %s\n', quarc_spool);

    end

end