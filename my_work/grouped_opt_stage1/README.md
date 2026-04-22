# grouped_opt_stage1

Stage-1 grouped optimization workspace under my_work.

## Structure
- groups/: benchmark lists used by stage-1 executors.
- configs/: per-group candidate parameter sets.
- results/: run outputs.
- Group preparation for dynamic scheduling has been moved to `my_work/dynamic_scheduler_work/prepare_group_inputs.sh`.
- run_group_experiments.sh: run one group with one case-list.
- run_stage1_all.sh: run A/B/C/D in sequence and merge summaries.
- summarize_unified_eval.sh: unified evaluator for merged summary.
- strategy_profiles.sh: per-group strategy defaults (quality/efficiency/hybrid/stable).
- run_group_strategy.sh: strategy entrypoint for one group.
- run_group_C_two_stage.sh: C-group two-stage executor (fast pre-screen then quality refine).
- run_stage1_all_strategy.sh: run A/B/C/D using strategy entrypoints and merge summaries.

## Quick start
1) (Moved) Generate LMH criticality groups in dynamic workspace:

bash my_work/dynamic_scheduler_work/prepare_group_inputs.sh <bench_criticality.csv>

2) Run all groups (A/B/C/D):

RUN_TAG=run_stage1_g1 bash my_work/grouped_opt_stage1/run_stage1_all.sh

3) Unified evaluation:

bash my_work/grouped_opt_stage1/summarize_unified_eval.sh my_work/grouped_opt_stage1/results/run_stage1_g1/summary_all.csv

## Strategy mode
1) Run one group with strategy controls:

RUN_GROUP=A bash my_work/grouped_opt_stage1/run_group_strategy.sh

2) Run all groups in strategy mode:

RUN_TAG=run_stage1_strategy_g1 bash my_work/grouped_opt_stage1/run_stage1_all_strategy.sh

3) C group defaults to two-stage. Disable with:

C_TWO_STAGE=0 RUN_GROUP=C bash my_work/grouped_opt_stage1/run_group_strategy.sh

## Notes
- Hard constraints remain PASS=100% and delay_worse=0.
- Default baseline uses i/p/f/g=0.50/0.40/0.05/0.05 and phyopt L/H=0.25/0.90.
- Per-group case list format:
  case_name alpha_low alpha_mid alpha_high k opt_low opt_high w_i w_p w_f w_g
