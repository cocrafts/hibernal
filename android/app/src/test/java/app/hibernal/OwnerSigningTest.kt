package app.hibernal

import com.solana.mobilewalletadapter.clientlib.AdapterOperations
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import com.solana.mobilewalletadapter.clientlib.protocol.JsonRpc20Client.JsonRpc20RemoteException
import com.solana.mobilewalletadapter.clientlib.protocol.MobileWalletAdapterClient.AuthorizationResult
import com.solana.mobilewalletadapter.clientlib.protocol.MobileWalletAdapterClient.SignPayloadsResult
import com.solana.mobilewalletadapter.common.ProtocolContract
import com.solana.publickey.SolanaPublicKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.lang.reflect.Proxy
import java.math.BigInteger

class OwnerSigningTest {
    private val owner = address(1)
    private val program = address(90)
    private val blockhash = address(91)
    private val signature = ByteArray(64) { (it + 7).toByte() }
    private val lastValid = BigInteger.valueOf(1_000)

    private fun unsigned() = OwnerTransaction.prepareSourceOnly(
        OwnerTransaction.canonicalBank(program, owner, address(2), address(3)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)

    private fun preview(observedHeight: Long = 900, simulationError: Any? = null) = OwnerPreflight.SourceOnlyPreview(
        unsigned(), SolanaRpc.DEVNET_ER, BigInteger.TEN, lastValid, BigInteger.valueOf(observedHeight),
        SolanaRpc.ContextValue(BigInteger.TEN, BigInteger.ZERO),
        SolanaRpc.ContextValue(BigInteger.TEN, SolanaRpc.Simulation(simulationError, emptyList(), BigInteger.ONE)))

    private fun signedBytes() = byteArrayOf(1) + signature + unsigned().messageBytes

    // Stands in for MobileWalletAdapter.transact: the block runs against fake wallet operations, a
    // thrown exception becomes Failure as the clientlib returns it.
    private class FakeWallet(
        val authorizedKey: ByteArray,
        val answer: (Array<ByteArray>) -> Array<ByteArray>,
        val outcome: TransactionResult<Array<ByteArray>>? = null,
    ) : OwnerSigning.Wallet {
        val calls = mutableListOf<String>()
        override suspend fun transact(
            block: suspend (AdapterOperations, AuthorizationResult) -> Array<ByteArray>,
        ): TransactionResult<Array<ByteArray>> {
            calls += "transact"
            outcome?.let { return it }
            val operations = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(AdapterOperations::class.java)) { _, method, arguments ->
                calls += method.name
                when {
                    method.name == "signTransactions" && arguments[0] is Array<*> && (arguments[0] as Array<*>).all { it is ByteArray } -> {
                        @Suppress("UNCHECKED_CAST")
                        SignPayloadsResult(answer(arguments[0] as Array<ByteArray>))
                    }
                    else -> throw UnsupportedOperationException(method.name)
                }
            } as AdapterOperations
            val authorization = AuthorizationResult.create("rotatedToken", authorizedKey, null, null)
            return try {
                TransactionResult.Success(block(operations, authorization), authorization)
            } catch (error: Exception) {
                TransactionResult.Failure("fake transact failure", error)
            }
        }
    }

    private fun signingWallet() = FakeWallet(SolanaPublicKey.from(owner).bytes, { payloads ->
        assertEquals(1, payloads.size)
        assertArrayEquals(unsigned().transactionBytes, payloads[0])
        arrayOf(signedBytes())
    })

    private fun failing(error: Exception) =
        FakeWallet(SolanaPublicKey.from(owner).bytes, { error("unused") }, TransactionResult.Failure("failed", error))

    private fun refused(answer: OwnerSigning.WalletAnswer) = answer as OwnerSigning.WalletAnswer.Refused

    @Test fun walletSignsReviewedEnvelopeThroughSignTransactionsOnly() = runBlocking {
        val wallet = signingWallet()
        val answer = OwnerSigning.sign(preview(), wallet) as OwnerSigning.WalletAnswer.Signed
        assertArrayEquals(signedBytes(), answer.shape.transactionBytes)
        assertArrayEquals(signature, answer.shape.signatureBytes)
        assertEquals("rotatedToken", answer.authToken)
        assertEquals(listOf("transact", "signTransactions"), wallet.calls)
    }

