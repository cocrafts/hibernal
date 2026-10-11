package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import org.junit.Assert.*
import org.junit.Test

class SourcePetReadTest {
    private val program = SolanaPublicKey(ByteArray(32) { 3 })
    private val owner = SolanaPublicKey(ByteArray(32) { (it + 1).toByte() })
    private val mint = SolanaPublicKey(ByteArray(32) { (it + 71).toByte() })
    private val maximum = BigInteger("18446744073709551615")
    private val high = BigInteger("9223372036854775808")
    private val profiles = OwnerTransaction.SourceProfile.entries

    private fun bodyOffset(profile: OwnerTransaction.SourceProfile) = when (profile) {
        OwnerTransaction.SourceProfile.CANONICAL_B50E0B5 -> 128
        OwnerTransaction.SourceProfile.HISTORICAL_D09815C6 -> 96
    }
    private fun put(bytes: ByteArray, offset: Int, width: Int, value: BigInteger) {
        repeat(width) { bytes[offset + it] = value.shiftRight(8 * it).toByte() }
    }
    private fun put(bytes: ByteArray, offset: Int, width: Int, value: Long) = put(bytes, offset, width, BigInteger.valueOf(value))
    private fun golden(profile: OwnerTransaction.SourceProfile): ByteArray {
        val bytes = ByteArray(if (profile == OwnerTransaction.SourceProfile.CANONICAL_B50E0B5) 304 else 272)
        byteArrayOf(0xdf.toByte(), 0xde.toByte(), 0x81.toByte(), 0x59, 0x46, 0xe7.toByte(), 0x8d.toByte(), 0xb8.toByte()).copyInto(bytes)
        owner.bytes.copyInto(bytes, 8)
        mint.bytes.copyInto(bytes, 40)
        put(bytes, 72, 4, 0xffffffffL)
        bytes[76] = 2
        bytes[77] = 255.toByte()
        bytes[78] = 254.toByte()
        put(bytes, 80, 8, high)
        put(bytes, 88, 8, maximum)
        val start = bodyOffset(profile)
        if (start == 128) {
            repeat(7) { put(bytes, 96 + it * 4, 4, 0xffffffffL - it) }
            put(bytes, 124, 4, 0xfffffffeL)
        }
        repeat(11) { put(bytes, start + it * 8, 8, maximum.subtract(BigInteger.valueOf(it.toLong()))) }
        put(bytes, start + 88, 4, 25L)
        put(bytes, start + 92, 4, 0xffffffffL)
        listOf(Int.MIN_VALUE, -17, Int.MAX_VALUE, 123456).forEachIndexed { index, value ->
            put(bytes, start + 96 + index * 4, 4, value.toLong())
        }
        listOf(65535, 65534, 32768, 65000, 1023, 60000, 62000, 65533).forEachIndexed { index, value ->
            put(bytes, start + 112 + index * 2, 2, value.toLong())
        }
        val tail = listOf(3, 1, 2, 251, 252, 253, 255, 254, 253, 252, 251, 250, 249, 248, 247, 3, 2, 246, -128, 245, 244)
        tail.forEachIndexed { index, value -> bytes[start + 128 + index] = value.toByte() }
        repeat(4) { index ->
            listOf(index + 1, index, 255 - index, index, 250 - index).forEachIndexed { part, value ->
                bytes[start + 149 + index * 5 + part] = value.toByte()
            }
        }
        bytes[start + 169] = 9
        bytes[start + 170] = 243.toByte()
        if (start == 128) {
            listOf(7, 6, 242, 1, 241).forEachIndexed { index, value -> bytes[start + 171 + index] = value.toByte() }
        }
        return bytes
    }
    private fun account(bytes: ByteArray, accountOwner: String = program.address, executable: Boolean = false) =
        SolanaRpc.Account(accountOwner, BigInteger.ONE, executable, bytes)
    private fun decode(profile: OwnerTransaction.SourceProfile, bytes: ByteArray = golden(profile)) =
        SourcePetRead.decodeSourceOnly(account(bytes), program, profile, owner, mint)
    private fun refuses(message: String, block: () -> Unit) {
        val error = assertThrows(SolanaRpc.Failure::class.java) { block() }
        assertTrue(error.message, error.message!!.contains(message))
    }
    private fun expected(profile: OwnerTransaction.SourceProfile): SourcePetRead.SourceOnlyDecodedPet {
        val quantities = List(11) { maximum.subtract(BigInteger.valueOf(it.toLong())) }
        val gear = SourcePetRead.Gear(
            SourcePetRead.Item(SourcePetRead.ItemRarity.Common, SourcePetRead.TalentKind.None, 255, SourcePetRead.ItemSkill.None, 250),
            SourcePetRead.Item(SourcePetRead.ItemRarity.Rare, SourcePetRead.TalentKind.Forage, 254, SourcePetRead.ItemSkill.Revive, 249),
            SourcePetRead.Item(SourcePetRead.ItemRarity.Epic, SourcePetRead.TalentKind.Might, 253, SourcePetRead.ItemSkill.AntiRobbery, 248),
            SourcePetRead.Item(SourcePetRead.ItemRarity.Legendary, SourcePetRead.TalentKind.Grit, 252, SourcePetRead.ItemSkill.DamageGuard, 247)
        )
        val canonical = profile == OwnerTransaction.SourceProfile.CANONICAL_B50E0B5
        val tail = if (canonical) SourcePetRead.SourceTail.Canonical(245, SourcePetRead.OwnerItem.Insurance,
            SourcePetRead.OwnerItem.LargeGrowth, 242, true, 241) else SourcePetRead.SourceTail.Historical(245)
        return SourcePetRead.SourceOnlyDecodedPet(profile, owner, mint, 0xffffffffL, SourcePetRead.Persona.Vengeful, 255, 254,
            high, maximum, if (canonical) SourcePetRead.CanonicalAccountFields(List(7) { 0xffffffffL - it }, 0xfffffffeL) else null,
            SourcePetRead.SourceOnlyRulesPet(quantities[0], quantities[1], quantities[2], quantities[3], quantities[4],
                quantities[5], quantities[6], quantities[7], quantities[8], quantities[9], quantities[10], 25, 0xffffffffL,
                Int.MIN_VALUE, -17, Int.MAX_VALUE, 123456, 65535, 65534, 32768, 65000, 1023, 60000, 62000, 65533,
                SourcePetRead.Seat.Fourth, true, SourcePetRead.Region.Survivor, 251, 252, 253, 255, 254, 253, 252, 251,
                SourcePetRead.Pantry(250, 249, 248), 247, SourcePetRead.TalentKind.Grit, SourcePetRead.Insurance.Used,
                246, -128, 244, gear, SourcePetRead.Seat.Tenth, 243, tail))
    }

