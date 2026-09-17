import numpy as np
import torch

from .env import DONE_DIED, DONE_TRUNCATED, HEADS, SELF_FEATURES

SLOTS = 10
REWARD_UNIT = 1_000_000.0


def holdActions(env, head):
    return np.full(env.rows, env.actionCounts[head] - 1 if head else 0, dtype=np.int32)


class Rollout:
    def __init__(self, env):
        self.env = env
        steps = env.stepsPerEpisode
        self.selfObservations = np.zeros((steps, env.rows, SELF_FEATURES), dtype=np.int8)
        self.values = np.zeros((steps, env.rows), dtype=np.float32)
        self.rewards = np.zeros((steps, env.rows), dtype=np.float32)
        self.dones = np.zeros((steps, env.rows), dtype=np.int8)
        self.active = np.zeros((steps, env.rows), dtype=bool)
        self.choices = [
            {"observations": [], "legal": [], "actions": [], "logProbabilities": [], "steps": [], "rows": []}
            for _ in HEADS
        ]

    def collect(self, policy):
        env = self.env
        episode = env.episode
        step = 0
        while env.episode == episode:
            head, observations, legal = env.observe()
            legalCount = legal.sum(axis=1)
            active = legalCount > 0
            actions = holdActions(env, head)
            with torch.no_grad():
                observed = torch.from_numpy(observations)
                self.values[step] = policy.value(observed).numpy()
                choosing = np.flatnonzero(legalCount > 1)
                if len(choosing) > 0:
                    allowed = torch.from_numpy(legal[choosing].astype(bool))
                    logits = policy.maskedLogits(head, observed[choosing], allowed)
                    distribution = torch.distributions.Categorical(logits=logits)
                    sampled = distribution.sample()
                    bucket = self.choices[head]
                    bucket["observations"].append(observations[choosing].astype(np.int8))
                    bucket["legal"].append(allowed.numpy())
                    bucket["actions"].append(sampled.numpy())
                    bucket["logProbabilities"].append(distribution.log_prob(sampled).numpy())
                    bucket["steps"].append(np.full(len(choosing), step, dtype=np.int32))
                    bucket["rows"].append(choosing.astype(np.int32))
                    actions[choosing] = sampled.numpy().astype(np.int32)
            forced = np.flatnonzero(legalCount == 1)
            actions[forced] = legal[forced].argmax(axis=1).astype(np.int32)
            rewards, dones = env.step(actions)
            self.selfObservations[step] = observations[:, :SELF_FEATURES]
            self.rewards[step] = rewards / REWARD_UNIT
            self.dones[step] = dones
            self.active[step] = active
            step += 1
        return self

    def perPet(self, values):
        rounds = values.shape[0] // (SLOTS * len(HEADS))
        shaped = values.reshape(rounds, SLOTS, len(HEADS), self.env.rows)
        return shaped.transpose(0, 2, 1, 3).reshape(rounds * len(HEADS), SLOTS * self.env.rows)

    def fromPerPet(self, values):
        rounds = values.shape[0] // len(HEADS)
        shaped = values.reshape(rounds, len(HEADS), SLOTS, self.env.rows)
        return shaped.transpose(0, 2, 1, 3).reshape(rounds * SLOTS * len(HEADS), self.env.rows)

    def advantages(self, discount, smoothing):
        rewards = self.perPet(self.rewards).copy()
        values = self.perPet(self.values)
        dones = self.perPet(self.dones)
        active = self.perPet(self.active)
        terminal = (dones == DONE_DIED) & active
        truncated = (dones == DONE_TRUNCATED) & active
        pets = np.arange(rewards.shape[1])
        lastActive = np.full(rewards.shape[1], -1)
        for step in range(rewards.shape[0]):
            orphan = ~active[step] & (lastActive >= 0) & ((rewards[step] != 0) | (dones[step] == DONE_DIED))
            rewards[lastActive[orphan], pets[orphan]] += rewards[step, orphan]
            terminal[lastActive[orphan], pets[orphan]] |= dones[step, orphan] == DONE_DIED
            lastActive[active[step]] = step
            lastActive[~active[step] & (dones[step] == DONE_DIED)] = -1
        advantages = np.zeros_like(rewards)
        nextValue = np.zeros(rewards.shape[1], dtype=np.float32)
        nextAdvantage = np.zeros(rewards.shape[1], dtype=np.float32)
        for step in range(rewards.shape[0] - 1, -1, -1):
            here = active[step]
            ends = terminal[step] | truncated[step]
            bootstrap = np.where(terminal[step], 0.0, np.where(truncated[step], values[step], nextValue))
            delta = rewards[step] + discount * bootstrap - values[step]
            advantage = delta + discount * smoothing * np.where(ends, 0.0, nextAdvantage)
            advantages[step] = np.where(here, advantage, 0.0)
            nextValue = np.where(here, values[step], nextValue)
            nextAdvantage = np.where(here, advantage, nextAdvantage)
        returns = advantages + values
        return self.fromPerPet(advantages), self.fromPerPet(returns)

    def choiceBatch(self, head):
        bucket = self.choices[head]
        if not bucket["actions"]:
            return None
        return {key: np.concatenate(parts) for key, parts in bucket.items()}

    def rewardPerPet(self):
        return float(self.rewards.sum() * REWARD_UNIT / 1000.0 / (self.env.rows * SLOTS))
