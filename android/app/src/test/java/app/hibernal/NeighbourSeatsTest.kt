package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

class NeighbourSeatsTest {
    private val program = SolanaPublicKey(ByteArray(32) { 3 })
    private val delegation = SolanaPublicKey(ByteArray(32) { 4 })
    private val owner = SolanaPublicKey(ByteArray(32) { (it + 1).toByte() })
    private val mySeat = 4
    private val blockId = 7L
    private val genesis = 1_700_000_000L
    private fun address(seat: Int) = SolanaPublicKey(ByteArray(32) { (seat + 20).toByte() }).address
    private val myAddress = address(mySeat)

    private fun tag(name: String) = MessageDigest.getInstance("SHA-256").digest("account:$name".toByteArray()).copyOf(8)
    private fun put(bytes: ByteArray, offset: Int, width: Int, value: Long) {
        repeat(width) { bytes[offset + it] = (value ushr (8 * it)).toByte() }
    }

    private fun pet(
        seat: Int,
        alive: Boolean = true,
        wild: Boolean = false,
        petBlock: Long = blockId,
        size: Int = 304,
    ): ByteArray {
        val bytes = ByteArray(304)
        tag("PetAccount").copyInto(bytes)
        bytes[78] = (240 + seat).toByte()
        owner.bytes.copyInto(bytes, 8)
        bytes[76] = 1
        if (!alive) put(bytes, 88, 8, 40L)
        val start = 128
        put(bytes, start, 8, 0b1011L shl seat)
        put(bytes, start + 8, 8, 1_000L + seat)
        put(bytes, start + 16, 8, 2_000L + seat)
        put(bytes, start + 32, 8, 5L)
        put(bytes, start + 40, 8, 41L)
        put(bytes, start + 48, 8, 41L)
        put(bytes, start + 80, 8, 39L)
        put(bytes, start + 88, 4, petBlock)
        put(bytes, start + 104, 4, 1500L)
        put(bytes, start + 108, 4, 700L)
        listOf(60 + seat, 70 + seat, 80 + seat, 3 + seat).forEachIndexed { index, value ->
            put(bytes, start + 112 + index * 2, 2, value.toLong())
        }
        put(bytes, start + 120, 2, 0b10_0000_0001L)
        put(bytes, start + 126, 2, 2L)
        bytes[start + 128] = seat.toByte()
        bytes[start + 129] = if (alive) 1 else 0
        bytes[start + 130] = 1
        bytes[start + 131] = 9
        bytes[start + 132] = 12
        bytes[start + 134] = 0b0000_0110
        bytes[start + 135] = 1
        bytes[start + 136] = 2
        bytes[start + 137] = 1
        bytes[start + 143] = 2
        put(bytes, start + 124, 2, 11000L)
        byteArrayOf(2, 2, 15, 2, 6).copyInto(bytes, start + 149)
        byteArrayOf(5, 3, 0, 3, 9).copyInto(bytes, start + 164)
        bytes[start + 169] = mySeat.toByte()
        bytes[start + 170] = 2
        bytes[start + 174] = if (wild) 1 else 0
        return bytes.copyOf(size)
    }

    private fun world() = ByteArray(136).also {
        tag("World").copyInto(it)
        put(it, 8, 8, genesis)
        put(it, 128, 8, 600L)
    }

    private class Fight(val index: Int, val epoch: Long, val attacker: Int, val defender: Int, val loot: Long, val won: Boolean)

    private fun block(
        occupied: Map<Int, String>,
        fights: List<Fight> = emptyList(),
        fightHead: Int = 0,
        grudges: Map<Int, Pair<Int, Long>> = emptyMap(),
    ) = ByteArray(4896).also {
        tag("Block").copyInto(it)
        it[104] = fightHead.toByte()
        for ((seat, grudge) in grudges) {
            it[440 + 16 * seat] = grudge.first.toByte()
            put(it, 448 + 16 * seat, 8, grudge.second)
        }
        for (fight in fights) {
            val start = 600 + 120 * fight.index
            put(it, start, 8, fight.epoch)
            put(it, start + 8, 8, -2L)
            put(it, start + 16, 8, 5_000_000L)
            put(it, start + 24, 8, fight.loot)
            put(it, start + 32, 4, fight.attacker.toLong())
            put(it, start + 36, 4, fight.defender.toLong())
            put(it, start + 40, 4, 3L)
            put(it, start + 44, 4, 90L)
            put(it, start + 72, 4, 7L)
            it[start + 76] = 2
            put(it, start + 80, 4, 60L)
            put(it, start + 108, 4, 11L)
            it[start + 116] = if (fight.won) 1 else 0
        }
        put(it, 8, 4, blockId)
        it[12] = occupied.size.toByte()
        put(it, 16, 8, 41L)
        repeat(10) { seat -> it[106 + seat] = seat.toByte() }
        it[116] = 1
        for ((seat, key) in occupied) SolanaPublicKey.from(key).bytes.copyInto(it, 120 + 32 * seat)
    }

