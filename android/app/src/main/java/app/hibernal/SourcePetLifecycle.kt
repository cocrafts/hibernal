package app.hibernal

import java.math.BigInteger

object SourcePetLifecycle {
    enum class Fact {
        CLAIMED_UNPLACED,
        FIRST_LIFE_ACTIVE,
        HEIR_ACTIVE,
        INACTIVE_WITHOUT_DEATH_RECORD,
        DEATH_RECORDED,
    }

    fun sourceFact(record: SourcePetRead.SourceOnlyDecodedPet): Fact {
        val pet = record.pet
        val deathRecorded = record.diedEpoch != BigInteger.ZERO
        if (pet.alive && deathRecorded) throw SolanaRpc.Failure("Alive source Pet still has death marker")
        if (deathRecorded) return Fact.DEATH_RECORDED
        if (pet.slot == SourcePetRead.Seat.Unplaced) return Fact.CLAIMED_UNPLACED
        if (pet.alive) return if (pet.lineageGeneration == 0) Fact.FIRST_LIFE_ACTIVE else Fact.HEIR_ACTIVE
        return Fact.INACTIVE_WITHOUT_DEATH_RECORD
    }
}
