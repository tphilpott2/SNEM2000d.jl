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
- A script to set REZ IBGs to voltage sources is stored in `scripts/make_powerfactory_model/set_rez_ibgs_to_voltage_sources.py`

The order of execution used in the development of the PowerFactory model is as follows:

1. `scripts/make_powerfactory_model/export_SNEM2000d.jl`
2. `scripts/make_powerfactory_model/make_network.jl`
3. `scripts/make_powerfactory_model/add_2050_operation_scenarios.jl`
4. `scripts/make_powerfactory_model/set_rez_IBGs_to_voltage_sources.jl`

#### Dynamic Studies using the PowerFactory model

The scripts used to perform the dynamic studies and analysis described in the related publication are stored in `scripts/powerfactory_studies`. The figures used in the publication are generated using the scripts in `scripts/IAS_publication_figures`.

Note that the figures generated and stored in `results/powerfactory/rms_steady_state_plots` are sorted manually into the subfolder categories.

#### Isolate section

The Python module `src/isolatesection` provides the functionality of isolating a section of the SNEM2000d model.


## Citation

If you use this code in your work, please cite the following publication:

- Add citation when published