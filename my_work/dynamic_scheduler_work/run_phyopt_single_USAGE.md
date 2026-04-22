# run_phyopt_single.sh

One-command wrapper for fitted-function phyopt flow.

## What it does

This command executes the complete flow:

1. `read_lib`
2. `read_aiger`
3. `map_oto`
4. `mapper_extract`
5. `phyread`
6. `phyopt`
7. `map; ps`
8. `write_verilog` / `write_blif` / `write_aiger` (optional outputs)

It also sets fit-function runtime env vars:

- `PHY_MICRO_ENABLE`
- `PHY_FIT_ENABLE`
- `PHY_FIT_COEF_FILE`
- `PHY_FIT_L0_SCALE`
- `PHY_FIT_L1_SCALE`

## Script path

`my_work/dynamic_scheduler_work/run_phyopt_single.sh`

## Quick start (inside WSL)

```bash
cd /mnt/d/My_abc_work/abc
bash my_work/dynamic_scheduler_work/run_phyopt_single.sh \
  --input-aig my_work/xiaorong_aig/c17.aig \
  --out-v my_work/out/c17_opt.v \
  --out-blif my_work/out/c17_opt.blif \
  --fit-file my_work/model/phy_fit_function_v1.txt
```

## Quick start (from PowerShell)

```powershell
wsl bash -lc "cd /mnt/d/My_abc_work/abc; bash my_work/dynamic_scheduler_work/run_phyopt_single.sh --input-aig my_work/xiaorong_aig/c17.aig --out-v my_work/out/c17_opt.v --out-blif my_work/out/c17_opt.blif --fit-file my_work/model/phy_fit_function_v1.txt"
```

## Main arguments

- `--input-aig <file>`: required input AIG
- `--out-v <file>`: write optimized Verilog
- `--out-blif <file>`: write optimized BLIF
- `--out-aig <file>`: write optimized AIG (strashed)
- `--fit-file <file>`: fit coefficient file (`bias`, `sample_count`, `weights`)

Flow knobs:

- `--i --p --f --g` for `phyread`
- `--rounds --k --L --H --timeout-sec` for `phyopt`

Fit knobs:

- `--micro-enable`
- `--fit-enable`
- `--fit-l0-scale`
- `--fit-l1-scale`

Use `--help` to print full argument list.

## Current default values

- `i/p/f/g = 0.50 / 0.40 / 0.05 / 0.05`
- `rounds = 3`
- `k = 40`
- `L/H = 0.25 / 0.90`
- `timeout-sec = 300`
- `micro-enable = 0`
- `fit-enable = 1`
- `fit-l0-scale = 0.35`
- `fit-l1-scale = 0.25`

## Outputs and logs

If not explicitly provided:

- phy csv defaults to `<out_dir>/<stem>.phy.csv`
- log defaults to `<out_dir>/<stem>.phyopt.log`

The script prints final `ps` line and log path on success.
