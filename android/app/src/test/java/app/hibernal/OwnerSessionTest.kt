package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import org.bouncycastle.math.ec.rfc8032.Ed25519
import org.junit.Assert.*
import org.junit.Test

// Expected values computed independently with @solana/kit and tools/chain/hibernal.mjs (createSession, engage)
// from the same 32-byte seed 1..32.
class OwnerSessionTest {
    private val program = "Cq4iAp7YLg6U31rk5ZHJUhXzkcK1Qa6YScft7n3DGhsX"
    private val owner = "2gLSTf4M2Lynf9YAkUBbywQcc3yog15YRDXzDKs5Z5zL"
    private val pet = "5bRCbqzEj9TvnNgApHAZkkm4sY6zWrkk7diRKhHj4kiE"
    private val world = "HGHqDpZoRDYQasGDsi33iV7M7auyNLTXYjHYaoX4ewNY"
    private val blockhash = "9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj"
    private val signer = OwnerSession.Signer(ByteArray(32) { (it + 1).toByte() })
    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }
    private fun message(transaction: ByteArray) = transaction.copyOfRange(1 + transaction[0] * 64, transaction.size)
    private fun keys(transaction: ByteArray): List<String> {
        val message = message(transaction)
        return (0 until message[3].toInt()).map { SolanaPublicKey(message.copyOfRange(4 + it * 32, 36 + it * 32)).address }
    }

    @Test fun keyTokenAndSignatureMatchKit(): Unit = runBlocking {
        assertEquals("9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj", signer.address)
        assertEquals("HaGg4zgucxzVRoyTVSpVvz2zgBtsvhHrVuz9gny9y9k3", OwnerSession.token(program, signer.address, owner))
        assertEquals("d00c3a207fc0c69681684a1a4f57c649978790ceabdf2cfa8f0d16082ab28d53" +
            "f6d50d808ea2ef6a452748a5799ec1bf240752f4dd68c1fa79f60b4221981b06", signer.sign("hibernal".toByteArray()).toHex())
    }

    @Test fun createSessionHasTheOwnerPayAndTheSessionKeySignSlotOne(): Unit = runBlocking {
        val token = OwnerSession.token(program, signer.address, owner)
        val transaction = OwnerSession.createSession(owner, signer, program, token, 1_792_000_000, blockhash)
        assertEquals(2, transaction[0].toInt())
        assertTrue(transaction.copyOfRange(1, 65).all { it == 0.toByte() })
        val message = message(transaction)
        assertEquals(listOf(2, 0), listOf(message[0].toInt(), message[1].toInt()))
        assertEquals(listOf(owner, signer.address, token), keys(transaction).take(3))
        assertTrue(message.toHex().contains("dfe96c0741c2eb26000100c0cf6a0000000000"))
        assertTrue(Ed25519.verify(transaction, 65, signer.publicKey, 0, message, 0, message.size))
    }

    @Test fun engageAndBankAreSignedByTheSessionKeyAlone(): Unit = runBlocking {
        val token = OwnerSession.token(program, signer.address, owner)
        for ((transaction, discriminator) in listOf(
            OwnerSession.engage(signer, program, pet, world, token, blockhash) to "22945b45b47f136e",
            OwnerSession.bank(signer, program, pet, world, token, blockhash) to "34489ea3a9b80206")) {
            val message = message(transaction)
            assertEquals(1, transaction[0].toInt())
            assertEquals(signer.address, keys(transaction).first())
            assertEquals(pet, keys(transaction)[1])
            // Instruction: program index, 4 accounts in Engage's order, then the 8-byte discriminator.
            val accounts = listOf(signer.address, pet, world, token).map { keys(transaction).indexOf(it).toByte() }.toByteArray()
            assertTrue(message.toHex().endsWith("04" + accounts.toHex() + "08" + discriminator))
            assertTrue(Ed25519.verify(transaction, 1, signer.publicKey, 0, message, 0, message.size))
        }
    }

    @Test fun walletMaySignOnlyItsOwnSlot(): Unit = runBlocking {
        val ownerSigner = OwnerSession.Signer(ByteArray(32) { 7 })
        val token = OwnerSession.token(program, signer.address, ownerSigner.address)
        val sent = OwnerSession.createSession(ownerSigner.address, signer, program, token, 1_792_000_000, blockhash)
        val returned = sent.copyOf().also { ownerSigner.sign(message(sent)).copyInto(it, 1) }
        assertArrayEquals(returned, OwnerSession.walletSigned(sent, returned))
        val unsigned = sent.copyOf()
        assertThrows(IllegalArgumentException::class.java) { OwnerSession.walletSigned(sent, unsigned) }
        val changed = returned.copyOf().also { it[it.size - 1] = (it[it.size - 1] + 1).toByte() }
        assertThrows(IllegalArgumentException::class.java) { OwnerSession.walletSigned(sent, changed) }
        val stripped = returned.copyOf().also { ByteArray(64).copyInto(it, 65) }
        assertThrows(IllegalArgumentException::class.java) { OwnerSession.walletSigned(sent, stripped) }
    }

    @Test fun bankWaitsEightGameHours() {
        val day = BigInteger.valueOf(86_400)
        val genesis = BigInteger.valueOf(1_791_710_912)
        val now = OwnerSession.gameSeconds(genesis, day, 1_791_710_912 + 10_000)
        assertEquals(BigInteger.valueOf(10_000), now)
        assertTrue(OwnerSession.bankCoolingDown(BigInteger.valueOf(10_000 - 8 * 3600 + 1), now))
        assertFalse(OwnerSession.bankCoolingDown(BigInteger.valueOf(10_000 - 8 * 3600), now))
        assertEquals(BigInteger.ZERO, OwnerSession.gameSeconds(genesis, day, 1_791_710_000))
    }
}
