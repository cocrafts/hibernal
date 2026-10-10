package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class SourcePetLifecycleTest {
    private fun record(profile: OwnerTransaction.SourceProfile, placed: Boolean, alive: Boolean,
        diedEpoch: Long = 0, generation: Int = 0): SourcePetRead.SourceOnlyDecodedPet {
        val canonical = profile == OwnerTransaction.SourceProfile.CANONICAL_B50E0B5
        val data = ByteArray(if (canonical) 304 else 272)
        byteArrayOf(0xdf.toByte(), 0xde.toByte(), 0x81.toByte(), 0x59, 0x46, 0xe7.toByte(), 0x8d.toByte(), 0xb8.toByte()).copyInto(data)
        val body = if (canonical) 128 else 96
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putLong(88, diedEpoch)
        buffer.putInt(body + 88, if (placed) 25 else -1)
        buffer.putShort(body + 126, generation.toShort())
        data[body + 128] = if (placed) 3 else 255.toByte()
        data[body + 129] = if (alive) 1 else 0
        val program = SolanaPublicKey(ByteArray(32) { 3 })
        return SourcePetRead.decodeSourceOnly(SolanaRpc.Account(program.address, BigInteger.ONE, false, data), program, profile)
    }

    @Test fun claimFalseAliveIsNotDeath() {
        for (profile in OwnerTransaction.SourceProfile.entries) {
            assertEquals(SourcePetLifecycle.Fact.CLAIMED_UNPLACED,
                SourcePetLifecycle.sourceFact(record(profile, false, false)))
        }
    }

    @Test fun activeLifeAndHeirRemainDistinct() {
        for (profile in OwnerTransaction.SourceProfile.entries) {
            assertEquals(SourcePetLifecycle.Fact.FIRST_LIFE_ACTIVE,
                SourcePetLifecycle.sourceFact(record(profile, true, true)))
            assertEquals(SourcePetLifecycle.Fact.HEIR_ACTIVE,
                SourcePetLifecycle.sourceFact(record(profile, true, true, generation = 1)))
        }
    }

    @Test fun falseAliveWithoutBurialDoesNotPromiseRecordedDeathOrHeir() {
        for (profile in OwnerTransaction.SourceProfile.entries) {
            assertEquals(SourcePetLifecycle.Fact.INACTIVE_WITHOUT_DEATH_RECORD,
                SourcePetLifecycle.sourceFact(record(profile, true, false)))
            assertEquals(SourcePetLifecycle.Fact.DEATH_RECORDED,
                SourcePetLifecycle.sourceFact(record(profile, true, false, diedEpoch = 28)))
        }
    }

    @Test fun unseatedHeirAwaitsPlacementAndUnseatedLostPetStaysDead() {
        for (profile in OwnerTransaction.SourceProfile.entries) {
            assertEquals(SourcePetLifecycle.Fact.CLAIMED_UNPLACED,
                SourcePetLifecycle.sourceFact(record(profile, false, true, generation = 1)))
            assertEquals(SourcePetLifecycle.Fact.DEATH_RECORDED,
                SourcePetLifecycle.sourceFact(record(profile, false, false, diedEpoch = 28)))
        }
    }

    @Test fun conflictingMarkersRefuseInsteadOfRepairOrReclaim() {
        for (profile in OwnerTransaction.SourceProfile.entries) {
            for (value in listOf(record(profile, false, true, 28), record(profile, true, true, 28))) {
                assertThrows(SolanaRpc.Failure::class.java) { SourcePetLifecycle.sourceFact(value) }
            }
        }
    }
}
