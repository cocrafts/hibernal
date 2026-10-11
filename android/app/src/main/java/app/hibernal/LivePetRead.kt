package app.hibernal

import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger

// The one source profile the client reads; any other deployed length is UnsupportedLayout,
// never decoded by a length-selected profile.
object LivePetRead {
    val PROFILE = OwnerTransaction.SourceProfile.CANONICAL_B50E0B5
    const val PET_BYTES = 304
    const val WORLD_BYTES = 136
    const val BLOCK_BYTES = 4896
    const val PAID_BYTES = 72
    private val PAID_TAG = byteArrayOf(0xe0.toByte(), 0x1c, 0x92.toByte(), 0xd5.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0x0b, 0x03)

    class UnsupportedLayout(message: String) : Exception(message)

    // Order is the native ABI: GamePetField in native/host/host.ms, HOST_GAME_PET_FIELDS in hostLink.h.
    enum class Field {
        LIFE, DELEGATED, MEMBER, BLOCK_STARTED, BLOCK_EPOCH, WORLD_DAY, LEVEL, XP, HARVEST, BURROW,
        HEARTS, MAX_HEARTS, BONDING, GROWTH_MULTIPLIER_BPS, GROWTH_MULTIPLIER_EXPIRY, LAST_TICK_EPOCH,
        FORAGE, MIGHT, GRIT, TALENT_KIND, TALENT_BPS, TREE, PERSONA, LINEAGE_GENERATION,
        BORN_EPOCH, CLAIMED_EPOCH, DIED_EPOCH, GIFT_OWED, COMMITTED_GIFT_OWED, PAID_TOTAL, NAME_ID,
        OWNER_FIRST, OWNER_SECOND, INSURANCE, SKIN, SKR_BALANCE, ITEMS_IN_TRANSIT,
        WORLD_GENESIS_TIMESTAMP, WORLD_REWARD_PER_WORK_POWER, WORLD_REWARD_EPOCH, WORLD_TOTAL_WORK_POWER,
        WORLD_RECYCLED_PENDING, WORLD_TREASURY, WORLD_ITEM_RESERVE, WORLD_EMITTED, WORLD_LIVING_PETS, WORLD_FLOOR_SLOTS,
        HEAD_RARITY, HEAD_STAT, HEAD_WEAR, HEAD_SKILL, HEAD_LEVEL,
        BODY_RARITY, BODY_STAT, BODY_WEAR, BODY_SKILL, BODY_LEVEL,
        HANDS_RARITY, HANDS_STAT, HANDS_WEAR, HANDS_SKILL, HANDS_LEVEL,
        FEET_RARITY, FEET_STAT, FEET_WEAR, FEET_SKILL, FEET_LEVEL, WORLD_SECONDS_PER_DAY, LEDGER_REBIRTHS, CONFIG_HATCH_FEE_LAMPORTS,
    }

    const val BLOCK_SEATS = 10

    // Order is the native ABI: SeatKind in native/host/host.ms.
    enum class SeatKind { EMPTY, SELF, LIVING, WILD, DEAD, MISSING, INVALID }

    // Order is the native ABI: GameSeatField in native/host/host.ms, HOST_GAME_SEAT_FIELDS in hostLink.h.
    enum class SeatField {
        KIND, LIFE, LEVEL, HEARTS, MAX_HEARTS, FORAGE, MIGHT, GRIT, MODS, LOOT_BPS, BITE_GUARD_BPS, HARVEST, BURROW,
        BORN_EPOCH, LAST_TICK_EPOCH, FIGHT_DAY, FIGHTS_OUT_TODAY, FIGHTS_IN_TODAY, BITES_IN_TODAY, SLOTS_ATTACKED_TODAY,
        GRUDGE_SLOT, RAGE, RAGE_EPOCH, REGION, PERSONA, LINEAGE_GENERATION, TALENT_KIND, TALENT_BPS,
        BLOCK_GRUDGE_ROBBER, BLOCK_GRUDGE_EPOCH, NAME_ID, TREE,
        HEAD_RARITY, HEAD_STAT, HEAD_WEAR, HEAD_SKILL, HEAD_LEVEL,
        BODY_RARITY, BODY_STAT, BODY_WEAR, BODY_SKILL, BODY_LEVEL,
        HANDS_RARITY, HANDS_STAT, HANDS_WEAR, HANDS_SKILL, HANDS_LEVEL,
        FEET_RARITY, FEET_STAT, FEET_WEAR, FEET_SKILL, FEET_LEVEL,
    }