    @Test fun historicalWholeGolden() {
        val profile = OwnerTransaction.SourceProfile.HISTORICAL_D09815C6
        assertEquals(expected(profile), decode(profile))
        assertEquals("511868044a069d6e35ddf512af5f5533cab501ac", decode(profile).sourceTree)
    }
    @Test fun canonicalWholeGolden() {
        val profile = OwnerTransaction.SourceProfile.CANONICAL_B50E0B5
        assertEquals(expected(profile), decode(profile))
        assertEquals("f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc", decode(profile).sourceTree)
    }
    @Test fun wrongExplicitProfileRefused() {
        for (profile in profiles) refuses("length") { decode(profile, golden(profiles.first { it != profile })) }
    }
    @Test fun metadataRefused() {
        for (profile in profiles) {
            refuses("program owner") { SourcePetRead.decodeSourceOnly(account(golden(profile), owner.address), program, profile) }
            refuses("executable") { SourcePetRead.decodeSourceOnly(account(golden(profile), executable = true), program, profile) }
        }
    }
    @Test fun allTruncationsAndTrailingBytesRefused() {
        for (profile in profiles) {
            val bytes = golden(profile)
            for (size in 0 until bytes.size) refuses("length") { decode(profile, bytes.copyOf(size)) }
            refuses("length") { decode(profile, bytes + byteArrayOf(0)) }
        }
    }
    @Test fun everyDiscriminatorByteRefused() {
        for (profile in profiles) repeat(8) { offset ->
            val bytes = golden(profile)
            bytes[offset] = (bytes[offset].toInt() xor 1).toByte()
            refuses("discriminator") { decode(profile, bytes) }
        }
    }
    @Test fun optionalExpectedIdentityValidated() {
        for (profile in profiles) {
            assertEquals(expected(profile), SourcePetRead.decodeSourceOnly(account(golden(profile)), program, profile))
            refuses("embedded owner") { SourcePetRead.decodeSourceOnly(account(golden(profile)), program, profile, mint, mint) }
            refuses("embedded mint") { SourcePetRead.decodeSourceOnly(account(golden(profile)), program, profile, owner, owner) }
        }
    }
    @Test fun reservedPaddingRefusedWithoutRepair() {
        for (profile in profiles) {
            val positions = listOf(79) + if (bodyOffset(profile) == 96) (267..271).toList() else emptyList()
            for (offset in positions) {
                val bytes = golden(profile)
                bytes[offset] = 1
                refuses("padding") { decode(profile, bytes) }
                assertEquals(1, bytes[offset].toInt())
            }
        }
    }
    @Test fun enumsBooleansAndBitsetRefused() {
        for (profile in profiles) {
            val start = bodyOffset(profile)
            val invalid = mutableListOf(76 to 3, start + 128 to 10, start + 129 to 2, start + 130 to 3,
                start + 143 to 4, start + 144 to 3, start + 169 to 254)
            repeat(4) { index ->
                invalid += start + 149 + index * 5 to 6
                invalid += start + 150 + index * 5 to 4
                invalid += start + 152 + index * 5 to 4
            }
            if (start == 128) invalid += listOf(start + 171 to 8, start + 172 to 8, start + 174 to 2)
            for ((offset, value) in invalid) {
                val bytes = golden(profile)
                bytes[offset] = value.toByte()
                refuses("Invalid Pet") { decode(profile, bytes) }
            }
            val bytes = golden(profile)
            put(bytes, start + 120, 2, 1024L)
            refuses("unknown BlockSlot bits") { decode(profile, bytes) }
        }
    }
    @Test fun unplacedAndDeadRetainedNotMadeReady() {
        for (profile in profiles) {
            val bytes = golden(profile)
            val start = bodyOffset(profile)
            put(bytes, start + 88, 4, 0xffffffffL)
            bytes[start + 128] = 255.toByte()
            bytes[start + 129] = 0
            val unplaced = decode(profile, bytes)
            assertEquals(SourcePetRead.Seat.Unplaced, unplaced.pet.slot)
            assertEquals(0xffffffffL, unplaced.pet.blockId)
            assertFalse(unplaced.pet.alive)
            val dead = golden(profile)
            dead[start + 129] = 0
            assertFalse(decode(profile, dead).pet.alive)
            assertEquals(SourcePetRead.Seat.Fourth, decode(profile, dead).pet.slot)
        }
    }
    @Test fun unplacedAliveFalseWithZeroDeathEpochIsNotRepaired() {
        for (profile in profiles) {
            val bytes = golden(profile)
            val start = bodyOffset(profile)
            put(bytes, 88, 8, BigInteger.ZERO)
            put(bytes, start + 88, 4, 0xffffffffL)
            bytes[start + 128] = 255.toByte()
            bytes[start + 129] = 0
            val decoded = decode(profile, bytes)
            assertFalse(decoded.pet.alive)
            assertEquals(BigInteger.ZERO, decoded.diedEpoch)
            assertEquals(SourcePetRead.Seat.Unplaced, decoded.pet.slot)
        }
    }
    @Test fun inconsistentPlacementRefused() {
        for (profile in profiles) {
            val start = bodyOffset(profile)
            val noBlock = golden(profile)
            put(noBlock, start + 88, 4, 0xffffffffL)
            refuses("NO_BLOCK/NO_SEAT") { decode(profile, noBlock) }
            val noSeat = golden(profile)
            noSeat[start + 128] = 255.toByte()
            refuses("NO_BLOCK/NO_SEAT") { decode(profile, noSeat) }
        }
    }
    @Test fun everyUint64IsExactAtBoundaries() {
        for (profile in profiles) {
            val start = bodyOffset(profile)
            for (value in listOf(BigInteger.ZERO, BigInteger.ONE, high.subtract(BigInteger.ONE), high, maximum)) {
                val bytes = golden(profile)
                for (offset in listOf(80, 88) + List(11) { start + it * 8 }) put(bytes, offset, 8, value)
                val decoded = decode(profile, bytes)
                val pet = decoded.pet
                assertEquals(List(13) { value }, listOf(decoded.claimedEpoch, decoded.diedEpoch, pet.tree, pet.harvest,
                    pet.burrow, pet.rewardSnapshot, pet.bornEpoch, pet.lastTickEpoch, pet.fightDay,
                    pet.growthMultiplierExpiry, pet.giftOwed, pet.ownerBankReadyAt, pet.rageEpoch))
            }
        }
    }
}
