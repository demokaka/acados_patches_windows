%% apply_acados_windows_patches.m
% Activate the local Windows/MSVC acados patch set for BOTH MATLAB and Python.
%
% Run this script from:
%
%   <acados>\interfaces\acados_matlab_octave
%
% It patches:
%
% MATLAB:
%   AcadosOcp.m
%   AcadosSim.m
%
% Python:
%   <acados>\interfaces\acados_template\acados_template\acados_ocp.py
%   <acados>\interfaces\acados_template\acados_template\acados_sim.py
%   <acados>\interfaces\acados_template\acados_template\builders.py
%
% The upstream lines are NOT deleted. They are commented out and the local
% replacements are inserted immediately below them.
%
% The script is idempotent and creates one-time backups with suffix:
%
%   .pre_windows_patch.bak
%
% Required local templates:
%
%   c_templates_tera\CMakeLists.in2.txt
%
%   c_templates_tera\matlab_templates\
%       make_mex.in2.m
%       make_mex_sim.in2.m
%       make_sfun.in2.m
%       make_sfun_sim.in2.m
%       mex_sim_solver.in2.m

clearvars;
clc;

fprintf('acados Windows/MSVC patcher\n');
fprintf('===========================\n\n');

%% Locate acados root
matlab_octave_dir = pwd;

[interfaces_dir, current_name] = fileparts(matlab_octave_dir);
[acados_root, interfaces_name] = fileparts(interfaces_dir);

if ~strcmp(current_name, 'acados_matlab_octave') || ...
        ~strcmp(interfaces_name, 'interfaces')
    error(['Run this script from:\n', ...
           '  <acados>\\interfaces\\acados_matlab_octave\n\n', ...
           'Current directory:\n  %s'], pwd);
end

fprintf('acados root:\n  %s\n\n', acados_root);

%% Source paths
ocp_matlab = fullfile(matlab_octave_dir, 'AcadosOcp.m');
sim_matlab = fullfile(matlab_octave_dir, 'AcadosSim.m');

python_dir = fullfile( ...
    acados_root, ...
    'interfaces', ...
    'acados_template', ...
    'acados_template');

ocp_python = fullfile(python_dir, 'acados_ocp.py');
sim_python = fullfile(python_dir, 'acados_sim.py');
builders_python = fullfile(python_dir, 'builders.py');

template_root = fullfile( ...
    python_dir, ...
    'c_templates_tera');

matlab_template_dir = fullfile(template_root, 'matlab_templates');

%% Verify local templates before touching source files
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
    fprintf(2, 'The local patch templates are not all installed yet:\n');
    for k = 1:numel(missing)
        fprintf(2, '  MISSING: %s\n', missing{k});
    end
    error('Install the *.in2.* files first, then run this script again.');
end

fprintf('All local *.in2.* templates were found.\n\n');

%% MATLAB AcadosOcp.m
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

patch_source_file(ocp_matlab, ocp_rules, '%');

%% MATLAB AcadosSim.m
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

patch_source_file(sim_matlab, sim_rules, '%');

%% Python acados_ocp.py
python_ocp_rules = { ...
    'Python OCP CMake template', ...
    "            template_list.append(('CMakeLists.in.txt', 'CMakeLists.txt'))", ...
    "            template_list.append(('CMakeLists.in2.txt', 'CMakeLists.txt'))" ...
};

patch_source_file(ocp_python, python_ocp_rules, '#');

%% Python acados_sim.py
python_sim_rules = { ...
    'Python SIM CMake template', ...
    "            template_list.append(('CMakeLists.in.txt', 'CMakeLists.txt'))", ...
    "            template_list.append(('CMakeLists.in2.txt', 'CMakeLists.txt'))" ...
};

patch_source_file(sim_python, python_sim_rules, '#');

%% Python builders.py
python_builder_rules = { ...
    'Visual Studio generator', ...
    "            self.generator = 'Visual Studio 15 2017 Win64'", ...
    sprintf("            self.generator = 'Visual Studio 17 2022'\n            self.host = 'x64'"); ...

    'Visual Studio install configuration', ...
    "        return f'cmake --install ""{self._build_dir}""'", ...
    sprintf([ ...
        "        if os.name == 'nt':\n", ...
        "            return f'cmake --install ""{self._build_dir}"" --config Release'\n", ...
        "        return f'cmake --install ""{self._build_dir}""'" ...
    ]) ...
};

patch_source_file(builders_python, python_builder_rules, '#');

fprintf('\nDone.\n\n');
fprintf('Activated patch set:\n');
fprintf('  MATLAB OCP/SIM -> *.in2.m and CMakeLists.in2.txt\n');
fprintf('  Python OCP/SIM -> CMakeLists.in2.txt for CMake builds\n');
fprintf('  Python builder -> Visual Studio 17 2022, x64\n');
fprintf('  Python install -> explicit --config Release on Windows\n\n');
fprintf('Original upstream lines were retained as comments.\n');
fprintf('Backups use the suffix: .pre_windows_patch.bak\n');


%% Local functions

function patch_source_file(filename, rules, comment_char)
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
            error(['Could not find the expected upstream code for:\n', ...
                   '  %s\n\n', ...
                   'acados may have changed this source file. ', ...
                   'No automatic guess was made.\nExpected:\n%s'], ...
                   label, original);
        end

        original_lines = splitlines(string(original));
        first_line = char(original_lines(1));
        indentation = regexp(first_line, '^\s*', 'match', 'once');

        commented = strings(numel(original_lines), 1);
        for j = 1:numel(original_lines)
            line = char(original_lines(j));
            line_indent = regexp(line, '^\s*', 'match', 'once');
            commented(j) = string([ ...
                line_indent, comment_char, ' ', strtrim(line)]);
        end

        commented_original = strjoin(commented, string(eol));

        patch_text = [ ...
            indentation, comment_char, ...
            ' WINDOWS/MSVC PATCH - original upstream code retained:', eol, ...
            char(commented_original), eol, ...
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