    const val FIGHT_RING = 32

    // Order is the native ABI: GameFightField in native/host/host.ms, HOST_GAME_FIGHT_FIELDS in hostLink.h.
    enum class FightField {
        EPOCH, SEED, STAKE, LOOT, ATTACKER_SEAT, DEFENDER_SEAT, ROUNDS, ATTACKER_WON,
        ATTACKER_MIGHT, ATTACKER_GRIT, ATTACKER_SPEED, ATTACKER_ARMOR, ATTACKER_ACCURACY, ATTACKER_LIFESTEAL,
        ATTACKER_BLEED, ATTACKER_HEARTS, ATTACKER_MODS,
        DEFENDER_MIGHT, DEFENDER_GRIT, DEFENDER_SPEED, DEFENDER_ARMOR, DEFENDER_ACCURACY, DEFENDER_LIFESTEAL,
        DEFENDER_BLEED, DEFENDER_HEARTS, DEFENDER_MODS,
    }

    class Source internal constructor(
        val address: String,
        val record: SourcePetRead.SourceOnlyDecodedPet,
        val delegated: Boolean,
        val onEphemeral: Boolean,
        // The L1 copy as of the last commit: ClaimReward pays from this one, not the ER Pet.
        val committedGiftOwed: BigInteger,
    )

    class Placement internal constructor(
        val member: Boolean,
        val blockStarted: Boolean,
        val blockEpoch: BigInteger,
        val worldDay: BigInteger,
        val world: SourceWorldRead.SourceOnlyWorld,
        val members: List<SolanaPublicKey>,
        val activity: SourceWorldRead.SourceOnlyBlockActivity?,
    )

    fun requireLayout(name: String, account: SolanaRpc.Account, bytes: Int) {
        if (account.data.size != bytes) {
            throw UnsupportedLayout("$name ${account.data.size} BYTES / CLIENT READS $bytes")
        }
    }

    // A delegated Pet lives on the ER; an undelegated one is still the L1 program account.
    fun source(
        local: List<SolanaRpc.KeyedAccount>,
        delegated: List<SolanaRpc.KeyedAccount>,
        remote: List<SolanaRpc.KeyedAccount>,
        program: SolanaPublicKey,
        delegation: SolanaPublicKey,
        owner: SolanaPublicKey,
    ): Source {
        val addresses = (local + delegated + remote).map { it.publicKey }.toSet()
        if (addresses.size != 1) throw UnsupportedLayout("${addresses.size} OWNER PETS / CLIENT READS ONE")
        val address = addresses.single()
        val isDelegated = delegated.isNotEmpty()
        val (entry, accountProgram) = when {
            isDelegated && remote.isNotEmpty() -> remote.single() to program
            isDelegated -> delegated.single() to delegation
            else -> (local.singleOrNull() ?: throw SolanaRpc.Failure("ER Pet without L1 delegation")) to program
        }
        requireLayout("PET", entry.account, PET_BYTES)
        val record = SourcePetRead.decodeSourceOnly(entry.account, accountProgram, PROFILE, owner)
        val committed = if (isDelegated && remote.isNotEmpty()) {
            requireLayout("PET", delegated.single().account, PET_BYTES)
            SourcePetRead.decodeSourceOnly(delegated.single().account, delegation, PROFILE, owner).pet.giftOwed
        } else record.pet.giftOwed
        return Source(address, record, isDelegated, isDelegated && remote.isNotEmpty(), committed)
    }

    suspend fun worldAddress(program: SolanaPublicKey): String =
        ProgramDerivedAddress.find(listOf("world".toByteArray()), program).getOrThrow().address

    suspend fun blockAddress(program: SolanaPublicKey, blockId: Long): String {
        val id = ByteArray(8) { (blockId ushr (8 * it)).toByte() }
        return ProgramDerivedAddress.find(listOf("block".toByteArray(), id), program).getOrThrow().address
    }

