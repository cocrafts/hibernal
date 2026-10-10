package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

object SourcePetRead {
    enum class Persona { Cautious, Greedy, Vengeful }
    enum class Region { Worker, Fighter, Survivor }
    enum class TalentKind { None, Forage, Might, Grit }
    enum class Insurance { None, Armed, Used }
    enum class ItemSkill { None, Revive, AntiRobbery, DamageGuard }
    enum class ItemRarity { Empty, Common, Rare, Epic, Legendary, Mythic }
    enum class OwnerItem { None, SmallFood, MediumFood, LargeFood, SmallGrowth, MediumGrowth, LargeGrowth, Insurance }
    enum class Seat(val sourceValue: Int) {
        First(0), Second(1), Third(2), Fourth(3), Fifth(4), Sixth(5), Seventh(6), Eighth(7), Ninth(8), Tenth(9), Unplaced(255)
    }

    @ConsistentCopyVisibility
    data class Item internal constructor(
        val rarity: ItemRarity, val stat: TalentKind, val wear: Int, val skill: ItemSkill, val level: Int
    )
    @ConsistentCopyVisibility
    data class Pantry internal constructor(val small: Int, val medium: Int, val large: Int)
    @ConsistentCopyVisibility
    data class Gear internal constructor(val head: Item, val body: Item, val hands: Item, val feet: Item)
    sealed interface SourceTail {
        @ConsistentCopyVisibility
        data class Historical internal constructor(val talksToday: Int) : SourceTail
        @ConsistentCopyVisibility
        data class Canonical internal constructor(
            val engagedToday: Int, val ownerFirst: OwnerItem, val ownerSecond: OwnerItem,
            val skin: Int, val wild: Boolean, val engagedRound: Int
        ) : SourceTail
    }
    @ConsistentCopyVisibility
    data class CanonicalAccountFields internal constructor(val loaded: List<Long>, val appearance: Long)
    @ConsistentCopyVisibility
    data class SourceOnlyRulesPet internal constructor(
        val tree: BigInteger,
        val harvest: BigInteger,
        val burrow: BigInteger,
        val rewardSnapshot: BigInteger,
        val bornEpoch: BigInteger,
        val lastTickEpoch: BigInteger,
        val fightDay: BigInteger,
        val growthMultiplierExpiry: BigInteger,
        val giftOwed: BigInteger,
        val ownerBankedAt: BigInteger,
        val rageEpoch: BigInteger,
        val blockId: Long,
        val xp: Long,
        val foodBps: Int,
        val experienceBps: Int,
        val lootBps: Int,
        val biteGuardBps: Int,
        val forage: Int,
        val might: Int,
        val grit: Int,
        val level: Int,
        val slotsAttackedToday: Int,
        val growthMultiplierBps: Int,
        val talentBps: Int,
        val lineageGeneration: Int,
        val slot: Seat,
        val alive: Boolean,
        val region: Region,
        val hearts: Int,
        val maxHearts: Int,
        val pointsUnspent: Int,
        val mods: Int,
        val fightsOutToday: Int,
        val fightsInToday: Int,
        val bitesInToday: Int,
        val minHearts: Int,
        val pantry: Pantry,
        val foodBoughtToday: Int,
        val talentKind: TalentKind,
        val insurance: Insurance,
        val scars: Int,
        val bonding: Int,
        val ownerFedToday: Int,
        val gear: Gear,
        val grudgeSlot: Seat,
        val rage: Int,
        val sourceTail: SourceTail
    )
    @ConsistentCopyVisibility
    data class SourceOnlyDecodedPet internal constructor(
        val sourceProfile: OwnerTransaction.SourceProfile,
        val owner: SolanaPublicKey,
        val mint: SolanaPublicKey,
        val ordinal: Long,
        val persona: Persona,
        val bump: Int,
        val nameId: Int,
        val claimedEpoch: BigInteger,
        val diedEpoch: BigInteger,
        val canonicalAccountFields: CanonicalAccountFields?,
        val pet: SourceOnlyRulesPet
    ) {
        val sourceTree: String get() = sourceProfile.sourceTree
    }

