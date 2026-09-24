# acados_patches_windows
acados is not well tested with Windows MSVC. 
In order to make it work with Matlab, Simulink, Python locally on Windows without using MinGW installation,
We need to make modifications a bit to their source code by using patches provided in this repository.



## Installation of acados for both Matlab and Python
The installation considered here is simply by running our patch scripts in matlab and it will install all acados components necessary for both Matlab Simulink and Python.

Put the files:
- `acados_install_shared_and_static_windows_msvc.m` 
- `acados_env_variables_windows_msvc_s.m`
- `acados_install_windows_msvc.m`

inside `acados\interfaces\acados_matlab_octave`.


Go to `acados\interfaces\acados_matlab_octave` and run:
```
acados_install_shared_and_static_windows_msvc('-DACADOS_WITH_QPOASES=ON -DACADOS_WITH_DAQP=OFF -DACADOS_WITH_QPDUNES=ON -DACADOS_WITH_OSQP=ON -DACADOS_WITH_HPMPC=OFF -DACADOS_WITH_CLARABEL=OFF -DACADOS_WITH_QORE=OFF -DACADOS_WITH_OOQP=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5')
```
or
```
acados_install_shared_and_static_windows_msvc( ...
    '-DACADOS_WITH_QPOASES=ON -DACADOS_WITH_QPDUNES=ON -DACADOS_WITH_OSQP=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5')
```
## Patches:
First, put the file `CMakeLists.in2.txt` inside `acados\interfaces\acados_template\acados_template\c_templates_tera`


Put those patch files inside `acados\interfaces\acados_template\acados_template\c_templates_tera\matlab_templates`:

```
make_mex.in2.m
make_sfun.in2.m


mex_sim_solver.in2.m
make_mex_sim.in2.m
make_sfun_sim.in2.m
```

Then go to `acados\interfaces\acados_matlab_octave`
Change 2 files: `AcadosOcp` and `AcadosSim` by using the patch script: either Matlab or Python:

- For MATLAB, put the script somewhere convenient, then from:
```
<acados>\interfaces\acados_matlab_octave
```
run:
```
apply_acados_windows_patches_complete
```

- For Python, start from the acados root:
```
cd C:\Users\khanh\deps\acados
python apply_acados_windows_patches_complete.py
```
or from anywhere:
```
python apply_acados_windows_patches_complete.py --acados-root C:\Users\khanh\deps\acados
```