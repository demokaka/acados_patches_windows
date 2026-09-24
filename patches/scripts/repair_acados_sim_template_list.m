%% repair_acados_sim_template_list.m
% Repair AcadosSim.m after the Windows/MSVC template patch.
%
% Run from:
%   <acados>\interfaces\acados_matlab_octave
%
% Why this exists:
% AcadosSim.m builds template_list as one continued MATLAB cell expression
% using "...". Inserting commented-out original lines *inside* that
% continued expression can make MATLAB parse the cell array incorrectly and
% trigger:
%
%   Error using vertcat
%   Dimensions of arrays being concatenated are not consistent.
%
% This repair replaces only that template_list block with a clean version.
% The upstream names are documented in comments ABOVE the cell expression,
% not between continued lines.

clearvars;
clc;

target = fullfile(pwd, 'AcadosSim.m');

if ~isfile(target)
    error(['AcadosSim.m not found.\n', ...
           'Run this script from <acados>\\interfaces\\acados_matlab_octave']);
end

backup = [target, '.pre_template_list_repair.bak'];
if ~isfile(backup)
    copyfile(target, backup);
    fprintf('Backup created:\n  %s\n\n', backup);
end

txt = fileread(target);

% Normalize line endings while editing.
uses_crlf = contains(txt, sprintf('\r\n'));
txtn = strrep(txt, sprintf('\r\n'), sprintf('\n'));

start_marker = '            % cell array with entries (template_file, output file)';
end_marker   = '            num_entries = length(template_list);';

i0 = strfind(txtn, start_marker);
i1 = strfind(txtn, end_marker);

if isempty(i0) || isempty(i1)
    error('Could not locate the AcadosSim template_list block.');
end

i0 = i0(1);
i1 = i1(find(i1 > i0, 1, 'first'));

if isempty(i1)
    error('Could not locate the end of the AcadosSim template_list block.');
end

clean_block = sprintf([ ...
'            %% cell array with entries (template_file, output file)\n' ...
'            %%\n' ...
'            %% WINDOWS/MSVC PATCH:\n' ...
'            %%   upstream mex_sim_solver.in.m  -> mex_sim_solver.in2.m\n' ...
'            %%   upstream make_mex_sim.in.m    -> make_mex_sim.in2.m\n' ...
'            %%   upstream make_sfun_sim.in.m   -> make_sfun_sim.in2.m\n' ...
'            %%   upstream CMakeLists.in.txt    -> CMakeLists.in2.txt\n' ...
'            %%\n' ...
'            %% Keep comments OUTSIDE the continued {...} expression below.\n' ...
'            template_list = { ...\n' ...
'                {''main_sim.in.c'', [''main_sim_'', self.name, ''.c'']}, ...\n' ...
'                {fullfile(matlab_template_path, ''mex_sim_solver.in2.m''), [self.name, ''_mex_sim_solver.m'']}, ...\n' ...
'                {fullfile(matlab_template_path, ''make_mex_sim.in2.m''), [''make_mex_sim_'', self.name, ''.m'']}, ...\n' ...
'                {fullfile(matlab_template_path, ''acados_sim_create.in.c''), [''acados_sim_create_'', self.name, ''.c'']}, ...\n' ...
'                {fullfile(matlab_template_path, ''acados_sim_free.in.c''), [''acados_sim_free_'', self.name, ''.c'']}, ...\n' ...
'                {fullfile(matlab_template_path, ''acados_sim_set.in.c''), [''acados_sim_set_'', self.name, ''.c'']}, ...\n' ...
'                {''acados_sim_solver.in.c'', [''acados_sim_solver_'', self.name, ''.c'']}, ...\n' ...
'                {''acados_sim_solver.in.h'', [''acados_sim_solver_'', self.name, ''.h'']}, ...\n' ...
'                {fullfile(matlab_template_path, ''acados_sim_solver_sfun.in.c''), [''acados_sim_solver_sfunction_'', self.name, ''.c'']}, ...\n' ...
'                {fullfile(matlab_template_path, ''make_sfun_sim.in2.m''), [''make_sfun_sim_'', self.name, ''.m'']}, ...\n' ...
'                {''Makefile.in'', ''Makefile''}, ...\n' ...
'                {''CMakeLists.in2.txt'', ''CMakeLists.txt''}};\n\n' ...
]);

txtn = [txtn(1:i0-1), clean_block, txtn(i1:end)];

if uses_crlf
    txtn = strrep(txtn, sprintf('\n'), sprintf('\r\n'));
end

fid = fopen(target, 'w');
if fid == -1
    error('Could not open AcadosSim.m for writing.');
end

cleanup = onCleanup(@() fclose(fid));
fwrite(fid, txtn, 'char');
clear cleanup;

fprintf('AcadosSim.m template_list repaired successfully.\n');
