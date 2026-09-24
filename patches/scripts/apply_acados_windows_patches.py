#!/usr/bin/env python3
"""
apply_acados_windows_patches.py

Activate the custom Windows/MSVC acados templates.

Run from the acados repository root:

    python apply_acados_windows_patches.py

The script modifies only:

    interfaces/acados_matlab_octave/AcadosOcp.m
    interfaces/acados_matlab_octave/AcadosSim.m

It does NOT delete the original upstream template-selection lines. Each
original line is commented out and the corresponding *.in2.* replacement is
inserted immediately below it.

The script is idempotent: running it again will not duplicate patches.
A one-time backup is made before each source file is modified.

Required custom templates:

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


OCP_RULES = [
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


SIM_RULES = [
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


def detect_newline(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def leading_whitespace(line: str) -> str:
    return line[: len(line) - len(line.lstrip())]


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

    # newline="" preserves the file's actual newline characters.
    with path.open("r", encoding="utf-8", newline="") as f:
        text = f.read()

    eol = detect_newline(text)
    changed = False

    for label, original, replacement in rules:
        if replacement in text:
            print(f"  [already patched] {label}")
            continue

        if original not in text:
            raise RuntimeError(
                "Could not find the expected upstream line for:\n"
                f"  {label}\n\n"
                "acados may have changed this source file. "
                "No automatic guess was made.\n"
                f"Expected:\n{original}"
            )

        indent = leading_whitespace(original)
        patch_text = (
            f"{indent}% WINDOWS/MSVC PATCH - original upstream line retained:{eol}"
            f"{indent}% {original.strip()}{eol}"
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


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Activate custom *.in2.* templates in the acados MATLAB interface."
    )
    parser.add_argument(
        "--acados-root",
        type=Path,
        default=Path.cwd(),
        help="acados repository root (default: current directory)",
    )
    args = parser.parse_args()

    root = args.acados_root.resolve()
    matlab_octave = root / "interfaces" / "acados_matlab_octave"
    template_root = (
        root
        / "interfaces"
        / "acados_template"
        / "acados_template"
        / "c_templates_tera"
    )
    matlab_templates = template_root / "matlab_templates"

    ocp_file = matlab_octave / "AcadosOcp.m"
    sim_file = matlab_octave / "AcadosSim.m"

    required_templates = [
        template_root / "CMakeLists.in2.txt",
        matlab_templates / "make_mex.in2.m",
        matlab_templates / "make_mex_sim.in2.m",
        matlab_templates / "make_sfun.in2.m",
        matlab_templates / "make_sfun_sim.in2.m",
        matlab_templates / "mex_sim_solver.in2.m",
    ]

    print("acados Windows/MSVC template patcher")
    print("====================================\n")
    print(f"acados root:\n  {root}\n")

    if not ocp_file.is_file() or not sim_file.is_file():
        print(
            "ERROR: this does not look like the acados repository root.\n"
            "Run the script from <acados>, or pass:\n"
            "  --acados-root <path-to-acados>",
            file=sys.stderr,
        )
        return 2

    missing = [p for p in required_templates if not p.is_file()]
    if missing:
        print("ERROR: the patch templates are not all installed yet:", file=sys.stderr)
        for p in missing:
            print(f"  MISSING: {p}", file=sys.stderr)
        print(
            "\nInstall the *.in2.* template files first, then run this script again.",
            file=sys.stderr,
        )
        return 3

    print("All custom templates were found.\n")

    try:
        patch_file(ocp_file, OCP_RULES)
        patch_file(sim_file, SIM_RULES)
    except Exception as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        return 1

    print("Done.")
    print("The upstream lines were retained as comments and the *.in2.* lines are active.")
    print("Backups use the suffix: .pre_windows_patch.bak")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