    fun placement(
        source: Source,
        world: SolanaRpc.Account?,
        block: SolanaRpc.Account?,
        program: SolanaPublicKey,
        nowSeconds: Long,
    ): Placement {
        if (world == null) throw SolanaRpc.Failure("ER World missing")
        requireLayout("WORLD", world, WORLD_BYTES)
        val decodedWorld = SourceWorldRead.decodeSourceOnlyWorld(world, program, PROFILE)
        if (decodedWorld.secondsPerDay.signum() == 0) throw SolanaRpc.Failure("World secondsPerDay is zero")
        val now = BigInteger.valueOf(nowSeconds)
        val worldDay = if (now < decodedWorld.genesisTimestamp) BigInteger.ZERO
            else (now - decodedWorld.genesisTimestamp) / decodedWorld.secondsPerDay
        if (block == null) return Placement(false, false, BigInteger.ZERO, worldDay, decodedWorld, emptyList(), null)
        requireLayout("BLOCK", block, BLOCK_BYTES)
        val head = SourceWorldRead.decodeSourceOnlyBlockHead(block, program, PROFILE)
        val pet = source.record.pet
        val member = head.id == pet.blockId && pet.slot != SourcePetRead.Seat.Unplaced &&
            head.members[pet.slot.sourceValue].address == source.address
        val activity = SourceWorldRead.decodeSourceOnlyBlockActivity(block, program, PROFILE)
        return Placement(member, head.started, head.epoch, worldDay, decodedWorld, head.members, activity)
    }

    private fun SolanaPublicKey.isZero() = bytes.all { it == 0.toByte() }

    fun neighbourAddresses(source: Source, placement: Placement?): List<String> {
        if (placement?.member != true) return emptyList()
        val mine = source.record.pet.slot.sourceValue
        return placement.members.withIndex()
            .filter { (seat, key) -> seat != mine && !key.isZero() }
            .map { it.value.address }
    }

    fun seats(
        source: Source,
        placement: Placement?,
        accounts: Map<String, SolanaRpc.Account?>,
        program: SolanaPublicKey,
    ): LongArray {
        if (placement?.member != true) return LongArray(0)
        val mine = source.record.pet.slot.sourceValue
        return placement.members.withIndex().map { (seat, key) ->
            val (kind, record) = when {
                seat == mine -> SeatKind.SELF to source.record
                key.isZero() -> SeatKind.EMPTY to null
                key.address !in accounts -> throw SolanaRpc.Failure("Seat $seat Pet was not read")
                else -> neighbour(seat, accounts[key.address], source.record.pet.blockId, program)
            }
            seatFields(kind, record, placement.activity!!.grudges[seat])
        }.reduce(LongArray::plus)
    }

    fun fights(placement: Placement?): LongArray {
        if (placement?.member != true) return LongArray(0)
        return placement.activity!!.fights.map { fight ->
            fun combatant(side: SourceWorldRead.Combatant) = with(side) {
                listOf(might, grit, speed, armor, accuracy, lifesteal, bleed, hearts, mods).map(Int::toLong)
            }
            val values = listOf(fight.epoch.toLong(), fight.seed.toLong(), fight.stake.toLong(), fight.loot.toLong(),
                fight.attackerSeat.toLong(), fight.defenderSeat.toLong(), fight.rounds.toLong(),
                if (fight.attackerWon) 1L else 0L) + combatant(fight.attacker) + combatant(fight.defender)
            check(values.size == FightField.entries.size) { "Fight fields incomplete" }
            values.toLongArray()
        }.fold(LongArray(0), LongArray::plus)
    }

    private fun neighbour(
        seat: Int,
        account: SolanaRpc.Account?,
        blockId: Long,
        program: SolanaPublicKey,
    ): Pair<SeatKind, SourcePetRead.SourceOnlyDecodedPet?> {
        if (account == null) return SeatKind.MISSING to null
        val record = try {
            SourcePetRead.decodeSourceOnly(account, program, PROFILE).also { SourcePetLifecycle.sourceFact(it) }
        } catch (error: SolanaRpc.Failure) {
            return SeatKind.INVALID to null
        }
        val pet = record.pet
        if (pet.blockId != blockId || pet.slot.sourceValue != seat) return SeatKind.INVALID to null
        val wild = (pet.sourceTail as SourcePetRead.SourceTail.Canonical).wild
        val kind = when {
            !pet.alive -> SeatKind.DEAD
            wild -> SeatKind.WILD
            else -> SeatKind.LIVING
        }
        return kind to record
    }

