#!/usr/bin/env python3
"""
apply_acados_windows_patches.py

Activate the local Windows/MSVC acados patch set for BOTH MATLAB and Python.

Run from the acados repository root:

    python apply_acados_windows_patches.py

or from anywhere:

    python apply_acados_windows_patches.py --acados-root C:\\path\\to\\acados

What this script changes
------------------------
MATLAB interface:
    interfaces/acados_matlab_octave/AcadosOcp.m
    interfaces/acados_matlab_octave/AcadosSim.m

Python interface:
    interfaces/acados_template/acados_template/acados_ocp.py
    interfaces/acados_template/acados_template/acados_sim.py
    interfaces/acados_template/acados_template/builders.py

The original upstream template-selection lines are NOT deleted. They are
commented out and the local replacement is inserted immediately below them.

The script is idempotent:
    - running it more than once does not duplicate patches;
    - a one-time backup is created before a file is modified;
    - if an expected upstream line changed, the script stops instead of
      guessing.

Required local templates
------------------------
    interfaces/acados_template/acados_template/c_templates_tera/
        CMakeLists.in2.txt

    interfaces/acados_template/acados_template/c_templates_tera/
        matlab_templates/
            make_mex.in2.m
            make_mex_sim.in2.m
            make_sfun.in2.m
            make_sfun_sim.in2.m
            mex_sim_solver.in2.m
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


MATLAB_OCP_RULES = [
    (
        "CMake template",
        "            template_list{end+1} = {'CMakeLists.in.txt', ['CMakeLists.txt']};",
        "            template_list{end+1} = {'CMakeLists.in2.txt', ['CMakeLists.txt']};",
    ),
    (
        "OCP MATLAB MEX build template",
        "            template_list{end+1} = {fullfile(matlab_template_path, 'make_mex.in.m'), ['make_mex_', self.name, '.m']};",
        "            template_list{end+1} = {fullfile(matlab_template_path, 'make_mex.in2.m'), ['make_mex_', self.name, '.m']};",
    ),
    (
        "OCP Simulink S-function build template",
        "                template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun.in.m'), ['make_sfun.m']};",
        "                template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun.in2.m'), ['make_sfun.m']};",
    ),
    (
        "integrator Simulink S-function build template used by OCP",
        "                    template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun_sim.in.m'), ['make_sfun_sim.m']};",
        "                    template_list{end+1} = {fullfile(matlab_template_path, 'make_sfun_sim.in2.m'), ['make_sfun_sim.m']};",
    ),
]


MATLAB_SIM_RULES = [
    (
        "SIM MATLAB wrapper template",
        "                {fullfile(matlab_template_path, 'mex_sim_solver.in.m'), [self.name, '_mex_sim_solver.m']}, ...",
        "                {fullfile(matlab_template_path, 'mex_sim_solver.in2.m'), [self.name, '_mex_sim_solver.m']}, ...",
    ),
    (
        "SIM MATLAB MEX build template",
        "                {fullfile(matlab_template_path, 'make_mex_sim.in.m'), ['make_mex_sim_', self.name, '.m']}, ...",
        "                {fullfile(matlab_template_path, 'make_mex_sim.in2.m'), ['make_mex_sim_', self.name, '.m']}, ...",
    ),
    (
        "SIM Simulink S-function build template",
        "                {fullfile(matlab_template_path, 'make_sfun_sim.in.m'), ['make_sfun_sim_', self.name, '.m']}, ...",
        "                {fullfile(matlab_template_path, 'make_sfun_sim.in2.m'), ['make_sfun_sim_', self.name, '.m']}, ...",
    ),
    (
        "CMake template",
        "                {'CMakeLists.in.txt', 'CMakeLists.txt'}};",
        "                {'CMakeLists.in2.txt', 'CMakeLists.txt'}};",
    ),
]


PYTHON_OCP_RULES = [
    (
        "Python OCP CMake template",
        "            template_list.append(('CMakeLists.in.txt', 'CMakeLists.txt'))",
        "            template_list.append(('CMakeLists.in2.txt', 'CMakeLists.txt'))",
    ),
]


PYTHON_SIM_RULES = [
    (
        "Python SIM CMake template",
        "            template_list.append(('CMakeLists.in.txt', 'CMakeLists.txt'))",
        "            template_list.append(('CMakeLists.in2.txt', 'CMakeLists.txt'))",
    ),
]


PYTHON_BUILDER_RULES = [
    (
        "Visual Studio generator",
        "            self.generator = 'Visual Studio 15 2017 Win64'",
        (
            "            self.generator = 'Visual Studio 17 2022'\n"
            "            self.host = 'x64'"
        ),
    ),
    (
        "Visual Studio install configuration",
        '        return f\'cmake --install "{self._build_dir}"\'',
        (
            "        if os.name == 'nt':\n"
            "            return f'cmake --install \"{self._build_dir}\" --config Release'\n"
            "        return f'cmake --install \"{self._build_dir}\"'"
        ),
    ),
]


def detect_newline(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def leading_whitespace(line: str) -> str:
    return line[: len(line) - len(line.lstrip())]


def comment_prefix_for(path: Path) -> str:
    return "%" if path.suffix.lower() == ".m" else "#"


def patch_file(path: Path, rules: list[tuple[str, str, str]]) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"File not found: {path}")

    print(f"Patching:\n  {path}")

    backup = path.with_name(path.name + ".pre_windows_patch.bak")
    if not backup.exists():
        shutil.copy2(path, backup)
        print(f"  backup created: {backup}")
    else:
        print("  backup already exists; leaving it untouched.")

    # newline="" keeps CRLF/LF exactly as stored in the source file.
    with path.open("r", encoding="utf-8", newline="") as f:
        text = f.read()

    eol = detect_newline(text)
    prefix = comment_prefix_for(path)
    changed = False

    for label, original, replacement in rules:
        if replacement in text:
            print(f"  [already patched] {label}")
            continue

        if original not in text:
            raise RuntimeError(
                "Could not find the expected upstream line/block for:\n"
                f"  {label}\n\n"
                "acados may have changed this source file. "
                "No automatic guess was made.\n"
                f"Expected:\n{original}"
            )

        indent = leading_whitespace(original.splitlines()[0])

        # Preserve the exact upstream code as comments, then add replacement.
        original_lines = original.splitlines()
        commented_original = eol.join(
            f"{leading_whitespace(line)}{prefix} {line.lstrip()}"
            for line in original_lines
        )

        patch_text = (
            f"{indent}{prefix} WINDOWS/MSVC PATCH - original upstream code retained:{eol}"
            f"{commented_original}{eol}"
            f"{replacement}"
        )

        text = text.replace(original, patch_text, 1)
        changed = True
        print(f"  [patched] {label}")

    if changed:
        with path.open("w", encoding="utf-8", newline="") as f:
            f.write(text)
        print("  file updated.\n")
    else:
        print("  no changes needed.\n")


def verify_templates(root: Path) -> None:
    template_root = (
        root
        / "interfaces"
        / "acados_template"
        / "acados_template"
        / "c_templates_tera"
    )
    matlab_templates = template_root / "matlab_templates"

    required = [
        template_root / "CMakeLists.in2.txt",
        matlab_templates / "make_mex.in2.m",
        matlab_templates / "make_mex_sim.in2.m",
        matlab_templates / "make_sfun.in2.m",
        matlab_templates / "make_sfun_sim.in2.m",
        matlab_templates / "mex_sim_solver.in2.m",
    ]

    missing = [p for p in required if not p.is_file()]
    if missing:
        lines = "\n".join(f"  MISSING: {p}" for p in missing)
        raise FileNotFoundError(
            "The local patch templates are not all installed yet:\n"
            f"{lines}\n\n"
            "Install the *.in2.* files first, then run this script again."
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Activate the local Windows/MSVC templates for both the MATLAB "
            "and Python acados interfaces."
        )
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
    python_dir = root / "interfaces" / "acados_template" / "acados_template"

    files_and_rules = [
        (matlab_dir / "AcadosOcp.m", MATLAB_OCP_RULES),
        (matlab_dir / "AcadosSim.m", MATLAB_SIM_RULES),
        (python_dir / "acados_ocp.py", PYTHON_OCP_RULES),
        (python_dir / "acados_sim.py", PYTHON_SIM_RULES),
        (python_dir / "builders.py", PYTHON_BUILDER_RULES),
    ]

    print("acados Windows/MSVC patcher")
    print("===========================\n")
    print(f"acados root:\n  {root}\n")

    # Validate repository layout before modifying anything.
    for path, _ in files_and_rules:
        if not path.is_file():
            print(
                "ERROR: this does not look like the expected acados checkout.\n"
                f"Missing:\n  {path}",
                file=sys.stderr,
            )
            return 2

    try:
        verify_templates(root)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 3

    print("All local *.in2.* templates were found.\n")

    try:
        for path, rules in files_and_rules:
            patch_file(path, rules)
    except Exception as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        return 1

    print("Done.")
    print()
    print("Activated patch set:")
    print("  MATLAB OCP/SIM -> *.in2.m and CMakeLists.in2.txt")
    print("  Python OCP/SIM -> CMakeLists.in2.txt when CMake is used")
    print("  Python CMakeBuilder -> Visual Studio 17 2022, x64")
    print("  Python CMake install -> explicit --config Release on Windows")
    print()
    print("Original upstream lines were retained as comments.")
    print("Backups use the suffix: .pre_windows_patch.bak")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
