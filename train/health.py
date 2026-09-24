import argparse
import time

import numpy as np

from hibernalTrain.env import CONTROL_TEACHER, PERSONAS, HibernalEnv
from hibernalTrain.feel import FEEL_FIELDS, personaRecall
from hibernalTrain.rollout import SLOTS, holdActions

POLICY_SLOT = 0
TEACHER = "teacher"
REGIONS = ("worker", "fighter", "survivor")
OWNERS = ("devoted", "casual", "absent")
LATE_BORN_EPOCH = 60


def field(counters, name):
    return counters[:, FEEL_FIELDS.index(name)].astype(np.float64)


def ratio(above, below):
    return float(above) / float(below) if below else float("nan")


def verdict(value, low, high):
    if low is None and high is None:
        return "info"
    if np.isnan(value):
        return "n/a"
    inside = (low is None or value >= low) and (high is None or value <= high)
    return "ok" if inside else "OFF"


def bounds(low, high):
    if low is None and high is None:
        return "-"
    if low is None:
        return f"<= {high:g}"
    if high is None:
        return f">= {low:g}"
    return f"{low:g}..{high:g}"


def play(arguments):
    env = HibernalEnv(seed=arguments.seed, envCount=arguments.worlds, epochs=arguments.epochs)
    if arguments.policy == TEACHER:
        env.assignAll(lambda index, slot: CONTROL_TEACHER)
    else:
        with open(f"checkpoints/{arguments.policy}.policy", "rb") as source:
            env.loadPolicy(POLICY_SLOT, source.read())
        env.assignAll(lambda index, slot: POLICY_SLOT)
    owners = env.ownerKinds()
    while env.episode == 0:
        closing = env.epoch == arguments.epochs and env.head == 2
        if closing:
            stats = env.stats()
        env.step(holdActions(env, env.head))
    return env, stats, env.feel(len(FEEL_FIELDS)), owners


def ownerRows(counters, owners):
    rows = []
    for kind, name in enumerate(OWNERS):
        mine = counters[owners == kind]
        days = field(mine, "livingEpochs").sum()
        lives = field(mine, "lives").sum()
        early = field(mine, "starved").sum() + field(mine, "bitten").sum() + field(mine, "diedAttacking").sum()
        living = field(mine, "living") > 0
        rows += [
            (f"{name} owners: share of pets, %", 100 * ratio(len(mine), len(counters)), None, None, "SIM B"),
            (f"{name} owners: mean bonding", ratio(field(mine, "bondingSum").sum(), days), None, None, "SIM B2"),
            (f"{name} owners: gift HBRN per pet-day", ratio(field(mine, "gifted").sum(), days), None, None, "SIM B2"),
            (f"{name} owners: gifts, % of the pet's income", 100 * ratio(field(mine, "gifted").sum(), field(mine, "earned").sum()), None, None, "SIM B2"),
            (f"{name} owners: SKR per pet-day", ratio(field(mine, "skr").sum(), days), None, None, "SIM B3"),
            (f"{name} owners: gift HBRN per SKR", ratio(field(mine, "gifted").sum(), field(mine, "skr").sum()), None, None, "SIM B3"),
            (f"{name} owners: early deaths per 100 lives", 100 * ratio(early, lives), None, None, "SIM B"),
            (f"{name} owners: insurance revivals per 100 lives", 100 * ratio(field(mine, "revived").sum(), lives), None, None, "BRIEF 3.5"),
            (f"{name} owners: refused meals", field(mine, "ownerRefusals").sum(), None, None, "SIM B1"),
            (f"{name} owners: wealth median", float(np.median(field(mine, "wealth")[living])) if living.any() else float("nan"), None, None, "SIM B"),
        ]
    return rows


