%% apply_acados_windows_patches.m
% Activate the custom Windows/MSVC acados templates.
%
% Run this script from:
%
%   <acados>\interfaces\acados_matlab_octave
%
% It modifies only:
%
%   AcadosOcp.m
%   AcadosSim.m
%
% The original upstream template-selection lines are NOT deleted. Each one
% is commented out and the corresponding *.in2.* replacement is inserted
% immediately below it.
%
% The script is idempotent: running it again will not duplicate patches.
% A one-time backup of each MATLAB class is created before modification.
%
% Required custom templates:
%
%   <acados>\interfaces\acados_template\acados_template\c_templates_tera\
%       CMakeLists.in2.txt
%
%   <acados>\interfaces\acados_template\acados_template\c_templates_tera\
%       matlab_templates\
%           make_mex.in2.m
%           make_mex_sim.in2.m
%           make_sfun.in2.m
%           make_sfun_sim.in2.m
%           mex_sim_solver.in2.m

clearvars;
clc;

fprintf('acados Windows/MSVC template patcher\n');
fprintf('====================================\n\n');

%% Locate acados
matlab_octave_dir = pwd;

[interfaces_dir, current_name] = fileparts(matlab_octave_dir);
[acados_root, interfaces_name] = fileparts(interfaces_dir);

if ~strcmp(current_name, 'acados_matlab_octave') || ~strcmp(interfaces_name, 'interfaces')
    error(['Run this script from:\n', ...
           '  <acados>\\interfaces\\acados_matlab_octave\n\n', ...
           'Current directory:\n  %s'], pwd);
end

ocp_file = fullfile(matlab_octave_dir, 'AcadosOcp.m');
sim_file = fullfile(matlab_octave_dir, 'AcadosSim.m');

template_root = fullfile( ...
    acados_root, ...
    'interfaces', ...
    'acados_template', ...
    'acados_template', ...
    'c_templates_tera');

matlab_template_dir = fullfile(template_root, 'matlab_templates');

%% Verify that all custom templates exist before touching source files
required_templates = { ...
    fullfile(template_root, 'CMakeLists.in2.txt'), ...
    fullfile(matlab_template_dir, 'make_mex.in2.m'), ...
    fullfile(matlab_template_dir, 'make_mex_sim.in2.m'), ...
    fullfile(matlab_template_dir, 'make_sfun.in2.m'), ...
    fullfile(matlab_template_dir, 'make_sfun_sim.in2.m'), ...
    fullfile(matlab_template_dir, 'mex_sim_solver.in2.m') ...
};

missing = {};
for k = 1:numel(required_templates)
    if ~isfile(required_templates{k})
        missing{end+1} = required_templates{k}; %#ok<SAGROW>
    end
end

if ~isempty(missing)
    fprintf(2, 'The patch templates are not all installed yet:\n');
    for k = 1:numel(missing)
        fprintf(2, '  MISSING: %s\n', missing{k});
    end
    error('Install the *.in2.* template files first, then run this script again.');
end

fprintf('acados root:\n  %s\n\n', acados_root);
fprintf('All custom templates were found.\n\n');

%% Patch AcadosOcp.m
ocp_rules = { ...
    'CMake template', ...
    "            template_list{end+1} = {'CMakeLists.in.txt', ['CMakeLists.txt']};", ...
    "            template_list{end+1} = {'CMakeLists.in2.txt', ['CMakeLists.txt']};"; ...

    'OCP MATLAB MEX build template', ...
    "            template_list{end+1} = {fullfile(matlab_template_path, 'make_mex.in.m'), ['make_mex_', self.name, '.m']};", ...
    "            template_list{end+1} = {fullfile(matlab_template_path, 'make_mex.in2.m'), ['make_mex_', self.name, '.m']};"; ...

    'OCP Simulink S-function build template', ...
    "                template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun.in.m'), ['make_sfun.m']};", ...
    "                template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun.in2.m'), ['make_sfun.m']};"; ...

    'integrator Simulink S-function build template used by OCP', ...
    "                    template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun_sim.in.m'), ['make_sfun_sim.m']};", ...
    "                    template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun_sim.in2.m'), ['make_sfun_sim.m']};" ...
};

patch_matlab_file(ocp_file, ocp_rules);

%% Patch AcadosSim.m
sim_rules = { ...
    'SIM MATLAB wrapper template', ...
    "                {fullfile(matlab_template_path, 'mex_sim_solver.in.m'), [self.name, '_mex_sim_solver.m']}, ...", ...
    "                {fullfile(matlab_template_path, 'mex_sim_solver.in2.m'), [self.name, '_mex_sim_solver.m']}, ..."; ...

    'SIM MATLAB MEX build template', ...
    "                {fullfile(matlab_template_path, 'make_mex_sim.in.m'), ['make_mex_sim_', self.name, '.m']}, ...", ...
    "                {fullfile(matlab_template_path, 'make_mex_sim.in2.m'), ['make_mex_sim_', self.name, '.m']}, ..."; ...

    'SIM Simulink S-function build template', ...
    "                {fullfile(matlab_template_path, 'make_sfun_sim.in.m'), ['make_sfun_sim_', self.name, '.m']}, ...", ...
    "                {fullfile(matlab_template_path, 'make_sfun_sim.in2.m'), ['make_sfun_sim_', self.name, '.m']}, ..."; ...

    'CMake template', ...
    "                {'CMakeLists.in.txt', 'CMakeLists.txt'}};", ...
    "                {'CMakeLists.in2.txt', 'CMakeLists.txt'}};" ...
};

patch_matlab_file(sim_file, sim_rules);

fprintf('\nDone.\n');
fprintf('The upstream lines were retained as comments and the *.in2.* lines are active.\n');
fprintf('Backups use the suffix: .pre_windows_patch.bak\n');


%% Local functions

function patch_matlab_file(filename, rules)
    if ~isfile(filename)
        error('File not found: %s', filename);
    end

    fprintf('Patching:\n  %s\n', filename);

    backup_file = [filename, '.pre_windows_patch.bak'];

    if ~isfile(backup_file)
        copyfile(filename, backup_file);
        fprintf('  backup created: %s\n', backup_file);
    else
        fprintf('  backup already exists; leaving it untouched.\n');
    end

    txt = fileread(filename);

    if contains(txt, sprintf('\r\n'))
        eol = sprintf('\r\n');
    else
        eol = sprintf('\n');
    end

    changed = false;

    for k = 1:size(rules, 1)
        label = char(rules{k, 1});
        original = char(rules{k, 2});
        replacement = char(rules{k, 3});

        if contains(txt, replacement)
            fprintf('  [already patched] %s\n', label);
            continue;
        end

        if ~contains(txt, original)
            error(['Could not find the expected upstream line for:\n', ...
                   '  %s\n\n', ...
                   'acados may have changed this source file. No automatic ', ...
                   'guess was made.\nExpected:\n%s'], label, original);
        end

        indentation = regexp(original, '^\s*', 'match', 'once');

        patch_text = [ ...
            indentation, '% WINDOWS/MSVC PATCH - original upstream line retained:', eol, ...
            indentation, '% ', strtrim(original), eol, ...
            replacement ...
        ];

        txt = strrep(txt, original, patch_text);
        changed = true;

        fprintf('  [patched] %s\n', label);
    end

    if changed
        fid = fopen(filename, 'w');
        if fid == -1
            error('Could not open file for writing: %s', filename);
        end

        cleanup = onCleanup(@() fclose(fid));
        fwrite(fid, txt, 'char');
        clear cleanup;

        fprintf('  file updated.\n\n');
    else
        fprintf('  no changes needed.\n\n');
    end
end
