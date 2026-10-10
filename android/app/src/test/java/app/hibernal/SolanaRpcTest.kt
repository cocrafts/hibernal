package app.hibernal

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.math.BigInteger

class SolanaRpcTest {
    private val publicKey = "11111111111111111111111111111111"
    private fun response(result: String) = """{"jsonrpc":"2.0","id":7,"result":$result}"""
    private fun parse(text: String): Any = SolanaRpc.parseResponse(text.toByteArray(), 7)
    private fun account(lamports: String = "1", owner: String = publicKey, data: String = "[\"AQI=\",\"base64\"]", executable: String = "false") =
        """{"owner":"$owner","lamports":$lamports,"executable":$executable,"data":$data}"""
    private fun context(value: String) = """{"context":{"slot":42},"value":$value}"""
    private fun failure(fragment: String, action: () -> Unit) {
        try {
            action()
            fail("Expected RPC failure: $fragment")
        } catch (error: SolanaRpc.Failure) {
            assertTrue(error.message.orEmpty(), error.message.orEmpty().contains(fragment))
        }
    }

    @Test fun validNullMeansAbsence() {
        val result = SolanaRpc.context(parse(response(context("null"))))
        assertEquals(BigInteger.valueOf(42), result.slot)
        assertNull(SolanaRpc.account(result.value))
    }

    @Test fun wideLamportsRemainExact() {
        val result = SolanaRpc.context(parse(response(context(account("18446744073709551615")))))
        val decoded = SolanaRpc.account(result.value)!!
        assertEquals(BigInteger("18446744073709551615"), decoded.lamports)
        assertEquals(publicKey, decoded.owner)
        assertTrue(decoded.data.contentEquals(byteArrayOf(1, 2)))
    }

    @Test fun envelopeValidation() {
        failure("id mismatch") { parse(response("null").replace("\"id\":7", "\"id\":8")) }
        failure("id mismatch") { parse(response("null").replace("\"id\":7", "\"id\":\"7\"")) }
        failure("version") { parse(response("null").replace("2.0", "1.0")) }
        failure("exactly one") { parse("""{"jsonrpc":"2.0","id":7}""") }
        failure("exactly one") { parse(response("null").dropLast(1) + ",\"error\":null}") }
        failure("Duplicate") { parse("""{"jsonrpc":"2.0","id":7,"id":7,"result":null}""") }
        failure("Malformed") { parse(response("null").dropLast(1)) }
        failure("Malformed") { parse(response("null") + " {}") }
        failure("Malformed") { parse("{unquoted:true}") }
    }

    @Test fun remoteErrorsAreExplicit() {
        try {
            parse("""{"jsonrpc":"2.0","id":7,"error":{"code":-32602,"message":"Invalid params"}}""")
            fail("Expected remote error")
        } catch (error: SolanaRpc.RemoteFailure) {
            assertEquals(BigInteger.valueOf(-32602), error.code)
            assertEquals("Invalid params", error.detail)
        }
        failure("code must be integer") { parse("""{"jsonrpc":"2.0","id":7,"error":{"code":"-1","message":"Bad"}}""") }
        failure("message must be string") { parse("""{"jsonrpc":"2.0","id":7,"error":{"code":-1,"message":false}}""") }
    }

    @Test fun absenceRequiresContextAndValue() {
        failure("context") { SolanaRpc.context(parse(response("{\"value\":null}"))) }
        failure("value") { SolanaRpc.context(parse(response("{\"context\":{\"slot\":1}}"))) }
        for (slot in listOf("\"42\"", "42.0", "-1", "18446744073709551616")) {
            failure("slot") { SolanaRpc.context(parse(response("{\"context\":{\"slot\":$slot},\"value\":null}"))) }
        }
        failure("object") { SolanaRpc.context(JSONObject.NULL) }
    }

    @Test fun accountMetadataIsStrict() {
        for (lamports in listOf("\"1\"", "1.0", "1e0", "-1", "18446744073709551616")) {
            failure("lamports") { SolanaRpc.account(parse(response(account(lamports)))) }
        }
        failure("boolean") { SolanaRpc.account(parse(response(account(executable = "\"false\"")))) }
        failure("public key") { SolanaRpc.account(parse(response(account(owner = "0".repeat(32))))) }
        failure("Public key") { SolanaRpc.account(parse(response(account(owner = "1".repeat(31))))) }
        failure("Invalid public key") { SolanaRpc.account(parse(response(account(owner = "1".repeat(33))))) }
        failure("lamports") { SolanaRpc.account(parse(response(account().replace("\"lamports\":1,", "")))) }
    }

