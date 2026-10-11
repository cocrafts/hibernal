import argparse
import random
import time

import numpy as np
import torch

from hibernalTrain import checkpoint
from hibernalTrain.env import CONTROL_LEARNER, CONTROL_TEACHER, DONE_DIED, HEADS, SELF_FEATURES, HibernalEnv
from hibernalTrain.feel import FEEL_FIELDS
from hibernalTrain.model import PetPolicy
from hibernalTrain.rollout import SLOTS, Rollout

POOL_SLOTS = 6
WEALTH = FEEL_FIELDS.index("wealth")
LIVING = FEEL_FIELDS.index("living")


class Pool:
    def __init__(self, prioritized, generator):
        self.prioritized = prioritized
        self.generator = generator
        self.slots = []
        self.beaten = {}

    def weights(self):
        if not self.prioritized:
            return [1.0] * len(self.slots)
        return [(1.0 - self.beaten[slot]) ** 2 + 0.05 for slot in self.slots]

    def pick(self):
        return self.generator.choices(self.slots, weights=self.weights())[0]

    def record(self, slot, won):
        self.beaten[slot] = 0.7 * self.beaten[slot] + 0.3 * won

    def nextSlot(self):
        if len(self.slots) < POOL_SLOTS:
            return len(self.slots)
        if not self.prioritized:
            return self.generator.randrange(POOL_SLOTS)
        return max(self.slots, key=lambda slot: self.beaten[slot])

    def store(self, slot):
        if slot not in self.slots:
            self.slots.append(slot)
        self.beaten[slot] = 0.5

    def describe(self):
        return " ".join(f"{slot}:{self.beaten[slot]:.2f}" for slot in self.slots)