    @Test fun walletDeclineIsCancelledNotFailure() = runBlocking {
        val declined = refused(OwnerSigning.sign(preview(),
            failing(JsonRpc20RemoteException(ProtocolContract.ERROR_NOT_SIGNED, "declined", null))))
        assertEquals(OwnerSigning.Outcome.CANCELLED, declined.outcome)
        val closed = refused(OwnerSigning.sign(preview(), failing(Exception(CancellationException("closed")))))
        assertEquals(OwnerSigning.Outcome.CANCELLED, closed.outcome)
    }

    @Test fun walletErrorsAreFailures() = runBlocking {
        val stale = refused(OwnerSigning.sign(preview(),
            failing(JsonRpc20RemoteException(ProtocolContract.ERROR_AUTHORIZATION_FAILED, "stale", null))))
        assertEquals(OwnerSigning.Outcome.WALLET_FAILED, stale.outcome)
        val invalid = refused(OwnerSigning.sign(preview(),
            failing(JsonRpc20RemoteException(ProtocolContract.ERROR_INVALID_PAYLOADS, "invalid", null))))
        assertEquals(OwnerSigning.Outcome.WALLET_FAILED, invalid.outcome)
        val transport = refused(OwnerSigning.sign(preview(), failing(IOException("association lost"))))
        assertEquals(OwnerSigning.Outcome.WALLET_FAILED, transport.outcome)
    }

    @Test fun missingWalletIsNoWallet() = runBlocking {
        val wallet = FakeWallet(ByteArray(32), { error("unused") }, TransactionResult.NoWalletFound("none"))
        assertEquals(OwnerSigning.Outcome.NO_WALLET, refused(OwnerSigning.sign(preview(), wallet)).outcome)
    }

    @Test fun otherAuthorizedAccountIsRefusedBeforeSigning() = runBlocking {
        val wallet = FakeWallet(SolanaPublicKey.from(address(5)).bytes, { error("must not sign") })
        val answer = refused(OwnerSigning.sign(preview(), wallet))
        assertEquals(OwnerSigning.Outcome.WALLET_FAILED, answer.outcome)
        assertTrue(answer.error is OwnerSigning.OwnerNotAuthorized)
        assertEquals(listOf("transact"), wallet.calls)
    }

    @Test fun walletReturnThatChangesTheMessageIsAFailure() = runBlocking {
        val changed = signedBytes().also { it[it.size - 1] = (it[it.size - 1] + 1).toByte() }
        val wallet = FakeWallet(SolanaPublicKey.from(owner).bytes, { arrayOf(changed) })
        val answer = refused(OwnerSigning.sign(preview(), wallet))
        assertEquals(OwnerSigning.Outcome.WALLET_FAILED, answer.outcome)
        assertTrue(answer.error is IllegalArgumentException)
    }

    @Test fun expiredOrFailingPreviewNeverReachesTheWallet() = runBlocking {
        for (stale in listOf(preview(observedHeight = 1_001), preview(simulationError = "AccountNotFound"))) {
            val wallet = signingWallet()
            assertEquals(OwnerSigning.Outcome.UNAVAILABLE, refused(OwnerSigning.sign(stale, wallet)).outcome)
            assertTrue(wallet.calls.isEmpty())
        }
        val wallet = signingWallet()
        assertTrue(OwnerSigning.sign(preview(observedHeight = 1_000), wallet) is OwnerSigning.WalletAnswer.Signed)
    }

    private class FakeChain(
        val heights: List<Long>,
        val statuses: List<SolanaRpc.SignatureStatus?>,
        val sendFails: Boolean = false,
        val readFails: Boolean = false,
    ) : OwnerSigning.Chain {
        var sent = 0
        var reads = 0
        override suspend fun send(signed: OwnerTransaction.SourceOnlyWalletReturnShape) {
            sent += 1
            if (sendFails) throw SolanaRpc.Failure("send timeout")
        }
        override suspend fun blockHeight(): BigInteger {
            if (readFails) throw SolanaRpc.RemoteFailure(BigInteger.valueOf(-32005), "unhealthy")
            return BigInteger.valueOf(heights[minOf(reads, heights.size - 1)])
        }
        override suspend fun status(signature: String): SolanaRpc.SignatureStatus? =
            statuses[minOf(reads++, statuses.size - 1)]
    }

