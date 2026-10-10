package app.hibernal

import android.os.SystemClock
import com.solana.publickey.SolanaPublicKey
import com.solana.publickey.ProgramDerivedAddress
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import kotlin.coroutines.coroutineContext
import kotlin.random.Random

object GameSync {
    internal const val PROGRAM = "FqNDZWzei5gvnUnNEVXVroe3MsMZ5tibJXyGsS3omQHP"
    private const val DELEGATION = "DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh"
    internal const val CONFIG = "AZGqC5edzRUNMBbPHcfHteisMWPYaQ7dhx7BaJ5MUujC"
    private const val DEVNET_GENESIS = "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG"
    internal const val DISCOVERY_TTL_MS = 600_000L
    internal const val REFRESH_INTERVAL_MS = 30_000L
    internal const val BACKOFF_INITIAL_MS = 60_000L
    internal const val BACKOFF_CAP_MS = 300_000L
    private val CONFIG_TAG = byteArrayOf(0x9b.toByte(), 0x0c, 0xaa.toByte(), 0xe0.toByte(), 0x1e, 0xfa.toByte(), 0xcc.toByte(), 0x82.toByte())
    private val PET_TAG = byteArrayOf(0xdf.toByte(), 0xde.toByte(), 0x81.toByte(), 0x59, 0x46, 0xe7.toByte(), 0x8d.toByte(), 0xb8.toByte())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var selection: Job? = null
    private var selectedOwner: ByteArray? = null

    data class LivePet(val owner: String, val address: String, val mint: String)

    // The selected owner's Pet as last read; owner actions start from it.
    @Volatile var livePet: LivePet? = null
        private set

    // Selecting the owner already shown rediscovers behind its last read instead of blanking it.
    @Synchronized
    fun select(publicKey: ByteArray?) {
        selection?.cancel()
        selection = null
        val owner = publicKey?.takeIf { it.size == 32 }?.copyOf()
        val sameOwner = owner != null && selectedOwner?.contentEquals(owner) == true
        selectedOwner = owner
        if (!sameOwner) livePet = null
        if (owner == null) return
        val revision = VoidNative.gameOwnerRevision()
        selection = scope.launch {
            val poll = Poll(owner, SolanaRpc(SolanaRpc.DEVNET), SolanaRpc(SolanaRpc.DEVNET_ER),
                SystemClock::elapsedRealtime, Random.Default, shown = sameOwner) { publish(revision, it) }
            while (true) delay(poll.cycle() ?: return@launch)
        }
    }

    internal data class Publication(
        val state: Int,
        val baseSlot: Long = 0,
        val ephemeralSlot: Long = 0,
        val holdings: Int = -1,
        val members: Int = -1,
        val unclaimed: Int = -1,
        val detail: String,
        val pet: List<Long> = emptyList(),
        val seats: List<Long> = emptyList(),
        val fights: List<Long> = emptyList(),
    )

    private class Discovery(
        val discoveredAt: Long,
        val group: String,
        val basePetOwners: Map<String, String>,
        val ephemeralPets: List<String>,
        val heldMints: List<Pair<String, String?>>,
        val members: List<AdmissionDiscovery.Member>,
        val publication: Publication,
    ) {
        val baseKeys = (listOf(CONFIG) + basePetOwners.keys + heldMints.map { it.first } +
            heldMints.mapNotNull { it.second } + members.flatMap { listOf(it.petAddress, it.paidAddress) }).distinct()
        val ephemeralKeys = (listOf(CONFIG) + ephemeralPets + members.map { it.petAddress }).distinct()
    }