    private fun seatFields(
        kind: SeatKind,
        record: SourcePetRead.SourceOnlyDecodedPet?,
        grudge: SourceWorldRead.Grudge,
    ): LongArray {
        val values = LongArray(SeatField.entries.size)
        values[SeatField.KIND.ordinal] = kind.ordinal.toLong()
        if (record == null) return values
        val pet = record.pet
        val named = mapOf(
            SeatField.LIFE to SourcePetLifecycle.sourceFact(record).ordinal.toLong(),
            SeatField.LEVEL to pet.level.toLong(),
            SeatField.HEARTS to pet.hearts.toLong(),
            SeatField.MAX_HEARTS to pet.maxHearts.toLong(),
            SeatField.FORAGE to pet.forage.toLong(),
            SeatField.MIGHT to pet.might.toLong(),
            SeatField.GRIT to pet.grit.toLong(),
            SeatField.MODS to pet.mods.toLong(),
            SeatField.LOOT_BPS to pet.lootBps.toLong(),
            SeatField.BITE_GUARD_BPS to pet.biteGuardBps.toLong(),
            SeatField.HARVEST to pet.harvest.toLong(),
            SeatField.BURROW to pet.burrow.toLong(),
            SeatField.BORN_EPOCH to pet.bornEpoch.toLong(),
            SeatField.LAST_TICK_EPOCH to pet.lastTickEpoch.toLong(),
            SeatField.FIGHT_DAY to pet.fightDay.toLong(),
            SeatField.FIGHTS_OUT_TODAY to pet.fightsOutToday.toLong(),
            SeatField.FIGHTS_IN_TODAY to pet.fightsInToday.toLong(),
            SeatField.BITES_IN_TODAY to pet.bitesInToday.toLong(),
            SeatField.SLOTS_ATTACKED_TODAY to pet.slotsAttackedToday.toLong(),
            SeatField.GRUDGE_SLOT to pet.grudgeSlot.sourceValue.toLong(),
            SeatField.RAGE to pet.rage.toLong(),
            SeatField.RAGE_EPOCH to pet.rageEpoch.toLong(),
            SeatField.REGION to pet.region.ordinal.toLong(),
            SeatField.PERSONA to record.persona.ordinal.toLong(),
            SeatField.LINEAGE_GENERATION to pet.lineageGeneration.toLong(),
            SeatField.TALENT_KIND to pet.talentKind.ordinal.toLong(),
            SeatField.TALENT_BPS to pet.talentBps.toLong(),
            SeatField.BLOCK_GRUDGE_ROBBER to grudge.robberSeat.toLong(),
            SeatField.BLOCK_GRUDGE_EPOCH to grudge.epoch.toLong(),
            SeatField.NAME_ID to record.nameId.toLong(),
            SeatField.TREE to pet.tree.toLong(),
        )
        val gear = gearValues(pet.gear)
        val gearFields = SeatField.entries.dropWhile { it != SeatField.HEAD_RARITY }
        check(named.size + gear.size == SeatField.entries.size - 1 && gearFields.size == gear.size) {
            "Seat fields incomplete"
        }
        for ((field, value) in named + gearFields.zip(gear)) values[field.ordinal] = value
        return values
    }

    suspend fun paidAddress(program: SolanaPublicKey, mint: SolanaPublicKey): String =
        ProgramDerivedAddress.find(listOf("paid".toByteArray(), mint.bytes), program).getOrThrow().address

    // Paid.total: HBRN already minted to the owner for this mint; absent before the first ClaimReward.
    fun paidTotal(account: SolanaRpc.Account?, mint: SolanaPublicKey, program: SolanaPublicKey): BigInteger {
        if (account == null) return BigInteger.ZERO
        if (account.owner != program.address || account.executable || account.data.size != PAID_BYTES ||
            !account.data.copyOfRange(0, 8).contentEquals(PAID_TAG) || !account.data.copyOfRange(8, 40).contentEquals(mint.bytes)) {
            throw UnsupportedLayout("PAID ACCOUNT NOT ACCEPTED")
        }
        return BigInteger(1, account.data.copyOfRange(40, 48).reversedArray())
    }

    private fun gearValues(gear: SourcePetRead.Gear) = listOf(gear.head, gear.body, gear.hands, gear.feet).flatMap {
        listOf(it.rarity.ordinal, it.stat.ordinal, it.wear, it.skill.ordinal, it.level).map(Int::toLong)
    }