    fun decodeSourceOnly(
        account: SolanaRpc.Account,
        program: SolanaPublicKey,
        sourceProfile: OwnerTransaction.SourceProfile,
        expectedOwner: SolanaPublicKey? = null,
        expectedMint: SolanaPublicKey? = null
    ): SourceOnlyDecodedPet {
        checkSource(program.bytes.size == 32 && account.owner == program.address, "Pet program owner mismatch")
        checkSource(!account.executable, "Pet account is executable")
        val canonical = when (sourceProfile) {
            OwnerTransaction.SourceProfile.CANONICAL_B50E0B5 -> true
            OwnerTransaction.SourceProfile.HISTORICAL_D09815C6 -> false
        }
        checkSource(account.data.size == if (canonical) 304 else 272, "Pet length mismatch for $sourceProfile")
        val bytes = ByteBuffer.wrap(account.data.copyOf()).order(ByteOrder.LITTLE_ENDIAN)
        fun unsigned8(): Int = bytes.get().toInt() and 255
        fun unsigned16(): Int = bytes.short.toInt() and 65535
        fun unsigned32(): Long = bytes.int.toLong() and 0xffffffffL
        fun unsigned64(): BigInteger = BigInteger(1, ByteArray(8).also { bytes.get(it) }.reversedArray())
        fun key(): SolanaPublicKey = SolanaPublicKey(ByteArray(32).also { bytes.get(it) })
        fun padding(count: Int) {
            repeat(count) { checkSource(unsigned8() == 0, "Nonzero Pet padding at ${bytes.position() - 1}") }
        }
        fun boolean(name: String): Boolean {
            val value = unsigned8()
            checkSource(value in 0..1, "Invalid Pet $name boolean: $value")
            return value == 1
        }
        fun seat(name: String): Seat {
            val value = unsigned8()
            return Seat.entries.firstOrNull { it.sourceValue == value }
                ?: throw SolanaRpc.Failure("Invalid Pet $name: $value")
        }
        fun item(): Item = Item(
            sourceEnum(unsigned8(), ItemRarity.entries, "item rarity"),
            sourceEnum(unsigned8(), TalentKind.entries, "item stat"), unsigned8(),
            sourceEnum(unsigned8(), ItemSkill.entries, "item skill"), unsigned8()
        )
        val discriminator = ByteArray(8).also { bytes.get(it) }
        val expectedDiscriminator = MessageDigest.getInstance("SHA-256")
            .digest("account:PetAccount".toByteArray(Charsets.UTF_8)).copyOf(8)
        checkSource(discriminator.contentEquals(expectedDiscriminator), "Pet discriminator mismatch")
        val owner = key()
        val mint = key()
        checkSource(expectedOwner == null || owner == expectedOwner, "Pet embedded owner mismatch")
        checkSource(expectedMint == null || mint == expectedMint, "Pet embedded mint mismatch")
        val ordinal = unsigned32()
        val persona = sourceEnum(unsigned8(), Persona.entries, "persona")
        val bump = unsigned8()
        val nameId = unsigned8()
        padding(1)
        val claimedEpoch = unsigned64()
        val diedEpoch = unsigned64()
        val canonicalFields = if (canonical) CanonicalAccountFields(List(7) { unsigned32() }, unsigned32()) else null
        val tree = unsigned64()
        val harvest = unsigned64()
        val burrow = unsigned64()
        val rewardSnapshot = unsigned64()
        val bornEpoch = unsigned64()
        val lastTickEpoch = unsigned64()
        val fightDay = unsigned64()
        val growthMultiplierExpiry = unsigned64()
        val giftOwed = unsigned64()
        val ownerBankedAt = unsigned64()
        val rageEpoch = unsigned64()
        val blockId = unsigned32()
        val xp = unsigned32()
        val foodBps = bytes.int
        val experienceBps = bytes.int
        val lootBps = bytes.int
        val biteGuardBps = bytes.int
        val forage = unsigned16()
        val might = unsigned16()
        val grit = unsigned16()
        val level = unsigned16()
        val attacked = unsigned16()
        checkSource(attacked and 0xfc00 == 0, "Pet slotsAttackedToday has unknown BlockSlot bits")
        val growthMultiplierBps = unsigned16()
        val talentBps = unsigned16()
        val lineageGeneration = unsigned16()
        val slot = seat("slot")
        checkSource((blockId == 0xffffffffL) == (slot == Seat.Unplaced), "Pet NO_BLOCK/NO_SEAT mismatch")
        val alive = boolean("alive")
        val region = sourceEnum(unsigned8(), Region.entries, "region")
        val hearts = unsigned8()
        val maxHearts = unsigned8()
        val pointsUnspent = unsigned8()
        val mods = unsigned8()
        val fightsOutToday = unsigned8()
        val fightsInToday = unsigned8()
        val bitesInToday = unsigned8()
        val minHearts = unsigned8()
        val pantry = Pantry(unsigned8(), unsigned8(), unsigned8())
        val foodBoughtToday = unsigned8()
        val talentKind = sourceEnum(unsigned8(), TalentKind.entries, "talentKind")
        val insurance = sourceEnum(unsigned8(), Insurance.entries, "insurance")
        val scars = unsigned8()
        val bonding = bytes.get().toInt()
        val interactionsToday = unsigned8()
        val ownerFedToday = unsigned8()
        val gear = Gear(item(), item(), item(), item())
        val grudgeSlot = seat("grudgeSlot")
        val rage = unsigned8()
        val tail = if (canonical) SourceTail.Canonical(
            interactionsToday, sourceEnum(unsigned8(), OwnerItem.entries, "ownerFirst"),
            sourceEnum(unsigned8(), OwnerItem.entries, "ownerSecond"), unsigned8(), boolean("wild"), unsigned8()
        ) else {
            padding(5)
            SourceTail.Historical(interactionsToday)
        }
        checkSource(!bytes.hasRemaining(), "Pet decoder left trailing bytes")
        return SourceOnlyDecodedPet(sourceProfile, owner, mint, ordinal, persona, bump, nameId, claimedEpoch, diedEpoch,
            canonicalFields, SourceOnlyRulesPet(tree, harvest, burrow, rewardSnapshot, bornEpoch, lastTickEpoch,
                fightDay, growthMultiplierExpiry, giftOwed, ownerBankedAt, rageEpoch, blockId, xp,
                foodBps, experienceBps, lootBps, biteGuardBps, forage, might, grit, level, attacked,
                growthMultiplierBps, talentBps, lineageGeneration, slot, alive, region, hearts, maxHearts,
                pointsUnspent, mods, fightsOutToday, fightsInToday, bitesInToday, minHearts, pantry,
                foodBoughtToday, talentKind, insurance, scars, bonding, ownerFedToday, gear, grudgeSlot, rage, tail))
    }

    private fun checkSource(condition: Boolean, message: String) {
        if (!condition) throw SolanaRpc.Failure(message)
    }
    private fun <T> sourceEnum(value: Int, entries: List<T>, name: String): T =
        entries.getOrNull(value) ?: throw SolanaRpc.Failure("Invalid Pet $name: $value")
}
