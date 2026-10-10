package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class SourceWorldReadTest {
    private val program = SolanaPublicKey.from("B1zQCgVyS3qVUKCzRv6Rje79mou45fHuz7dc415ukh1o")
    private val profiles = OwnerTransaction.SourceProfile.entries
    private val maximum = BigInteger.ONE.shiftLeft(64).subtract(BigInteger.ONE)
    private val edges = listOf(BigInteger.ZERO, BigInteger.ONE,
        BigInteger.ONE.shiftLeft(63).subtract(BigInteger.ONE), BigInteger.ONE.shiftLeft(63), maximum)

    private fun account(data: ByteArray) = SolanaRpc.Account(program.address, maximum, false, data)
    private fun put64(data: ByteArray, offset: Int, value: BigInteger) {
        repeat(8) { data[offset + it] = value.shiftRight(it * 8).toByte() }
    }
    private fun put32(data: ByteArray, offset: Int, value: Long) {
        ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).putInt(offset, value.toInt())
    }
    private fun worldOffsets(profile: OwnerTransaction.SourceProfile): List<Int> = when (profile) {
        OwnerTransaction.SourceProfile.CANONICAL_B50E0B5 ->
            listOf(8, 16, 24, 32, 40, 48, 56, 64, 80, 88, 96, 104, 128)
        OwnerTransaction.SourceProfile.HISTORICAL_D09815C6 ->
            listOf(8, 16, 24, 32, 40, 48, 56, 72, 80, 88, 96, 120)
    }
    private fun world(profile: OwnerTransaction.SourceProfile): ByteArray {
        val canonical = profile == OwnerTransaction.SourceProfile.CANONICAL_B50E0B5
        val data = ByteArray(if (canonical) 136 else 128)
        byteArrayOf(0x91.toByte(), 0x2d, 0xaa.toByte(), 0xae.toByte(), 0x7a, 0x20, 0x9b.toByte(), 0x7c)
            .copyInto(data)
        worldOffsets(profile).forEach { put64(data, it, BigInteger.valueOf(1000L + it)) }
        put32(data, if (canonical) 72 else 64, 0xffffffffL)
        put32(data, if (canonical) 76 else 68, 0x80000000L)
        data[if (canonical) 112 else 104] = 255.toByte()
        data[if (canonical) 113 else 105] = 1
        put32(data, if (canonical) 116 else 108, 0xfffffffeL)
        put32(data, if (canonical) 120 else 112, 0x80000001L)
        return data
    }
    private fun worldValues(value: SourceWorldRead.SourceOnlyWorld): List<BigInteger> =
        listOf(value.genesisTimestamp, value.rewardPerWorkPower, value.rewardEpoch,
            value.totalWorkPower, value.recycledPending) + when (val economy = value.sourceEconomy) {
            is SourceWorldRead.SourceEconomy.Canonical -> listOf(economy.treasury, economy.itemReserve, economy.emitted)
            is SourceWorldRead.SourceEconomy.Historical -> listOf(economy.protocolPending, economy.burned)
        } + listOf(value.epoch, value.resortEvery, value.rotation, value.resortedEpoch, value.secondsPerDay)

    private val blockOffsets = listOf(16, 24, 32, 40, 56, 64, 72, 80, 88, 96)
    private fun memberBytes(seat: Int): ByteArray =
        if (seat == 3) ByteArray(32) else ByteArray(32) { (seat * 23 + it + 1).toByte() }
    private fun block(): ByteArray {
        val data = ByteArray(4896)
        byteArrayOf(0x0c, 0x48, 0xcf.toByte(), 0x6c, 0x01, 0xe4.toByte(), 0xa7.toByte(), 0xdd.toByte())
            .copyInto(data)
        put32(data, 8, 0xffffffffL)
        data[12] = 10
        data[13] = 2
        data[14] = 255.toByte()
        data[15] = 10
        blockOffsets.forEach { put64(data, it, BigInteger.valueOf(2000L + it)) }
        ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).putLong(48, Long.MIN_VALUE)
        data[104] = 31
        data[105] = 255.toByte()
        repeat(10) { data[106 + it] = (9 - it).toByte() }
        data[116] = 1
        repeat(10) { memberBytes(it).copyInto(data, 120 + 32 * it) }
        for (index in 440 until 4896) data[index] = (index * 17 + 3).toByte()
        return data
    }
    private fun blockValues(value: SourceWorldRead.SourceOnlyBlockHead) =
        listOf(value.epoch, value.roundSeed, value.requests, value.pendingRequest, value.rotation,
            value.minStrength, value.maxStrength, value.crankSeq, value.dueSlot, value.dawnedEpoch)
    private fun refuse(fragment: String, action: () -> Unit) {
        try { action(); fail("Expected refusal: $fragment") }
        catch (failure: SolanaRpc.Failure) {
            assertTrue("Unexpected refusal: ${failure.message}", failure.message!!.contains(fragment))
        }
    }

    @Test fun bothWorldProfilesDecodeEveryFieldAtIndependentAbsolutePositions() {
        for (profile in profiles) {
            val value = SourceWorldRead.decodeSourceOnlyWorld(account(world(profile)), program, profile)
            assertEquals(profile, value.sourceProfile)
            assertEquals(profile.sourceTree, value.sourceTree)
            assertEquals(worldOffsets(profile).map { BigInteger.valueOf(1000L + it) }, worldValues(value))
            assertEquals(0xffffffffL, value.livingPets)
            assertEquals(0x80000000L, value.floorSlots)
            assertEquals(0xfffffffeL, value.unplaced)
            assertEquals(0x80000001L, value.placed)
            assertEquals(255, value.bump)
            assertTrue(value.resorting)
            when (profile) {
                OwnerTransaction.SourceProfile.CANONICAL_B50E0B5 ->
                    assertTrue(value.sourceEconomy is SourceWorldRead.SourceEconomy.Canonical)
                OwnerTransaction.SourceProfile.HISTORICAL_D09815C6 ->
                    assertTrue(value.sourceEconomy is SourceWorldRead.SourceEconomy.Historical)
            }
        }
    }
    @Test fun bothWorldProfilesPreserveEveryUnsigned64Edge() {
        for (profile in profiles) for (edge in edges) {
            val data = world(profile)
            worldOffsets(profile).forEach { put64(data, it, edge) }
            assertEquals(List(worldOffsets(profile).size) { edge }, worldValues(
                SourceWorldRead.decodeSourceOnlyWorld(account(data), program, profile)))
        }
    }
    @Test fun worldWrongExplicitProfileNeverAdaptsLength() {
        for (profile in profiles) for (other in profiles.filter { it != profile }) {
            refuse("length") { SourceWorldRead.decodeSourceOnlyWorld(account(world(profile)), program, other) }
        }
    }
    @Test fun worldRefusesMetadataAndDiscriminator() {
        for (profile in profiles) {
            val good = account(world(profile))
            for (owner in listOf(OwnerTransaction.DELEGATION_PROGRAM, "11111111111111111111111111111111")) {
                refuse("owner") { SourceWorldRead.decodeSourceOnlyWorld(good.copy(owner = owner), program, profile) }
            }
            refuse("executable") { SourceWorldRead.decodeSourceOnlyWorld(good.copy(executable = true), program, profile) }
            val bad = world(profile).also { it[0] = 0 }
            refuse("discriminator") { SourceWorldRead.decodeSourceOnlyWorld(account(bad), program, profile) }
        }
    }
    @Test fun worldRefusesAllPadsBoolAndWholeLength() {
        for (profile in profiles) {
            val canonical = profile == OwnerTransaction.SourceProfile.CANONICAL_B50E0B5
            val pads = if (canonical) listOf(114, 115, 124, 125, 126, 127) else listOf(106, 107, 116, 117, 118, 119)
            for (offset in pads) {
                val bad = world(profile).also { it[offset] = 1 }
                refuse("padding") { SourceWorldRead.decodeSourceOnlyWorld(account(bad), program, profile) }
            }
            for (bool in listOf(2, 255)) {
                val bad = world(profile).also { it[if (canonical) 113 else 105] = bool.toByte() }
                refuse("boolean") { SourceWorldRead.decodeSourceOnlyWorld(account(bad), program, profile) }
            }
            for (length in listOf(0, 7, world(profile).size - 1, world(profile).size + 1)) {
                refuse("length") { SourceWorldRead.decodeSourceOnlyWorld(account(world(profile).copyOf(length)), program, profile) }
            }
        }
    }
    @Test fun bothBlockProfilesDecodeEveryHeadFieldAndAllTenExactMemberKeys() {
        for (profile in profiles) {
            val data = block()
            val value = SourceWorldRead.decodeSourceOnlyBlockHead(account(data), program, profile)
            assertEquals(profile, value.sourceProfile)
            assertEquals(profile.sourceTree, value.sourceTree)
            assertEquals(0xffffffffL, value.id)
            assertEquals(10, value.filled)
            assertEquals(SourceWorldRead.Phase.Acting, value.phase)
            assertEquals(255, value.round)
            assertEquals(10, value.cursor)
            assertEquals(blockOffsets.map { BigInteger.valueOf(2000L + it) }, blockValues(value))
            assertEquals(Long.MIN_VALUE, value.requestedAt)
            assertEquals(31, value.fightHead)
            assertEquals(255, value.bump)
            assertEquals((9 downTo 0).toList(), value.turns)
            assertTrue(value.started)
            assertEquals(10, value.members.size)
            repeat(10) { assertArrayEquals(memberBytes(it), value.members[it].bytes) }
            assertEquals("11111111111111111111111111111111", value.members[3].address)
            assertEquals(440, value.decodedPrefixBytes)
            assertEquals(4456, value.unparsedTailBytes)
            data.fill(0)
            repeat(10) { assertArrayEquals(memberBytes(it), value.members[it].bytes) }
        }
    }
    @Test fun bothBlockProfilesPreserveEveryUnsigned64EdgeAndSignedRequestedAt() {
        for (profile in profiles) for (edge in edges) {
            val data = block()
            blockOffsets.forEach { put64(data, it, edge) }
            for (signed in listOf(Long.MIN_VALUE, -1L, 0L, 1L, Long.MAX_VALUE)) {
                ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).putLong(48, signed)
                val value = SourceWorldRead.decodeSourceOnlyBlockHead(account(data), program, profile)
                assertEquals(List(10) { edge }, blockValues(value))
                assertEquals(signed, value.requestedAt)
            }
        }
    }
    @Test fun blockRefusesMetadataDiscriminatorAndExactWholeLengthIncludingMemberWidthChanges() {
        for (profile in profiles) {
            val good = account(block())
            for (owner in listOf(OwnerTransaction.DELEGATION_PROGRAM, "11111111111111111111111111111111")) {
                refuse("owner") { SourceWorldRead.decodeSourceOnlyBlockHead(good.copy(owner = owner), program, profile) }
            }
            refuse("executable") { SourceWorldRead.decodeSourceOnlyBlockHead(good.copy(executable = true), program, profile) }
            refuse("discriminator") {
                SourceWorldRead.decodeSourceOnlyBlockHead(account(block().also { it[7] = 0 }), program, profile)
            }
            for (length in listOf(0, 7, 119, 439, 440, 4895, 4897)) {
                refuse("length") { SourceWorldRead.decodeSourceOnlyBlockHead(account(block().copyOf(length)), program, profile) }
            }
            val data = block()
            val shortMember = data.copyOfRange(0, 439) + data.copyOfRange(440, data.size)
            val longMember = data.copyOfRange(0, 440) + byteArrayOf(0) + data.copyOfRange(440, data.size)
            for (bad in listOf(shortMember, longMember)) {
                refuse("length") { SourceWorldRead.decodeSourceOnlyBlockHead(account(bad), program, profile) }
            }
        }
    }
    @Test fun blockRefusesHeaderPadBoolUnknownPhaseFilledFightHeadAndTurnSeat() {
        for (profile in profiles) {
            val mutations = listOf(12 to 11, 12 to 255, 13 to 3, 13 to 255,
                104 to 32, 104 to 255, 116 to 2, 116 to 255,
                117 to 1, 118 to 1, 119 to 1) + (106..115).map { it to 10 }
            for ((offset, bad) in mutations) {
                val fragment = when (offset) {
                    12 -> "filled"
                    13 -> "phase"
                    104 -> "fightHead"
                    116 -> "boolean"
                    in 117..119 -> "padding"
                    else -> "turn seat"
                }
                refuse(fragment) {
                    SourceWorldRead.decodeSourceOnlyBlockHead(account(block().also { it[offset] = bad.toByte() }), program, profile)
                }
            }
        }
    }
    @Test fun emptyWorldAndUnstartedEmptyBlockAreValidNotReadyEvidence() {
        for (profile in profiles) {
            val worldData = ByteArray(world(profile).size).also { world(profile).copyInto(it, 0, 0, 8) }
            val decodedWorld = SourceWorldRead.decodeSourceOnlyWorld(account(worldData), program, profile)
            assertFalse(decodedWorld.resorting)
            assertEquals(BigInteger.ZERO, decodedWorld.epoch)
            val blockData = ByteArray(4896).also { block().copyInto(it, 0, 0, 8) }
            val decodedBlock = SourceWorldRead.decodeSourceOnlyBlockHead(account(blockData), program, profile)
            assertFalse(decodedBlock.started)
            assertEquals(0, decodedBlock.filled)
            assertEquals(SourceWorldRead.Phase.Idle, decodedBlock.phase)
            assertTrue(decodedBlock.members.all { it.address == "11111111111111111111111111111111" })
            assertEquals(List(10) { 0 }, decodedBlock.turns)
        }
    }
    @Test fun blockTailContentsAreNotClaimedDecodedAndSameSchemaCannotIdentifyProfile() {
        for (profile in profiles) for (phase in SourceWorldRead.Phase.entries) {
            val first = block().also { it[13] = phase.ordinal.toByte() }
            val second = first.copyOf().also { java.util.Arrays.fill(it, 440, 4896, 255.toByte()) }
            assertEquals(SourceWorldRead.decodeSourceOnlyBlockHead(account(first), program, profile),
                SourceWorldRead.decodeSourceOnlyBlockHead(account(second), program, profile))
        }
        val canonical = SourceWorldRead.decodeSourceOnlyBlockHead(account(block()), program, profiles[0])
        val historical = SourceWorldRead.decodeSourceOnlyBlockHead(account(block()), program, profiles[1])
        assertEquals(canonical.copy(sourceProfile = historical.sourceProfile), historical)
    }
}
