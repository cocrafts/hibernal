package app.hibernal

import android.util.JsonReader
import android.util.JsonToken
import com.solana.publickey.SolanaPublicKey
import com.funkatronics.encoders.Base58
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.StringReader
import java.math.BigDecimal
import java.math.BigInteger
import java.net.URL
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.Base64
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.HttpsURLConnection
import kotlin.coroutines.coroutineContext

open class SolanaRpc(val endpoint: String) {
    class Failure(message: String, cause: Throwable? = null) : IOException(message, cause)
    class RemoteFailure(val code: BigInteger, val detail: String) : IOException("RPC error $code: $detail")
    data class ContextValue<T>(val slot: BigInteger, val value: T)
    data class Account(val owner: String, val lamports: BigInteger, val executable: Boolean, val data: ByteArray)
    data class KeyedAccount(val publicKey: String, val account: Account)
    data class Blockhash(val blockhash: String, val lastValidBlockHeight: BigInteger)
    data class Simulation(val error: Any?, val logs: List<String>?, val unitsConsumed: BigInteger?)
    enum class Confirmation { PROCESSED, CONFIRMED, FINALIZED }
    data class SignatureStatus(val slot: BigInteger, val confirmations: BigInteger?, val confirmation: Confirmation?, val error: Any?)

    init { checkValue(endpoint == DEVNET || endpoint == DEVNET_ER, "Unsupported RPC endpoint") }
    private val nextId = AtomicLong(1)

    open suspend fun call(method: String, params: JSONArray = JSONArray()): Any {
        checkValue(method in READ_METHODS, "Unsupported read-only RPC method: $method")
        return post(method, params)
    }

    suspend fun sendTransaction(signed: OwnerTransaction.SourceOnlyWalletReturnShape): String =
        sendTransaction(signed.transactionBytes, signed.signatureBase58)

    suspend fun sendTransaction(transaction: ByteArray, signature: String): String = withContext(Dispatchers.IO) {
        val options = JSONObject().put("encoding", "base64").put("preflightCommitment", "confirmed")
        sentSignature(post("sendTransaction", JSONArray()
            .put(Base64.getEncoder().encodeToString(transaction)).put(options)), signature)
    }

