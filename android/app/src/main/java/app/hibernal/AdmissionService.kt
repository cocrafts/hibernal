package app.hibernal

import com.solana.publickey.SolanaPublicKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.net.URL
import javax.net.ssl.HttpsURLConnection

object AdmissionService {
    sealed interface Answer {
        data class Ticket(val mint: String, val issued: Boolean) : Answer
        data object NoSeekerGenesisToken : Answer
    }

    class Failure(message: String, cause: Throwable? = null) : IOException(message, cause)

    const val BASE = "https://hibernal.metascriptlang.org"
    private const val MAX_BODY_BYTES = 64 * 1024

    // The game's own answer to a gift on the ER: it commits the Pet to L1 and pays for it.
    sealed interface CommitAnswer {
        data object Committed : CommitAnswer
        data class TooSoon(val retryAfterSeconds: Long) : CommitAnswer
        data object NothingToClaim : CommitAnswer
    }

    suspend fun admit(owner: String, base: String = BASE): Answer {
        val (status, body) = post(base, "admit", JSONObject().put("owner", key(owner, "owner")))
        return answer(status, body, owner)
    }

    suspend fun commit(mint: String, base: String = BASE): CommitAnswer {
        val (status, body) = post(base, "commit", JSONObject().put("mint", key(mint, "mint")))
        return commitAnswer(status, body)
    }

    private suspend fun post(base: String, path: String, request: JSONObject): Pair<Int, String> = withContext(Dispatchers.IO) {
        check(base.startsWith("https://"), "admission service must be https")
        val body = request.toString().toByteArray(Charsets.UTF_8)
        val connection = URL("$base/$path").openConnection() as HttpsURLConnection
        try {
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10_000
            connection.readTimeout = 30_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Connection", "close")
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val stream = (if (status < 400) connection.inputStream else connection.errorStream)
                ?: throw Failure("admission service HTTP $status without body")
            val bytes = stream.use { it.readNBytes(MAX_BODY_BYTES + 1) }
            check(bytes.size <= MAX_BODY_BYTES, "admission response exceeds body limit")
            status to String(bytes, Charsets.UTF_8)
        } catch (error: Failure) {
            throw error
        } catch (error: IOException) {
            throw Failure("admission transport failed: ${error.javaClass.simpleName}", error)
        } finally {
            connection.disconnect()
        }
    }

    internal fun answer(status: Int, body: String, owner: String): Answer {
        val json = try { JSONObject(body) } catch (error: JSONException) {
            throw Failure("admission HTTP $status body is not JSON", error)
        }
        return when (status) {
            200 -> {
                check(json.optString("owner") == owner, "admission answered for another owner")
                val ticket = key(json.optString("ticket"), "ticket")
                when (val kind = json.optString("status")) {
                    "issued" -> Answer.Ticket(ticket, issued = true)
                    "already" -> Answer.Ticket(ticket, issued = false)
                    else -> throw Failure("admission status unknown: $kind")
                }
            }
            403 -> when (val error = json.optString("error")) {
                "NoSeekerGenesisToken" -> Answer.NoSeekerGenesisToken
                else -> throw Failure("admission refused: $error")
            }
            else -> throw Failure("admission HTTP $status: ${json.optString("error")} ${json.optString("detail")}".trim())
        }
    }

    internal fun commitAnswer(status: Int, body: String): CommitAnswer {
        val json = try { JSONObject(body) } catch (error: JSONException) {
            throw Failure("commit HTTP $status body is not JSON", error)
        }
        return when {
            status == 200 && json.optString("status") == "committed" -> CommitAnswer.Committed
            status == 429 && json.optString("error") == "TooSoon" ->
                CommitAnswer.TooSoon(json.optLong("retryAfterSeconds", -1).also { check(it >= 0, "TooSoon without retryAfterSeconds") })
            status == 409 && json.optString("error") == "NothingToClaim" -> CommitAnswer.NothingToClaim
            else -> throw Failure("commit HTTP $status: ${json.optString("error")} ${json.optString("status")}".trim())
        }
    }

    private fun key(address: String, field: String): String = try {
        SolanaPublicKey.from(address).address.also { check(it == address, "$field is not canonical base58") }
    } catch (error: Failure) {
        throw error
    } catch (error: Exception) {
        throw Failure("$field is not a public key", error)
    }

    private fun check(valid: Boolean, message: String) { if (!valid) throw Failure(message) }
}
