package app.hibernal

import java.math.BigInteger
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SignatureStatusTest {
    private fun response(statuses: String, slot: String = "10") = SolanaRpc.parseResponse(
        """{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":$slot},"value":$statuses}}""".toByteArray(), 1,
    )
    private fun status(confirmation: String = "\"confirmed\"", confirmations: String = "2", error: String = "null", slot: String = "9") =
        """{"slot":$slot,"confirmations":$confirmations,"confirmationStatus":$confirmation,"err":$error}"""

    @Test fun nullMeansNoConfirmationEvidence() {
        assertNull(SolanaRpc.signatureStatuses(response("[null]"), 1).value.single())
    }

    @Test fun levelsAreExplicitAndNullDoesNotInferFinalized() {
        val result = SolanaRpc.signatureStatuses(response("[${status("\"processed\"","0")},${status()},${status("\"finalized\"","null")},${status("null","null")}]"), 4)
        assertEquals(SolanaRpc.Confirmation.PROCESSED, result.value[0]!!.confirmation)
        assertEquals(SolanaRpc.Confirmation.CONFIRMED, result.value[1]!!.confirmation)
        assertEquals(SolanaRpc.Confirmation.FINALIZED, result.value[2]!!.confirmation)
        assertNull(result.value[3]!!.confirmation)
    }

    @Test fun finalizationDoesNotEraseExecutionFailure() {
        val result = SolanaRpc.signatureStatuses(response("[${status("\"finalized\"", "null", "{\"InstructionError\":[0,{\"Custom\":2001}]}")}]"), 1)
        assertTrue(result.value.single()!!.error is JSONObject)
    }

    @Test fun impossibleOrMissingStatusRefuses() {
        for (value in listOf(status("\"unknown\""), status(slot = "11"), status(confirmations = "-1"), status(error = "true"), "{}")) {
            assertThrows(SolanaRpc.Failure::class.java) { SolanaRpc.signatureStatuses(response("[$value]"), 1) }
        }
        assertThrows(SolanaRpc.Failure::class.java) { SolanaRpc.signatureStatuses(response("[]"), 1) }
    }

    @Test fun unsignedWidthPreserved() {
        val maximum = "18446744073709551615"
        val result = SolanaRpc.signatureStatuses(response("[${status(slot = maximum, confirmations = maximum)}]", maximum), 1)
        assertEquals(BigInteger(maximum), result.value.single()!!.slot)
        assertEquals(BigInteger(maximum), result.value.single()!!.confirmations)
    }

    @Test fun signaturesRequireFullCanonical64Bytes() {
        assertEquals("1".repeat(64), SolanaRpc.signature("1".repeat(64)))
        for (text in listOf("1".repeat(32), "1".repeat(65), "0".repeat(64), "1".repeat(89))) {
            assertThrows(SolanaRpc.Failure::class.java) { SolanaRpc.signature(text) }
        }
    }
}
