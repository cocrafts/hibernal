import numpy as np
import torch

from hibernalTrain.env import HEADS, HibernalEnv
from hibernalTrain.model import ECONOMY, PetPolicy, foldPortionSizes

torch.manual_seed(3)
env = HibernalEnv(seed=11, envCount=2, epochs=20)
policy = PetPolicy(env.selfInputIndexes)
with torch.no_grad():
    for parameter in policy.parameters():
        parameter.mul_(3.0)
policyBytes = policy.toBytes(env.engineVersion)
env.loadPolicy(0, policyBytes)
try:
    env.loadPolicy(1, policyBytes[:8] + bytes(8) + policyBytes[16:])
    print("stale engine version accepted: WRONG")
except ValueError as refused:
    print("stale engine version refused:", refused)
compared = [0, 0, 0]
mismatched = [0, 0, 0]
while env.episode == 0:
    head, observations, legal = env.observe()
    if env.epoch % 3 == 0:
        allowed = legal == 1
        ours = policy.integerLogits(head, torch.from_numpy(observations))
        if head == ECONOMY:
            ours = foldPortionSizes(ours, torch.from_numpy(allowed))
        ours = ours.numpy()
        theirs = env.policyLogits(0)
        compared[head] += int(allowed.sum())
        mismatched[head] += int((ours[allowed] != theirs[allowed]).sum())
    env.step(env.teacherActions())
for head, name in enumerate(HEADS):
    print(f"{name}: {compared[head]} legal logits compared, {mismatched[head]} differ")
print("policy bytes", len(policyBytes))
