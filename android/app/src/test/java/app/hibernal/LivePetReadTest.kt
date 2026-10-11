package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

class LivePetReadTest {
    private val program = SolanaPublicKey(ByteArray(32) { 3 })
    private val delegation = SolanaPublicKey(ByteArray(32) { 4 })
    private val owner = SolanaPublicKey(ByteArray(32) { (it + 1).toByte() })
    private val mint = SolanaPublicKey(ByteArray(32) { (it + 71).toByte() })
    private val petAddress = SolanaPublicKey(ByteArray(32) { 9 }).address
    private val maximum = BigInteger("18446744073709551615")
    private val genesis = 1_700_000_000L
    private val secondsPerDay = 600L

    private fun tag(name: String) = MessageDigest.getInstance("SHA-256").digest("account:$name".toByteArray()).copyOf(8)
    private fun put(bytes: ByteArray, offset: Int, width: Int, value: BigInteger) {
        repeat(width) { bytes[offset + it] = value.shiftRight(8 * it).toByte() }
    }
    private fun put(bytes: ByteArray, offset: Int, width: Int, value: Long) = put(bytes, offset, width, BigInteger.valueOf(value))

    private fun pet(seat: Int = 4, blockId: Long = 7, alive: Boolean = true, generation: Int = 0, size: Int = 304): ByteArray {
        val bytes = ByteArray(304)
        tag("PetAccount").copyInto(bytes)
        owner.bytes.copyInto(bytes, 8)
        mint.bytes.copyInto(bytes, 40)
        put(bytes, 72, 4, 12L)
        bytes[76] = 2
        bytes[77] = 254.toByte()
        bytes[78] = 201.toByte()
        put(bytes, 80, 8, 3L)
        val start = 128
        put(bytes, start, 8, 0x3ff9L)
        put(bytes, start + 8, 8, maximum)
        put(bytes, start + 16, 8, 2_179_950_569L)
        put(bytes, start + 32, 8, 5L)
        put(bytes, start + 40, 8, 9L)
        put(bytes, start + 56, 8, 10L)
        put(bytes, start + 64, 8, 77L)
        put(bytes, start + 88, 4, if (seat == 255) 0xffffffffL else blockId)
        put(bytes, start + 92, 4, 0xffffffffL)
        listOf(11, 12, 13, 14).forEachIndexed { index, value -> put(bytes, start + 112 + index * 2, 2, value.toLong()) }
        put(bytes, start + 122, 2, 11500L)
        put(bytes, start + 124, 2, 13400L)
        put(bytes, start + 126, 2, generation.toLong())
        bytes[start + 128] = seat.toByte()
        bytes[start + 129] = if (alive) 1 else 0
        bytes[start + 131] = 8
        bytes[start + 132] = 18
        bytes[start + 143] = 1
        bytes[start + 146] = (-40).toByte()
        return bytes.copyOf(size)
    }
    private fun world(size: Int = 136): ByteArray {
        val bytes = ByteArray(136)
        tag("World").copyInto(bytes)
        put(bytes, 8, 8, genesis)
        put(bytes, 128, 8, secondsPerDay)
        return bytes.copyOf(size)
    }
    private fun block(id: Long = 7, seat: Int = 4, member: String = petAddress, epoch: Long = 41, started: Boolean = true, size: Int = 4896): ByteArray {
        val bytes = ByteArray(4896)
        tag("Block").copyInto(bytes)
        put(bytes, 8, 4, id)
        bytes[12] = 1
        put(bytes, 16, 8, epoch)
        repeat(10) { bytes[106 + it] = it.toByte() }
        bytes[116] = if (started) 1 else 0
        SolanaPublicKey.from(member).bytes.copyInto(bytes, 120 + 32 * seat)
        return bytes.copyOf(size)
    }
    private fun account(bytes: ByteArray, accountOwner: SolanaPublicKey = program) =
        SolanaRpc.Account(accountOwner.address, BigInteger.ONE, false, bytes)
    private fun keyed(bytes: ByteArray, accountOwner: SolanaPublicKey = program) =
        SolanaRpc.KeyedAccount(petAddress, account(bytes, accountOwner))
    private fun placedSource(bytes: ByteArray = pet()) =
        LivePetRead.source(emptyList(), listOf(keyed(bytes, delegation)), listOf(keyed(bytes)), program, delegation, owner)
    private fun now(day: Long) = genesis + day * secondsPerDay + 5
    private val noShop = OwnerShop.Holdings(BigInteger.ZERO, 0, 0, 0)
    private fun LongArray.at(field: LivePetRead.Field) = this[field.ordinal]
    private fun unsupported(message: String, block: () -> Unit) {
        val error = assertThrows(LivePetRead.UnsupportedLayout::class.java) { block() }
        assertEquals(message, error.message)
    }