    private fun status(confirmation: SolanaRpc.Confirmation?, error: Any? = null) =
        SolanaRpc.SignatureStatus(BigInteger.ONE, null, confirmation, error)

    private fun confirm(chain: FakeChain): Pair<OwnerSigning.Outcome, Int> = runBlocking {
        val shape = OwnerTransaction.inspectSourceOnlyWalletReturnShape(unsigned(), arrayOf(signedBytes()))
        var pauses = 0
        val failures = mutableListOf<IOException>()
        val outcome = OwnerSigning.confirm(shape, lastValid, chain, { failures += it }) { pauses += 1 }
        assertEquals(1, chain.sent)
        outcome to pauses
    }

    @Test fun confirmationIsAwaitingReadNotReady() {
        val chain = FakeChain(listOf(900), listOf(null, status(SolanaRpc.Confirmation.PROCESSED), status(SolanaRpc.Confirmation.CONFIRMED)))
        assertEquals(OwnerSigning.Outcome.CONFIRMED_AWAITING_READ to 2, confirm(chain))
        val finalized = FakeChain(listOf(900), listOf(status(SolanaRpc.Confirmation.FINALIZED)))
        assertEquals(OwnerSigning.Outcome.CONFIRMED_AWAITING_READ to 0, confirm(finalized))
    }

    @Test fun executionErrorFailsOnlyOnceConfirmed() {
        val chain = FakeChain(listOf(900), listOf(status(SolanaRpc.Confirmation.PROCESSED, "Custom"),
            status(SolanaRpc.Confirmation.CONFIRMED, "Custom")))
        assertEquals(OwnerSigning.Outcome.FAILED_ON_CHAIN to 1, confirm(chain))
    }

    @Test fun absentSignatureExpiresOnlyPastLastValidHeight() {
        val chain = FakeChain(listOf(999, 1_000, 1_001), listOf(null))
        assertEquals(OwnerSigning.Outcome.EXPIRED to 2, confirm(chain))
    }

    @Test fun failedSendIsStillObservedAndCanConfirm() {
        val chain = FakeChain(listOf(900), listOf(status(SolanaRpc.Confirmation.CONFIRMED)), sendFails = true)
        assertEquals(OwnerSigning.Outcome.CONFIRMED_AWAITING_READ to 0, confirm(chain))
        val lost = FakeChain(listOf(1_001), listOf(null), sendFails = true)
        assertEquals(OwnerSigning.Outcome.EXPIRED to 0, confirm(lost))
    }

    @Test fun unreadableOrUnsettledChainEndsUnknownAfterBudget() {
        val unreadable = FakeChain(listOf(900), listOf(null), readFails = true)
        assertEquals(OwnerSigning.Outcome.UNKNOWN to OwnerSigning.MAX_POLLS, confirm(unreadable))
        val processedPastExpiry = FakeChain(listOf(5_000), listOf(status(SolanaRpc.Confirmation.PROCESSED)))
        assertEquals(OwnerSigning.Outcome.UNKNOWN to OwnerSigning.MAX_POLLS, confirm(processedPastExpiry))
    }

    @Test fun hostAbiOrdinalsMatchHostMs() {
        assertEquals(listOf("IDLE", "REQUESTED", "CANCELLED", "NO_WALLET", "WALLET_FAILED", "SENT_PENDING",
            "CONFIRMED_AWAITING_READ", "FAILED_ON_CHAIN", "EXPIRED", "UNKNOWN", "UNAVAILABLE",
            "NO_SEEKER_GENESIS_TOKEN", "ADMISSION_FAILED"),
            OwnerSigning.Outcome.entries.map { it.name })
        assertEquals(listOf("CLAIM", "DELEGATE_PET", "ENGAGE", "BANK", "BUY", "LOAD", "COMMIT_PET", "CLAIM_REWARD"),
            OwnerSigning.OwnerAction.entries.map { it.name })
    }

    @Test fun packedRequestDecodesActionAndSixteenBitItem() {
        assertEquals(OwnerSigning.Request(OwnerSigning.OwnerAction.BUY, 0x713), OwnerSigning.request(5 or (0x713 shl 8)))
        assertEquals(OwnerSigning.Request(OwnerSigning.OwnerAction.CLAIM, 0), OwnerSigning.request(1))
        for (bad in listOf(0, 9, 1 or (1 shl 24), -1)) {
            assertThrows(IllegalArgumentException::class.java) { OwnerSigning.request(bad) }
        }
    }