    internal class Poll(
        private val selected: ByteArray,
        private val base: SolanaRpc,
        private val ephemeral: SolanaRpc,
        private val clock: () -> Long,
        private val random: Random,
        private val wallSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
        shown: Boolean = false,
        private val publish: (Publication) -> Boolean,
    ) {
        private val address = SolanaPublicKey(selected).address
        private var cache: Discovery? = null
        private var failures = 0
        private var reported = shown
        private var placementKeys = emptyList<String>()
        private var neighbourKeys = emptyList<String>()
        private var shopKeys = emptyList<String>()

        suspend fun cycle(): Long? {
            val outcome = try {
                if (!reported && !publish(Publication(1, detail = "CHECKING PUBLIC OWNER"))) return null
                cache = cache?.takeIf { clock() - it.discoveredAt < DISCOVERY_TTL_MS }
                val publication = cache?.let { refresh(it) } ?: run {
                    cache = null
                    discover() ?: return null
                }
                failures = 0
                publication
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                coroutineContext.ensureActive()
                failures += 1
                Publication(5, detail = when (error) {
                    is SolanaRpc.RemoteFailure -> "RPC ERROR ${error.code}"
                    is SolanaRpc.Failure -> error.message ?: "RPC VALIDATION FAILED"
                    else -> "RPC FAILURE ${error.javaClass.simpleName}"
                })
            }
            coroutineContext.ensureActive()
            if (!publish(outcome)) return null
            reported = true
            if (failures == 0) return REFRESH_INTERVAL_MS
            val exponential = minOf(BACKOFF_CAP_MS, BACKOFF_INITIAL_MS shl minOf(failures - 1, 16))
            return exponential / 2 + random.nextLong(exponential / 2 + 1)
        }

        private suspend fun discover(): Publication? {
            if (base.getGenesisHash() != DEVNET_GENESIS) throw SolanaRpc.Failure("Wrong L1 genesis")
            val baseConfig = base.getAccountInfo(CONFIG)
            val group = validateConfig(baseConfig.value)
            val ephemeralConfig = ephemeral.getAccountInfo(CONFIG)
            validateConfig(ephemeralConfig.value)
            if (!baseConfig.value!!.data.contentEquals(ephemeralConfig.value!!.data)) {
                throw SolanaRpc.Failure("L1/ER config mismatch")
            }
            if (!reported && !publish(Publication(1, baseConfig.slot.longValueExact(), ephemeralConfig.slot.longValueExact(),
                    detail = "L1 / ER CONFIG MATCHED. DISCOVERING OWNER PET"))) return null
            val filters = JSONArray()
                .put(JSONObject().put("memcmp", JSONObject().put("offset", 0)
                    .put("bytes", "396BWUbnjbg=").put("encoding", "base64")))
                .put(JSONObject().put("memcmp", JSONObject().put("offset", 8).put("bytes", address)))
            val local = base.getProgramAccounts(PROGRAM, filters)
            val delegated = base.getProgramAccounts(DELEGATION, filters).let { scan ->
                scan.copy(value = scan.value.filter { petOfThisProgram(it.publicKey, it.account) })
            }
            val remote = ephemeral.getProgramAccounts(PROGRAM, filters)
            for (entry in local.value) validatePetPrefix(entry, PROGRAM, selected)
            for (entry in delegated.value) validatePetPrefix(entry, DELEGATION, selected)
            for (entry in remote.value) validatePetPrefix(entry, PROGRAM, selected)
            val holdings = base.getTokenAccountsByOwner(address)
            val admission = AdmissionDiscovery.read(base, ephemeral, holdings, address, group, PROGRAM)
            val candidates = local.value + delegated.value + remote.value
            val claimedAdmission = admission.members.any { it.claimRecordPresent }
            val state = if (candidates.isEmpty() && !claimedAdmission) 2 else 4
            val detail = when {
                candidates.isNotEmpty() -> "PET FOUND / DEPLOYED LAYOUT NOT ACCEPTED"
                claimedAdmission -> "ADMISSION CLAIM RECORD EXISTS / DO NOT CLAIM AGAIN"
                admission.unclaimed > 0 -> "ADMISSION MEMBER MATCHED / READY TO SUMMON"
                holdings.value.isEmpty() -> "NO OWNER PET / NO TOKEN-2022 HOLDINGS"
                else -> "NO OWNER PET / NO MATCHING ADMISSION MEMBER"
            }
            val baseSlot = minOf(local.slot, delegated.slot, admission.baseSlot).longValueExact()
            val ephemeralSlot = admission.ephemeralSlot?.let { minOf(it, remote.slot) } ?: remote.slot
            val publication = Publication(state, baseSlot, ephemeralSlot.longValueExact(), holdings.value.size,
                admission.members.size, admission.unclaimed, detail)
            cache = Discovery(clock(), group,
                local.value.associate { it.publicKey to PROGRAM } + delegated.value.associate { it.publicKey to DELEGATION },
                remote.value.map { it.publicKey },
                holdings.value.map { it.publicKey to TokenAdmission.heldMint(it, address) },
                admission.members, publication)
            return withPet(publication, local.value, delegated.value, remote.value, emptyMap(), emptyMap())
        }

        private suspend fun refresh(known: Discovery): Publication? {
            val baseAccounts = accounts(base, (known.baseKeys + shopKeys).distinct())
            val ephemeralAccounts = accounts(ephemeral, (known.ephemeralKeys + placementKeys + neighbourKeys).distinct())
            val group = validateConfig(baseAccounts[CONFIG])
            validateConfig(ephemeralAccounts[CONFIG])
            if (!baseAccounts[CONFIG]!!.data.contentEquals(ephemeralAccounts[CONFIG]!!.data)) {
                throw SolanaRpc.Failure("L1/ER config mismatch")
            }
            val unchanged = try {
                group == known.group && unchanged(known, baseAccounts, ephemeralAccounts)
            } catch (error: SolanaRpc.Failure) {
                false
            }
            if (!unchanged) return null
            fun held(owner: String) = known.basePetOwners.filterValues { it == owner }.keys
                .map { SolanaRpc.KeyedAccount(it, baseAccounts[it]!!) }
            return withPet(known.publication, held(PROGRAM), held(DELEGATION),
                known.ephemeralPets.map { SolanaRpc.KeyedAccount(it, ephemeralAccounts[it]!!) }, ephemeralAccounts, baseAccounts)
        }

        private suspend fun withPet(
            publication: Publication,
            local: List<SolanaRpc.KeyedAccount>,
            delegated: List<SolanaRpc.KeyedAccount>,
            remote: List<SolanaRpc.KeyedAccount>,
            fetched: Map<String, SolanaRpc.Account?>,
            baseFetched: Map<String, SolanaRpc.Account?>,
        ): Publication {
            if (local.isEmpty() && delegated.isEmpty() && remote.isEmpty()) return publication
            return try {
                val program = SolanaPublicKey.from(PROGRAM)
                val source = LivePetRead.source(local, delegated, remote, program, SolanaPublicKey.from(DELEGATION),
                    SolanaPublicKey(selected))
                var ephemeralSlot = publication.ephemeralSlot
                val accounts = fetched.toMutableMap()
                suspend fun read(keys: List<String>) {
                    val missing = keys.filter { it !in accounts }
                    if (missing.isEmpty()) return
                    val read = ephemeral.getMultipleAccounts(missing)
                    ephemeralSlot = minOf(ephemeralSlot, read.slot.longValueExact())
                    missing.zip(read.value).toMap(accounts)
                }
                val placement = if (source.onEphemeral && source.record.pet.slot != SourcePetRead.Seat.Unplaced) {
                    placementKeys = listOf(LivePetRead.worldAddress(program),
                        LivePetRead.blockAddress(program, source.record.pet.blockId))
                    read(placementKeys + neighbourKeys)
                    LivePetRead.placement(source, accounts[placementKeys[0]], accounts[placementKeys[1]], program, wallSeconds())
                } else null
                neighbourKeys = LivePetRead.neighbourAddresses(source, placement)
                read(neighbourKeys)
                val paidAt = LivePetRead.paidAddress(program, source.record.mint)
                val ledgerAt = OwnerShop.ledgerAddress(program, source.record.mint)
                val baseAccounts = baseFetched.toMutableMap()
                suspend fun readBase(keys: List<String>) {
                    val missing = keys.filter { it !in baseAccounts }
                    if (missing.isNotEmpty()) missing.zip(base.getMultipleAccounts(missing).value).toMap(baseAccounts)
                }
                readBase(listOf(CONFIG, paidAt, ledgerAt))
                val skrMint = OwnerShop.skrMint(baseAccounts[CONFIG] ?: throw SolanaRpc.Failure("Config missing on L1"))
                readBase(listOf(skrMint))
                val skrTokenProgram = baseAccounts[skrMint]?.owner ?: throw SolanaRpc.Failure("SKR mint missing on L1")
                val skrAccount = OwnerReward.associated(address, skrMint, skrTokenProgram)
                readBase(listOf(skrAccount))
                shopKeys = listOf(paidAt, ledgerAt, skrMint, skrAccount)
                val paidTotal = LivePetRead.paidTotal(baseAccounts[paidAt], source.record.mint, program)
                val loaded = source.record.canonicalAccountFields?.loaded
                    ?: throw LivePetRead.UnsupportedLayout("PET LOADED COUNTS MISSING")
                val holdings = OwnerShop.Holdings(OwnerShop.balance(baseAccounts[skrAccount], address, skrMint, skrTokenProgram),
                    OwnerShop.inTransit(OwnerShop.bought(baseAccounts[ledgerAt], source.record.mint, program), loaded))
                livePet = LivePet(SolanaPublicKey(selected).address, source.address, source.record.mint.address)
                publication.copy(state = 3, ephemeralSlot = ephemeralSlot, detail = "VALIDATED ${LivePetRead.PET_BYTES}-BYTE PET",
                    pet = LivePetRead.fields(source, placement, paidTotal, holdings).toList(),
                    seats = LivePetRead.seats(source, placement, accounts, program).toList(),
                    fights = LivePetRead.fights(placement).toList())
            } catch (error: LivePetRead.UnsupportedLayout) {
                publication.copy(state = 4, detail = error.message ?: "DEPLOYED LAYOUT NOT ACCEPTED")
            }
        }

        private suspend fun unchanged(
            known: Discovery,
            baseAccounts: Map<String, SolanaRpc.Account?>,
            ephemeralAccounts: Map<String, SolanaRpc.Account?>,
        ): Boolean {
            for ((pet, owner) in known.basePetOwners) {
                val account = baseAccounts[pet] ?: return false
                if (account.owner != owner) return false
                validatePetPrefix(SolanaRpc.KeyedAccount(pet, account), owner, selected)
            }
            for (pet in known.ephemeralPets) {
                val account = ephemeralAccounts[pet] ?: return false
                if (account.owner != PROGRAM) return false
                validatePetPrefix(SolanaRpc.KeyedAccount(pet, account), PROGRAM, selected)
            }
            for ((token, mint) in known.heldMints) {
                val account = baseAccounts[token] ?: return false
                if (TokenAdmission.heldMint(SolanaRpc.KeyedAccount(token, account), address) != mint) return false
            }
            val members = mutableListOf<AdmissionDiscovery.Member>()
            for (mint in known.heldMints.mapNotNull { it.second }.distinct().sorted()) {
                val number = TokenAdmission.memberNumber(mint, baseAccounts[mint] ?: return false, known.group) ?: continue
                val member = known.members.firstOrNull { it.mint == mint } ?: return false
                val claimed = AdmissionDiscovery.claimRecordPresent(baseAccounts[member.petAddress],
                    ephemeralAccounts[member.petAddress], baseAccounts[member.paidAddress], SolanaPublicKey.from(mint).bytes, PROGRAM)
                members.add(member.copy(memberNumber = number, claimRecordPresent = claimed))
            }
            return members == known.members
        }

        private suspend fun accounts(rpc: SolanaRpc, keys: List<String>): Map<String, SolanaRpc.Account?> {
            val accounts = mutableMapOf<String, SolanaRpc.Account?>()
            for (batch in keys.chunked(100)) batch.zip(rpc.getMultipleAccounts(batch).value).toMap(accounts)
            return accounts
        }
    }