    @Test fun placedMemberPetPublishesExactIntegers() {
        val source = placedSource()
        val placement = LivePetRead.placement(source, account(world()), account(block()), program, now(41))
        val fields = LivePetRead.fields(source, placement, BigInteger.valueOf(40), OwnerShop.Holdings(BigInteger.valueOf(200_000_000), 2, 3, 20_000_000))
        assertEquals(LivePetRead.Field.entries.size, fields.size)
        assertEquals(SourcePetLifecycle.Fact.FIRST_LIFE_ACTIVE.ordinal.toLong(), fields.at(LivePetRead.Field.LIFE))
        assertEquals(1L, fields.at(LivePetRead.Field.DELEGATED))
        assertEquals(1L, fields.at(LivePetRead.Field.MEMBER))
        assertEquals(1L, fields.at(LivePetRead.Field.BLOCK_STARTED))
        assertEquals(41L, fields.at(LivePetRead.Field.BLOCK_EPOCH))
        assertEquals(41L, fields.at(LivePetRead.Field.WORLD_DAY))
        assertEquals(14L, fields.at(LivePetRead.Field.LEVEL))
        assertEquals(0xffffffffL, fields.at(LivePetRead.Field.XP))
        assertEquals(maximum, BigInteger(java.lang.Long.toUnsignedString(fields.at(LivePetRead.Field.HARVEST))))
        assertEquals(2_179_950_569L, fields.at(LivePetRead.Field.BURROW))
        assertEquals(8L, fields.at(LivePetRead.Field.HEARTS))
        assertEquals(18L, fields.at(LivePetRead.Field.MAX_HEARTS))
        assertEquals(-40L, fields.at(LivePetRead.Field.BONDING))
        assertEquals(200_000_000L, fields.at(LivePetRead.Field.SKR_BALANCE))
        assertEquals(2L, fields.at(LivePetRead.Field.ITEMS_IN_TRANSIT))
        assertEquals(3L, fields.at(LivePetRead.Field.LEDGER_REBIRTHS))
        assertEquals(20_000_000L, fields.at(LivePetRead.Field.CONFIG_HATCH_FEE_LAMPORTS))
        assertEquals(0L, fields.at(LivePetRead.Field.OWNER_FIRST))
        assertEquals(11500L, fields.at(LivePetRead.Field.GROWTH_MULTIPLIER_BPS))
        assertEquals(10L, fields.at(LivePetRead.Field.GROWTH_MULTIPLIER_EXPIRY))
        assertEquals(9L, fields.at(LivePetRead.Field.LAST_TICK_EPOCH))
        assertEquals(listOf(11L, 12L, 13L), listOf(LivePetRead.Field.FORAGE, LivePetRead.Field.MIGHT, LivePetRead.Field.GRIT).map { fields.at(it) })
        assertEquals(1L, fields.at(LivePetRead.Field.TALENT_KIND))
        assertEquals(13400L, fields.at(LivePetRead.Field.TALENT_BPS))
        assertEquals(0x3ff9L, fields.at(LivePetRead.Field.TREE))
        assertEquals(2L, fields.at(LivePetRead.Field.PERSONA))
        assertEquals(0L, fields.at(LivePetRead.Field.LINEAGE_GENERATION))
        assertEquals(5L, fields.at(LivePetRead.Field.BORN_EPOCH))
        assertEquals(3L, fields.at(LivePetRead.Field.CLAIMED_EPOCH))
        assertEquals(0L, fields.at(LivePetRead.Field.DIED_EPOCH))
        assertEquals(77L, fields.at(LivePetRead.Field.GIFT_OWED))
        assertEquals(77L, fields.at(LivePetRead.Field.COMMITTED_GIFT_OWED))
        assertEquals(40L, fields.at(LivePetRead.Field.PAID_TOTAL))
        assertEquals(201L, fields.at(LivePetRead.Field.NAME_ID))
    }

    @Test fun historicalOrUnknownPetLengthIsUnsupportedNotMisread() {
        for (size in listOf(272, 303, 305)) {
            unsupported("PET $size BYTES / CLIENT READS 304") { placedSource(pet(size = size)) }
        }
        unsupported("PET 272 BYTES / CLIENT READS 304") {
            LivePetRead.source(listOf(keyed(pet(size = 272))), emptyList(), emptyList(), program, delegation, owner)
        }
    }

    @Test fun worldAndBlockLengthsAreAssertedBeforeDecoding() {
        val source = placedSource()
        unsupported("WORLD 128 BYTES / CLIENT READS 136") {
            LivePetRead.placement(source, account(world(128)), account(block()), program, now(41))
        }
        unsupported("BLOCK 4895 BYTES / CLIENT READS 4896") {
            LivePetRead.placement(source, account(world()), account(block(size = 4895)), program, now(41))
        }
    }

    @Test fun staleBlockKeepsItsEpochAndTheClockDay() {
        val source = placedSource()
        val fields = LivePetRead.fields(source, LivePetRead.placement(source, account(world()), account(block(epoch = 30)), program, now(41)), BigInteger.ZERO, noShop)
        assertEquals(30L, fields.at(LivePetRead.Field.BLOCK_EPOCH))
        assertEquals(41L, fields.at(LivePetRead.Field.WORLD_DAY))
        val early = LivePetRead.placement(source, account(world()), account(block()), program, genesis - 1)
        assertEquals(BigInteger.ZERO, early.worldDay)
    }