    private fun account(bytes: ByteArray, accountOwner: SolanaPublicKey = program) =
        SolanaRpc.Account(accountOwner.address, BigInteger.ONE, false, bytes)

    private fun mine(): LivePetRead.Source {
        val bytes = pet(mySeat)
        return LivePetRead.source(emptyList(), listOf(SolanaRpc.KeyedAccount(myAddress, account(bytes, delegation))),
            listOf(SolanaRpc.KeyedAccount(myAddress, account(bytes))), program, delegation, owner)
    }

    private val fullBlock = (0 until 10).associateWith { address(it) }

    private fun seated(
        occupied: Map<Int, String> = fullBlock,
        blockBytes: ByteArray = block(occupied),
    ): Pair<LivePetRead.Source, LivePetRead.Placement> {
        val source = mine()
        return source to LivePetRead.placement(source, account(world()), account(blockBytes), program, genesis + 41 * 600)
    }

    private fun neighbourAccounts(override: Map<Int, SolanaRpc.Account?> = emptyMap()): Map<String, SolanaRpc.Account?> =
        (0 until 10).filter { it != mySeat }.associate { seat ->
            address(seat) to if (seat in override) override[seat] else account(pet(seat))
        }

    private fun LongArray.seat(seat: Int, field: LivePetRead.SeatField) =
        this[seat * LivePetRead.SeatField.entries.size + field.ordinal]

    private fun LongArray.kinds() = (0 until LivePetRead.BLOCK_SEATS).map {
        LivePetRead.SeatKind.entries[seat(it, LivePetRead.SeatField.KIND).toInt()]
    }

    private fun seats(accounts: Map<String, SolanaRpc.Account?>, occupied: Map<Int, String> = fullBlock): LongArray {
        val (source, placement) = seated(occupied)
        return LivePetRead.seats(source, placement, accounts, program)
    }

    @Test fun nineValidNeighboursAndMySeatArePublishedInSeatOrder() {
        val values = seats(neighbourAccounts())
        assertEquals(52, LivePetRead.SeatField.entries.size)
        assertEquals(26, LivePetRead.FightField.entries.size)
        assertEquals(LivePetRead.BLOCK_SEATS * LivePetRead.SeatField.entries.size, values.size)
        val expected = List(10) { if (it == mySeat) LivePetRead.SeatKind.SELF else LivePetRead.SeatKind.LIVING }
        assertEquals(expected, values.kinds())
        val seven = 7
        fun at(field: LivePetRead.SeatField) = values.seat(seven, field)
        assertEquals(SourcePetLifecycle.Fact.HEIR_ACTIVE.ordinal.toLong(), at(LivePetRead.SeatField.LIFE))
        assertEquals(listOf(67L, 77L, 87L, 10L), listOf(LivePetRead.SeatField.FORAGE, LivePetRead.SeatField.MIGHT,
            LivePetRead.SeatField.GRIT, LivePetRead.SeatField.LEVEL).map(::at))
        assertEquals(listOf(9L, 12L), listOf(LivePetRead.SeatField.HEARTS, LivePetRead.SeatField.MAX_HEARTS).map(::at))
        assertEquals(247L, at(LivePetRead.SeatField.NAME_ID))
        assertEquals(0b1011L shl 7, at(LivePetRead.SeatField.TREE))
        assertEquals(1_007L, at(LivePetRead.SeatField.HARVEST))
        assertEquals(2_007L, at(LivePetRead.SeatField.BURROW))
        assertEquals(6L, at(LivePetRead.SeatField.MODS))
        assertEquals(1500L, at(LivePetRead.SeatField.LOOT_BPS))
        assertEquals(700L, at(LivePetRead.SeatField.BITE_GUARD_BPS))
        assertEquals(0b10_0000_0001L, at(LivePetRead.SeatField.SLOTS_ATTACKED_TODAY))
        assertEquals(listOf(41L, 1L, 2L, 1L), listOf(LivePetRead.SeatField.FIGHT_DAY, LivePetRead.SeatField.FIGHTS_OUT_TODAY,
            LivePetRead.SeatField.FIGHTS_IN_TODAY, LivePetRead.SeatField.BITES_IN_TODAY).map(::at))
        assertEquals(listOf(mySeat.toLong(), 2L, 39L), listOf(LivePetRead.SeatField.GRUDGE_SLOT, LivePetRead.SeatField.RAGE,
            LivePetRead.SeatField.RAGE_EPOCH).map(::at))
        assertEquals(listOf(5L, 41L, 1L, 1L, 2L, 11000L), listOf(LivePetRead.SeatField.BORN_EPOCH,
            LivePetRead.SeatField.LAST_TICK_EPOCH, LivePetRead.SeatField.REGION, LivePetRead.SeatField.PERSONA,
            LivePetRead.SeatField.TALENT_KIND, LivePetRead.SeatField.TALENT_BPS).map(::at))
        assertEquals(listOf(2L, 2L, 15L, 2L, 6L), listOf(LivePetRead.SeatField.HEAD_RARITY, LivePetRead.SeatField.HEAD_STAT,
            LivePetRead.SeatField.HEAD_WEAR, LivePetRead.SeatField.HEAD_SKILL, LivePetRead.SeatField.HEAD_LEVEL).map(::at))
        assertEquals(listOf(5L, 3L, 0L, 3L, 9L), listOf(LivePetRead.SeatField.FEET_RARITY, LivePetRead.SeatField.FEET_STAT,
            LivePetRead.SeatField.FEET_WEAR, LivePetRead.SeatField.FEET_SKILL, LivePetRead.SeatField.FEET_LEVEL).map(::at))
        assertEquals(0L, at(LivePetRead.SeatField.BODY_RARITY))
    }

