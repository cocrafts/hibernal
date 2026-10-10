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

    suspend fun admit(owner: String, base: String = BASE): Answer = withContext(Dispatchers.IO) {
        check(base.startsWith("https://"), "admission service must be https")
        val body = JSONObject().put("owner", key(owner, "owner")).toString().toByteArray(Charsets.UTF_8)
        val connection = URL("$base/admit").openConnection() as HttpsURLConnection
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
            answer(status, String(bytes, Charsets.UTF_8), owner)
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

    private fun key(address: String, field: String): String = try {
        SolanaPublicKey.from(address).address.also { check(it == address, "$field is not canonical base58") }
    } catch (error: Failure) {
        throw error
    } catch (error: Exception) {
        throw Failure("$field is not a public key", error)
    }

    private fun check(valid: Boolean, message: String) { if (!valid) throw Failure(message) }
}