def assignOpponents(env, pool, alternate):
    controllers = np.full((env.rows // env.blocks, SLOTS), CONTROL_LEARNER, dtype=np.int32)
    for index in range(len(controllers)):
        kind = index % 4
        if kind == 0:
            continue
        opponent = CONTROL_TEACHER if kind == 1 or not pool.slots else pool.pick()
        parity = (index // 4 + 1) % 2 if alternate else 1
        controllers[index, parity::2] = opponent
    env.assignAll(lambda index, slot: int(controllers[index, slot]))
    return controllers


def wealthBySlot(env, before):
    counters = env.feel(len(FEEL_FIELDS)).astype(np.int64)
    gained = (counters - before).reshape(-1, env.blocks, SLOTS, len(FEEL_FIELDS)).sum(axis=1)
    return counters, gained[..., WEALTH] / np.maximum(gained[..., LIVING], 1)


def learnerWealth(wealth, controllers, pool):
    learner = controllers == CONTROL_LEARNER
    mixed = ~learner.all(axis=1)
    for index in np.flatnonzero(mixed):
        opponent = int(controllers[index][~learner[index]][0])
        if opponent in pool.beaten:
            pool.record(opponent, float(wealth[index][learner[index]].mean() > wealth[index][~learner[index]].mean()))
    return float(wealth[mixed][learner[mixed]].mean()), float(wealth[mixed][~learner[mixed]].mean())


def updateHead(policy, optimizer, head, batch, advantages, arguments):
    observations = torch.from_numpy(batch["observations"])
    legal = torch.from_numpy(batch["legal"])
    actions = torch.from_numpy(batch["actions"])
    before = torch.from_numpy(batch["logProbabilities"])
    teacher = torch.from_numpy(batch["teacher"]) if "teacher" in batch else None
    gains = torch.from_numpy(advantages[batch["steps"], batch["rows"]])
    gains = (gains - gains.mean()) / (gains.std() + 1e-8)
    count = len(actions)
    size = min(arguments.batch, max(512, count // 16))
    divergence = 0.0
    entropy = 0.0
    for _ in range(arguments.passes):
        order = torch.randperm(count)
        for start in range(0, count, size):
            part = order[start : start + size]
            distribution = torch.distributions.Categorical(
                logits=policy.maskedLogits(head, observations[part], legal[part])
            )
            logProbability = distribution.log_prob(actions[part])
            ratio = torch.exp(logProbability - before[part])
            clipped = torch.clamp(ratio, 1.0 - arguments.clip, 1.0 + arguments.clip)
            surrogate = torch.min(ratio * gains[part], clipped * gains[part]).mean()
            entropy = distribution.entropy().mean()
            loss = -surrogate - arguments.entropy * entropy
            if "teacher" in batch and arguments.imitation > 0:
                imitated = policy.maskedLogits(head, observations[part], legal[part])
                loss = loss + arguments.imitation * torch.nn.functional.cross_entropy(imitated, teacher[part])
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(policy.parameters(), 0.5)
            optimizer.step()
            divergence = float((before[part] - logProbability).mean().detach())
            if divergence > arguments.targetDivergence:
                return divergence, float(entropy.detach())
    return divergence, float(entropy.detach())


def updateCritic(policy, optimizer, rollout, returns, arguments):
    active = np.flatnonzero(rollout.active.reshape(-1))
    chosen = np.random.choice(active, size=min(len(active), arguments.criticSamples), replace=False)
    observations = torch.from_numpy(rollout.selfObservations.reshape(-1, SELF_FEATURES)[chosen])
    targets = torch.from_numpy(returns.reshape(-1)[chosen])
    loss = torch.zeros(())
    for _ in range(arguments.passes):
        order = torch.randperm(len(chosen))
        for start in range(0, len(chosen), arguments.batch):
            part = order[start : start + arguments.batch]
            loss = torch.nn.functional.smooth_l1_loss(policy.value(observations[part]), targets[part])
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
    explained = 1.0 - float(((targets - policy.value(observations).detach()) ** 2).mean() / (targets.var() + 1e-8))
    return float(loss.detach()), explained


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", default="bc")
    parser.add_argument("--name", default="ppo")
    parser.add_argument("--envs", type=int, default=8)
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--criticWarmup", type=int, default=1)
    parser.add_argument("--snapshotEvery", type=int, default=4)
    parser.add_argument("--learningRate", type=float, default=3e-4)
    parser.add_argument("--criticLearningRate", type=float, default=1e-3)
    parser.add_argument("--discount", type=float, default=0.999)
    parser.add_argument("--smoothing", type=float, default=0.95)
    parser.add_argument("--clip", type=float, default=0.2)
    parser.add_argument("--entropy", type=float, default=0.003)
    parser.add_argument("--targetDivergence", type=float, default=0.03)
    parser.add_argument("--passes", type=int, default=2)
    parser.add_argument("--batch", type=int, default=8192)
    parser.add_argument("--criticSamples", type=int, default=400000)
    parser.add_argument("--seed", type=int, default=5)
    parser.add_argument("--reward", default="")
    parser.add_argument("--pool", choices=("uniform", "prioritized"), default="uniform")
    parser.add_argument("--alternate", action="store_true")
    parser.add_argument("--threads", type=int, default=0)
    parser.add_argument("--imitation", type=float, default=0.0)
    arguments = parser.parse_args()
    if arguments.threads > 0:
        torch.set_num_threads(arguments.threads)
    torch.manual_seed(arguments.seed)
    np.random.seed(arguments.seed)
    generator = random.Random(arguments.seed)
    env = HibernalEnv(seed=arguments.seed, envCount=arguments.envs, epochs=arguments.epochs)
    env.setRewards(arguments.reward)
    policy, _ = checkpoint.load(arguments.start, env)
    heads = [policy.economy, policy.node, policy.attack]
    optimizers = [torch.optim.Adam(head.parameters(), lr=arguments.learningRate) for head in heads]
    criticOptimizer = torch.optim.Adam(policy.critic.parameters(), lr=arguments.criticLearningRate)
    pool = Pool(arguments.pool == "prioritized", generator)
    counters = env.feel(len(FEEL_FIELDS)).astype(np.int64)
    print(f"engine {env.engineVersion} rows {env.rows} start {arguments.start} reward {arguments.reward or 'default'}")
    for iteration in range(arguments.iterations):
        clock = time.perf_counter()
        controllers = assignOpponents(env, pool, arguments.alternate)
        rollout = Rollout(env, (0,) if arguments.imitation > 0 else ()).collect(policy)
        collected = time.perf_counter() - clock
        advantages, returns = rollout.advantages(arguments.discount, arguments.smoothing)
        criticLoss, explained = updateCritic(policy, criticOptimizer, rollout, returns, arguments)
        notes = []
        for head, name in enumerate(HEADS):
            batch = rollout.choiceBatch(head)
            if batch is None or iteration < arguments.criticWarmup:
                continue
            divergence, entropy = updateHead(policy, optimizers[head], head, batch, advantages, arguments)
            notes.append(f"{name} n {len(batch['actions'])} kl {divergence:.4f} ent {entropy:.2f}")
        counters, wealth = wealthBySlot(env, counters)
        mine, others = learnerWealth(wealth, controllers, pool)
        died = int((rollout.perPet(rollout.dones) == DONE_DIED).any(axis=0).sum())
        print(
            f"iteration {iteration:3d} mixed worlds: learner {mine:8.0f} others {others:8.0f} brain units/pet · died {died} · "
            f"critic {criticLoss:.3f} ev {explained:.2f} · {' · '.join(notes)} · pool {pool.describe()} · "
            f"collect {collected:.0f}s total {time.perf_counter() - clock:.0f}s",
            flush=True,
        )
        if (iteration + 1) % arguments.snapshotEvery == 0:
            slot = pool.nextSlot()
            env.loadPolicy(slot, policy.toBytes(env.engineVersion))
            pool.store(slot)
            checkpoint.save(f"{arguments.name}{iteration + 1:03d}", policy, env, {"iteration": iteration + 1})
    checkpoint.save(arguments.name, policy, env, {"iteration": arguments.iterations, "reward": arguments.reward})
    print(f"saved checkpoints/{arguments.name}.pt and .policy")


main()
