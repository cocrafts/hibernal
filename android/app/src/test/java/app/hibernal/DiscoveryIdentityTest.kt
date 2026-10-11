package app.hibernal

import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import java.lang.reflect.InvocationTargetException
import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import org.junit.Assert.*
import org.junit.Test

class DiscoveryIdentityTest {
    private val program = SolanaPublicKey.from(GameSync.PROGRAM)
    private val owner = ByteArray(32) { 8 }
    private val mint = ByteArray(32) { 7 }
    private fun derive(seed: String) = runBlocking {
        ProgramDerivedAddress.find(listOf(seed.toByteArray(), mint), program).getOrThrow()
    }
    private fun pet(size: Int = 272, accountOwner: String = program.address) = SolanaRpc.Account(
        accountOwner, BigInteger.ONE, false, ByteArray(size).also {
            byteArrayOf(0xdf.toByte(), 0xde.toByte(), 0x81.toByte(), 0x59, 0x46, 0xe7.toByte(), 0x8d.toByte(), 0xb8.toByte()).copyInto(it)
            owner.copyInto(it, 8)
            mint.copyInto(it, 40)
            it[77] = derive("pet").nonce.toByte()
        })
    private fun paid() = SolanaRpc.Account(program.address, BigInteger.ONE, false, ByteArray(72).also {
        byteArrayOf(0xe0.toByte(), 0x1c, 0x92.toByte(), 0xd5.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0x0b, 0x03).copyInto(it)
        mint.copyInto(it, 8)
        it[64] = derive("paid").nonce.toByte()
    })
    private fun validate(entry: SolanaRpc.KeyedAccount, expectedOwner: String = program.address) {
        val method = GameSync::class.java.declaredMethods.single { it.name == "validatePetPrefix" }
        method.isAccessible = true
        try {
            if (method.parameterCount == 3) method.invoke(GameSync, entry, expectedOwner, owner)
            else runBlocking {
                suspendCoroutineUninterceptedOrReturn<Unit> { continuation ->
                    method.invoke(GameSync, entry, expectedOwner, owner, continuation)
                }
            }
        } catch (error: InvocationTargetException) { throw error.targetException }
    }
    private fun entry(account: SolanaRpc.Account = pet(), address: String = derive("pet").address) =
        SolanaRpc.KeyedAccount(address, account)

    private fun claimed(base: SolanaRpc.Account?, remote: SolanaRpc.Account?, paid: SolanaRpc.Account?) = runBlocking {
        AdmissionDiscovery.claimRecordPresent(base, remote, paid, mint, program.address)
    }

    @Test fun sourceCommonPrefixesKeepCorrectProgramAndDelegatedCandidatesUnsupportedNotDecoded() {
        for (size in listOf(272, 304)) {
            validate(entry(pet(size)))
            validate(entry(pet(size, OwnerTransaction.DELEGATION_PROGRAM)), OwnerTransaction.DELEGATION_PROGRAM)
            assertTrue(claimed(pet(size), null, paid()))
        }
    }
    @Test fun ownerFilterAndTagDoNotProvePetPda() {
        assertThrows(SolanaRpc.Failure::class.java) {
            validate(entry(address = SolanaPublicKey(ByteArray(32) { 6 }).address))
        }
    }
    @Test fun petCandidateMustMatchEmbeddedMintSeed() {
        val wrongMint = pet().also { it.data[40] = 9 }
        assertThrows(SolanaRpc.Failure::class.java) { validate(entry(wrongMint)) }
    }
    @Test fun petCandidateStoredBumpMustMatchDerivedBumpIncludingDelegatedBase() {
        for (accountOwner in listOf(program.address, OwnerTransaction.DELEGATION_PROGRAM)) {
            val wrongBump = pet(accountOwner = accountOwner).also { it.data[77] = (it.data[77].toInt() xor 1).toByte() }
            assertThrows(SolanaRpc.Failure::class.java) { validate(entry(wrongBump), accountOwner) }
        }
    }
    @Test fun malformedPetBumpAtQueriedPdaCannotBecomeClaimedFact() {
        val wrongBump = pet().also { it.data[77] = (it.data[77].toInt() xor 1).toByte() }
        assertThrows(SolanaRpc.Failure::class.java) {
            claimed(wrongBump, null, null)
        }
        assertThrows(SolanaRpc.Failure::class.java) {
            claimed(null, wrongBump, null)
        }
    }
    @Test fun malformedPaidBumpAtQueriedPdaCannotBecomeClaimedFact() {
        val wrongBump = paid().also { it.data[64] = (it.data[64].toInt() xor 1).toByte() }
        assertThrows(SolanaRpc.Failure::class.java) {
            claimed(null, null, wrongBump)
        }
    }
}