    @Test fun mySeatIsSelfFromMyOwnPetAndNeverReadAsANeighbour() {
        val (source, placement) = seated()
        val addresses = LivePetRead.neighbourAddresses(source, placement)
        assertEquals(9, addresses.size)
        assertFalse(myAddress in addresses)
        val stranger = neighbourAccounts() + (myAddress to account(pet(mySeat, alive = false)))
        val values = LivePetRead.seats(source, placement, stranger, program)
        assertEquals(LivePetRead.SeatKind.SELF, values.kinds()[mySeat])
        assertEquals(64L, values.seat(mySeat, LivePetRead.SeatField.FORAGE))
        assertEquals(SourcePetLifecycle.Fact.HEIR_ACTIVE.ordinal.toLong(), values.seat(mySeat, LivePetRead.SeatField.LIFE))
    }

    @Test fun emptySeatIsEmptyAndNotRead() {
        val occupied = fullBlock - 2
        val (source, placement) = seated(occupied)
        assertFalse(address(2) in LivePetRead.neighbourAddresses(source, placement))
        val values = LivePetRead.seats(source, placement, neighbourAccounts() - address(2), program)
        assertEquals(LivePetRead.SeatKind.EMPTY, values.kinds()[2])
        assertTrue((1 until LivePetRead.SeatField.entries.size).all { values[2 * LivePetRead.SeatField.entries.size + it] == 0L })
    }

    @Test fun wildDeadMissingAndInvalidAreTheirOwnKinds() {
        val values = seats(neighbourAccounts(mapOf(
            0 to account(pet(0, wild = true)),
            1 to account(pet(1, alive = false)),
            2 to null,
            3 to account(pet(3, size = 272)),
            5 to account(pet(5), delegation),
            6 to account(pet(6, petBlock = 8)),
            7 to account(pet(8)),
            8 to account(pet(8, alive = false, wild = true)),
            9 to account(pet(9).also { it[0] = 0 }),
        )))
        val kinds = values.kinds()
        assertEquals(LivePetRead.SeatKind.WILD, kinds[0])
        assertEquals(LivePetRead.SeatKind.DEAD, kinds[1])
        assertEquals(SourcePetLifecycle.Fact.DEATH_RECORDED.ordinal.toLong(), values.seat(1, LivePetRead.SeatField.LIFE))
        assertEquals(LivePetRead.SeatKind.MISSING, kinds[2])
        assertEquals(List(4) { LivePetRead.SeatKind.INVALID }, listOf(kinds[3], kinds[5], kinds[6], kinds[7]))
        assertEquals(LivePetRead.SeatKind.DEAD, kinds[8])
        assertEquals(LivePetRead.SeatKind.INVALID, kinds[9])
        for (seat in listOf(2, 3, 5, 6, 7, 9)) {
            assertTrue((1 until LivePetRead.SeatField.entries.size).all {
                values[seat * LivePetRead.SeatField.entries.size + it] == 0L
            })
        }
    }

