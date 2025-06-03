# SNEM2000d

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://tphilpott2.github.io/SNEM2000d.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tphilpott2.github.io/SNEM2000d.jl/dev/)
[![Build Status](https://github.com/tphilpott2/SNEM2000d.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tphilpott2/SNEM2000d.jl/actions/workflows/CI.yml?query=branch%3Amain)

## Description

This package contains the code used to develop the SNEM2000d model, a synthetic power system model representing Australis's National Electricity Market (NEM). The model extends on the SNEM2300 and SNEM2000 models described in 

- F. Arraño-Vargas and G. Konstantinou, "Synthetic Grid Modeling for Real-Time Simulations," 2021 IEEE PES Innovative Smart Grid Technologies - Asia (ISGT Asia), 2021, pp. 1-5, doi: 10.1109/ISGTAsia49270.2021.9715654 
- R. Heidari, M. Amos and F. Geth, "An Open Optimal Power Flow Model for the Australian National Electricity Market," 2023 IEEE PES Innovative Smart Grid Technologies - Asia (ISGT Asia), Auckland, New Zealand, 2023, pp. 1-5, doi: 10.1109/ISGTAsia54891.2023.10372618.

Extensions to the model include:

- Dynamic models for solar PV and wind generators (using WECC generic models)
- Future transmission network expansions and planned renewable energy zones (added by the package ISPHVDC.jl)
- Addition of reactive compensation and OLTC transformers to enable OPF convergence
- A series of highly renewable operating scenarios to be used for dynamic analysis

### NOTE: Data used to develop the model is not included in this repository. This data is all publicly available. Contact the authors for more information.


## Installation

You can clone the package and add it to your julia environment using

```julia
] develop https://github.com/tphilpott2/SNEM2000d.jl.git
```

Make sure to also install the unregistered packages ISPHVDC.jl and PowerModelsACDCsecurityconstrained.jl to your Julia environment.

- https://github.com/hakanergun/ISPhvdc.jl/tree/Philpott-Branch
- https://github.com/csiro-energy-systems/PowerModelsACDCsecurityconstrained.jl


Additionally, the data used by the ISPHVDC.jl package should be downloaded according to the instructions in the ISPHVDC.jl repository, and stored in the `data/ISPHVDC` folder.


## Repository structure

This repository contains both Julia and Python code. The Python code is used to interact with PowerFactory, while all other code is written in Julia. Note that all results are omitted from the repository to reduce the size.

There are three main components/functionalities in the development of the SNEM2000d model stored in this repository:

#### OPF Studies

The cursory OPF studies used to determine highly renewable operating scenarios.

- The scripts used to perform and analyse the OPF studies are stored in `scripts/opf_studies`
- The OPF formulations, including variable and constraint definitions, are stored in `src/opf`
- The details of the model used as an input to the OPF are stored in `src/opf/prepare_opf_data.jl`
- OPF results are stored in `results/opf`

#### Building the PowerFactory model of the SNEM2000d

This section of the project contains Julia code, used to export CSVs which store the network data necessary for the dynamic model, and a Python module that constructs the PowerFactory model from these CSVs.

- The Julia source code is stored in `src/make_powerfactory_model/write_pf_data_csvs`
- The Python source code is stored in `src/make_powerfactory_model/make_network`
- The operating scenarios derived from the OPF studies are applied to the PowerFactory model using the module `src/make_powerfactory_model/applyscenario`

The order of execution used in the development of the PowerFactory model is as follows below. Note that these scripts must be run in order, as later scripts use files generated in earlier scripts, or, in the case of the python scripts, subsequent modifications to the network build on each other.

1. `scripts/make_powerfactory_model/export_SNEM2000d.jl`
2. `scripts/make_powerfactory_model/make_network.jl`
3. `scripts/make_powerfactory_model/add_2050_operation_scenarios.jl`

#### Dynamic Studies using the PowerFactory model

The scripts used to perform the dynamic studies and analysis described in the related publication are stored in `scripts/powerfactory_studies`. The figures used in the publication are generated using the scripts in `scripts/IAS_publication_figures`.

Note that the results files for dynamic studies have been omitted as they are quite large.

The order of execution and results files generated for the studies run in the paper is:

Small signal studies:
1. `sripts\powerfactory_studies\small_signal\small_signal_1.py`
 - `results\powerfactory\small_signal\small_signal_1`
2. `sripts\powerfactory_studies\small_signal\analysis_small_signal_1.jl`
 - `results\powerfactory\small_signal\unstable_hours_stage_1.txt`
3. `sripts\powerfactory_studies\small_signal\small_signal_2.py`
4. `sripts\powerfactory_studies\small_signal\small_signal_3.py`
5. `scripts\IAS_publication_figures\small_signal_polar_plots.jl`
 - `results\IAS_publication_figures\(all polar plot figures).png`

Time domain studies:
1. `sripts\powerfactory_studies\mainland_lccs\run_mainland_LCCs_no_FCAS.py`
 - results\powerfactory\mainland_lccs_no_FCAS
2. `sripts\powerfactory_studies\mainland_lccs\analyse_FCAS_capacity.jl`
 - data\mainland_fcas_ibgs_2050.csv
3. `sripts\powerfactory_studies\mainland_lccs\run_mainland_LCCs_with_FCAS.py`
 - results\powerfactory\mainland_lccs_with_FCAS
4. `sripts\powerfactory_studies\mainland_lccs\make_mainland_LCC_result_summary.jl`
 - results\powerfactory\mainland_lccs_results_summary.csv
 - results\mainland_lccs_plots\manual_sort

At this stage plots are manually sorted to identify unstable simulations. Subsequenct analysis for the paper is then performed identify

`scripts\IAS_publication_figures\fcas_procured.jl`
`scripts\IAS_publication_figures\frequency_nadir.jl`
`scripts\IAS_publication_figures\instability_category.jl`


#### Isolate section

The Python module `src/isolatesection` provides the functionality of isolating a section of the SNEM2000d model.


## Citation

If you use this code in your work, please cite the following publication:

- Add citation when published