    fun fields(source: Source, placement: Placement?, paidTotal: BigInteger, shop: OwnerShop.Holdings): LongArray {
        val record = source.record
        val pet = record.pet
        val tail = pet.sourceTail as SourcePetRead.SourceTail.Canonical
        fun flag(value: Boolean) = if (value) 1L else 0L
        val world = placement?.world
        val economy = world?.sourceEconomy as SourceWorldRead.SourceEconomy.Canonical?
        fun worldValue(value: BigInteger?) = (value ?: BigInteger.ZERO).toLong()
        val values = mapOf(
            Field.LIFE to SourcePetLifecycle.sourceFact(record).ordinal.toLong(),
            Field.DELEGATED to flag(source.delegated),
            Field.MEMBER to flag(source.onEphemeral && placement?.member == true),
            Field.BLOCK_STARTED to flag(placement?.blockStarted == true),
            Field.BLOCK_EPOCH to (placement?.blockEpoch ?: BigInteger.ZERO).toLong(),
            Field.WORLD_DAY to (placement?.worldDay ?: BigInteger.ZERO).toLong(),
            Field.LEVEL to pet.level.toLong(),
            Field.XP to pet.xp,
            Field.HARVEST to pet.harvest.toLong(),
            Field.BURROW to pet.burrow.toLong(),
            Field.HEARTS to pet.hearts.toLong(),
            Field.MAX_HEARTS to pet.maxHearts.toLong(),
            Field.BONDING to pet.bonding.toLong(),
            Field.GROWTH_MULTIPLIER_BPS to pet.growthMultiplierBps.toLong(),
            Field.GROWTH_MULTIPLIER_EXPIRY to pet.growthMultiplierExpiry.toLong(),
            Field.LAST_TICK_EPOCH to pet.lastTickEpoch.toLong(),
            Field.FORAGE to pet.forage.toLong(),
            Field.MIGHT to pet.might.toLong(),
            Field.GRIT to pet.grit.toLong(),
            Field.TALENT_KIND to pet.talentKind.ordinal.toLong(),
            Field.TALENT_BPS to pet.talentBps.toLong(),
            Field.TREE to pet.tree.toLong(),
            Field.PERSONA to record.persona.ordinal.toLong(),
            Field.LINEAGE_GENERATION to pet.lineageGeneration.toLong(),
            Field.BORN_EPOCH to pet.bornEpoch.toLong(),
            Field.CLAIMED_EPOCH to record.claimedEpoch.toLong(),
            Field.DIED_EPOCH to record.diedEpoch.toLong(),
            Field.GIFT_OWED to pet.giftOwed.toLong(),
            Field.COMMITTED_GIFT_OWED to source.committedGiftOwed.toLong(),
            Field.PAID_TOTAL to paidTotal.toLong(),
            Field.NAME_ID to record.nameId.toLong(),
            Field.OWNER_FIRST to tail.ownerFirst.ordinal.toLong(),
            Field.OWNER_SECOND to tail.ownerSecond.ordinal.toLong(),
            Field.INSURANCE to pet.insurance.ordinal.toLong(),
            Field.SKIN to tail.skin.toLong(),
            Field.SKR_BALANCE to shop.skrBalance.longValueExact(),
            Field.ITEMS_IN_TRANSIT to shop.inTransit,
            Field.WORLD_GENESIS_TIMESTAMP to worldValue(world?.genesisTimestamp),
            Field.WORLD_REWARD_PER_WORK_POWER to worldValue(world?.rewardPerWorkPower),
            Field.WORLD_REWARD_EPOCH to worldValue(world?.rewardEpoch),
            Field.WORLD_TOTAL_WORK_POWER to worldValue(world?.totalWorkPower),
            Field.WORLD_RECYCLED_PENDING to worldValue(world?.recycledPending),
            Field.WORLD_TREASURY to worldValue(economy?.treasury),
            Field.WORLD_ITEM_RESERVE to worldValue(economy?.itemReserve),
            Field.WORLD_EMITTED to worldValue(economy?.emitted),
            Field.WORLD_LIVING_PETS to (world?.livingPets ?: 0L),
            Field.WORLD_FLOOR_SLOTS to (world?.floorSlots ?: 0L),
            Field.WORLD_SECONDS_PER_DAY to worldValue(world?.secondsPerDay),
            Field.LEDGER_REBIRTHS to shop.rebirths,
            Field.CONFIG_HATCH_FEE_LAMPORTS to shop.hatchFeeLamports,
        ) + Field.entries.dropWhile { it != Field.HEAD_RARITY }.zip(gearValues(pet.gear))
        check(values.size == Field.entries.size) { "Live Pet fields incomplete" }
        return LongArray(Field.entries.size) { values.getValue(Field.entries[it]) }
    }
}
