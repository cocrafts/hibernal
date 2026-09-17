import argparse
import time

import numpy as np

from hibernalTrain.env import CONTROL_TEACHER, DONE_DIED, HEADS, HibernalEnv
from hibernalTrain.rollout import SLOTS, holdActions

POLICY_SLOT = 0
GROUPS = ("policy world", "teacher world", "mixed world")


def controllerFor(group, slot):
    if group == 0:
        return POLICY_SLOT
    if group == 1:
        return CONTROL_TEACHER
    return POLICY_SLOT if slot % 2 == 0 else CONTROL_TEACHER


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
    reward = np.zeros((worlds, SLOTS))
    died = np.zeros((worlds, SLOTS), dtype=np.int64)
    wasDead = np.zeros((env.rows, SLOTS), dtype=bool)
    step = 0
    lastStats = [None] * worlds
    while env.episode == 0:
        head = env.head
        slot = (step // len(HEADS)) % SLOTS
        closing = env.epoch == arguments.epochs and step % (SLOTS * len(HEADS)) == SLOTS * len(HEADS) - 1
        if closing:
            lastStats = [env.stats(index) for index in range(worlds)]
        rewards, dones = env.step(holdActions(env, head))
        reward[:, slot] += rewards.reshape(worlds, env.blocks).sum(axis=1) / 1000.0
        dead = dones == DONE_DIED
        died[:, slot] += (dead & ~wasDead[:, slot]).reshape(worlds, env.blocks).sum(axis=1)
        wasDead[:, slot] = dead
        step += 1
    print(f"policy {arguments.policy} · engine {env.engineVersion} · {worlds} worlds x {env.blocks * SLOTS} pets · {time.perf_counter() - started:.0f}s")
    for group, name in enumerate(GROUPS):
        mine = np.arange(worlds) % len(GROUPS) == group
        stats = [lastStats[index] for index in np.flatnonzero(mine)]
        total = {key: sum(world[key] for world in stats) for key in stats[0]}
        pets = mine.sum() * env.blocks
        line = (
            f"{name:13s} fights/pet {total['fights'] / (pets * SLOTS):5.2f} attacker wins {total['wins'] / max(total['fights'], 1):.2f} "
            f"illegal {total['illegal']} level {total['levels'] / max(total['living'], 1):.1f}"
        )
        if group < 2:
            print(f"{line} · score {reward[mine].sum() / (pets * SLOTS):8.0f} HBRN/pet · deaths {died[mine].sum()}")
            continue
        policySlots = np.arange(SLOTS) % 2 == 0
        print(
            f"{line} · policy {reward[mine][:, policySlots].sum() / (pets * policySlots.sum()):8.0f} "
            f"vs teacher {reward[mine][:, ~policySlots].sum() / (pets * (~policySlots).sum()):8.0f} HBRN/pet · "
            f"deaths {died[mine][:, policySlots].sum()} vs {died[mine][:, ~policySlots].sum()}"
        )


main()
