# Grouped Strategy Playbook

This playbook maps reject-profile groups to optimization priorities and candidate actions.

## Group A (area high, runtime low)
Priority: candidate quality first.
Primary actions:
- Increase structural emphasis in alpha mix (example: L/M/H = 0.15/0.45/0.75).
- Keep robust search scale (example: k=40).
- Tighten candidate pre-filtering only if area-worse rejects remain dominant.

## Group B (runtime high, area low)
Priority: evaluation efficiency first.
Primary actions:
- Reduce evaluation cost per candidate (example: k from 40 to 30 for this group).
- Keep alpha near conservative default (example: 0.20/0.50/0.80).
- Add early stopping and runtime guardrails.

## Group C (area high, runtime high)
Priority: hybrid strategy.
Primary actions:
- Two-stage flow: fast pre-screen (k=30) then quality refinement (k=40).
- Use moderately structural alpha (example: 0.15/0.45/0.75) in refinement stage.
- Enforce strict reject budget to avoid runtime blowup.

## Group D (area low, runtime low)
Priority: stability baseline.
Primary actions:
- Keep default stable config.
- Minimize parameter perturbation.
- Use this group as regression guard.

## U_small / U_mid
Priority: observation and low-risk experiments.
Primary actions:
- Do not overfit due to insufficient or mixed evidence.
- Collect more samples before promoting to A/B/C/D.

## Global rules
- Hard constraints: PASS=100%, delay_worse=0.
- Evaluate both group-level gains and global aggregate.
- Use fixed reject thresholds per experiment cycle to maintain comparability.
