package app.hibernal

import com.funkatronics.encoders.Base58
import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.util.Base64
import kotlin.random.Random
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class GameSyncPollTest {
    private val program = GameSync.PROGRAM
    private val config = GameSync.CONFIG
    private val owner = ByteArray(32) { 8 }
    private val mint = ByteArray(32) { 7 }
    private val group = ByteArray(32) { 9 }
    private val skrMint = ByteArray(32) { 11 }
    private val tokenAccount = SolanaPublicKey(ByteArray(32) { 10 }).address
    private val mintAddress = SolanaPublicKey(mint).address
    private fun derive(seed: String) = runBlocking {
        ProgramDerivedAddress.find(listOf(seed.toByteArray(), mint), SolanaPublicKey.from(program)).getOrThrow()
    }
    private val petAddress = derive("pet").address
    private val paidAddress = derive("paid").address

    private class Chain {
        val base = mutableMapOf<String, SolanaRpc.Account>()
        val ephemeral = mutableMapOf<String, SolanaRpc.Account>()
        val calls = mutableListOf<String>()
        var slot = 100L
        var failure: Exception? = null
        fun count(method: String) = calls.count { it.endsWith(":$method") }
    }

    private class FakeRpc(endpoint: String, val chain: Chain) : SolanaRpc(endpoint) {
        private val side = if (endpoint == SolanaRpc.DEVNET) "base" else "ephemeral"
        private val accounts get() = if (side == "base") chain.base else chain.ephemeral
        override suspend fun call(method: String, params: JSONArray): Any {
            chain.calls.add("$side:$method")
            chain.failure?.let { throw it }
            val result: Any = when (method) {
                "getGenesisHash" -> "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG"
                "getAccountInfo" -> context(json(accounts[params.getString(0)]))
                "getMultipleAccounts" -> params.getJSONArray(0).let { keys ->
                    context(JSONArray((0 until keys.length()).map { json(accounts[keys.getString(it)]) }))
                }
                "getProgramAccounts" -> {
                    val filter = Base58.decode(params.getJSONObject(1).getJSONArray("filters")
                        .getJSONObject(1).getJSONObject("memcmp").getString("bytes"))
                    keyed { it.owner == params.getString(0) && it.data.size >= 72 &&
                        it.data[0] == 0xdf.toByte() && it.data.copyOfRange(8, 40).contentEquals(filter) }
                }
                "getTokenAccountsByOwner" -> {
                    val filter = SolanaPublicKey.from(params.getString(0)).bytes
                    keyed { it.owner == SolanaRpc.TOKEN_2022 && it.data.size == 165 && it.data.copyOfRange(32, 64).contentEquals(filter) }
                }
                else -> error("Unexpected fake RPC method $method")
            }
            val text = JSONObject().put("jsonrpc", "2.0").put("id", 1).put("result", result).toString()
            return SolanaRpc.parseResponse(text.toByteArray(), 1)
        }
        private fun keyed(match: (SolanaRpc.Account) -> Boolean) = context(JSONArray(accounts.filter { match(it.value) }.map {
            JSONObject().put("pubkey", it.key).put("account", json(it.value))
        }))
        private fun context(value: Any) = JSONObject().put("context", JSONObject().put("slot", chain.slot)).put("value", value)
        private fun json(account: SolanaRpc.Account?): Any = account?.let {
            JSONObject().put("owner", it.owner).put("lamports", 1).put("executable", it.executable)
                .put("data", JSONArray().put(Base64.getEncoder().encodeToString(it.data)).put("base64"))
        } ?: JSONObject.NULL
    }

    private fun configAccount(groupBytes: ByteArray = group) = SolanaRpc.Account(program, BigInteger.ONE, false, ByteArray(GameSync.CONFIG_BYTES).also {
        byteArrayOf(0x9b.toByte(), 0x0c, 0xaa.toByte(), 0xe0.toByte(), 0x1e, 0xfa.toByte(), 0xcc.toByte(), 0x82.toByte()).copyInto(it)
        groupBytes.copyInto(it, 40)
        skrMint.copyInto(it, 176)
        it[136] = runBlocking { ProgramDerivedAddress.find(listOf("config".toByteArray()), SolanaPublicKey.from(program)).getOrThrow() }.nonce.toByte()
    })
    private fun pet() = SolanaRpc.Account(program, BigInteger.ONE, false, ByteArray(272).also {
        byteArrayOf(0xdf.toByte(), 0xde.toByte(), 0x81.toByte(), 0x59, 0x46, 0xe7.toByte(), 0x8d.toByte(), 0xb8.toByte()).copyInto(it)
        owner.copyInto(it, 8)
        mint.copyInto(it, 40)
        it[77] = derive("pet").nonce.toByte()
    })
    private fun paid() = SolanaRpc.Account(program, BigInteger.ONE, false, ByteArray(72).also {
        byteArrayOf(0xe0.toByte(), 0x1c, 0x92.toByte(), 0xd5.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0x0b, 0x03).copyInto(it)
        mint.copyInto(it, 8)
        it[64] = derive("paid").nonce.toByte()
    })
    private fun token() = SolanaRpc.Account(SolanaRpc.TOKEN_2022, BigInteger.ONE, false, ByteArray(165).also {
        mint.copyInto(it, 0); owner.copyInto(it, 32); it[64] = 1; it[108] = 1
    })
    private fun tlv(kind: Int, value: ByteArray) = byteArrayOf(kind.toByte(), 0, value.size.toByte(), 0) + value
    private fun memberMint() = SolanaRpc.Account(SolanaRpc.TOKEN_2022, BigInteger.ONE, false,
        ByteArray(166).also { it[45] = 1; it[165] = 1 } +
            tlv(22, ByteArray(64).also { mint.copyInto(it, 32) }) +
            tlv(23, ByteArray(72).also { mint.copyInto(it, 0); group.copyInto(it, 32); it[64] = 5 }))

    private fun chain() = Chain().also {
        it.base[config] = configAccount()
        it.base[SolanaPublicKey(skrMint).address] =
            SolanaRpc.Account("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", BigInteger.ONE, false, ByteArray(82))
        it.ephemeral[config] = configAccount()
    }
    private fun poll(chain: Chain, clock: LongArray, published: MutableList<GameSync.Publication>, random: Random = Random(7), selected: ByteArray = owner) =
        GameSync.Poll(selected, FakeRpc(SolanaRpc.DEVNET, chain), FakeRpc(SolanaRpc.DEVNET_ER, chain), { clock[0] }, random) {
            published.add(it); true
        }
    private fun cycle(poll: GameSync.Poll) = runBlocking { poll.cycle() }

    @Test fun emptyOwnerDiscoversOnceThenRefreshesConfigInOneBatchPerEndpoint() {
        val chain = chain()
        val clock = longArrayOf(0)
        val published = mutableListOf<GameSync.Publication>()
        val poll = poll(chain, clock, published)
        assertEquals(GameSync.REFRESH_INTERVAL_MS, cycle(poll))
        assertEquals(listOf("base:getGenesisHash", "base:getAccountInfo", "ephemeral:getAccountInfo", "base:getProgramAccounts",
            "base:getProgramAccounts", "ephemeral:getProgramAccounts", "base:getTokenAccountsByOwner"), chain.calls)
        val discovered = published.last()
        assertEquals(GameSync.Publication(2, 100, 100, 0, 0, 0, "NO OWNER PET / NO TOKEN-2022 HOLDINGS"), discovered)
        for (step in 1..19) {
            chain.calls.clear()
            published.clear()
            chain.slot += 75
            clock[0] = step * GameSync.REFRESH_INTERVAL_MS
            assertEquals(GameSync.REFRESH_INTERVAL_MS, cycle(poll))
            assertEquals(listOf("base:getMultipleAccounts", "ephemeral:getMultipleAccounts"), chain.calls)
            assertEquals(listOf(discovered), published)
        }
    }

    @Test fun aDelegatedPetOfAnEarlierProgramIsNotThisOwnersPet() {
        val chain = chain()
        val earlier = runBlocking { ProgramDerivedAddress.find(listOf("pet".toByteArray(), mint),
            SolanaPublicKey.from("B1zQCgVyS3qVUKCzRv6Rje79mou45fHuz7dc415ukh1o")).getOrThrow().address }
        chain.base[earlier] = canonicalPet(delegationProgram)
        val published = mutableListOf<GameSync.Publication>()
        cycle(poll(chain, longArrayOf(0), published))
        assertEquals(GameSync.Publication(2, 100, 100, 0, 0, 0, "NO OWNER PET / NO TOKEN-2022 HOLDINGS"), published.last())
    }

    @Test fun discoveryExpiresAndRunsTheScansAgain() {
        val chain = chain()
        val clock = longArrayOf(0)
        val poll = poll(chain, clock, mutableListOf())
        cycle(poll)
        clock[0] = GameSync.DISCOVERY_TTL_MS - 1
        cycle(poll)
        assertEquals(3, chain.count("getProgramAccounts"))
        clock[0] = GameSync.DISCOVERY_TTL_MS
        cycle(poll)
        assertEquals(6, chain.count("getProgramAccounts"))
    }

    @Test fun configIsReReadEachRefreshAndAGroupChangeRediscovers() {
        val chain = chain()
        val published = mutableListOf<GameSync.Publication>()
        val poll = poll(chain, longArrayOf(0), published)
        cycle(poll)
        chain.base[config] = configAccount().also { it.data[200] = 1 }
        chain.calls.clear()
        cycle(poll)
        assertEquals(GameSync.Publication(5, detail = "L1/ER config mismatch"), published.last())
        assertEquals(listOf("base:getMultipleAccounts", "ephemeral:getMultipleAccounts"), chain.calls)
        chain.base[config] = configAccount(ByteArray(32) { 11 })
        cycle(poll)
        assertEquals("L1/ER config mismatch", published.last().detail)
        assertEquals(5, published.last().state)
        chain.ephemeral[config] = configAccount(ByteArray(32) { 11 })
        chain.calls.clear()
        cycle(poll)
        assertEquals(1, chain.count("getGenesisHash"))
        assertEquals(3, chain.count("getProgramAccounts"))
        assertEquals(2, published.last().state)
    }

    @Test fun anotherOwnerNeverReusesTheDiscovery() {
        val chain = chain()
        val clock = longArrayOf(0)
        cycle(poll(chain, clock, mutableListOf()))
        chain.calls.clear()
        cycle(poll(chain, clock, mutableListOf(), selected = ByteArray(32) { 12 }))
        assertEquals(3, chain.count("getProgramAccounts"))
    }

    @Test fun foundPetIsRefreshedByAddressAndItsDisappearanceRediscoversInTheSameCycle() {
        val chain = chain()
        chain.base[petAddress] = pet()
        val published = mutableListOf<GameSync.Publication>()
        val poll = poll(chain, longArrayOf(0), published)
        cycle(poll)
        assertEquals(4, published.last().state)
        chain.calls.clear()
        cycle(poll)
        assertEquals(0, chain.count("getProgramAccounts"))
        assertEquals(4, published.last().state)
        chain.base.remove(petAddress)
        chain.calls.clear()
        cycle(poll)
        assertEquals(3, chain.count("getProgramAccounts"))
        assertEquals("NO OWNER PET / NO TOKEN-2022 HOLDINGS", published.last().detail)
    }

    @Test fun admissionMemberIsRefreshedByAddressAndANewClaimRecordRediscovers() {
        val chain = chain()
        chain.base[tokenAccount] = token()
        chain.base[mintAddress] = memberMint()
        val published = mutableListOf<GameSync.Publication>()
        val poll = poll(chain, longArrayOf(0), published)
        cycle(poll)
        assertEquals(GameSync.Publication(2, 100, 100, 1, 1, 1, "ADMISSION MEMBER MATCHED / READY TO SUMMON"), published.last())
        chain.calls.clear()
        cycle(poll)
        assertEquals(listOf("base:getMultipleAccounts", "ephemeral:getMultipleAccounts"), chain.calls)
        assertEquals(1, published.last().unclaimed)
        chain.base[paidAddress] = paid()
        chain.calls.clear()
        cycle(poll)
        assertEquals(3, chain.count("getProgramAccounts"))
        assertEquals(GameSync.Publication(4, 100, 100, 1, 1, 0, "ADMISSION CLAIM RECORD EXISTS / DO NOT CLAIM AGAIN"), published.last())
    }

    @Test fun throttledReadsBackOffWithJitterUpToTheCapAndKeepTheDiscovery() {
        val chain = chain()
        val published = mutableListOf<GameSync.Publication>()
        val poll = poll(chain, longArrayOf(0), published)
        cycle(poll)
        val delays = mutableListOf<Long>()
        chain.failure = SolanaRpc.Failure("RPC HTTP status 429")
        repeat(6) {
            delays.add(cycle(poll)!!)
            assertEquals(GameSync.Publication(5, detail = "RPC HTTP status 429"), published.last())
        }
        val windows = listOf(60_000L, 120_000L, 240_000L, 300_000L, 300_000L, 300_000L)
        for ((delay, window) in delays.zip(windows)) assertTrue("$delay in $window", delay in window / 2..window)
        assertTrue(delays.all { it >= GameSync.REFRESH_INTERVAL_MS })
        assertTrue(delays.toSet().size > 1)
        chain.failure = SolanaRpc.RemoteFailure(BigInteger.valueOf(-32005), "Too many requests")
        assertTrue(cycle(poll)!! in GameSync.BACKOFF_CAP_MS / 2..GameSync.BACKOFF_CAP_MS)
        assertEquals(GameSync.Publication(5, detail = "RPC ERROR -32005"), published.last())
        chain.failure = null
        chain.calls.clear()
        assertEquals(GameSync.REFRESH_INTERVAL_MS, cycle(poll))
        assertEquals(listOf("base:getMultipleAccounts", "ephemeral:getMultipleAccounts"), chain.calls)
        assertEquals(2, published.last().state)
    }

    @Test fun backoffIsDeterministicForAnInjectedRandom() {
        fun delays(seed: Int): List<Long> {
            val chain = chain().also { it.failure = SolanaRpc.Failure("RPC transport failed: IOException") }
            val poll = poll(chain, longArrayOf(0), mutableListOf(), Random(seed))
            return List(4) { cycle(poll)!! }
        }
        assertEquals(delays(3), delays(3))
        assertNotEquals(delays(3), delays(4))
    }

    private val delegationProgram = "DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh"
    private val genesis = 1_700_000_000L
    private val programKey = SolanaPublicKey.from(program)
    private val worldAddress = runBlocking { LivePetRead.worldAddress(programKey) }
    private val blockAddress = runBlocking { LivePetRead.blockAddress(programKey, 7) }
    private fun tag(name: String) = java.security.MessageDigest.getInstance("SHA-256").digest("account:$name".toByteArray()).copyOf(8)
    private fun little(bytes: ByteArray, offset: Int, width: Int, value: Long) {
        repeat(width) { bytes[offset + it] = (value ushr (8 * it)).toByte() }
    }
    private fun canonicalPet(accountOwner: String, hearts: Int = 8) = SolanaRpc.Account(accountOwner, BigInteger.ONE, false, ByteArray(304).also {
        tag("PetAccount").copyInto(it)
        owner.copyInto(it, 8)
        mint.copyInto(it, 40)
        it[77] = derive("pet").nonce.toByte()
        little(it, 216, 4, 7)
        little(it, 220, 4, 191)
        little(it, 246, 2, 2)
        it[256] = 4
        it[257] = 1
        it[259] = hearts.toByte()
        it[260] = 18
    })
    private fun worldAccount() = SolanaRpc.Account(program, BigInteger.ONE, false, ByteArray(136).also {
        tag("World").copyInto(it)
        little(it, 8, 8, genesis)
        little(it, 128, 8, 600)
    })
    private fun blockAccount(member: String = petAddress) = SolanaRpc.Account(program, BigInteger.ONE, false, ByteArray(4896).also {
        tag("Block").copyInto(it)
        little(it, 8, 4, 7)
        it[12] = 1
        little(it, 16, 8, 41)
        repeat(10) { seat -> it[106 + seat] = seat.toByte() }
        it[116] = 1
        SolanaPublicKey.from(member).bytes.copyInto(it, 120 + 32 * 4)
    })
    private fun placedChain() = chain().also {
        it.base[petAddress] = canonicalPet(delegationProgram)
        it.ephemeral[petAddress] = canonicalPet(program)
        it.ephemeral[worldAddress] = worldAccount()
        it.ephemeral[blockAddress] = blockAccount()
    }
    private fun livePoll(chain: Chain, published: MutableList<GameSync.Publication>) =
        GameSync.Poll(owner, FakeRpc(SolanaRpc.DEVNET, chain), FakeRpc(SolanaRpc.DEVNET_ER, chain), { 0L }, Random(7),
            { genesis + 41 * 600 + 5 }) { published.add(it); true }
    private fun GameSync.Publication.field(field: LivePetRead.Field) = pet[field.ordinal]

    @Test fun delegatedPlacedPetIsPublishedWithMembershipAndTheClockDay() {
        val chain = placedChain()
        val published = mutableListOf<GameSync.Publication>()
        cycle(livePoll(chain, published))
        val read = published.last()
        assertEquals(3, read.state)
        assertEquals(LivePetRead.Field.entries.size, read.pet.size)
        assertEquals(1L, read.field(LivePetRead.Field.DELEGATED))
        assertEquals(1L, read.field(LivePetRead.Field.MEMBER))
        assertEquals(41L, read.field(LivePetRead.Field.BLOCK_EPOCH))
        assertEquals(41L, read.field(LivePetRead.Field.WORLD_DAY))
        assertEquals(8L, read.field(LivePetRead.Field.HEARTS))
        assertEquals(4, chain.count("getMultipleAccounts"))
    }

    @Test fun refreshReReadsTheLivePetBodyAndPlacementInTheSameTwoBatches() {
        val chain = placedChain()
        val published = mutableListOf<GameSync.Publication>()
        val poll = livePoll(chain, published)
        cycle(poll)
        chain.ephemeral[petAddress] = canonicalPet(program, hearts = 5)
        chain.calls.clear()
        published.clear()
        cycle(poll)
        assertEquals(listOf("base:getMultipleAccounts", "ephemeral:getMultipleAccounts"), chain.calls)
        assertEquals(1, published.size)
        assertEquals(5L, published.single().field(LivePetRead.Field.HEARTS))
        chain.ephemeral[blockAddress] = blockAccount(SolanaPublicKey(ByteArray(32) { 13 }).address)
        cycle(poll)
        assertEquals(3, published.last().state)
        assertEquals(0L, published.last().field(LivePetRead.Field.MEMBER))
    }

    @Test fun aLiveResultIsNeverReplacedByCheckingOnLaterCycles() {
        val chain = placedChain()
        val published = mutableListOf<GameSync.Publication>()
        val poll = livePoll(chain, published)
        cycle(poll)
        assertEquals(1, published.first().state)
        published.clear()
        repeat(3) { cycle(poll) }
        assertTrue(published.all { it.state == 3 })
    }

    @Test fun rediscoveringTheShownOwnerPublishesOnlyTheNewRead() {
        val chain = placedChain()
        val published = mutableListOf<GameSync.Publication>()
        val poll = GameSync.Poll(owner, FakeRpc(SolanaRpc.DEVNET, chain), FakeRpc(SolanaRpc.DEVNET_ER, chain), { 0L },
            Random(7), { genesis + 41 * 600 + 5 }, shown = true) { published.add(it); true }
        cycle(poll)
        assertEquals(1, published.size)
        assertTrue(published.none { it.state == 1 })
    }

    @Test fun historicalPetLayoutIsPublishedAsUnsupported() {
        val chain = chain()
        chain.base[petAddress] = pet()
        val published = mutableListOf<GameSync.Publication>()
        cycle(poll(chain, longArrayOf(0), published))
        assertEquals(GameSync.Publication(4, 100, 100, 0, 0, 0, "PET 272 BYTES / CLIENT READS 304"), published.last())
    }

    private fun neighbourAddress(seat: Int) = SolanaPublicKey(ByteArray(32) { (seat + 40).toByte() }).address
    private fun neighbourPet(seat: Int) = canonicalPet(program).let { it.copy(data = it.data.copyOf().also { bytes ->
        bytes[256] = seat.toByte()
        bytes.fill(seat.toByte(), 8, 40)
    }) }
    private fun GameSync.Publication.seatKind(seat: Int) =
        LivePetRead.SeatKind.entries[seats[seat * LivePetRead.SeatField.entries.size].toInt()]

    @Test fun neighboursRideTheRefreshBatchAfterTheBlockNamesThem() {
        val chain = placedChain()
        chain.ephemeral[blockAddress] = blockAccount().also { block ->
            for (seat in listOf(1, 7)) SolanaPublicKey.from(neighbourAddress(seat)).bytes.copyInto(block.data, 120 + 32 * seat)
        }
        chain.ephemeral[neighbourAddress(1)] = neighbourPet(1)
        val published = mutableListOf<GameSync.Publication>()
        val poll = livePoll(chain, published)
        cycle(poll)
        assertEquals(published.last().detail, 5, chain.count("getMultipleAccounts"))
        val first = published.last()
        assertEquals(3, first.state)
        assertEquals(LivePetRead.BLOCK_SEATS * LivePetRead.SeatField.entries.size, first.seats.size)
        assertEquals(LivePetRead.SeatKind.LIVING, first.seatKind(1))
        assertEquals(LivePetRead.SeatKind.SELF, first.seatKind(4))
        assertEquals(LivePetRead.SeatKind.MISSING, first.seatKind(7))
        assertEquals(LivePetRead.SeatKind.EMPTY, first.seatKind(0))
        assertEquals(emptyList<Long>(), first.fights)
        chain.ephemeral[neighbourAddress(7)] = neighbourPet(7)
        chain.calls.clear()
        cycle(poll)
        assertEquals(listOf("base:getMultipleAccounts", "ephemeral:getMultipleAccounts"), chain.calls)
        assertEquals(LivePetRead.SeatKind.LIVING, published.last().seatKind(7))
    }

    @Test fun aPetWithoutABlockSeatPublishesNoSeats() {
        val chain = placedChain()
        chain.ephemeral[blockAddress] = blockAccount(SolanaPublicKey(ByteArray(32) { 13 }).address)
        val published = mutableListOf<GameSync.Publication>()
        cycle(livePoll(chain, published))
        assertEquals(3, published.last().state)
        assertEquals(emptyList<Long>(), published.last().seats)
    }
}
