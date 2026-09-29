import argparse
import concurrent.futures
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

TRAIN = Path(__file__).resolve().parent
REPO = TRAIN.parent
COPIES = Path("/tmp/hibernal-tune")
BASE = COPIES / "base"
RESULTS = REPO / "out" / "tune"
GATE_PENALTY = 10.0
TAIL = re.compile(r"\s*(?P<bounds>.+?)\s{2}(?P<mark>ok|OFF|info)\s")


class Knob:
    def __init__(self, spec):
        location, values = spec.split("=", 1)
        self.file, self.name = location.split(":")
        self.values = values.split(",")
        text = (REPO / self.file).read_text()
        found = re.findall(rf"export const {self.name}: [^=]+= ([^;]+);", text)
        if len(found) != 1:
            raise SystemExit(f"{self.file} has {len(found)} definitions of {self.name}, expected one")
        self.default = found[0]

    def label(self):
        return f"{self.file}:{self.name}"


def parseBounds(text):
    text = text.strip()
    if text == "-":
        return None, None
    if text.startswith(">="):
        return float(text[2:]), None
    if text.startswith("<="):
        return None, float(text[2:])
    low, high = text.split("..")
    return float(low), float(high)


def parseScorecard(output):
    rows = {}
    for line in output.splitlines():
        if "  target " not in line:
            continue
        left, right = line.split("  target ", 1)
        name, value = left.rsplit(None, 1)
        match = TAIL.match(right + " ")
        low, high = parseBounds(match["bounds"])
        rows[name.strip()] = (float(value), low, high, match["mark"])
    if not rows:
        raise RuntimeError(f"health printed no scorecard:\n{output[-2000:]}")
    return rows


def distance(value, low, high):
    if math.isnan(value):
        return 1.0
    if low is not None and high is not None and low == high:
        return GATE_PENALTY * abs(value - low)
    if low is not None and value < low:
        return (low - value) / max(abs(low), 1e-9)
    if high is not None and value > high:
        return (value - high) / max(abs(high), 1e-9)
    return 0.0


def score(rows, weights, limits):
    total = 0.0
    for name, (value, low, high, _mark) in rows.items():
        if name in limits:
            total += GATE_PENALTY * distance(value, None, limits[name])
        if low is None and high is None:
            continue
        total += weights.get(name, 1.0) * distance(value, low, high)
    return total


def patched(setting, knobs):
    key = hashlib.sha1(json.dumps(setting, sort_keys=True).encode()).hexdigest()[:12]
    copy = COPIES / key
    if copy.exists():
        shutil.rmtree(copy)
    subprocess.run(["rsync", "-a", f"{BASE}/", f"{copy}/"], check=True)
    for knob in knobs:
        path = copy / knob.file
        text = path.read_text()
        pattern = rf"(export const {knob.name}: [^=]+= )([^;]+);"
        path.write_text(re.sub(pattern, lambda found: f"{found[1]}{setting[knob.label()]};", text, count=1))
    return copy


def measure(setting, knobs, arguments, extra=()):
    copy = patched(setting, knobs)
    command = ["uv", "run", "--project", str(TRAIN), "python", "health.py", "--policy", arguments.policy,
               "--worlds", str(arguments.worlds), "--seed", str(arguments.seed), *extra]
    finished = subprocess.run(command, cwd=copy / "train", capture_output=True, text=True)
    shutil.rmtree(copy)
    if finished.returncode != 0:
        raise RuntimeError(f"health failed for {setting}:\n{finished.stderr[-2000:]}")
    return parseScorecard(finished.stdout)


def main():
    parser = argparse.ArgumentParser(description="Coordinate search over rules knobs, scored by health.py")
    parser.add_argument("--knob", action="append", required=True, help="file:NAME=value,value,...")
    parser.add_argument("--weight", action="append", default=[], help="scorecard row name=weight")
    parser.add_argument("--limit", action="append", default=[], help="scorecard row name=ceiling, a hard cap")
    parser.add_argument("--policy", default="teacher")
    parser.add_argument("--worlds", type=int, default=4)
    parser.add_argument("--seed", type=int, default=9001)
    parser.add_argument("--passes", type=int, default=2)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--name", default="run")
    arguments = parser.parse_args()
    knobs = [Knob(spec) for spec in arguments.knob]
    weights = {name: float(value) for name, value in (item.rsplit("=", 1) for item in arguments.weight)}
    limits = {name: float(value) for name, value in (item.rsplit("=", 1) for item in arguments.limit)}
    RESULTS.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsync", "-a", "--delete", "--exclude", ".git", "--exclude", "out", "--exclude", "train/checkpoints",
         "--exclude", "train/.venv", f"{REPO}/", f"{BASE}/"],
        check=True,
    )
    table = RESULTS / f"{arguments.name}.tsv"
    measured = {}

    def evaluate(settings):
        fresh = [setting for setting in settings if json.dumps(setting, sort_keys=True) not in measured]
        with concurrent.futures.ThreadPoolExecutor(arguments.jobs) as pool:
            for setting, rows in zip(fresh, pool.map(lambda setting: measure(setting, knobs, arguments), fresh)):
                key = json.dumps(setting, sort_keys=True)
                measured[key] = rows
                off = sum(1 for row in rows.values() if row[3] == "OFF")
                values = "\t".join(setting[knob.label()] for knob in knobs)
                with table.open("a") as out:
                    out.write(f"{values}\t{score(rows, weights, limits):.4f}\t{off}\n")
                print(f"{values}  score {score(rows, weights, limits):.4f}  off {off}", flush=True)
        return {json.dumps(setting, sort_keys=True): measured[json.dumps(setting, sort_keys=True)] for setting in settings}

    with table.open("w") as out:
        out.write("\t".join(knob.name for knob in knobs) + "\tscore\toff\n")
    best = {knob.label(): knob.default for knob in knobs}
    bestRows = evaluate([best])[json.dumps(best, sort_keys=True)]
    for sweep in range(arguments.passes):
        moved = False
        for knob in knobs:
            candidates = [{**best, knob.label(): value} for value in knob.values]
            results = evaluate(candidates)
            for setting in candidates:
                rows = results[json.dumps(setting, sort_keys=True)]
                if score(rows, weights, limits) < score(bestRows, weights, limits) - 1e-9:
                    best, bestRows, moved = setting, rows, True
        print(f"pass {sweep + 1}: best {best} score {score(bestRows, weights, limits):.4f}", flush=True)
        if not moved:
            break
    print("best setting:")
    for knob in knobs:
        print(f"  {knob.label()} = {best[knob.label()]}  (default {knob.default})")
    print("rows off target at the best setting:")
    for name, (value, low, high, mark) in bestRows.items():
        if mark == "OFF":
            print(f"  {name}: {value:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