    @Test fun membershipNeedsMatchingBlockIdSeatAndAddress() {
        val source = placedSource()
        val stranger = SolanaPublicKey(ByteArray(32) { 8 }).address
        for (wrong in listOf(block(id = 8), block(member = stranger), block(seat = 5))) {
            val fields = LivePetRead.fields(source, LivePetRead.placement(source, account(world()), account(wrong), program, now(41)), BigInteger.ZERO, noShop)
            assertEquals(0L, fields.at(LivePetRead.Field.MEMBER))
        }
        val missing = LivePetRead.fields(source, LivePetRead.placement(source, account(world()), null, program, now(41)), BigInteger.ZERO, noShop)
        assertEquals(0L, missing.at(LivePetRead.Field.MEMBER))
        assertEquals(0L, missing.at(LivePetRead.Field.BLOCK_STARTED))
        assertThrows(SolanaRpc.Failure::class.java) { LivePetRead.placement(source, null, account(block()), program, now(41)) }
    }

    @Test fun claimedPetIsPendingNotDeadAndDelegationWithoutCloneIsNotOnEphemeral() {
        val claimed = LivePetRead.source(listOf(keyed(pet(seat = 255, alive = false))), emptyList(), emptyList(), program, delegation, owner)
        assertFalse(claimed.delegated)
        val fields = LivePetRead.fields(claimed, null, BigInteger.ZERO, noShop)
        assertEquals(SourcePetLifecycle.Fact.CLAIMED_UNPLACED.ordinal.toLong(), fields.at(LivePetRead.Field.LIFE))
        assertEquals(0L, fields.at(LivePetRead.Field.DELEGATED))
        assertEquals(0L, fields.at(LivePetRead.Field.MEMBER))
        val waiting = LivePetRead.source(emptyList(), listOf(keyed(pet(), delegation)), emptyList(), program, delegation, owner)
        assertTrue(waiting.delegated)
        assertFalse(waiting.onEphemeral)
        assertEquals(0L, LivePetRead.fields(waiting, null, BigInteger.ZERO, noShop).at(LivePetRead.Field.MEMBER))
    }

    @Test fun deathAndHeirAreDistinctLifeFacts() {
        val dead = pet(alive = false).also { put(it, 88, 8, 40L) }
        assertEquals(SourcePetLifecycle.Fact.DEATH_RECORDED.ordinal.toLong(),
            LivePetRead.fields(placedSource(dead), null, BigInteger.ZERO, noShop).at(LivePetRead.Field.LIFE))
        val heir = LivePetRead.fields(placedSource(pet(generation = 3)), null, BigInteger.ZERO, noShop)
        assertEquals(SourcePetLifecycle.Fact.HEIR_ACTIVE.ordinal.toLong(), heir.at(LivePetRead.Field.LIFE))
        assertEquals(3L, heir.at(LivePetRead.Field.LINEAGE_GENERATION))
    }

    @Test fun anErPetWithoutL1DelegationOrSeveralPetsAreRefused() {
        assertThrows(SolanaRpc.Failure::class.java) {
            LivePetRead.source(emptyList(), emptyList(), listOf(keyed(pet())), program, delegation, owner)
        }
        val other = SolanaRpc.KeyedAccount(SolanaPublicKey(ByteArray(32) { 8 }).address, account(pet()))
        unsupported("2 OWNER PETS / CLIENT READS ONE") {
            LivePetRead.source(listOf(keyed(pet()), other), emptyList(), emptyList(), program, delegation, owner)
        }
    }

    @Test fun derivedAddressesUseProgramSeeds() = kotlinx.coroutines.runBlocking {
        assertNotEquals(LivePetRead.blockAddress(program, 7), LivePetRead.blockAddress(program, 8))
        assertNotEquals(LivePetRead.worldAddress(program), LivePetRead.blockAddress(program, 0))
    }

    @Test fun paidTotalReadsTheLedgerOrZeroBeforeTheFirstClaim() {
        val mint = SolanaPublicKey(ByteArray(32) { 5 })
        assertEquals(BigInteger.ZERO, LivePetRead.paidTotal(null, mint, program))
        val paid = ByteArray(72)
        byteArrayOf(0xe0.toByte(), 0x1c, 0x92.toByte(), 0xd5.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0x0b, 0x03).copyInto(paid)
        mint.bytes.copyInto(paid, 8)
        put(paid, 40, 8, 1234L)
        assertEquals(BigInteger.valueOf(1234), LivePetRead.paidTotal(account(paid), mint, program))
        unsupported("PAID ACCOUNT NOT ACCEPTED") { LivePetRead.paidTotal(account(paid), SolanaPublicKey(ByteArray(32) { 6 }), program) }
        unsupported("PAID ACCOUNT NOT ACCEPTED") { LivePetRead.paidTotal(account(paid, delegation), mint, program) }
        unsupported("PAID ACCOUNT NOT ACCEPTED") { LivePetRead.paidTotal(account(paid.copyOf(71)), mint, program) }
    }
}
