import ctypes
import subprocess
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
LIBRARY = REPO / "out" / "env" / ("libhibernal.dylib" if sys.platform == "darwin" else "libhibernal.so")
HEADS = ("economy", "node", "attack")
SELF_FEATURES = 46
FEATURE_ONE = 127
DONE_RUNNING, DONE_DIED, DONE_TRUNCATED = 0, 1, 2
CONTROL_LEARNER, CONTROL_TEACHER = -2, -1
PERSONAS = ("cautious", "greedy", "vengeful")
REWARD_TERMS = ("heart", "death", "comfort", "lossAversion")
STAT_FIELDS = ("fights", "wins", "deaths", "heirs", "illegal", "living", "levels", "wealth")


def buildLibrary(force=False):
    sources = list((REPO / "rules").glob("*.ms")) + list((REPO / "sim").rglob("*.ms"))
    newest = max(source.stat().st_mtime for source in sources)
    if not force and LIBRARY.exists() and LIBRARY.stat().st_mtime >= newest:
        return LIBRARY
    LIBRARY.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["msc", "build", "sim/env/ffi.ms", "--app=lib", "--release", f"--output={LIBRARY}"],
        cwd=REPO,
        check=True,
    )
    return LIBRARY


class HibernalEnv:
    def __init__(self, seed, envCount, blocks=20, epochs=120, library=None):
        lib = ctypes.CDLL(str(library or buildLibrary()))
        lib.MsMain()
        pointer = ctypes.c_void_p
        lib.hibernal_engine_version.restype = ctypes.c_uint64
        lib.hibernal_reset.argtypes = [ctypes.c_uint64, ctypes.c_int32, ctypes.c_int32, ctypes.c_int32]
        lib.hibernal_observe.argtypes = [ctypes.c_int32, pointer, pointer]
        lib.hibernal_teacher_actions.argtypes = [ctypes.c_int32, pointer]
        lib.hibernal_actors.argtypes = [pointer]
        lib.hibernal_owner_kinds.argtypes = [pointer]
        lib.hibernal_step.argtypes = [ctypes.c_int32, pointer, pointer, pointer]
        lib.hibernal_stats.argtypes = [ctypes.c_int32, pointer]
        lib.hibernal_load_policy.argtypes = [ctypes.c_int32, ctypes.c_char_p, ctypes.c_int32]
        lib.hibernal_policy_logits.argtypes = [ctypes.c_int32, pointer]
        lib.hibernal_feel.argtypes = [pointer, ctypes.c_int32]
        self.lib = lib
        self.engineVersion = int(lib.hibernal_engine_version())
        self.blocks = blocks
        self.epochs = epochs
        self.rows = lib.hibernal_reset(seed, envCount, blocks, epochs)
        if self.rows <= 0:
            raise ValueError("hibernal_reset refused the batch shape")
        self.observationSizes = [lib.hibernal_observation_size(head) for head in range(len(HEADS))]
        self.actionCounts = [lib.hibernal_action_count(head) for head in range(len(HEADS))]
        self.observations = [np.zeros((self.rows, size), dtype=np.int32) for size in self.observationSizes]
        self.legal = [np.zeros((self.rows, count), dtype=np.int32) for count in self.actionCounts]
        self.teacher = np.zeros(self.rows, dtype=np.int32)
        self.actorSlots = np.zeros(self.rows, dtype=np.int32)
        self.rewards = np.zeros(self.rows, dtype=np.int32)
        self.dones = np.zeros(self.rows, dtype=np.int32)
        self.statBuffer = np.zeros(len(STAT_FIELDS), dtype=np.int32)
        self.logits = [np.zeros((self.rows, count), dtype=np.int32) for count in self.actionCounts]
        self.selfInputIndexes = [
            [lib.hibernal_self_input(head, position) for position in range(lib.hibernal_self_inputs(head))]
            for head in range(len(HEADS))
        ]

    @property
    def head(self):
        return self.lib.hibernal_head()

    @property
    def epoch(self):
        return self.lib.hibernal_epoch()

    @property
    def episode(self):
        return self.lib.hibernal_episode()

    @property
    def stepsPerEpisode(self):
        return self.epochs * 4 * 10 * len(HEADS)

    def observe(self):
        head = self.head
        observations, legal = self.observations[head], self.legal[head]
        if self.lib.hibernal_observe(head, observations.ctypes.data, legal.ctypes.data) != self.rows:
            raise RuntimeError("hibernal_observe refused")
        return head, observations, legal

    def teacherActions(self):
        if self.lib.hibernal_teacher_actions(self.head, self.teacher.ctypes.data) != self.rows:
            raise RuntimeError("hibernal_teacher_actions refused")
        return self.teacher

    def actors(self):
        if self.lib.hibernal_actors(self.actorSlots.ctypes.data) != self.rows:
            raise RuntimeError("hibernal_actors refused")
        return self.actorSlots

    def ownerKinds(self):
        kinds = np.zeros(self.rows * 10, dtype=np.int32)
        if self.lib.hibernal_owner_kinds(kinds.ctypes.data) != kinds.size:
            raise RuntimeError("hibernal_owner_kinds refused")
        return kinds

    def step(self, actions):
        actions = np.ascontiguousarray(actions, dtype=np.int32)
        stepped = self.lib.hibernal_step(
            self.head, actions.ctypes.data, self.rewards.ctypes.data, self.dones.ctypes.data
        )
        if stepped != self.rows:
            raise RuntimeError("hibernal_step refused")
        return self.rewards, self.dones

    def stats(self, world=-1):
        if self.lib.hibernal_stats(world, self.statBuffer.ctypes.data) < 0:
            raise ValueError("hibernal_stats refused the world index")
        return dict(zip(STAT_FIELDS, (int(value) for value in self.statBuffer)))

    def feel(self, fields):
        counters = np.zeros((self.rows * 10, fields), dtype=np.int32)
        if self.lib.hibernal_feel(counters.ctypes.data, counters.size) != counters.size:
            raise RuntimeError("hibernal_feel refused: the counter list differs from sim/env/feel.ms")
        return counters

    def setReward(self, persona, term, value):
        if self.lib.hibernal_reward(PERSONAS.index(persona), REWARD_TERMS.index(term), int(value)) != 0:
            raise ValueError("hibernal_reward refused")

    def setRewards(self, text):
        for part in filter(None, text.split(",")):
            name, value = part.split("=")
            persona, term = name.split(".")
            self.setReward(persona, term, value)

    def loadPolicy(self, slot, policyBytes):
        loaded = self.lib.hibernal_load_policy(slot, policyBytes, len(policyBytes))
        if loaded != len(policyBytes):
            raise ValueError(f"hibernal_load_policy refused the policy: {loaded}")

    def assign(self, env, slot, controller):
        if self.lib.hibernal_assign(env, slot, controller) != 0:
            raise ValueError("hibernal_assign refused")

    def assignAll(self, controllerOfSlot):
        for env in range(self.rows // self.blocks):
            for slot in range(10):
                self.assign(env, slot, controllerOfSlot(env, slot))

    def policyLogits(self, slot):
        logits = self.logits[self.head]
        if self.lib.hibernal_policy_logits(slot, logits.ctypes.data) != self.rows:
            raise RuntimeError("hibernal_policy_logits refused")
        return logits
