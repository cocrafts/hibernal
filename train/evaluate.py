import argparse
import time

import numpy as np

from hibernalTrain.env import CONTROL_TEACHER, HEADS, HibernalEnv
from hibernalTrain.feel import FEEL_FIELDS, feelTable
from hibernalTrain.rollout import SLOTS, holdActions

POLICY_SLOT = 0
GROUPS = ("policy world", "teacher world", "mixed, policy on even slots", "mixed, policy on odd slots")
WEALTH = FEEL_FIELDS.index("wealth")
LIVING = FEEL_FIELDS.index("living")
DEATHS = [FEEL_FIELDS.index("starved"), FEEL_FIELDS.index("bitten")]


def controllerFor(group, slot):
    if group == 0:
        return POLICY_SLOT
    if group == 1:
        return CONTROL_TEACHER
    return POLICY_SLOT if slot % 2 == group % 2 else CONTROL_TEACHER


def wealthPerPet(counters):
    return counters[..., WEALTH].sum() / max(counters[..., LIVING].sum(), 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", default="bc")
    parser.add_argument("--worlds", type=int, default=4)
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--seed", type=int, default=9001)
    arguments = parser.parse_args()
    started = time.perf_counter()
    env = HibernalEnv(seed=arguments.seed, envCount=arguments.worlds * len(GROUPS), epochs=arguments.epochs)
    with open(f"checkpoints/{arguments.policy}.policy", "rb") as source:
        env.loadPolicy(POLICY_SLOT, source.read())
    env.assignAll(lambda index, slot: controllerFor(index % len(GROUPS), slot))
    worlds = env.rows // env.blocks
    step = 0
    lastStats = [None] * worlds
    while env.episode == 0:
        closing = env.epoch == arguments.epochs and step % (SLOTS * len(HEADS)) == SLOTS * len(HEADS) - 1
        if closing:
            lastStats = [env.stats(index) for index in range(worlds)]
        env.step(holdActions(env, env.head))
        step += 1
    counters = env.feel(len(FEEL_FIELDS)).reshape(worlds, env.blocks, SLOTS, len(FEEL_FIELDS))
    print(f"policy {arguments.policy} · engine {env.engineVersion} · {worlds} worlds x {env.blocks * SLOTS} pets · {time.perf_counter() - started:.0f}s")
    policyWealth, teacherWealth = [], []
    for group, name in enumerate(GROUPS):
        mine = np.flatnonzero(np.arange(worlds) % len(GROUPS) == group)
        total = {key: sum(lastStats[index][key] for index in mine) for key in lastStats[mine[0]]}
        pets = len(mine) * env.blocks * SLOTS
        line = (
            f"{name:28s} fights/pet {total['fights'] / pets:5.2f} attacker wins {total['wins'] / max(total['fights'], 1):.2f} "
            f"illegal {total['illegal']} level {total['levels'] / max(total['living'], 1):.1f}"
        )
        if group < 2:
            print(f"{line} · wealth {wealthPerPet(counters[mine]):8.0f} HBRN/pet · deaths {counters[mine][..., DEATHS].sum()}")
            continue
        policySlots = np.arange(SLOTS) % 2 == group % 2
        policyWealth.append(wealthPerPet(counters[mine][:, :, policySlots]))
        teacherWealth.append(wealthPerPet(counters[mine][:, :, ~policySlots]))
        print(
            f"{line} · policy {policyWealth[-1]:8.0f} vs teacher {teacherWealth[-1]:8.0f} HBRN/pet · "
            f"deaths {counters[mine][:, :, policySlots][..., DEATHS].sum()} vs {counters[mine][:, :, ~policySlots][..., DEATHS].sum()}"
        )
    policyMean, teacherMean = np.mean(policyWealth), np.mean(teacherWealth)
    print(f"mixed, both sides of the block: policy {policyMean:8.0f} vs teacher {teacherMean:8.0f} HBRN/pet ({(policyMean / teacherMean - 1) * 100:+.1f}%)")

    def labelOf(world, slot):
        group = world % len(GROUPS)
        player = "teacher" if controllerFor(group, slot) == CONTROL_TEACHER else arguments.policy
        return f"{player} {'mixed' if group >= 2 else 'own'}"

    for line in feelTable(counters.reshape(-1, len(FEEL_FIELDS)), env.blocks, labelOf):
        print(line)


main()
