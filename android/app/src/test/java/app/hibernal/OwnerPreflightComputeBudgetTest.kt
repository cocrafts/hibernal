package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import java.util.Base64
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class OwnerPreflightComputeBudgetTest {
    private val owner = address(1)
    private val program = address(90)
    private val blockhash = address(91)
    private val limitOffset = 4 + 5 * 32 + 32 + 1 + 3 + 1

    @Test fun finalTransactionCarriesSimulatedUnitsPlusTwentyPercentAndItsOwnFee() = runBlocking {
        val rpc = FakeRpc(450)
        val preview = OwnerPreflight.inspectSourceOnly(rpc, bank(), owner, program)
        val simulated = Base64.getDecoder().decode(rpc.params("simulateTransaction").getString(0))
        assertEquals(OwnerTransaction.MAX_COMPUTE_UNIT_LIMIT, limit(simulated.copyOfRange(65, simulated.size)))
        assertEquals(540, limit(preview.unsigned.messageBytes))
        assertArrayEquals(preview.unsigned.messageBytes,
            Base64.getDecoder().decode(rpc.params("getFeeForMessage").getString(0)))
        assertEquals(BigInteger.valueOf(5100), preview.fee.value)
        assertEquals(blockhash, preview.unsigned.blockhash)
    }

    @Test fun simulationWithoutUnitsRefusesBeforeFee() = runBlocking {
        val rpc = FakeRpc(null)
        val failure = assertThrows(SolanaRpc.Failure::class.java) {
            runBlocking { OwnerPreflight.inspectSourceOnly(rpc, bank(), owner, program) }
        }
        assertEquals("Simulation reported no compute units", failure.message)
        assertFalse(rpc.calls.any { it.first == "getFeeForMessage" })
    }

    private fun bank() = OwnerTransaction.canonicalBank(program, owner, address(2), address(3))
    private fun limit(message: ByteArray): Int {
        assertEquals(2, message[limitOffset - 1].toInt())
        return (0 until 4).sumOf { (message[limitOffset + it].toInt() and 255) shl (8 * it) }
    }

    private inner class FakeRpc(private val units: Long?) : SolanaRpc(SolanaRpc.DEVNET) {
        val calls = mutableListOf<Pair<String, JSONArray>>()
        fun params(method: String) = calls.single { it.first == method }.second

        override suspend fun call(method: String, params: JSONArray): Any {
            calls += method to params
            val result: Any = when (method) {
                "getLatestBlockhash" -> context(JSONObject().put("blockhash", blockhash).put("lastValidBlockHeight", 500))
                "simulateTransaction" -> context(JSONObject().put("err", JSONObject.NULL).put("logs", JSONArray())
                    .apply { if (units != null) put("unitsConsumed", units) })
                "getFeeForMessage" -> context(5100)
                "getBlockHeight" -> 400
                else -> throw AssertionError("Unexpected RPC $method")
            }
            val text = JSONObject().put("jsonrpc", "2.0").put("id", 1).put("result", result).toString()
            return SolanaRpc.parseResponse(text.toByteArray(), 1)
        }

        private fun context(value: Any) = JSONObject().put("context", JSONObject().put("slot", 42)).put("value", value)
    }

    private fun address(value: Int) = SolanaPublicKey(ByteArray(32) { value.toByte() }).address
}
