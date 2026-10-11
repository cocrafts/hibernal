import sys
import time

import numpy as np

from hibernalTrain.env import HEADS, HibernalEnv

envCount = int(sys.argv[1]) if len(sys.argv) > 1 else 16
epochs = int(sys.argv[2]) if len(sys.argv) > 2 else 120
withTeacher = len(sys.argv) <= 3 or sys.argv[3] != "hold"
started = time.perf_counter()
env = HibernalEnv(seed=7, envCount=envCount, epochs=epochs)
print(f"engine {env.engineVersion} rows {env.rows} reset+version {time.perf_counter() - started:.2f}s")
spent = {"observe": [0.0] * 3, "teacher": [0.0] * 3, "step": [0.0] * 3}
rewardTotal = 0
truncated = 0
legalBroken = 0
steps = 0
while env.episode == 0:
    clock = time.perf_counter()
    head, observations, legal = env.observe()
    spent["observe"][head] += time.perf_counter() - clock
    clock = time.perf_counter()
    if withTeacher:
        actions = env.teacherActions()
        active = legal.sum(axis=1) > 0
        legalBroken += int((legal[np.arange(env.rows), actions] == 0)[active].sum())
    else:
        actions = np.full(env.rows, [0, 24, 40][head], dtype=np.int32)
    spent["teacher"][head] += time.perf_counter() - clock
    if env.epoch == epochs and head == 2:
        lastStats = env.stats()
    clock = time.perf_counter()
    rewards, dones = env.step(actions)
    spent["step"][head] += time.perf_counter() - clock
    rewardTotal += int(rewards.sum())
    truncated += int((dones == 2).sum())
    steps += 1
elapsed = time.perf_counter() - started
print(f"steps {steps} of {env.stepsPerEpisode} · {elapsed:.1f}s · {steps * env.rows / elapsed:,.0f} row-steps/s")
for phase, byHead in spent.items():
    print(phase, " ".join(f"{HEADS[head]} {seconds / (steps / 3) * 1e6:.0f}us" for head, seconds in enumerate(byHead)))
print(f"teacher actions outside the mask {legalBroken} · truncated rows {truncated} · reward/pet {rewardTotal / (env.rows * 10) / 1000:.0f} brain units")
print("stats near the end", lastStats)
