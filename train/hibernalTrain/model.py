import struct

import numpy as np
import torch
from torch import nn

from .env import SELF_FEATURES

POLICY_MAGIC = 0x4E524248
POLICY_FORMAT = 3
ACTIVATION_ONE = 128.0
ACTIVATION_MAX = 127.0
WEIGHT_MAX = 127.0
DEFAULT_SHIFT = 7
ECONOMY, NODE, ATTACK = 0, 1, 2
NODE_CANDIDATES, NODE_FEATURES = 65, 22
TARGET_CANDIDATES, TARGET_FEATURES = 11, 13
STAKE_LEVELS = 4
BUY_SMALL, EAT_SMALL, PORTION_SIZES = 2, 5, 3


def foldPortionSizes(logits, legal):
    folded = logits.clone()
    for smallest in (BUY_SMALL, EAT_SMALL):
        carried = logits[:, smallest]
        carrying = torch.zeros_like(legal[:, smallest])
        for action in range(smallest + PORTION_SIZES - 1, smallest - 1, -1):
            here = legal[:, action]
            value = logits[:, action]
            folded[:, action] = torch.where(here & carrying, torch.maximum(value, carried), value)
            carried = torch.where(carrying, torch.maximum(carried, value), value)
            carrying = ~here
    return folded


def straightThrough(value, quantized):
    return quantized.detach() + (value - value.detach())


class QuantDense(nn.Module):
    def __init__(self, inputs, outputs, activate, shift=DEFAULT_SHIFT):
        super().__init__()
        bound = 1.0 / np.sqrt(inputs)
        self.weight = nn.Parameter(torch.empty(outputs, inputs).uniform_(-bound, bound))
        self.bias = nn.Parameter(torch.zeros(outputs))
        self.activate = activate
        self.shift = shift

    def integerWeights(self):
        scale = float(1 << self.shift)
        weight = torch.clamp(torch.round(self.weight * scale), -WEIGHT_MAX, WEIGHT_MAX)
        bias = torch.round(self.bias * scale * ACTIVATION_ONE)
        return weight, bias

    def forward(self, inputs):
        scale = float(1 << self.shift)
        weight, bias = self.integerWeights()
        weight = straightThrough(self.weight, weight / scale)
        bias = straightThrough(self.bias, bias / (scale * ACTIVATION_ONE))
        exact = nn.functional.linear(inputs, weight, bias)
        outputs = straightThrough(exact, torch.floor(exact * ACTIVATION_ONE) / ACTIVATION_ONE)
        if self.activate:
            outputs = torch.clamp(outputs, 0.0, ACTIVATION_MAX / ACTIVATION_ONE)
        return outputs

    def toBytes(self):
        weight, bias = self.integerWeights()
        weights = weight.detach().to(torch.int8).numpy().tobytes()
        biases = bias.detach().to(torch.int32).numpy().astype("<i4").tobytes()
        return bytes([self.shift]) + weights + biases


def stack(*layers):
    return nn.Sequential(*layers)


class PetPolicy(nn.Module):
    def __init__(self, selfInputIndexes):
        super().__init__()
        self.register_buffer("nodeSelf", torch.tensor(selfInputIndexes[NODE], dtype=torch.long))
        self.register_buffer("attackSelf", torch.tensor(selfInputIndexes[ATTACK], dtype=torch.long))
        self.economy = stack(QuantDense(SELF_FEATURES, 32, True), QuantDense(32, 10, False))
        self.node = stack(QuantDense(30, 32, True), QuantDense(32, 1, False))
        self.attack = stack(QuantDense(25, 32, True), QuantDense(32, 16, True), QuantDense(16, 4, False))
        self.critic = stack(nn.Linear(SELF_FEATURES, 64), nn.Tanh(), nn.Linear(64, 64), nn.Tanh(), nn.Linear(64, 1))

    def candidates(self, observations, selfIndexes, count, features):
        own = observations[:, selfIndexes].unsqueeze(1).expand(-1, count, -1)
        rows = observations[:, SELF_FEATURES:].reshape(-1, count, features)
        return torch.cat([own, rows], dim=2)

    def logits(self, head, observations):
        inputs = observations.to(torch.float32) / ACTIVATION_ONE
        if head == ECONOMY:
            return self.economy(inputs)
        if head == NODE:
            scored = self.node(self.candidates(inputs, self.nodeSelf, NODE_CANDIDATES, NODE_FEATURES))
            return scored.squeeze(2)
        scored = self.attack(self.candidates(inputs, self.attackSelf, TARGET_CANDIDATES, TARGET_FEATURES))
        attacks = scored[:, : TARGET_CANDIDATES - 1, :].reshape(-1, (TARGET_CANDIDATES - 1) * STAKE_LEVELS)
        return torch.cat([attacks, scored[:, TARGET_CANDIDATES - 1, :1]], dim=1)

    def integerLogits(self, head, observations):
        return torch.round(self.logits(head, observations) * ACTIVATION_ONE).to(torch.int32)

    def maskedLogits(self, head, observations, legal):
        logits = self.logits(head, observations)
        if head == ECONOMY:
            logits = foldPortionSizes(logits, legal)
        return logits.masked_fill(~legal, -1e9)

    def value(self, observations):
        inputs = observations[:, :SELF_FEATURES].to(torch.float32) / ACTIVATION_ONE
        return self.critic(inputs).squeeze(1)

    def toBytes(self, engineVersion):
        header = struct.pack("<iiQ", POLICY_MAGIC, POLICY_FORMAT, engineVersion)
        layers = [layer for head in (self.economy, self.node, self.attack) for layer in head]
        return header + b"".join(layer.toBytes() for layer in layers)
