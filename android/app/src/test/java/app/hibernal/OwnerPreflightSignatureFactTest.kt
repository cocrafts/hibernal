package app.hibernal

import java.math.BigInteger
import org.junit.Assert.*
import org.junit.Test

class OwnerPreflightSignatureFactTest {
    private val lastValidHeight = BigInteger.valueOf(100)

    @Test fun absentStatusAndUnknownConfirmationStayUnresolvedAtEveryExpiry() {
        val unknown = status(null, confirmations = BigInteger.valueOf(999))
        for (height in listOf(null, BigInteger.valueOf(99), lastValidHeight, BigInteger.valueOf(101))) {
            assertEquals(OwnerPreflight.SignatureFact.ABSENT, observe(null, height).signature)
            assertEquals(OwnerPreflight.SignatureFact.CONFIRMATION_UNKNOWN, observe(unknown, height).signature)
        }
        assertEquals(OwnerPreflight.BlockhashFact.EXPIRED, observe(null, BigInteger.valueOf(101)).blockhash)
        assertEquals(OwnerPreflight.BlockhashFact.HEIGHT_UNKNOWN, observe(null, null).blockhash)
    }

    @Test fun inclusiveLastValidHeightAndUint64HeightsPreserved() {
        assertEquals(OwnerPreflight.BlockhashFact.WITHIN_VALID_HEIGHT, observe(null, lastValidHeight).blockhash)
        assertEquals(OwnerPreflight.BlockhashFact.EXPIRED, observe(null, lastValidHeight + BigInteger.ONE).blockhash)
        val maximum = BigInteger("18446744073709551615")
        assertEquals(OwnerPreflight.BlockhashFact.WITHIN_VALID_HEIGHT,
            OwnerPreflight.observeSignature(null, maximum, maximum).blockhash)
        for (invalid in listOf(BigInteger.valueOf(-1), maximum + BigInteger.ONE)) {
            assertThrows(IllegalArgumentException::class.java) { OwnerPreflight.observeSignature(null, invalid, null) }
            assertThrows(IllegalArgumentException::class.java) { OwnerPreflight.observeSignature(null, lastValidHeight, invalid) }
        }
    }

    @Test fun processedIsNotConfirmedEvenWithNullOrLargeConfirmationCounts() {
        for (count in listOf(null, BigInteger.ZERO, BigInteger.valueOf(999))) {
            val processed = status(SolanaRpc.Confirmation.PROCESSED, confirmations = count)
            assertEquals(OwnerPreflight.SignatureFact.PROCESSED, observe(processed, BigInteger.valueOf(101)).signature)
            assertEquals(OwnerPreflight.BlockhashFact.EXPIRED, observe(processed, BigInteger.valueOf(101)).blockhash)
        }
    }

    @Test fun executionErrorNeverBecomesCleanConfirmationIncludingFinalizedAndExpired() {
        for (confirmation in listOf(null) + SolanaRpc.Confirmation.entries) {
            for (height in listOf(null, lastValidHeight, lastValidHeight + BigInteger.ONE)) {
                val failed = status(confirmation, error = "AccountNotFound")
                assertEquals(OwnerPreflight.SignatureFact.EXECUTION_ERROR, observe(failed, height).signature)
            }
        }
    }

    @Test fun cleanConfirmedAndFinalizedAlwaysAwaitTypedDeltaEvenAfterExpiry() {
        for (height in listOf(null, lastValidHeight, lastValidHeight + BigInteger.ONE)) {
            assertEquals(OwnerPreflight.SignatureFact.CONFIRMED_AWAITING_TYPED_DELTA,
                observe(status(SolanaRpc.Confirmation.CONFIRMED), height).signature)
            assertEquals(OwnerPreflight.SignatureFact.FINALIZED_AWAITING_TYPED_DELTA,
                observe(status(SolanaRpc.Confirmation.FINALIZED), height).signature)
        }
    }

    private fun status(confirmation: SolanaRpc.Confirmation?, confirmations: BigInteger? = null, error: Any? = null) =
        SolanaRpc.SignatureStatus(BigInteger.valueOf(42), confirmations, confirmation, error)
    private fun observe(status: SolanaRpc.SignatureStatus?, height: BigInteger?) =
        OwnerPreflight.observeSignature(status, lastValidHeight, height)
}