    @Test fun base64ShapeAndBytesAreStrict() {
        for (data in listOf("\"AQI=\"", "[\"AQI=\",\"base58\"]", "[\"AQI=\",\"base64\",0]", "[false,\"base64\"]")) {
            failure("data") { SolanaRpc.account(parse(response(account(data = data)))) }
        }
        failure("Invalid account base64") { SolanaRpc.account(parse(response(account(data = "[\"!\",\"base64\"]")))) }
        failure("Noncanonical") { SolanaRpc.account(parse(response(account(data = "[\"AQI\",\"base64\"]")))) }
        failure("Noncanonical") { SolanaRpc.account(parse(response(account(data = "[\"AR==\",\"base64\"]")))) }
    }

    @Test fun cancellationAndReadOnlyGuard() = kotlinx.coroutines.runBlocking {
        val client = SolanaRpc(SolanaRpc.DEVNET)
        try {
            client.call("sendTransaction")
            fail("Expected read-only refusal")
        } catch (error: SolanaRpc.Failure) {
            assertTrue(error.message.orEmpty().contains("read-only"))
        }
        try {
            client.call("getSlot", org.json.JSONArray().put("x".repeat(SolanaRpc.MAX_BODY_BYTES)))
            fail("Expected request body limit")
        } catch (error: SolanaRpc.Failure) {
            assertTrue(error.message.orEmpty().contains("request exceeds body limit"))
        }
        val job = kotlinx.coroutines.Job().also { it.cancel() }
        try {
            kotlinx.coroutines.withContext(job) { client.getSlot() }
            fail("Expected cancellation")
        } catch (_: kotlinx.coroutines.CancellationException) {
        }
    }

    @Test fun simulationDistinguishesFailureAndMissingUnits() {
        val success = SolanaRpc.simulation(parse(response("""{"err":null,"logs":["done"],"unitsConsumed":427559}""")))
        assertNull(success.error)
        assertEquals(listOf("done"), success.logs)
        assertEquals(BigInteger.valueOf(427559), success.unitsConsumed)
        val refused = SolanaRpc.simulation(parse(response("""{"err":{"InstructionError":[0,{"Custom":3}]},"logs":null}""")))
        assertTrue(refused.error is JSONObject)
        assertNull(refused.logs)
        assertNull(refused.unitsConsumed)
        for (units in listOf("-1", "1.0", "\"1\"", "18446744073709551616")) {
            failure("unitsConsumed") { SolanaRpc.simulation(parse(response("""{"err":null,"logs":[],"unitsConsumed":$units}"""))) }
        }
        failure("err") { SolanaRpc.simulation(parse(response("""{"logs":[]}"""))) }
        failure("logs") { SolanaRpc.simulation(parse(response("""{"err":null}"""))) }
        failure("error") { SolanaRpc.simulation(parse(response("""{"err":false,"logs":[]}"""))) }
        failure("log must be string") { SolanaRpc.simulation(parse(response("""{"err":null,"logs":[1]}"""))) }
    }

    @Test fun preflightInputsRefuseBeforeNetwork() = kotlinx.coroutines.runBlocking {
        val client = SolanaRpc(SolanaRpc.DEVNET)
        for (size in listOf(0, 1233)) {
            try {
                client.getFeeForMessage(ByteArray(size))
                fail("Expected message bound refusal")
            } catch (error: SolanaRpc.Failure) {
                assertTrue(error.message.orEmpty().contains("legacy transaction limit"))
            }
            try {
                client.simulateTransaction(ByteArray(size), BigInteger.ZERO)
                fail("Expected transaction bound refusal")
            } catch (error: SolanaRpc.Failure) {
                assertTrue(error.message.orEmpty().contains("legacy transaction limit"))
            }
        }
        try {
            client.simulateTransaction(byteArrayOf(0), BigInteger.valueOf(-1))
            fail("Expected minimum slot refusal")
        } catch (error: SolanaRpc.Failure) {
            assertTrue(error.message.orEmpty().contains("minContextSlot"))
        }
    }

    @Test fun boundsAndEncoding() {
        failure("body limit") { SolanaRpc.parseResponse(ByteArray(SolanaRpc.MAX_BODY_BYTES + 1), 7) }
        failure("Malformed") { SolanaRpc.parseResponse(byteArrayOf(0xc3.toByte(), 0x28), 7) }
        failure("nesting") { parse(response("[".repeat(34) + "null" + "]".repeat(34))) }
        failure("numeric token") { parse(response("1".repeat(129))) }
        failure("endpoint") { SolanaRpc("http://api.devnet.solana.com") }
        failure("endpoint") { SolanaRpc("https://api.devnet.solana.com/redirect") }
    }
}
