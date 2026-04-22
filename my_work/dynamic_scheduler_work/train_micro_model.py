#!/usr/bin/env python3
import argparse
import csv
import math
import random
from pathlib import Path

FEAT_DIM = 11


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def sigmoid(x):
    x = clamp(x, -20.0, 20.0)
    return 1.0 / (1.0 + math.exp(-x))


def make_features(row):
    part = int(row["part"])
    pot = float(row["pot"])
    crit = float(row["criticality"])
    slack_pot = float(row["slack_potential"])
    struct_pot = float(row["struct_potential"])
    fanout = int(row["fanout"])
    window = int(row["window_size"])
    prior = float(row["prior"])
    slack_norm = clamp(float(row.get("slack", "0.0")) / 0.30, 0.0, 1.0)

    return [
        pot,
        crit,
        slack_pot,
        struct_pot,
        clamp(fanout / 12.0, 0.0, 1.0),
        clamp(window / 32.0, 0.0, 1.0),
        prior,
        1.0 if part == 0 else 0.0,
        1.0 if part == 1 else 0.0,
        1.0 if part == 2 else 0.0,
        slack_norm,
    ]


def make_label(row, goal_min_area_impr_pct, delay_eps):
    goal_hit = row.get("goal_hit", "")
    if goal_hit != "":
        try:
            return 1 if int(float(goal_hit)) > 0 else 0
        except ValueError:
            pass

    try:
        area_impr = float(row.get("area_impr_pct", "0.0"))
    except ValueError:
        area_impr = 0.0
    try:
        delay_delta = float(row.get("delay_delta", "0.0"))
    except ValueError:
        delay_delta = 0.0

    if delay_delta <= delay_eps and area_impr >= goal_min_area_impr_pct:
        return 1

    # Backward compatibility for very old CSVs without QoR deltas.
    if "area_impr_pct" not in row and "delay_delta" not in row:
        try:
            return 1 if int(row.get("accepted", "0")) > 0 else 0
        except ValueError:
            return 0
    return 0


def read_samples(paths, goal_min_area_impr_pct, delay_eps):
    xs = []
    ys = []
    for p in paths:
        with open(p, "r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if "part" not in row:
                    continue
                y = make_label(row, goal_min_area_impr_pct, delay_eps)
                xs.append(make_features(row))
                ys.append(y)
    return xs, ys


def fit_logistic(xs, ys, epochs, lr, l2, seed, balance):
    rng = random.Random(seed)
    w = [0.0] * FEAT_DIM
    b = 0.0

    pos = sum(ys)
    neg = len(ys) - pos
    if pos == 0 or neg == 0:
        raise RuntimeError("training data only has one class")

    w_pos = 1.0
    w_neg = 1.0
    if balance:
        w_pos = len(ys) / (2.0 * pos)
        w_neg = len(ys) / (2.0 * neg)

    idx = list(range(len(ys)))
    for _ in range(epochs):
        rng.shuffle(idx)
        for i in idx:
            x = xs[i]
            y = ys[i]
            p = sigmoid(b + sum(wj * xj for wj, xj in zip(w, x)))
            err = (y - p) * (w_pos if y == 1 else w_neg)
            for k in range(FEAT_DIM):
                w[k] += lr * (err * x[k] - l2 * w[k])
                w[k] = clamp(w[k], -8.0, 8.0)
            b += lr * err
            b = clamp(b, -8.0, 8.0)
    return b, w


def eval_acc(xs, ys, b, w):
    correct = 0
    for x, y in zip(xs, ys):
        p = sigmoid(b + sum(wj * xj for wj, xj in zip(w, x)))
        pred = 1 if p >= 0.5 else 0
        correct += 1 if pred == y else 0
    return correct / len(ys) if ys else 0.0


def save_model(path, bias, weights, sample_count):
    with open(path, "w", encoding="utf-8") as f:
        f.write("# phy micro model v1\n")
        f.write(f"bias {bias:.8f}\n")
        f.write(f"sample_count {sample_count}\n")
        f.write("weights")
        for wi in weights:
            f.write(f" {wi:.8f}")
        f.write("\n")


def main():
    ap = argparse.ArgumentParser(description="Train tiny logistic model for phyopt candidate filtering/ranking.")
    ap.add_argument("--input", nargs="+", required=True, help="CSV files exported by PHY_MICRO_TRAIN_CSV")
    ap.add_argument("--output", required=True, help="Output model file for PHY_MICRO_MODEL_FILE")
    ap.add_argument("--goal-min-area-impr-pct", type=float, default=0.0,
                    help="Positive label threshold: min area improvement percent under non-worse delay")
    ap.add_argument("--delay-eps", type=float, default=1e-3,
                    help="Delay non-regression epsilon used when goal_hit column is absent")
    ap.add_argument("--epochs", type=int, default=20)
    ap.add_argument("--lr", type=float, default=0.05)
    ap.add_argument("--l2", type=float, default=0.001)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--balance", action="store_true", help="Class-balanced weighting")
    args = ap.parse_args()

    inputs = [str(Path(p)) for p in args.input]
    xs, ys = read_samples(inputs, args.goal_min_area_impr_pct, args.delay_eps)
    if not xs:
        raise RuntimeError("no samples loaded")

    bias, weights = fit_logistic(xs, ys, args.epochs, args.lr, args.l2, args.seed, args.balance)
    acc = eval_acc(xs, ys, bias, weights)

    save_model(args.output, bias, weights, len(ys))
    pos = sum(ys)
    print(f"samples={len(ys)} pos={pos} neg={len(ys)-pos} train_acc={acc:.4f}")
    print(f"saved model -> {args.output}")


if __name__ == "__main__":
    main()