    private suspend fun post(method: String, params: JSONArray): Any = withContext(Dispatchers.IO) {
        val id = nextId.getAndIncrement()
        checkValue(id > 0, "RPC request id exhausted")
        val body = JSONObject().put("jsonrpc", "2.0").put("id", id).put("method", method)
            .put("params", params).toString().toByteArray(Charsets.UTF_8)
        checkValue(body.size <= MAX_BODY_BYTES, "RPC request exceeds body limit")
        val connection = URL(endpoint).openConnection() as HttpsURLConnection
        try {
            coroutineContext.ensureActive()
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept-Encoding", "identity")
            connection.setRequestProperty("Connection", "close")
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            checkValue(connection.responseCode == 200, "RPC HTTP status ${connection.responseCode}")
            checkValue(connection.contentEncoding == null || connection.contentEncoding == "identity", "RPC unexpected content encoding")
            val declared = connection.contentLengthLong
            checkValue(declared <= MAX_BODY_BYTES, "RPC response exceeds body limit")
            val bytes = connection.inputStream.use { stream ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    coroutineContext.ensureActive()
                    val count = stream.read(buffer)
                    if (count == -1) break
                    checkValue(output.size() + count <= MAX_BODY_BYTES, "RPC response exceeds body limit")
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            checkValue(declared < 0 || declared == bytes.size.toLong(), "RPC truncated response")
            coroutineContext.ensureActive()
            parseResponse(bytes, id)
        } catch (error: Exception) {
            coroutineContext.ensureActive()
            if (error is kotlinx.coroutines.CancellationException || error is Failure || error is RemoteFailure) throw error
            throw Failure("RPC transport failed: ${error.javaClass.simpleName}", error)
        } finally {
            connection.disconnect()
        }
    }

    suspend fun getAccountInfo(publicKey: String): ContextValue<Account?> = withContext(Dispatchers.IO) {
        accountContext(call("getAccountInfo", JSONArray().put(key(publicKey)).put(config())))
    }

    suspend fun getMultipleAccounts(publicKeys: List<String>): ContextValue<List<Account?>> = withContext(Dispatchers.IO) {
        checkValue(publicKeys.size in 1..100, "getMultipleAccounts requires 1..100 keys")
        val result = context(call("getMultipleAccounts", JSONArray().put(JSONArray(publicKeys.map(::key))).put(config())))
        val values = array(result.value, "getMultipleAccounts value")
        checkValue(values.length() == publicKeys.size, "getMultipleAccounts count mismatch")
        ContextValue(result.slot, (0 until values.length()).map { account(values.get(it)) })
    }

    suspend fun getProgramAccounts(program: String, filters: JSONArray = JSONArray()): ContextValue<List<KeyedAccount>> = withContext(Dispatchers.IO) {
        keyedContext(call("getProgramAccounts", JSONArray().put(key(program)).put(config().put("withContext", true).put("filters", filters))))
    }

    suspend fun getTokenAccountsByOwner(owner: String): ContextValue<List<KeyedAccount>> = withContext(Dispatchers.IO) {
        keyedContext(call("getTokenAccountsByOwner", JSONArray().put(key(owner)).put(JSONObject().put("programId", TOKEN_2022)).put(config())))
    }

    suspend fun getSlot(): BigInteger = withContext(Dispatchers.IO) {
        unsigned(call("getSlot", JSONArray().put(config())), "slot")
    }
    suspend fun getGenesisHash(): String = withContext(Dispatchers.IO) { key(call("getGenesisHash")) }
    suspend fun getLatestBlockhash(): ContextValue<Blockhash> = withContext(Dispatchers.IO) {
        val result = context(call("getLatestBlockhash", JSONArray().put(config())))
        val value = obj(result.value, "blockhash value")
        ContextValue(result.slot, Blockhash(key(value.required("blockhash")), unsigned(value.required("lastValidBlockHeight"), "lastValidBlockHeight")))
    }

    suspend fun getSignatureStatuses(signatures: List<String>): ContextValue<List<SignatureStatus?>> = withContext(Dispatchers.IO) {
        checkValue(signatures.size in 1..256, "getSignatureStatuses requires 1..256 signatures")
        signatureStatuses(call("getSignatureStatuses", JSONArray().put(JSONArray(signatures.map(::signature)))
            .put(JSONObject().put("searchTransactionHistory", true))), signatures.size)
    }

    suspend fun getBlockHeight(): BigInteger = withContext(Dispatchers.IO) {
        unsigned(call("getBlockHeight", JSONArray().put(config())), "blockHeight")
    }

    suspend fun getFeeForMessage(message: ByteArray): ContextValue<BigInteger?> = withContext(Dispatchers.IO) {
        checkValue(message.size in 1..1232, "Message outside legacy transaction limit")
        val result = context(call("getFeeForMessage", JSONArray()
            .put(Base64.getEncoder().encodeToString(message)).put(config())))
        ContextValue(result.slot, if (result.value === JSONObject.NULL) null else unsigned(result.value, "fee"))
    }

    suspend fun simulateTransaction(transaction: ByteArray, minimumContextSlot: BigInteger): ContextValue<Simulation> = withContext(Dispatchers.IO) {
        checkValue(transaction.size in 1..1232, "Transaction outside legacy transaction limit")
        unsigned(minimumContextSlot, "minContextSlot")
        val options = config().put("sigVerify", false).put("replaceRecentBlockhash", false)
            .put("minContextSlot", minimumContextSlot)
        val result = context(call("simulateTransaction", JSONArray()
            .put(Base64.getEncoder().encodeToString(transaction)).put(options)))
        checkValue(result.slot >= minimumContextSlot, "Simulation context predates request")
        ContextValue(result.slot, simulation(result.value))
    }

    private fun accountContext(value: Any): ContextValue<Account?> {
        val result = context(value)
        return ContextValue(result.slot, account(result.value))
    }
    private fun keyedContext(value: Any): ContextValue<List<KeyedAccount>> {
        val result = context(value)
        val values = array(result.value, "accounts value")
        return ContextValue(result.slot, (0 until values.length()).map {
            val entry = obj(values.get(it), "keyed account")
            KeyedAccount(key(entry.required("pubkey")), account(entry.required("account")) ?: throw Failure("Null keyed account"))
        })
    }

    companion object {
        const val DEVNET = "https://api.devnet.solana.com"
        const val DEVNET_ER = "https://devnet-as.magicblock.app"
        const val TOKEN_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
        const val MAX_BODY_BYTES = 4 * 1024 * 1024
        private val MAX_UNSIGNED = BigInteger("18446744073709551615")
        private val READ_METHODS = setOf("getAccountInfo", "getMultipleAccounts", "getProgramAccounts", "getTokenAccountsByOwner", "getSlot", "getGenesisHash", "getLatestBlockhash", "getBlockHeight", "getFeeForMessage", "simulateTransaction", "getSignatureStatuses")
        private fun checkValue(valid: Boolean, message: String) { if (!valid) throw Failure(message) }
        private fun config() = JSONObject().put("encoding", "base64").put("commitment", "confirmed")
        private fun JSONObject.required(name: String): Any = opt(name) ?: throw Failure("Missing RPC field: $name")
        private fun obj(value: Any, field: String) = value as? JSONObject ?: throw Failure("$field must be object")
        private fun array(value: Any, field: String) = value as? JSONArray ?: throw Failure("$field must be array")
        internal fun signature(text: String): String {
            checkValue(text.length in 64..88, "Signature must be canonical base58")
            try {
                val bytes = Base58.decode(text)
                checkValue(bytes.size == 64 && Base58.encodeToString(bytes) == text, "Signature must be canonical 64 bytes")
            } catch (error: Exception) {
                if (error is Failure) throw error
                throw Failure("Invalid signature", error)
            }
            return text
        }

        internal fun sentSignature(value: Any, expected: String): String {
            checkValue(value is String && signature(value) == expected, "sendTransaction returned another signature")
            return expected
        }

        internal fun signatureStatuses(value: Any, expectedCount: Int): ContextValue<List<SignatureStatus?>> {
            checkValue(expectedCount in 1..256, "Invalid expected signature count")
            val result = context(value)
            val values = array(result.value, "signature status value")
            checkValue(values.length() == expectedCount, "Signature status count mismatch")
            return ContextValue(result.slot, (0 until values.length()).map { index ->
                val raw = values.get(index)
                if (raw === JSONObject.NULL) return@map null
                val entry = obj(raw, "signature status")
                val slot = unsigned(entry.required("slot"), "signature slot")
                checkValue(slot <= result.slot, "Signature slot exceeds context")
                val count = entry.required("confirmations")
                val confirmations = if (count === JSONObject.NULL) null else unsigned(count, "confirmations")
                val confirmation = when (val status = entry.required("confirmationStatus")) {
                    JSONObject.NULL -> null
                    "processed" -> Confirmation.PROCESSED
                    "confirmed" -> Confirmation.CONFIRMED
                    "finalized" -> Confirmation.FINALIZED
                    else -> throw Failure("Unknown confirmation status: $status")
                }
                val error = entry.required("err")
                checkValue(error === JSONObject.NULL || error is JSONObject || error is String, "Invalid signature error")
                SignatureStatus(slot, confirmations, confirmation, if (error === JSONObject.NULL) null else error)
            })
        }

        private fun key(value: Any): String {
            checkValue(value is String && value.length in 32..44, "Public key must be canonical base58")
            val text = value as String
            try {
                val decoded = SolanaPublicKey.from(text)
                checkValue(decoded.bytes.size == 32 && decoded.address == text, "Public key must be canonical 32 bytes")
            } catch (error: Exception) {
                if (error is Failure) throw error
                throw Failure("Invalid public key", error)
            }
            return text
        }
        private fun unsigned(value: Any, field: String): BigInteger {
            val number = value as? BigInteger ?: throw Failure("$field must be integer")
            checkValue(number.signum() >= 0 && number <= MAX_UNSIGNED, "$field outside uint64")
            return number
        }
        internal fun context(value: Any): ContextValue<Any> {
            val result = obj(value, "result")
            val slot = unsigned(obj(result.required("context"), "context").required("slot"), "context.slot")
            checkValue(result.has("value"), "Missing context value")
            return ContextValue(slot, result.required("value"))
        }
        internal fun account(value: Any): Account? {
            if (value === JSONObject.NULL) return null
            val fields = obj(value, "account")
            val owner = key(fields.required("owner"))
            val lamports = unsigned(fields.required("lamports"), "lamports")
            val executable = fields.required("executable") as? Boolean ?: throw Failure("executable must be boolean")
            val data = array(fields.required("data"), "account.data")
            checkValue(data.length() == 2 && data.get(0) is String && data.get(1) == "base64", "account.data must be [string, base64]")
            val encoded = data.get(0) as String
            val bytes = try { Base64.getDecoder().decode(encoded) } catch (error: IllegalArgumentException) { throw Failure("Invalid account base64", error) }
            checkValue(Base64.getEncoder().encodeToString(bytes) == encoded, "Noncanonical account base64")
            return Account(owner, lamports, executable, bytes)
        }
        internal fun simulation(value: Any): Simulation {
            val fields = obj(value, "simulation value")
            val error = fields.required("err")
            checkValue(error === JSONObject.NULL || error is String || error is JSONObject, "Invalid simulation error")
            val rawLogs = fields.required("logs")
            val logs = if (rawLogs === JSONObject.NULL) null else {
                val entries = array(rawLogs, "simulation logs")
                (0 until entries.length()).map { entries.get(it) as? String ?: throw Failure("Simulation log must be string") }
            }
            val rawUnits = fields.opt("unitsConsumed")
            val units = if (rawUnits == null || rawUnits === JSONObject.NULL) null else unsigned(rawUnits, "unitsConsumed")
            return Simulation(if (error === JSONObject.NULL) null else error, logs, units)
        }

        internal fun parseResponse(bytes: ByteArray, id: Long): Any {
            checkValue(bytes.size <= MAX_BODY_BYTES, "RPC response exceeds body limit")
            try {
                val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
                val envelope = JsonReader(StringReader(text)).use { reader ->
                    reader.isLenient = false
                    val value = obj(readJson(reader, 0), "RPC envelope")
                    checkValue(reader.peek() == JsonToken.END_DOCUMENT, "Trailing RPC JSON")
                    value
                }
                checkValue(envelope.required("jsonrpc") == "2.0", "Invalid JSON-RPC version")
                checkValue(envelope.required("id") == BigInteger.valueOf(id), "RPC id mismatch")
                checkValue(envelope.has("result") != envelope.has("error"), "RPC requires exactly one result or error")
                if (envelope.has("error")) {
                    val error = obj(envelope.required("error"), "RPC error")
                    val code = error.required("code") as? BigInteger ?: throw Failure("RPC error code must be integer")
                    checkValue(code.bitLength() <= 31, "RPC error code outside int32")
                    val message = error.required("message") as? String ?: throw Failure("RPC error message must be string")
                    throw RemoteFailure(code, message)
                }
                return envelope.required("result")
            } catch (error: Exception) {
                if (error is Failure || error is RemoteFailure) throw error
                throw Failure("Malformed RPC response", error)
            }
        }
        private fun readJson(reader: JsonReader, depth: Int): Any {
            checkValue(depth <= 32, "RPC JSON nesting exceeds limit")
            return when (reader.peek()) {
                JsonToken.BEGIN_OBJECT -> JSONObject().also { result ->
                    reader.beginObject()
                    while (reader.hasNext()) {
                        val name = reader.nextName()
                        checkValue(!result.has(name), "Duplicate RPC JSON field")
                        result.put(name, readJson(reader, depth + 1))
                    }
                    reader.endObject()
                }
                JsonToken.BEGIN_ARRAY -> JSONArray().also { result ->
                    reader.beginArray()
                    while (reader.hasNext()) result.put(readJson(reader, depth + 1))
                    reader.endArray()
                }
                JsonToken.STRING -> reader.nextString()
                JsonToken.NUMBER -> reader.nextString().let {
                    checkValue(it.length <= 128, "RPC numeric token exceeds limit")
                    if (it.matches(Regex("-?(0|[1-9][0-9]*)"))) BigInteger(it) else BigDecimal(it)
                }
                JsonToken.BOOLEAN -> reader.nextBoolean()
                JsonToken.NULL -> { reader.nextNull(); JSONObject.NULL }
                else -> throw Failure("Invalid RPC JSON token")
            }
        }
    }
}
