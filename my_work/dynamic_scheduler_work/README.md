# dynamic_scheduler_work

Dynamic scheduling workspace for fixed-parameter experiments.

This folder is intentionally separated from reject-profile grouping workflows.

## Files
- `run_dynamic_per_aig_full.sh`: primary runner. Processes each AIG independently and uses per-node dynamic scheduling inside `phyopt -d`.
- `result/`: per-run outputs and summary CSV for Stage C comparison.

## Per-AIG Dynamic Run
Run full flow on `my_work/xiaorong_aig` with Stage C `cfg_winvpair_base` parameters:

```bash
RUN_TAG=run_dynamic_per_aig_full \
bash my_work/dynamic_scheduler_work/run_dynamic_per_aig_full.sh
```

Policy is implemented inside `phyopt -d` for each AIG:
- Initial phase: each criticality partition runs 15%.
- Iteration: leader partition runs 5%, other partitions run 1% probes.
- Partition early stop: 10 consecutive nodes without effective improvement.
- Global early stop: 2 consecutive rounds without global score improvement.