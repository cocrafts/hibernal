package app.hibernal

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.math.BigInteger
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLStreamHandler
import java.security.cert.Certificate
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.BeforeClass
import org.junit.Test

class SolanaRpcTransportTest {
    companion object {
        private val next = AtomicReference<FakeConnection?>()
        @BeforeClass @JvmStatic fun installIsolatedJvmTransport() {
            URL.setURLStreamHandlerFactory { protocol ->
                if (protocol != "https") null else object : URLStreamHandler() {
                    override fun openConnection(url: URL): FakeConnection =
                        checkNotNull(next.getAndSet(null)) { "Unexpected JVM HTTPS request" }.also {
                            check(url.toString() == SolanaRpc.DEVNET)
                        }
                }
            }
        }
    }

    private class FakeConnection : HttpsURLConnection(URL(SolanaRpc.DEVNET)) {
        val request = ByteArrayOutputStream()
        val disconnected = CountDownLatch(1)
        var status = 200
        var encoding: String? = null
        var declaredLength = -1L
        var reads = 0
        var inputClosed = false
        var response: InputStream = ByteArrayInputStream(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":18446744073709551615}".toByteArray())
        val fixedRequestLength: Int get() = fixedContentLength
        override fun connect() = Unit
        override fun disconnect() { disconnected.countDown() }
        override fun usingProxy() = false
        override fun getCipherSuite() = "JVM-FAKE-NO-TLS"
        override fun getLocalCertificates(): Array<Certificate>? = null
        override fun getServerCertificates(): Array<Certificate> = emptyArray()
        override fun getOutputStream() = request
        override fun getResponseCode() = status
        override fun getContentEncoding() = encoding
        override fun getContentLengthLong() = declaredLength
        override fun getInputStream(): InputStream {
            reads += 1
            return object : InputStream() {
                override fun read() = response.read()
                override fun read(bytes: ByteArray, offset: Int, length: Int) = response.read(bytes, offset, length)
                override fun close() { inputClosed = true; response.close() }
            }
        }
    }

    private fun slot(connection: FakeConnection): BigInteger {
        check(next.compareAndSet(null, connection))
        return runBlocking { SolanaRpc(SolanaRpc.DEVNET).getSlot() }
    }

    @Test fun boundedPostRetainsPlatformTlsDefaultsAndFullUnsignedResult() {
        val connection = FakeConnection()
        assertEquals(BigInteger("18446744073709551615"), slot(connection))
        assertEquals("POST", connection.requestMethod)
        assertFalse(connection.instanceFollowRedirects)
        assertEquals(10_000, connection.connectTimeout)
        assertEquals(15_000, connection.readTimeout)
        assertEquals(connection.request.size(), connection.fixedRequestLength)
        assertEquals("application/json", connection.getRequestProperty("Content-Type"))
        assertEquals("identity", connection.getRequestProperty("Accept-Encoding"))
        assertSame(HttpsURLConnection.getDefaultSSLSocketFactory(), connection.sslSocketFactory)
        assertSame(HttpsURLConnection.getDefaultHostnameVerifier(), connection.hostnameVerifier)
        assertTrue(connection.inputClosed)
        assertEquals(0L, connection.disconnected.count)
    }

    @Test fun redirectCompressionAndOversizeHeadersRefuseBeforeReadingBody() {
        for (connection in listOf(
            FakeConnection().also { it.status = 302 },
            FakeConnection().also { it.encoding = "gzip" },
            FakeConnection().also { it.declaredLength = Long.MAX_VALUE }
        )) {
            assertThrows(SolanaRpc.Failure::class.java) { slot(connection) }
            assertEquals(0, connection.reads)
            assertEquals(0L, connection.disconnected.count)
        }
    }

    @Test fun truncationAndSocketTimeoutRemainFailuresAndCloseConnection() {
        val truncated = FakeConnection().also { it.declaredLength = 1000 }
        assertEquals("RPC truncated response", assertThrows(SolanaRpc.Failure::class.java) { slot(truncated) }.message)
        assertTrue(truncated.inputClosed)
        assertEquals(0L, truncated.disconnected.count)
        val timeout = FakeConnection().also {
            it.response = object : InputStream() {
                override fun read(): Int = throw SocketTimeoutException("fixture timeout")
            }
        }
        val failure = assertThrows(SolanaRpc.Failure::class.java) { slot(timeout) }
        assertEquals("RPC transport failed: SocketTimeoutException", failure.message)
        assertTrue(failure.cause is SocketTimeoutException)
        assertTrue(timeout.inputClosed)
        assertEquals(0L, timeout.disconnected.count)
    }

    @Test fun unknownLengthStreamAcceptsExactLimitAndRefusesOneExtraByte() {
        val exact = FakeConnection()
        val bytes = ByteArray(SolanaRpc.MAX_BODY_BYTES) { 32 }
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":1}".toByteArray().copyInto(bytes)
        exact.response = ByteArrayInputStream(bytes)
        assertEquals(BigInteger.ONE, slot(exact))
        assertTrue(exact.inputClosed)
        assertEquals(0L, exact.disconnected.count)
        val oversized = FakeConnection().also { it.response = ByteArrayInputStream(bytes + byteArrayOf(32)) }
        val failure = assertThrows(SolanaRpc.Failure::class.java) { slot(oversized) }
        assertEquals("RPC response exceeds body limit", failure.message)
        assertTrue(oversized.inputClosed)
        assertEquals(0L, oversized.disconnected.count)
    }

    @Test fun oversizedRequestAndWriteMethodRefuseBeforeOpeningConnection() {
        for ((method, params, expected) in listOf(
            Triple("getSlot", org.json.JSONArray().put("x".repeat(SolanaRpc.MAX_BODY_BYTES)), "RPC request exceeds body limit"),
            Triple("sendTransaction", org.json.JSONArray(), "Unsupported read-only RPC method: sendTransaction")
        )) {
            val unused = FakeConnection()
            check(next.compareAndSet(null, unused))
            try {
                val failure = assertThrows(SolanaRpc.Failure::class.java) {
                    runBlocking { SolanaRpc(SolanaRpc.DEVNET).call(method, params) }
                }
                assertEquals(expected, failure.message)
                assertSame(unused, next.get())
            } finally { next.set(null) }
        }
    }

    @Test fun cancellationAfterBlockedReadIsReleasedPropagatesAndDisconnects() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val connection = FakeConnection().also {
            it.response = object : InputStream() {
                override fun read(): Int {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS)) { "Fixture read release missing" }
                    return -1
                }
            }
        }
        check(next.compareAndSet(null, connection))
        val attempt = async(Dispatchers.IO) { SolanaRpc(SolanaRpc.DEVNET).getSlot() }
        try {
            assertTrue(entered.await(3, TimeUnit.SECONDS))
            attempt.cancel()
        } finally { release.countDown() }
        try { attempt.await(); fail("Cancelled read must not publish result") }
        catch (_: CancellationException) { }
        assertTrue(connection.disconnected.await(3, TimeUnit.SECONDS))
        assertTrue(connection.inputClosed)
    }
}
