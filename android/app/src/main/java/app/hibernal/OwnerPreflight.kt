package app.hibernal

import java.math.BigInteger

object OwnerPreflight {
    enum class SignatureFact {
        ABSENT,
        CONFIRMATION_UNKNOWN,
        PROCESSED,
        EXECUTION_ERROR,
        CONFIRMED_AWAITING_TYPED_DELTA,
        FINALIZED_AWAITING_TYPED_DELTA,
    }

    enum class BlockhashFact { HEIGHT_UNKNOWN, WITHIN_VALID_HEIGHT, EXPIRED }

    data class SignatureObservation(val signature: SignatureFact, val blockhash: BlockhashFact)

    fun observeSignature(status: SolanaRpc.SignatureStatus?, lastValidBlockHeight: BigInteger,
        observedBlockHeight: BigInteger?): SignatureObservation {
        require(lastValidBlockHeight.signum() >= 0 && lastValidBlockHeight.bitLength() <= 64 &&
            (observedBlockHeight == null || (observedBlockHeight.signum() >= 0 && observedBlockHeight.bitLength() <= 64))) {
            "Signature observation heights must be uint64"
        }
        val blockhash = when {
            observedBlockHeight == null -> BlockhashFact.HEIGHT_UNKNOWN
            observedBlockHeight > lastValidBlockHeight -> BlockhashFact.EXPIRED
            else -> BlockhashFact.WITHIN_VALID_HEIGHT
        }
        val signature = when {
            status == null -> SignatureFact.ABSENT
            status.error != null -> SignatureFact.EXECUTION_ERROR
            else -> when (status.confirmation) {
                null -> SignatureFact.CONFIRMATION_UNKNOWN
                SolanaRpc.Confirmation.PROCESSED -> SignatureFact.PROCESSED
                SolanaRpc.Confirmation.CONFIRMED -> SignatureFact.CONFIRMED_AWAITING_TYPED_DELTA
                SolanaRpc.Confirmation.FINALIZED -> SignatureFact.FINALIZED_AWAITING_TYPED_DELTA
            }
        }
        return SignatureObservation(signature, blockhash)
    }

    data class SourceOnlyPreview(
        val unsigned: OwnerTransaction.SourceOnlyUnsigned,
        val endpoint: String,
        val blockhashSlot: BigInteger,
        val lastValidBlockHeight: BigInteger,
        val observedBlockHeight: BigInteger,
        val fee: SolanaRpc.ContextValue<BigInteger?>,
        val simulation: SolanaRpc.ContextValue<SolanaRpc.Simulation>,
    ) {
        val expired: Boolean get() = observedBlockHeight > lastValidBlockHeight
    }

    suspend fun inspectSourceOnly(
        rpc: SolanaRpc,
        source: OwnerTransaction.SourceInstruction,
        owner: String,
        program: String,
    ): SourceOnlyPreview = inspectSourceOnly(rpc, listOf(source), owner, program)

    suspend fun inspectSourceOnly(
        rpc: SolanaRpc,
        source: List<OwnerTransaction.SourceInstruction>,
        owner: String,
        program: String,
    ): SourceOnlyPreview {
        val blockhash = rpc.getLatestBlockhash()
        val measured = OwnerTransaction.prepareSourceOnly(source, owner, program, blockhash.value.blockhash,
            OwnerTransaction.MAX_COMPUTE_UNIT_LIMIT)
        val simulation = rpc.simulateTransaction(measured.transactionBytes, blockhash.slot)
        val consumed = simulation.value.unitsConsumed ?: throw SolanaRpc.Failure("Simulation reported no compute units")
        val unsigned = OwnerTransaction.prepareSourceOnly(source, owner, program, blockhash.value.blockhash,
            OwnerTransaction.computeUnitLimitFor(consumed))
        val fee = rpc.getFeeForMessage(unsigned.messageBytes)
        if (fee.slot < blockhash.slot) throw SolanaRpc.Failure("Fee context predates blockhash")
        val height = rpc.getBlockHeight()
        return SourceOnlyPreview(unsigned, rpc.endpoint, blockhash.slot,
            blockhash.value.lastValidBlockHeight, height, fee, simulation)
    }
}