    private suspend fun validateConfig(account: SolanaRpc.Account?): String {
        if (account == null || account.owner != PROGRAM || account.executable ||
            account.data.size != 304 || !account.data.copyOfRange(0, 8).contentEquals(CONFIG_TAG)) {
            throw SolanaRpc.Failure("Config owner/discriminator/length mismatch")
        }
        val derived = ProgramDerivedAddress.find(listOf("config".toByteArray()), SolanaPublicKey.from(PROGRAM)).getOrThrow()
        if (derived.address != CONFIG || derived.nonce.toInt() != (account.data[136].toInt() and 255)) {
            throw SolanaRpc.Failure("Config PDA/bump mismatch")
        }
        val bytes = account.data.copyOfRange(40, 72)
        if (bytes.all { it == 0.toByte() }) throw SolanaRpc.Failure("Config admission group unset")
        return SolanaPublicKey(bytes).address
    }

    // The delegation program holds delegated Pets of every program, a closed earlier deployment included.
    private suspend fun petOfThisProgram(address: String, account: SolanaRpc.Account): Boolean =
        account.data.size >= 72 && ProgramDerivedAddress.find(listOf("pet".toByteArray(), account.data.copyOfRange(40, 72)),
            SolanaPublicKey.from(PROGRAM)).getOrThrow().address == address