def scorecard(counters, stats, epochs):
    slots = np.arange(len(counters)) % SLOTS
    regions = slots % 3
    personas = (slots // 3) % 3
    lives = field(counters, "lives").sum()
    starved = field(counters, "starved").sum()
    early = starved + field(counters, "bitten").sum() + field(counters, "diedAttacking").sum()
    attacks = field(counters, "attacks").sum()
    livingDays = field(counters, "livingEpochs").sum()
    earned = field(counters, "earned")
    living = field(counters, "living") > 0
    wealth = field(counters, "wealth")[living]
    median = np.median(wealth) if len(wealth) else float("nan")
    born = field(counters, "bornAtEnd")[living]
    topQuartile = np.percentile(wealth, 75) if len(wealth) else float("nan")
    late = born >= LATE_BORN_EPOCH
    vengeful = personas == PERSONAS.index("vengeful")
    days = field(counters, "livingEpochs")
    dailyIncome = earned[days > 0] / days[days > 0]
    rows = [
        ("illegal actions", stats["illegal"], 0, 0, "gate"),
        ("starved with food or money", field(counters, "starvedStocked").sum(), 0, 0, "SIM A7"),
        ("starved, any", starved, None, None, "SIM A7"),
        ("early deaths per 100 lives", 100 * ratio(early, lives), None, None, "SIM A7"),
        ("age at level 10, mean", ratio(field(counters, "earlyLevelAgeSum").sum(), field(counters, "earlyLevelLives").sum()), 5, 10, "BRIEF 6.1"),
        ("age at level 20, mean", ratio(field(counters, "capLevelAgeSum").sum(), field(counters, "capLevelLives").sum()), 24, 40, "BRIEF 6.1"),
        ("lives reaching level 20, %", 100 * ratio(field(counters, "capLevelLives").sum(), lives), None, None, "BRIEF 6.1"),
        ("food bill at level 20, % of income", 100 * ratio(field(counters, "foodSpentAtCap").sum(), field(counters, "earnedAtCap").sum()), 60, 70, "BRIEF 6.2"),
        ("food bill, all levels, % of income", 100 * ratio(field(counters, "foodSpent").sum(), earned.sum()), None, None, "BRIEF 6.2"),
        ("wealth p90 / median", ratio(np.percentile(wealth, 90), median), 2.0, 3.2, "BRIEF 6.3"),
        ("wealth p99 / median", ratio(np.percentile(wealth, 99), median), 3.0, 5.0, "BRIEF 6.3"),
        ("wealth top / median", ratio(wealth.max(), median), 10.0, None, "BRIEF 6.3"),
        ("income per day p90 / median", ratio(np.percentile(dailyIncome, 90), np.median(dailyIncome)), 2.0, 3.2, "BRIEF 6.3"),
        ("income per day p99 / median", ratio(np.percentile(dailyIncome, 99), np.median(dailyIncome)), 3.0, 5.0, "BRIEF 6.3"),
        ("income per day top / median", ratio(dailyIncome.max(), np.median(dailyIncome)), 10.0, None, "BRIEF 6.3"),
        ("born day 60+ in the top wealth quartile, %", 100 * ratio((wealth[late] >= topQuartile).sum(), late.sum()), 5, None, "BRIEF 6.4"),
    ]
    for region, name in enumerate(REGIONS):
        mine = regions == region
        perDay = ratio(earned[mine].sum(), field(counters[mine], "livingEpochs").sum())
        rows.append((f"income per day, {name} start", perDay, None, None, "BRIEF 6.5"))
    regionWealth = [np.median(field(counters[regions == region], "wealth")[living[regions == region]]) for region in range(3)]
    rows += [
        ("wealth median, highest / lowest start", ratio(max(regionWealth), min(regionWealth)), 1.0, 1.5, "SIM F2"),
        ("item mints per life", ratio(field(counters, "mints").sum(), lives), None, None, "BRIEF 3.12"),
        ("item spend, % of income", 100 * ratio(field(counters, "mintSpent").sum(), earned.sum()), None, None, "BRIEF 3.12"),
        ("gear bonus, mean bps per pet-day", ratio(field(counters, "gearBonusSum").sum(), livingDays), None, None, "BRIEF 3.12"),
        ("loot lost, % of income", 100 * ratio(field(counters, "lootLost").sum(), earned.sum()), None, None, "SIM C6"),
        ("attacks under 40% odds, %", 100 * ratio(field(counters, "recklessAttacks").sum(), attacks), None, 1.0, "SIM C1"),
        ("attacks per pet per day", ratio(attacks, livingDays), None, None, "SIM C"),
        ("incoming fights per pet per day", ratio(field(counters, "fightsInSum").sum(), livingDays), None, None, "SIM C2"),
        ("pet-days at the incoming cap, %", 100 * ratio(field(counters, "fightsInCapDays").sum(), livingDays), None, None, "SIM C2"),
        ("robberies by the same robber within 3 days, %", 100 * ratio(field(counters, "robbedAgain").sum(), field(counters, "robbed").sum()), None, None, "SIM D1"),
        ("vengeful revenge within 3 days, %", 100 * ratio(field(counters[vengeful], "avenged").sum(), field(counters[vengeful], "robbed").sum()), None, None, "SIM D1"),
        ("persona told from one log with revenge, balanced", float(np.mean(personaRecall(counters, personas, True))), 0.9, None, "SIM D2"),
    ]
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", default=TEACHER)
    parser.add_argument("--worlds", type=int, default=8)
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--seed", type=int, default=9001)
    parser.add_argument("--save", default="")
    arguments = parser.parse_args()
    started = time.perf_counter()
    env, stats, counters, owners = play(arguments)
    if arguments.save:
        np.save(arguments.save, counters)
    print(
        f"health {arguments.policy} · engine {env.engineVersion} · {arguments.worlds} worlds x {env.blocks * SLOTS} pets "
        f"x {arguments.epochs} days · seed {arguments.seed} · {time.perf_counter() - started:.0f}s"
    )
    off = 0
    for name, value, low, high, source in scorecard(counters, stats, arguments.epochs) + ownerRows(counters, owners):
        mark = verdict(float(value), low, high)
        off += mark == "OFF"
        print(f"{name:44s} {float(value):10.2f}  target {bounds(low, high):>10s}  {mark:4s}  {source}")
    print(f"{off} off target")


main()
