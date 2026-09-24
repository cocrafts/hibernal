import numpy as np

from .env import PERSONAS

FEEL_FIELDS = (
    "attacks",
    "attacksWon",
    "recklessAttacks",
    "underPersonaAttacks",
    "winChanceSum",
    "stakeShareSum",
    "burrowShareSum",
    "robbed",
    "avenged",
    "meals",
    "mealHeartsSum",
    "banks",
    "livingEpochs",
    "heartsSum",
    "starved",
    "starvedUnbanked",
    "starvedStocked",
    "bitten",
    "wealth",
    "living",
    "agedOut",
    "heartsBitten",
    "heartsLostAttacking",
    "lives",
    "diedAttacking",
    "earlyLevelLives",
    "earlyLevelAgeSum",
    "capLevelLives",
    "capLevelAgeSum",
    "earned",
    "earnedAtCap",
    "foodSpent",
    "foodSpentAtCap",
    "lootLost",
    "fightsInSum",
    "fightsInCapDays",
    "bornAtEnd",
    "bondingSum",
    "revived",
    "gifted",
    "skr",
    "ownerVisits",
    "ownerRefusals",
    "mints",
    "mintSpent",
    "gearBonusSum",
)
SLOTS = 10
PERSONA_OF_SLOT = np.array([(slot // 3) % 3 for slot in range(SLOTS)])
HEADER = (
    f"{'':24s} {'pets':>5s} {'fights':>6s} {'won':>5s} {'odds':>5s} {'<40%':>5s} {'<own':>5s} "
    f"{'stake':>5s} {'burrow':>6s} {'meals':>6s} {'at':>6s} {'hearts':>6s} {'robbed':>6s} {'avenged':>7s} "
    f"{'starved':>9s} {'bitten':>6s} {'aged':>5s} {'wealth':>7s} {'bite♥':>6s} {'lost♥':>6s}"
)


def ratio(above, below):
    return float(above) / float(below) if below else float("nan")


def feelLine(name, counters):
    total = {field: int(counters[:, index].sum()) for index, field in enumerate(FEEL_FIELDS)}
    pets = len(counters)
    attacks = total["attacks"]
    return (
        f"{name:24s} {pets:5d} {ratio(attacks, pets):6.2f} {ratio(total['attacksWon'], attacks):5.2f} "
        f"{ratio(total['winChanceSum'], attacks) / 100:5.1f} {ratio(total['recklessAttacks'], attacks) * 100:5.1f} "
        f"{ratio(total['underPersonaAttacks'], attacks) * 100:5.1f} {ratio(total['stakeShareSum'], attacks) / 100:5.1f} "
        f"{ratio(total['burrowShareSum'], attacks) / 100:6.1f} {ratio(total['meals'], pets):6.1f} "
        f"{ratio(total['mealHeartsSum'], total['meals']):6.2f} {ratio(total['heartsSum'], total['livingEpochs']):6.2f} "
        f"{ratio(total['robbed'], pets):6.2f} "
        f"{ratio(total['avenged'], total['robbed']) * 100:6.1f}% "
        f"{total['starved']:3d}/{total['starvedUnbanked']}/{total['starvedStocked']:<3d} {total['bitten']:6d} {total['agedOut']:5d} "
        f"{ratio(total['wealth'], total['living']):7.0f} {ratio(total['heartsBitten'], pets):6.2f} "
        f"{ratio(total['heartsLostAttacking'], pets):6.2f}"
    )


def personaFeatures(counters, revenge=False):
    field = {name: counters[:, index].astype(np.float64) for index, name in enumerate(FEEL_FIELDS)}
    attacks = np.maximum(field["attacks"], 1.0)
    meals = np.maximum(field["meals"], 1.0)
    columns = [
        field["attacks"],
        field["winChanceSum"] / attacks,
        field["stakeShareSum"] / attacks,
        field["burrowShareSum"] / attacks,
        field["meals"],
        field["mealHeartsSum"] / meals,
        field["banks"],
        field["heartsSum"] / np.maximum(field["livingEpochs"], 1.0),
    ]
    averaged = [(1, field["attacks"]), (2, field["attacks"]), (3, field["attacks"]), (5, field["meals"])]
    if revenge:
        columns.append(field["avenged"] / np.maximum(field["robbed"], 1.0))
        averaged.append((len(columns) - 1, field["robbed"]))
    features = np.stack(columns, axis=1)
    for column, count in averaged:
        seen = count > 0
        features[~seen, column] = features[seen, column].mean() if seen.any() else 0.0
    return (features - features.mean(axis=0)) / (features.std(axis=0) + 1e-9)


def personaRecall(counters, personas, revenge=False):
    features = personaFeatures(counters, revenge)
    present = [kind for kind in range(len(PERSONAS)) if (personas == kind).any()]
    centroids = np.stack([features[personas == kind].mean(axis=0) for kind in present])
    distances = ((features[:, None, :] - centroids[None, :, :]) ** 2).sum(axis=2)
    guessed = np.array(present)[distances.argmin(axis=1)]
    return [float((guessed[personas == kind] == kind).mean()) for kind in present]


def feelTable(counters, blocks, labelOf):
    worlds = len(counters) // (blocks * SLOTS)
    shaped = counters.reshape(worlds, blocks, SLOTS, len(FEEL_FIELDS))
    labels = [[labelOf(world, slot) for slot in range(SLOTS)] for world in range(worlds)]
    lines = [HEADER]
    for name in dict.fromkeys(label for row in labels for label in row):
        mine = np.array([[label == name for label in row] for row in labels])
        chosen = np.broadcast_to(mine[:, None, :], shaped.shape[:3])
        personas = np.broadcast_to(PERSONA_OF_SLOT[None, None, :], shaped.shape[:3])[chosen]
        rows = shaped[chosen]
        for kind, persona in enumerate(PERSONAS):
            lines.append(feelLine(f"{name} {persona}", rows[personas == kind]))
        for label, revenge in (("", False), (" with revenge", True)):
            recall = personaRecall(rows, personas, revenge)
            lines.append(
                f"{name}: persona told from one pet's log{label}, nearest centroid: "
                + " ".join(f"{PERSONAS[kind]} {value:.2f}" for kind, value in enumerate(recall))
                + f" · balanced {np.mean(recall):.2f} (chance 0.33)"
            )
    return lines