    @Test fun wrongLengthIsInvalidForEveryOtherLength() {
        for (size in listOf(272, 303, 305)) {
            val bytes = if (size > 304) pet(1) + ByteArray(size - 304) else pet(1, size = size)
            assertEquals(LivePetRead.SeatKind.INVALID, seats(neighbourAccounts(mapOf(1 to account(bytes)))).kinds()[1])
        }
    }

    @Test fun anUnreadOccupiedSeatFailsLoudAndAnUnseatedPetHasNoSeats() {
        assertThrows(SolanaRpc.Failure::class.java) { seats(neighbourAccounts() - address(3)) }
        val source = mine()
        val stranger = LivePetRead.placement(source, account(world()), account(block(fullBlock - mySeat)), program, genesis)
        assertFalse(stranger.member)
        assertEquals(emptyList<String>(), LivePetRead.neighbourAddresses(source, stranger))
        assertEquals(0, LivePetRead.seats(source, stranger, neighbourAccounts(), program).size)
        assertEquals(0, LivePetRead.seats(source, null, neighbourAccounts(), program).size)
    }

    @Test fun blockGrudgesArePublishedPerSeatAndTheFightRingOldestFirst() {
        val bytes = block(fullBlock, fightHead = 2, grudges = mapOf(mySeat to (7 to 40L), 7 to (mySeat to 41L)), fights = listOf(
            Fight(0, 40, mySeat, 7, 900, true),
            Fight(1, 41, 7, mySeat, 0, false),
            Fight(30, 38, 1, 2, 50, true),
            Fight(31, 39, 7, mySeat, 300, true),
        ))
        val (source, placement) = seated(blockBytes = bytes)
        val values = LivePetRead.seats(source, placement, neighbourAccounts(), program)
        assertEquals(listOf(7L, 40L), listOf(values.seat(mySeat, LivePetRead.SeatField.BLOCK_GRUDGE_ROBBER),
            values.seat(mySeat, LivePetRead.SeatField.BLOCK_GRUDGE_EPOCH)))
        assertEquals(41L, values.seat(7, LivePetRead.SeatField.BLOCK_GRUDGE_EPOCH))
        assertEquals(0L, values.seat(3, LivePetRead.SeatField.BLOCK_GRUDGE_EPOCH))
        val fights = LivePetRead.fights(placement)
        val width = LivePetRead.FightField.entries.size
        assertEquals(4 * width, fights.size)
        fun at(index: Int, field: LivePetRead.FightField) = fights[index * width + field.ordinal]
        assertEquals(listOf(38L, 39L, 40L, 41L), (0 until 4).map { at(it, LivePetRead.FightField.EPOCH) })
        assertEquals(listOf(7L, mySeat.toLong(), 300L, 1L), listOf(LivePetRead.FightField.ATTACKER_SEAT,
            LivePetRead.FightField.DEFENDER_SEAT, LivePetRead.FightField.LOOT, LivePetRead.FightField.ATTACKER_WON).map { at(1, it) })
        assertEquals(listOf(-2L, 5_000_000L, 3L, 90L, 7L, 2L, 60L, 11L), listOf(LivePetRead.FightField.SEED,
            LivePetRead.FightField.STAKE, LivePetRead.FightField.ROUNDS, LivePetRead.FightField.ATTACKER_MIGHT,
            LivePetRead.FightField.ATTACKER_HEARTS, LivePetRead.FightField.ATTACKER_MODS, LivePetRead.FightField.DEFENDER_MIGHT,
            LivePetRead.FightField.DEFENDER_HEARTS).map { at(3, it) })
        assertEquals(0L, at(3, LivePetRead.FightField.ATTACKER_WON))
    }

    @Test fun aCorruptFightRecordOrGrudgeFailsTheBlockRead() {
        val selfFight = block(fullBlock, fights = listOf(Fight(3, 40, 2, 2, 0, true)))
        assertThrows(SolanaRpc.Failure::class.java) { seated(blockBytes = selfFight) }
        val farSeat = block(fullBlock, fights = listOf(Fight(3, 40, 2, 10, 0, true)))
        assertThrows(SolanaRpc.Failure::class.java) { seated(blockBytes = farSeat) }
        val badGrudge = block(fullBlock, grudges = mapOf(1 to (10 to 3L)))
        assertThrows(SolanaRpc.Failure::class.java) { seated(blockBytes = badGrudge) }
        val unseated = mine()
        val stranger = LivePetRead.placement(unseated, account(world()), account(block(fullBlock - mySeat,
            fights = listOf(Fight(0, 40, 1, 2, 0, true)))), program, genesis)
        assertEquals(0, LivePetRead.fights(stranger).size)
    }
}
