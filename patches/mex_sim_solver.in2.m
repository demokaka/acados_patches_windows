%
% Copyright (c) The acados authors.
%
% This file is part of acados.
%
% The 2-Clause BSD License
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
%
% 1. Redistributions of source code must retain the above copyright notice,
% this list of conditions and the following disclaimer.
%
% 2. Redistributions in binary form must reproduce the above copyright notice,
% this list of conditions and the following disclaimer in the documentation
% and/or other materials provided with the distribution.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.;

%

classdef {{ name }}_mex_sim_solver < handle

    properties
        C_sim
        name
        code_gen_dir
    end % properties



    methods

        % constructor
        function obj = {{ name }}_mex_sim_solver(varargin)

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % PATCH: avoid recompiling the problem-specific SIM MEX wrappers
            % on every AcadosSimSolver construction.
            %
            % Upstream behavior historically called:
            %
            %     make_mex_sim_{{ name }}();
            %
            % unconditionally in this constructor. On Windows/MSVC this means
            % that the following wrappers are rebuilt every time:
            %
            %     acados_sim_create_{{ name }}.<mexext>
            %     acados_sim_free_{{ name }}.<mexext>
            %     acados_sim_set_{{ name }}.<mexext>
            %
            % Besides being unnecessary, repeated recompilation can fail when
            % MATLAB still has one of the MEX binaries loaded.
            %
            % This patch reuses the existing wrappers when all three binaries
            % are already present. They are compiled only when at least one is
            % missing.
            %
            % Optional forward-compatible behavior:
            % If solver_creation_opts is passed as the first constructor
            % argument and contains compile_mex_wrapper=true, recompilation is
            % forced explicitly. The current AcadosSimSolver can still call
            % this constructor with no arguments, so this patch remains
            % backward compatible.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            mex_create = fullfile(pwd, ['acados_sim_create_{{ name }}.' mexext]);
            mex_free   = fullfile(pwd, ['acados_sim_free_{{ name }}.' mexext]);
            mex_set    = fullfile(pwd, ['acados_sim_set_{{ name }}.' mexext]);

            mex_wrapper_missing = ...
                ~isfile(mex_create) || ...
                ~isfile(mex_free)   || ...
                ~isfile(mex_set);

            force_compile_mex_wrapper = false;

            if nargin >= 1
                solver_creation_opts = varargin{1};

                if isstruct(solver_creation_opts) && ...
                        isfield(solver_creation_opts, 'compile_mex_wrapper')
                    force_compile_mex_wrapper = ...
                        solver_creation_opts.compile_mex_wrapper;
                end
            end

            if force_compile_mex_wrapper
                disp('SIM MEX wrapper recompilation requested. Compiling...');
                make_mex_sim_{{ name }}();

            elseif mex_wrapper_missing
                disp('SIM MEX wrapper missing. Compiling...');
                make_mex_sim_{{ name }}();

            else
                disp('SIM MEX wrapper found. Reusing existing binaries.');
            end

            % END PATCH
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            obj.C_sim = acados_sim_create_{{ name }}();
            % to have path to destructor when changing directory
            addpath('.')
            obj.name = '{{ name }}';
        end

        % set -- borrowed from MEX interface
        function set(obj, field, value)
            if ~isa(field, 'char')
                error('field must be a char vector, use '' ''');
            end
            acados_sim_set_{{ name }}(obj.C_sim, field, value);
        end

        % get -- borrowed from MEX interface
        function value = get(obj, field)
            if ~isa(field, 'char')
                error('field must be a char vector, use '' ''');
            end
            value = sim_get(obj.C_sim, field);
        end

        % solve
        function status = solve(obj)
            status = sim_solve(obj.C_sim);
        end

        % destructor
        function delete(obj)
            disp("delete template...");
            if ~isempty(obj.C_sim)
                acados_sim_free_{{ name }}(obj.C_sim);
            end
            disp("done.");
        end

    end % methods

end % class
