import argparse
import concurrent.futures
import itertools
import subprocess
import sys

import numpy as np

import tune
from hibernalTrain.feel import FEEL_FIELDS
from hibernalTrain.rollout import SLOTS

MASK = "sim/teacher.ms:TEACHER_GEAR_SLOTS"
HALVES = ("341", "682")


def field(counters, name):
    return counters[:, FEEL_FIELDS.index(name)].astype(np.float64)


def seatSummary(counters, seats):
    lives = field(counters, "lives")[seats].sum()
    early = sum(field(counters, name)[seats].sum() for name in ("starved", "bitten", "diedAttacking"))
    living = field(counters, "living")[seats] > 0
    wealth = field(counters, "wealth")[seats][living]
    days = field(counters, "livingEpochs")[seats].sum()
    return {
        "wealth": float(np.median(wealth)) if len(wealth) else float("nan"),
        "early": 100.0 * early / max(lives, 1),
        "income": field(counters, "earned")[seats].sum() / max(days, 1),
        "gear": (field(counters, "mintSpent")[seats].sum() + field(counters, "marketSpent")[seats].sum()) / max(days, 1),
    }


def main():
    parser = argparse.ArgumentParser(description="Does gear pay back its buyer: half the seats buy gear, then the other half")
    parser.add_argument("--knob", action="append", default=[], help="file:NAME=value,value,...")
    parser.add_argument("--worlds", type=int, default=4)
    parser.add_argument("--seed", type=int, default=9001)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--policy", default="teacher")
    arguments = parser.parse_args()
    knobs = [tune.Knob(spec) for spec in arguments.knob] + [tune.Knob(f"{MASK}=" + ",".join(HALVES))]
    subprocess.run(
        ["rsync", "-a", "--delete", "--exclude", ".git", "--exclude", "out", "--exclude", "train/checkpoints",
         "--exclude", "train/.venv", f"{tune.REPO}/", f"{tune.BASE}/"],
        check=True,
    )
    mask = knobs[-1].label()
    grid = list(itertools.product(*(knob.values for knob in knobs[:-1]))) or [()]
    runs = []
    for values in grid:
        for half in HALVES:
            setting = {knob.label(): knob.default for knob in knobs}
            setting.update({knob.label(): value for knob, value in zip(knobs, values)})
            setting[mask] = half
            runs.append((values, half, setting))
    tune.RESULTS.mkdir(parents=True, exist_ok=True)

    def run(entry):
        values, half, setting = entry
        path = tune.RESULTS / f"payback.{'-'.join(values) or 'default'}.{half}.npy"
        tune.measure(setting, knobs, arguments, ("--save", str(path)))
        return np.load(path)

    with concurrent.futures.ThreadPoolExecutor(arguments.jobs) as pool:
        counters = list(pool.map(run, runs))
    names = " ".join(knob.name for knob in knobs[:-1]) or "default"
    print(f"{names:40s} gear minus no gear, same seats: wealth median · early deaths/100 · income/day · gear spend/day")
    for position, values in enumerate(grid):
        first, second = counters[2 * position], counters[2 * position + 1]
        slots = np.arange(len(first)) % SLOTS
        rows = []
        for group, seats in (("even", slots % 2 == 0), ("odd", slots % 2 == 1)):
            geared = seatSummary(first if group == "even" else second, seats)
            bare = seatSummary(second if group == "even" else first, seats)
            rows.append({key: geared[key] - bare[key] for key in geared} | {"bareWealth": bare["wealth"], "gearSpend": geared["gear"]})
        wealth = np.mean([row["wealth"] for row in rows])
        bareWealth = np.mean([row["bareWealth"] for row in rows])
        early = np.mean([row["early"] for row in rows])
        income = np.mean([row["income"] for row in rows])
        spend = np.mean([row["gearSpend"] for row in rows])
        label = " ".join(values) or "default"
        print(f"{label:40s} {wealth:+9.0f} ({100 * wealth / bareWealth:+5.1f}%) · {early:+5.2f} · {income:+7.1f} · {spend:7.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