    @Test fun sendResultMustEchoTheReviewedSignature() {
        val shape = OwnerTransaction.inspectSourceOnlyWalletReturnShape(unsigned(), arrayOf(signedBytes()))
        assertEquals(shape.signatureBase58, SolanaRpc.sentSignature(shape.signatureBase58, shape.signatureBase58))
        val other = com.funkatronics.encoders.Base58.encodeToString(ByteArray(64) { 9 })
        assertThrows(SolanaRpc.Failure::class.java) { SolanaRpc.sentSignature(other, shape.signatureBase58) }
        assertThrows(SolanaRpc.Failure::class.java) { SolanaRpc.sentSignature(address(9), shape.signatureBase58) }
        assertThrows(SolanaRpc.Failure::class.java) { SolanaRpc.sentSignature(42, shape.signatureBase58) }
    }

    private fun address(value: Int) = SolanaPublicKey(ByteArray(32) { value.toByte() }).address

    // A wallet session that refuses some saved authorizations with a protocol code and connects otherwise.
    private class FakeSession(val refusals: Map<String?, Int>) : OwnerSigning.Session {
        val opened = mutableListOf<String?>()
        override suspend fun <T> open(
            authToken: String?, block: suspend (AdapterOperations, AuthorizationResult) -> T,
        ): TransactionResult<T> {
            opened += authToken
            refusals[authToken]?.let { return TransactionResult.Failure("refused", JsonRpc20RemoteException(it, "refused", null)) }
            val operations = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(AdapterOperations::class.java)) { _, method, _ ->
                throw UnsupportedOperationException(method.name)
            } as AdapterOperations
            val authorization = AuthorizationResult.create("fresh", ByteArray(32) { 3 }, null, null)
            return TransactionResult.Success(block(operations, authorization), authorization)
        }
    }

    private class SavedAuthorization(var token: String?) : OwnerSigning.Authorization {
        override suspend fun saved() = token
        override suspend fun keep(authToken: String) { token = authToken }
        override suspend fun forget() { token = null }
    }

    private fun connectedRun(session: FakeSession, saved: SavedAuthorization, connected: MutableList<String>) = runBlocking {
        OwnerSigning.ConnectedWallet(session, saved) { connected += it.authToken }.run { _, _ -> 7 }
    }

    @Test fun noSavedAuthorizationConnectsThenActsInOneSessionAndKeepsIt() {
        val session = FakeSession(emptyMap())
        val saved = SavedAuthorization(null)
        val connected = mutableListOf<String>()
        assertEquals(7, (connectedRun(session, saved, connected) as TransactionResult.Success).payload)
        assertEquals(listOf<String?>(null), session.opened)
        assertEquals("fresh", saved.token)
        assertEquals(listOf("fresh"), connected)
    }

    @Test fun aRefusedSavedAuthorizationIsForgottenAndConnectAskedOnce() {
        val session = FakeSession(mapOf("stale" to ProtocolContract.ERROR_AUTHORIZATION_FAILED))
        val saved = SavedAuthorization("stale")
        assertTrue(connectedRun(session, saved, mutableListOf()) is TransactionResult.Success)
        assertEquals(listOf("stale", null), session.opened)
        assertEquals("fresh", saved.token)
    }

    @Test fun aDeclineOrARefusedFreshConnectIsNotRetried() {
        val declined = FakeSession(mapOf("saved" to ProtocolContract.ERROR_NOT_SIGNED))
        val kept = SavedAuthorization("saved")
        assertTrue(connectedRun(declined, kept, mutableListOf()) is TransactionResult.Failure)
        assertEquals(listOf<String?>("saved"), declined.opened)
        assertEquals("saved", kept.token)
        val refused = FakeSession(mapOf(null to ProtocolContract.ERROR_AUTHORIZATION_FAILED))
        val connected = mutableListOf<String>()
        assertTrue(connectedRun(refused, SavedAuthorization(null), connected) is TransactionResult.Failure)
        assertEquals(listOf<String?>(null), refused.opened)
        assertTrue(connected.isEmpty())
    }
}
