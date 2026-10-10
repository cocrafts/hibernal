package app.hibernal

import com.solana.mobilewalletadapter.clientlib.AdapterOperations
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import com.solana.mobilewalletadapter.clientlib.protocol.JsonRpc20Client.JsonRpc20RemoteException
import com.solana.mobilewalletadapter.clientlib.protocol.MobileWalletAdapterClient.AuthorizationResult
import com.solana.mobilewalletadapter.common.ProtocolContract
import com.solana.publickey.SolanaPublicKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import java.io.IOException
import java.math.BigInteger

object OwnerSigning {
    // Ordinals are the host ABI: native/host/host.ms OwnerAction and OwnerActionOutcome.
    enum class OwnerAction { CLAIM, DELEGATE_PET, ENGAGE, BANK, BUY, LOAD, COMMIT_PET, CLAIM_REWARD }

    enum class Outcome {
        IDLE,
        REQUESTED,
        CANCELLED,
        NO_WALLET,
        WALLET_FAILED,
        SENT_PENDING,
        CONFIRMED_AWAITING_READ,
        FAILED_ON_CHAIN,
        EXPIRED,
        UNKNOWN,
        UNAVAILABLE,
        NO_SEEKER_GENESIS_TOKEN,
        ADMISSION_FAILED,
    }

    data class Request(val action: OwnerAction, val item: Int, val tier: Int)

    fun request(packed: Int): Request {
        val action = (packed and 0xff) - 1
        require(action in OwnerAction.entries.indices && packed ushr 24 == 0) { "Unknown owner action request $packed" }
        return Request(OwnerAction.entries[action], (packed ushr 8) and 0xff, (packed ushr 16) and 0xff)
    }

    fun interface Wallet {
        suspend fun transact(
            block: suspend (AdapterOperations, AuthorizationResult) -> Array<ByteArray>,
        ): TransactionResult<Array<ByteArray>>
    }

    interface Chain {
        suspend fun send(signed: OwnerTransaction.SourceOnlyWalletReturnShape)
        suspend fun blockHeight(): BigInteger
        suspend fun status(signature: String): SolanaRpc.SignatureStatus?
    }

    fun chain(rpc: SolanaRpc): Chain = object : Chain {
        override suspend fun send(signed: OwnerTransaction.SourceOnlyWalletReturnShape) { rpc.sendTransaction(signed) }
        override suspend fun blockHeight() = rpc.getBlockHeight()
        override suspend fun status(signature: String) = rpc.getSignatureStatuses(listOf(signature)).value.single()
    }

    sealed interface WalletAnswer {
        class Signed(val shape: OwnerTransaction.SourceOnlyWalletReturnShape, val authToken: String) : WalletAnswer
        class Refused(val outcome: Outcome, val error: Exception?, val forgetAuthorization: Boolean = false) : WalletAnswer
    }

    class OwnerNotAuthorized : IllegalStateException("Wallet authorization does not include the fee payer owner")

    // signTransactions, not signAndSendTransactions: nothing reaches a cluster until send() below, so
    // every wallet-phase failure means "not sent", and ER actions go to the ER endpoint the preview read.
    suspend fun sign(preview: OwnerPreflight.SourceOnlyPreview, wallet: Wallet): WalletAnswer {
        if (preview.expired || preview.simulation.value.error != null) return WalletAnswer.Refused(Outcome.UNAVAILABLE, null)
        val unsigned = preview.unsigned
        val owner = SolanaPublicKey.from(unsigned.owner).bytes
        val result = wallet.transact { operations, authorization ->
            if (authorization.accounts.none { it.publicKey.contentEquals(owner) }) throw OwnerNotAuthorized()
            operations.signTransactions(arrayOf(unsigned.transactionBytes)).signedPayloads
        }
        return when (result) {
            is TransactionResult.Success -> try {
                WalletAnswer.Signed(OwnerTransaction.inspectSourceOnlyWalletReturnShape(unsigned, result.payload),
                    result.authResult.authToken)
            } catch (error: IllegalArgumentException) {
                WalletAnswer.Refused(Outcome.WALLET_FAILED, error)
            }
            is TransactionResult.NoWalletFound -> WalletAnswer.Refused(Outcome.NO_WALLET, null)
            is TransactionResult.Failure -> refusal(result.e)
        }
    }

    private fun refusal(error: Exception): WalletAnswer.Refused {
        val causes = generateSequence<Throwable>(error) { it.cause }.take(8).toList()
        return when (remoteCode(error)) {
            ProtocolContract.ERROR_NOT_SIGNED -> WalletAnswer.Refused(Outcome.CANCELLED, error)
            ProtocolContract.ERROR_AUTHORIZATION_FAILED -> WalletAnswer.Refused(Outcome.WALLET_FAILED, error, forgetAuthorization = true)
            null -> if (causes.any { it is InterruptedException || (it is CancellationException && it !is TimeoutCancellationException) }) {
                WalletAnswer.Refused(Outcome.CANCELLED, error)
            } else {
                WalletAnswer.Refused(Outcome.WALLET_FAILED, error)
            }
            else -> WalletAnswer.Refused(Outcome.WALLET_FAILED, error)
        }
    }

    fun remoteCode(error: Throwable): Int? =
        generateSequence(error) { it.cause }.take(8).filterIsInstance<JsonRpc20RemoteException>().firstOrNull()?.code

    const val POLL_MILLIS = 2_000L
    const val MAX_POLLS = 300
    private val pollPause: suspend () -> Unit = { delay(POLL_MILLIS) }

    // A failed send may still have been forwarded, so it is observed like a sent one until the
    // blockhash expires. The block height is read before the status: an absent signature after an
    // expired height cannot land any more.
    suspend fun confirm(
        signed: OwnerTransaction.SourceOnlyWalletReturnShape,
        lastValidBlockHeight: BigInteger,
        chain: Chain,
        onRpcFailure: (IOException) -> Unit,
        pause: suspend () -> Unit = pollPause,
    ): Outcome {
        try { chain.send(signed) } catch (error: IOException) { onRpcFailure(error) }
        repeat(MAX_POLLS) {
            try {
                val height = chain.blockHeight()
                val status = chain.status(signed.signatureBase58)
                val observation = OwnerPreflight.observeSignature(status, lastValidBlockHeight, height)
                when (observation.signature) {
                    OwnerPreflight.SignatureFact.CONFIRMED_AWAITING_TYPED_DELTA,
                    OwnerPreflight.SignatureFact.FINALIZED_AWAITING_TYPED_DELTA -> return Outcome.CONFIRMED_AWAITING_READ
                    OwnerPreflight.SignatureFact.EXECUTION_ERROR ->
                        if (status?.confirmation.let { it == SolanaRpc.Confirmation.CONFIRMED || it == SolanaRpc.Confirmation.FINALIZED }) {
                            return Outcome.FAILED_ON_CHAIN
                        }
                    OwnerPreflight.SignatureFact.ABSENT ->
                        if (observation.blockhash == OwnerPreflight.BlockhashFact.EXPIRED) return Outcome.EXPIRED
                    OwnerPreflight.SignatureFact.PROCESSED,
                    OwnerPreflight.SignatureFact.CONFIRMATION_UNKNOWN -> Unit
                }
            } catch (error: IOException) {
                onRpcFailure(error)
            }
            pause()
        }
        return Outcome.UNKNOWN
    }
}