    private suspend fun validatePetPrefix(entry: SolanaRpc.KeyedAccount, expectedOwner: String, selected: ByteArray) {
        val account = entry.account
        if (account.owner != expectedOwner || account.executable || account.data.size !in listOf(272, 304) ||
            !account.data.copyOfRange(0, 8).contentEquals(PET_TAG) ||
            !account.data.copyOfRange(8, 40).contentEquals(selected)) {
            throw SolanaRpc.Failure("Pet candidate owner/discriminator/length mismatch")
        }
        val mint = account.data.copyOfRange(40, 72)
        val derived = ProgramDerivedAddress.find(listOf("pet".toByteArray(), mint), SolanaPublicKey.from(PROGRAM)).getOrThrow()
        if (derived.address != entry.publicKey || derived.nonce.toInt() != (account.data[77].toInt() and 255)) {
            throw SolanaRpc.Failure("Pet candidate PDA/bump mismatch")
        }
    }

    private fun publish(revision: Int, publication: Publication): Boolean = with(publication) {
        livePet?.takeIf { state == 3 }?.let { VoidNative.setDeathNoticeSeen(DeathNoticeStore.seen(it.owner, it.address)) }
        VoidNative.setGameRead(revision, state, baseSlot, ephemeralSlot, holdings, members, unclaimed, detail, pet.toLongArray(),
            seats.toLongArray(), fights.toLongArray())
    }
}
