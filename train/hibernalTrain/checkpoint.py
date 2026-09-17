from pathlib import Path

import torch

from .model import PetPolicy

CHECKPOINTS = Path(__file__).resolve().parents[1] / "checkpoints"


def save(name, policy, env, extra=None):
    CHECKPOINTS.mkdir(exist_ok=True)
    torch.save(
        {
            "engineVersion": env.engineVersion,
            "selfInputIndexes": env.selfInputIndexes,
            "state": policy.state_dict(),
            "extra": extra or {},
        },
        CHECKPOINTS / f"{name}.pt",
    )
    (CHECKPOINTS / f"{name}.policy").write_bytes(policy.toBytes(env.engineVersion))


def load(name, env):
    saved = torch.load(CHECKPOINTS / f"{name}.pt", weights_only=False)
    if saved["engineVersion"] != env.engineVersion:
        raise ValueError(
            f"checkpoint {name} was trained on engine {saved['engineVersion']}, the library is {env.engineVersion}"
        )
    if saved["selfInputIndexes"] != env.selfInputIndexes:
        raise ValueError(f"checkpoint {name} gathers different inputs than the library")
    policy = PetPolicy(env.selfInputIndexes)
    policy.load_state_dict(saved["state"])
    return policy, saved["extra"]
