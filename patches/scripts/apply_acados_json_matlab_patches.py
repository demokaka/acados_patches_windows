#!/usr/bin/env python3
"""
apply_acados_json_matlab_patches.py

Apply the small MATLAB JSON / struct compatibility fixes used in this local
acados workflow.

Run from the acados repository root:

    python apply_acados_json_matlab_patches.py

or from anywhere:

    python apply_acados_json_matlab_patches.py --acados-root C:\\path\\to\\acados

This script patches only:

    interfaces/acados_matlab_octave/compare_struct_to_json.m
    interfaces/acados_matlab_octave/AcadosSimOptions.m
    interfaces/acados_matlab_octave/AcadosSimSolver.m

The script is idempotent, preserves upstream code as comments where a block
is replaced, and creates one-time backups with suffix:

    .pre_json_patch.bak
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


COMPARE_OLD = """    elseif ismatrix(ocp_data) && ismatrix(json_data)
        diff_mask = abs(ocp_data - json_data) < tol;
        if ~isequal(size(ocp_data), size(json_data))
            mismatched{end+1} = path;
        elseif ~all(diff_mask(:))
            % check relative tolerance
            rel_diff = abs(ocp_data - json_data) ./ max(abs(json_data), abs(ocp_data));
            if ~all(rel_diff(:) < tol)
                mismatched{end+1} = path;
            end
        end
"""

COMPARE_NEW = """    elseif (isnumeric(ocp_data) || islogical(ocp_data)) && ...
           (isnumeric(json_data) || islogical(json_data))
        % JSON/STRUCT PATCH:
        % Only perform subtraction for numeric/logical arrays. MATLAB's
        % ismatrix() is a dimensionality test and does not guarantee that
        % the operands support subtraction.

        if ~isequal(size(ocp_data), size(json_data))
            mismatched{end+1} = path;
            return;
        end

        a = double(ocp_data);
        b = double(json_data);

        abs_diff = abs(a - b);

        if ~all(abs_diff(:) < tol)
            % Relative-tolerance fallback. Avoid 0/0 when both values are 0.
            scale = max(abs(a), abs(b));
            rel_diff = zeros(size(abs_diff));

            idx = scale > 0;
            rel_diff(idx) = abs_diff(idx) ./ scale(idx);

            if ~all(rel_diff(:) < tol)
                mismatched{end+1} = path;
            end
        end
"""

SIM_SOLVER_OLD = """                sim_struct_restore = loadjson(fileread(json_file), 'SimplifyCell', 0);"""

SIM_SOLVER_NEW = """                % JSON/STRUCT PATCH:
                % Use the SIM object's configured JSON file. The upstream
                % code refers to an undefined local variable "json_file".
                sim_struct_restore = loadjson( ...
                    fileread(obj.sim.code_gen_options.json_file), ...
                    'SimplifyCell', 0);"""

SIM_OPTIONS_MARKER = "% JSON/STRUCT PATCH: AcadosSimOptions.from_struct"

SIM_OPTIONS_STATIC_METHODS = r"""
    methods (Static)
        function obj = from_struct(s)
            % JSON/STRUCT PATCH: AcadosSimOptions.from_struct
            %
            % Reconstruct AcadosSimOptions from the representation written
            % by to_struct()/JSON. Some simulation-method options are stored
            % in JSON with the "sim_method_" prefix, while the MATLAB class
            % uses the shorter property names.

            if ~isstruct(s)
                error('AcadosSimOptions.from_struct input must be a struct.');
            end

            obj = AcadosSimOptions();

            json_to_property = struct( ...
                'sim_method_num_stages',  'num_stages', ...
                'sim_method_num_steps',   'num_steps', ...
                'sim_method_newton_iter', 'newton_iter', ...
                'sim_method_newton_tol',  'newton_tol', ...
                'sim_method_jac_reuse',   'jac_reuse' ...
            );

            fields = fieldnames(s);

            for i = 1:numel(fields)
                source_name = fields{i};

                if isfield(json_to_property, source_name)
                    target_name = json_to_property.(source_name);
                else
                    target_name = source_name;
                end

                if isprop(obj, target_name)
                    obj.(target_name) = s.(source_name);
                else
                    warning( ...
                        'AcadosSimOptions.from_struct: ignoring unknown field "%s".', ...
                        source_name);
                end
            end
        end
    end
