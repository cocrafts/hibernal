import argparse
import time

import numpy as np
import torch

from hibernalTrain import checkpoint
from hibernalTrain.env import HEADS, HibernalEnv
from hibernalTrain.model import PetPolicy
from hibernalTrain.rollout import holdActions

STUDENT_SLOT = 0


def collect(env, play=None):
    samples = [{"observations": [], "legal": [], "actions": []} for _ in HEADS]
    episode = env.episode
    while env.episode == episode:
        head, observations, legal = env.observe()
        actions = env.teacherActions()
        choice = legal.sum(axis=1) > 1
        samples[head]["observations"].append(observations[choice].astype(np.int8))
        samples[head]["legal"].append(legal[choice].astype(bool))
        samples[head]["actions"].append(actions[choice].astype(np.int64))
        env.step(actions if play is None else play(env, head, legal))
    return [{key: np.concatenate(parts) for key, parts in bucket.items()} for bucket in samples]


def studentPlay(env, head, legal):
    logits = env.policyLogits(STUDENT_SLOT)
    best = np.where(legal.astype(bool), logits, np.iinfo(np.int32).min).argmax(axis=1)
    return np.where(legal.any(axis=1), best, holdActions(env, head)).astype(np.int32)


def collectStudent(seed, envCount, policy, engineVersion):
    env = HibernalEnv(seed=seed, envCount=envCount)
    env.loadPolicy(STUDENT_SLOT, policy.toBytes(engineVersion))
    return collect(env, studentPlay)


def merged(first, second):
    return [{key: np.concatenate([mine[key], theirs[key]]) for key in mine} for mine, theirs in zip(first, second)]


def accuracy(policy, head, data, batch=65536):
    hits = 0
    recalls = {}
    with torch.no_grad():
        for start in range(0, len(data["actions"]), batch):
            part = slice(start, start + batch)
            logits = policy.maskedLogits(
                head, torch.from_numpy(data["observations"][part]), torch.from_numpy(data["legal"][part])
            )
            chosen = logits.argmax(dim=1).numpy()
            wanted = data["actions"][part]
            hits += int((chosen == wanted).sum())
            for action in np.unique(wanted):
                seen, right = recalls.get(int(action), (0, 0))
                mine = wanted == action
                recalls[int(action)] = (seen + int(mine.sum()), right + int((chosen[mine] == action).sum()))
    macro = float(np.mean([right / seen for seen, right in recalls.values()]))
    return hits / max(len(data["actions"]), 1), macro


def labelWeights(actions, count, balance):
    if balance == 0:
        return None
    seen = np.bincount(actions, minlength=count).astype(np.float64)
    present = seen > 0
    weights = np.zeros(count)
    weights[present] = (seen[present].mean() / seen[present]) ** balance
    return torch.from_numpy(weights / weights[present].mean()).to(torch.float32)


def clone(policy, head, data, steps, batch, learningRate, balance):
    parameters = list([policy.economy, policy.node, policy.attack][head].parameters())
    optimizer = torch.optim.Adam(parameters, lr=learningRate)
    schedule = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, steps)
    observations = torch.from_numpy(data["observations"])
    legal = torch.from_numpy(data["legal"])
    actions = torch.from_numpy(data["actions"])
    weights = labelWeights(data["actions"], data["legal"].shape[1], balance)
    recent = []
    for _ in range(steps):
        part = torch.randint(0, len(actions), (batch,))
        logits = policy.maskedLogits(head, observations[part], legal[part])
        loss = torch.nn.functional.cross_entropy(logits, actions[part], weight=weights)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        schedule.step()
        recent = (recent + [float(loss.detach())])[-50:]
    return sum(recent) / len(recent)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--envs", type=int, default=16)
    parser.add_argument("--steps", type=int, default=4000)
    parser.add_argument("--batch", type=int, default=2048)
    parser.add_argument("--learningRate", type=float, default=3e-3)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--name", default="bc")
    parser.add_argument("--studentRounds", type=int, default=2)
    parser.add_argument("--balance", type=float, default=0.5, help="label weight (mean count / count) ** balance")
    arguments = parser.parse_args()
    torch.manual_seed(arguments.seed)
    started = time.perf_counter()
    env = HibernalEnv(seed=arguments.seed, envCount=arguments.envs)
    train = collect(env)
    heldOut = collect(HibernalEnv(seed=arguments.seed + 1000, envCount=max(arguments.envs // 4, 1)))
    print(f"collected in {time.perf_counter() - started:.0f}s · engine {env.engineVersion}")
    engineVersion = env.engineVersion
    policy = PetPolicy(env.selfInputIndexes)
    for studentRound in range(arguments.studentRounds + 1):
        for head, name in enumerate(HEADS):
            clock = time.perf_counter()
            loss = clone(
                policy, head, train[head], arguments.steps, arguments.batch, arguments.learningRate, arguments.balance
            )
            trainAccuracy, _ = accuracy(policy, head, train[head])
            heldAccuracy, heldRecall = accuracy(policy, head, heldOut[head])
            print(
                f"round {studentRound} {name:8s} samples {len(train[head]['actions']):8d} loss {loss:.3f} "
                f"accuracy train {trainAccuracy:.3f} held-out {heldAccuracy:.3f} macro recall {heldRecall:.3f} "
                f"({time.perf_counter() - clock:.0f}s)"
            )
        if studentRound == arguments.studentRounds:
            break
        clock = time.perf_counter()
        visited = collectStudent(arguments.seed + 1 + studentRound, arguments.envs, policy, engineVersion)
        for head, name in enumerate(HEADS):
            visitedAccuracy, visitedRecall = accuracy(policy, head, visited[head])
            print(
                f"round {studentRound} {name:8s} states the student reached {len(visited[head]['actions']):8d} "
                f"teacher agreement {visitedAccuracy:.3f} macro recall {visitedRecall:.3f}"
            )
        train = merged(train, visited)
        print(f"student round {studentRound} collected in {time.perf_counter() - clock:.0f}s")
    checkpoint.save(arguments.name, policy, env)
    print(f"saved checkpoints/{arguments.name}.pt and .policy")


main()
