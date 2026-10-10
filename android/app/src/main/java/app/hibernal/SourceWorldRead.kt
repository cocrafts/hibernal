package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

object SourceWorldRead {
    enum class Phase { Idle, Seeding, Acting }

    sealed interface SourceEconomy {
        @ConsistentCopyVisibility
        data class Historical internal constructor(
            val protocolPending: BigInteger, val burned: BigInteger
        ) : SourceEconomy
        @ConsistentCopyVisibility
        data class Canonical internal constructor(
            val treasury: BigInteger, val itemReserve: BigInteger, val emitted: BigInteger
        ) : SourceEconomy
    }

    @ConsistentCopyVisibility
    data class SourceOnlyWorld internal constructor(
        val sourceProfile: OwnerTransaction.SourceProfile,
        val genesisTimestamp: BigInteger,
        val rewardPerWorkPower: BigInteger,
        val rewardEpoch: BigInteger,
        val totalWorkPower: BigInteger,
        val recycledPending: BigInteger,
        val sourceEconomy: SourceEconomy,
        val livingPets: Long,
        val floorSlots: Long,
        val epoch: BigInteger,
        val resortEvery: BigInteger,
        val rotation: BigInteger,
        val resortedEpoch: BigInteger,
        val bump: Int,
        val resorting: Boolean,
        val unplaced: Long,
        val placed: Long,
        val secondsPerDay: BigInteger
    ) {
        val sourceTree: String get() = sourceProfile.sourceTree
    }

    @ConsistentCopyVisibility
    data class SourceOnlyBlockHead internal constructor(
        val sourceProfile: OwnerTransaction.SourceProfile,
        val id: Long,
        val filled: Int,
        val phase: Phase,
        val round: Int,
        val cursor: Int,
        val epoch: BigInteger,
        val roundSeed: BigInteger,
        val requests: BigInteger,
        val pendingRequest: BigInteger,
        val requestedAt: Long,
        val rotation: BigInteger,
        val minStrength: BigInteger,
        val maxStrength: BigInteger,
        val crankSeq: BigInteger,
        val dueSlot: BigInteger,
        val dawnedEpoch: BigInteger,
        val fightHead: Int,
        val bump: Int,
        val turns: List<Int>,
        val started: Boolean,
        val members: List<SolanaPublicKey>
    ) {
        val sourceTree: String get() = sourceProfile.sourceTree
        val decodedPrefixBytes: Int get() = 440
        val unparsedTailBytes: Int get() = 4456
    }

    fun decodeSourceOnlyWorld(
        account: SolanaRpc.Account,
        program: SolanaPublicKey,
        sourceProfile: OwnerTransaction.SourceProfile
    ): SourceOnlyWorld {
        val size = when (sourceProfile) {
            OwnerTransaction.SourceProfile.CANONICAL_B50E0B5 -> 136
            OwnerTransaction.SourceProfile.HISTORICAL_D09815C6 -> 128
        }
        val bytes = sourceBytes(account, program, size, "World")
        val genesisTimestamp = bytes.unsigned64()
        val rewardPerWorkPower = bytes.unsigned64()
        val rewardEpoch = bytes.unsigned64()
        val totalWorkPower = bytes.unsigned64()
        val recycledPending = bytes.unsigned64()
        val economy = when (sourceProfile) {
            OwnerTransaction.SourceProfile.CANONICAL_B50E0B5 -> SourceEconomy.Canonical(
                bytes.unsigned64(), bytes.unsigned64(), bytes.unsigned64())
            OwnerTransaction.SourceProfile.HISTORICAL_D09815C6 -> SourceEconomy.Historical(
                bytes.unsigned64(), bytes.unsigned64())
        }
        val livingPets = bytes.unsigned32()
        val floorSlots = bytes.unsigned32()
        val epoch = bytes.unsigned64()
        val resortEvery = bytes.unsigned64()
        val rotation = bytes.unsigned64()
        val resortedEpoch = bytes.unsigned64()
        val bump = bytes.unsigned8()
        val resorting = bytes.sourceBoolean("World resorting")
        bytes.padding(2, "World")
        val unplaced = bytes.unsigned32()
        val placed = bytes.unsigned32()
        bytes.padding(4, "World")
        val secondsPerDay = bytes.unsigned64()
        checkSource(!bytes.hasRemaining(), "World decoder left trailing bytes")
        return SourceOnlyWorld(sourceProfile, genesisTimestamp, rewardPerWorkPower, rewardEpoch,
            totalWorkPower, recycledPending, economy, livingPets, floorSlots, epoch, resortEvery,
            rotation, resortedEpoch, bump, resorting, unplaced, placed, secondsPerDay)
    }