"""


def detect_newline(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def make_backup(path: Path) -> None:
    backup = path.with_name(path.name + ".pre_json_patch.bak")
    if not backup.exists():
        shutil.copy2(path, backup)
        print(f"  backup created: {backup}")
    else:
        print("  backup already exists; leaving it untouched.")


def comment_matlab_block(block: str, eol: str) -> str:
    lines = block.rstrip("\r\n").splitlines()
    result = []
    for line in lines:
        indent = line[: len(line) - len(line.lstrip())]
        result.append(f"{indent}% {line.lstrip()}")
    return eol.join(result)


def patch_compare(path: Path) -> None:
    print(f"Patching:\n  {path}")
    make_backup(path)

    with path.open("r", encoding="utf-8", newline="") as f:
        text = f.read()

    if "JSON/STRUCT PATCH:" in text and COMPARE_NEW.splitlines()[0] in text:
        print("  [already patched] numeric/logical comparison\n")
        return

    if COMPARE_OLD not in text:
        raise RuntimeError(
            f"Could not find expected comparison block in {path}. "
            "acados may have changed upstream."
        )

    eol = detect_newline(text)
    commented = comment_matlab_block(COMPARE_OLD, eol)
    replacement = (
        "    % JSON/STRUCT PATCH - original upstream comparison retained below:\n"
        f"{commented}\n"
        f"{COMPARE_NEW.rstrip()}"
    ).replace("\n", eol)

    text = text.replace(COMPARE_OLD.rstrip("\r\n"), replacement, 1)

    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(text)

    print("  [patched] numeric/logical comparison\n")


def patch_sim_solver(path: Path) -> None:
    print(f"Patching:\n  {path}")
    make_backup(path)

    with path.open("r", encoding="utf-8", newline="") as f:
        text = f.read()

    if "fileread(obj.sim.code_gen_options.json_file)" in text:
        print("  [already patched] SIM JSON filename\n")
        return

    if SIM_SOLVER_OLD not in text:
        raise RuntimeError(
            f"Could not find expected loadjson(...) line in {path}. "
            "acados may have changed upstream."
        )

    eol = detect_newline(text)
    replacement = (
        "                % JSON/STRUCT PATCH - original upstream line retained:\n"
        "                % sim_struct_restore = loadjson(fileread(json_file), 'SimplifyCell', 0);\n"
        f"{SIM_SOLVER_NEW}"
    ).replace("\n", eol)

    text = text.replace(SIM_SOLVER_OLD, replacement, 1)

    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(text)

    print("  [patched] SIM JSON filename\n")


def patch_sim_options(path: Path) -> None:
    print(f"Patching:\n  {path}")
    make_backup(path)

    with path.open("r", encoding="utf-8", newline="") as f:
        text = f.read()

    if SIM_OPTIONS_MARKER in text:
        print("  [already patched] AcadosSimOptions.from_struct\n")
        return

    eol = detect_newline(text)
    normalized = text.replace("\r\n", "\n")

    closing = "    end\nend\n"
    idx = normalized.rfind(closing)

    if idx < 0:
        raise RuntimeError(
            f"Could not locate final AcadosSimOptions class ending in {path}. "
            "acados may have changed upstream."
        )

    insert_at = idx + len("    end\n")
    patched = (
        normalized[:insert_at]
        + "\n"
        + SIM_OPTIONS_STATIC_METHODS.strip("\n")
        + "\n"
        + normalized[insert_at:]
    )

    if eol == "\r\n":
        patched = patched.replace("\n", "\r\n")

    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(patched)

    print("  [patched] AcadosSimOptions.from_struct\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Apply local acados MATLAB JSON/struct compatibility fixes."
    )
    parser.add_argument(
        "--acados-root",
        type=Path,
        default=Path.cwd(),
        help="acados repository root (default: current directory)",
    )
    args = parser.parse_args()

    root = args.acados_root.resolve()
    matlab_dir = root / "interfaces" / "acados_matlab_octave"

    compare_file = matlab_dir / "compare_struct_to_json.m"
    sim_options_file = matlab_dir / "AcadosSimOptions.m"
    sim_solver_file = matlab_dir / "AcadosSimSolver.m"

    required = [compare_file, sim_options_file, sim_solver_file]

    print("acados MATLAB JSON/struct patcher")
    print("=================================\n")
    print(f"acados root:\n  {root}\n")

    missing = [p for p in required if not p.is_file()]
    if missing:
        print("ERROR: expected acados MATLAB files are missing:", file=sys.stderr)
        for p in missing:
            print(f"  {p}", file=sys.stderr)
        return 2

    try:
        patch_compare(compare_file)
        patch_sim_options(sim_options_file)
        patch_sim_solver(sim_solver_file)
    except Exception as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        return 1

    print("Done.")
    print("Applied JSON/struct compatibility fixes:")
    print("  compare_struct_to_json.m -> numeric/logical-safe comparison")
    print("  AcadosSimOptions.m       -> from_struct() JSON field mapping")
    print("  AcadosSimSolver.m        -> correct configured JSON filename")
    print()
    print("Backups use the suffix: .pre_json_patch.bak")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
