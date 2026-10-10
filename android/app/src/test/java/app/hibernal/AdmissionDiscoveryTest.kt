package app.hibernal

import com.solana.publickey.SolanaPublicKey
import com.solana.publickey.ProgramDerivedAddress
import kotlinx.coroutines.runBlocking
import java.math.BigInteger
import org.junit.Assert.*
import org.junit.Test

class AdmissionDiscoveryTest {
    private val program = SolanaPublicKey(ByteArray(32) { 3 }).address
    private val mint = ByteArray(32) { 4 }
    private fun bump(seed: String) = runBlocking {
        ProgramDerivedAddress.find(listOf(seed.toByteArray(), mint), SolanaPublicKey.from(program)).getOrThrow().nonce.toInt()
    }
    private fun claimed(base: SolanaRpc.Account?, remote: SolanaRpc.Account?, paid: SolanaRpc.Account?, mint: ByteArray, program: String) = runBlocking {
        AdmissionDiscovery.claimRecordPresent(base, remote, paid, mint, program)
    }
    private fun pet(owner: String = program, size: Int = 272): SolanaRpc.Account {
        val bytes = ByteArray(size)
        byteArrayOf(0xdf.toByte(), 0xde.toByte(), 0x81.toByte(), 0x59, 0x46, 0xe7.toByte(), 0x8d.toByte(), 0xb8.toByte()).copyInto(bytes)
        mint.copyInto(bytes, 40)
        bytes[77] = bump("pet").toByte()
        return SolanaRpc.Account(owner, BigInteger.ONE, false, bytes)
    }
    private fun paid(): SolanaRpc.Account {
        val bytes = ByteArray(72)
        byteArrayOf(0xe0.toByte(), 0x1c, 0x92.toByte(), 0xd5.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0x0b, 0x03).copyInto(bytes)
        mint.copyInto(bytes, 8)
        bytes[64] = bump("paid").toByte()
        return SolanaRpc.Account(program, BigInteger.ONE, false, bytes)
    }

    @Test fun onlyCompleteNullLookupsAllowUnclaimed() {
        assertFalse(claimed(null, null, null, mint, program))
        assertTrue(claimed(pet(), null, null, mint, program))
        assertTrue(claimed(null, pet(), null, mint, program))
        assertTrue(claimed(null, null, paid(), mint, program))
        assertTrue(claimed(pet(size = 304), null, paid(), mint, program))
    }

    @Test fun delegatedBaseSnapshotIsPresenceNotEphemeralLiveState() {
        val delegated = pet(OwnerTransaction.DELEGATION_PROGRAM)
        assertTrue(claimed(delegated, null, null, mint, program))
        assertThrows(SolanaRpc.Failure::class.java) {
            claimed(null, delegated, null, mint, program)
        }
    }

    @Test fun malformedRecordsNeverBecomeUnclaimed() {
        val invalid = listOf(
            pet().copy(owner = OwnerTransaction.SYSTEM_PROGRAM),
            pet().copy(executable = true),
            pet().copy(data = ByteArray(271)),
            pet().copy(data = ByteArray(272)),
            pet().also { it.data[40] = 0 },
        )
        for (account in invalid) assertThrows(SolanaRpc.Failure::class.java) {
            claimed(account, null, null, mint, program)
        }
        for (account in listOf(paid().copy(data = ByteArray(72)), paid().copy(owner = OwnerTransaction.DELEGATION_PROGRAM))) {
            assertThrows(SolanaRpc.Failure::class.java) {
                claimed(null, null, account, mint, program)
            }
        }
    }
}