    fun decodeSourceOnlyBlockHead(
        account: SolanaRpc.Account,
        program: SolanaPublicKey,
        sourceProfile: OwnerTransaction.SourceProfile
    ): SourceOnlyBlockHead {
        val size = when (sourceProfile) {
            OwnerTransaction.SourceProfile.CANONICAL_B50E0B5 -> 4896
            OwnerTransaction.SourceProfile.HISTORICAL_D09815C6 -> 4896
        }
        val bytes = sourceBytes(account, program, size, "Block")
        val id = bytes.unsigned32()
        val filled = bytes.unsigned8()
        checkSource(filled <= 10, "Invalid Block filled: $filled")
        val phaseValue = bytes.unsigned8()
        val phase = Phase.entries.getOrNull(phaseValue)
            ?: throw SolanaRpc.Failure("Invalid Block phase: $phaseValue")
        val round = bytes.unsigned8()
        val cursor = bytes.unsigned8()
        val epoch = bytes.unsigned64()
        val roundSeed = bytes.unsigned64()
        val requests = bytes.unsigned64()
        val pendingRequest = bytes.unsigned64()
        val requestedAt = bytes.long
        val rotation = bytes.unsigned64()
        val minStrength = bytes.unsigned64()
        val maxStrength = bytes.unsigned64()
        val crankSeq = bytes.unsigned64()
        val dueSlot = bytes.unsigned64()
        val dawnedEpoch = bytes.unsigned64()
        val fightHead = bytes.unsigned8()
        checkSource(fightHead < 32, "Invalid Block fightHead: $fightHead")
        val bump = bytes.unsigned8()
        val turns = List(10) {
            bytes.unsigned8().also { checkSource(it < 10, "Invalid Block turn seat: $it") }
        }
        val started = bytes.sourceBoolean("Block started")
        bytes.padding(3, "Block")
        val members = List(10) { SolanaPublicKey(ByteArray(32).also { bytes.get(it) }) }
        checkSource(bytes.position() == 440, "Block member prefix consumption mismatch")
        return SourceOnlyBlockHead(sourceProfile, id, filled, phase, round, cursor, epoch, roundSeed,
            requests, pendingRequest, requestedAt, rotation, minStrength, maxStrength, crankSeq,
            dueSlot, dawnedEpoch, fightHead, bump, turns, started, members)
    }

    @ConsistentCopyVisibility
    data class Combatant internal constructor(
        val might: Int, val grit: Int, val speed: Int, val armor: Int, val accuracy: Int,
        val lifesteal: Int, val bleed: Int, val hearts: Int, val mods: Int
    )

    @ConsistentCopyVisibility
    data class FightRecord internal constructor(
        val epoch: BigInteger, val seed: BigInteger, val stake: BigInteger, val loot: BigInteger,
        val attackerSeat: Int, val defenderSeat: Int, val rounds: Int,
        val attacker: Combatant, val defender: Combatant, val attackerWon: Boolean
    )

    @ConsistentCopyVisibility
    data class Grudge internal constructor(val robberSeat: Int, val epoch: BigInteger)

    @ConsistentCopyVisibility
    data class SourceOnlyBlockActivity internal constructor(
        val grudges: List<Grudge>,
        val fights: List<FightRecord>
    )

    fun decodeSourceOnlyBlockActivity(
        account: SolanaRpc.Account,
        program: SolanaPublicKey,
        sourceProfile: OwnerTransaction.SourceProfile
    ): SourceOnlyBlockActivity {
        val head = decodeSourceOnlyBlockHead(account, program, sourceProfile)
        val bytes = sourceBytes(account, program, 4896, "Block")
        bytes.position(440)
        val grudges = List(10) {
            val robber = bytes.unsigned8()
            bytes.padding(7, "Block grudge")
            Grudge(robber, bytes.unsigned64()).also { grudge ->
                checkSource(grudge.robberSeat < 10, "Invalid Block grudge robber: ${grudge.robberSeat}")
            }
        }
        val ring = List(32) {
            val start = bytes.position()
            val record = FightRecord(bytes.unsigned64(), bytes.unsigned64(), bytes.unsigned64(), bytes.unsigned64(),
                bytes.int, bytes.int, bytes.int, bytes.combatant(), bytes.combatant(), bytes.sourceBoolean("fight outcome"))
            bytes.padding(3, "Block fight")
            val unwritten = (start until start + 120).all { bytes.get(it) == 0.toByte() }
            checkSource(unwritten || (record.attackerSeat in 0..9 && record.defenderSeat in 0..9 &&
                record.attackerSeat != record.defenderSeat), "Invalid Block fight seats at $start")
            record.takeIf { !unwritten }
        }
        checkSource(bytes.position() == 4440, "Block fight ring consumption mismatch")
        val fights = List(32) { ring[(head.fightHead + it) % 32] }.filterNotNull()
        return SourceOnlyBlockActivity(grudges, fights)
    }

    private fun ByteBuffer.combatant(): Combatant {
        val values = List(8) { int }
        val mods = unsigned8()
        padding(3, "Block combatant")
        return Combatant(values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7], mods)
    }

    private fun sourceBytes(
        account: SolanaRpc.Account, program: SolanaPublicKey, size: Int, name: String
    ): ByteBuffer {
        checkSource(program.bytes.size == 32 && account.owner == program.address, "$name program owner mismatch")
        checkSource(!account.executable, "$name account is executable")
        checkSource(account.data.size == size, "$name length mismatch for explicit source profile")
        val bytes = ByteBuffer.wrap(account.data.copyOf()).order(ByteOrder.LITTLE_ENDIAN)
        val discriminator = ByteArray(8).also { bytes.get(it) }
        val expected = MessageDigest.getInstance("SHA-256")
            .digest("account:$name".toByteArray(Charsets.UTF_8)).copyOf(8)
        checkSource(discriminator.contentEquals(expected), "$name discriminator mismatch")
        return bytes
    }

    private fun ByteBuffer.unsigned8(): Int = get().toInt() and 255
    private fun ByteBuffer.unsigned32(): Long = int.toLong() and 0xffffffffL
    private fun ByteBuffer.unsigned64(): BigInteger =
        BigInteger(1, ByteArray(8).also { get(it) }.reversedArray())
    private fun ByteBuffer.sourceBoolean(name: String): Boolean {
        val value = unsigned8()
        checkSource(value in 0..1, "Invalid $name boolean: $value")
        return value == 1
    }
    private fun ByteBuffer.padding(count: Int, name: String) {
        repeat(count) { checkSource(unsigned8() == 0, "Nonzero $name padding at ${position() - 1}") }
    }
    private fun checkSource(condition: Boolean, message: String) {
        if (!condition) throw SolanaRpc.Failure(message)
    }
}
