package app.hibernal

import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

// Expected addresses computed independently with @solana/kit getProgramDerivedAddress.
class OwnerOnboardingTest {
    private val program = "B1zQCgVyS3qVUKCzRv6Rje79mou45fHuz7dc415ukh1o"
    private val config = "BaP5CCGgVDFeF6G82BmvAtTAq6H5KrzMQSSWWzy7NvG6"
    private val owner = "2gLSTf4M2Lynf9YAkUBbywQcc3yog15YRDXzDKs5Z5zL"
    private val ticket = "39oc3g26wCkGXNfgrMaJ3hoXzbxVXDVnMFptHhkvTB4v"
    private val pet = "AbhFiZKgbMyWtEaVBBd98XdtTdNsj26CNgbm6LATSVPx"
    private val paid = "AygW7WBGQ1SyzWioZNDTpHSyP9vcA75BmYs51UUY37os"
    private val buffer = "BG93KfBJRxSTWNscKGxda7z4M9awqXCgdK7ApW3kdpiL"
    private val record = "DEEown9AK7sAkBrdA7ZKF28EwiWZGC4w9NzxRRS1KX9g"
    private val metadata = "8j2CVGuCSMVRr2ta8SnkZqwC5SaP1KxkrQd3R4wWJjSo"
    private val ledger = "5gSMmwT9eZQHT9PZwCDQkQXYGWqNay4sBHUCifqiQ6Gw"
    private val fund = "GcQJXcQxZnxttXbNemDZLmixFygr5gGd3Ben1at7FKgB"
    private val held = "GKnzC96m5gPN5ti85Nn4eqfeQPcRowbNxSB8YVu92WVV"
    private val system = OwnerTransaction.SYSTEM_PROGRAM
    private val delegation = OwnerTransaction.DELEGATION_PROGRAM
    private val hbrnMint = "So11111111111111111111111111111111111111112"
    private val tokenProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    private val hbrnAccount = "6uUvQkg1si27XZpaw93DNztx2FARwYLAwJTrE1bngeTh"

    private fun account(owner: String) = SolanaRpc.Account(owner, BigInteger.ONE, false, ByteArray(0))

    @Test fun stepFollowsTheL1PetAccountOwner() {
        assertEquals(OwnerOnboarding.Step.CLAIM_AND_DELEGATE, OwnerOnboarding.step(null, program))
        assertEquals(OwnerOnboarding.Step.DELEGATE, OwnerOnboarding.step(account(program), program))
        assertEquals(OwnerOnboarding.Step.ALREADY_DELEGATED, OwnerOnboarding.step(account(delegation), program))
        assertThrows(SolanaRpc.Failure::class.java) { OwnerOnboarding.step(account(system), program) }
    }

    @Test fun claimAndDelegateNameTheDeployedAccountsInOrder() = runBlocking {
        val (account, claim, delegate) = OwnerOnboarding.instructions(OwnerOnboarding.Step.CLAIM_AND_DELEGATE, owner, ticket, program, config, 7, hbrnMint, tokenProgram)
        assertEquals(listOf(owner, hbrnAccount, owner, hbrnMint, system, tokenProgram),
            account.instruction.accounts.map { it.publicKey.address })
        assertEquals(listOf(owner, config, ticket, held, pet, paid, system, ledger, fund), claim.instruction.accounts.map { it.publicKey.address })
        assertEquals(listOf(true, true, false, false, true, true, false, true, true), claim.instruction.accounts.map { it.isWritable })
        assertEquals(listOf(owner, config, pet, program, buffer, record, metadata, delegation, system),
            delegate.instruction.accounts.map { it.publicKey.address })
        assertEquals(listOf(true, false, true, false, true, true, true, false, false), delegate.instruction.accounts.map { it.isWritable })
        assertEquals("3ec6d6c1d59f6cd207", claim.instruction.data.toHex())
        assertEquals("824f91bdf70a6ac7", delegate.instruction.data.toHex())
        val only = OwnerOnboarding.instructions(OwnerOnboarding.Step.DELEGATE, owner, ticket, program, config, 7, hbrnMint, tokenProgram)
        assertEquals(listOf("delegate_pet"), only.map { it.action })
    }

    @Test fun oneTransactionCarriesClaimAndDelegateWithOneSigner() = runBlocking {
        val sources = OwnerOnboarding.instructions(OwnerOnboarding.Step.CLAIM_AND_DELEGATE, owner, ticket, program, config, 7, hbrnMint, tokenProgram)
        val unsigned = OwnerTransaction.prepareSourceOnly(sources, owner, program, config, TEST_COMPUTE_UNIT_LIMIT)
        val message = unsigned.messageBytes
        assertEquals(listOf(1, 0), listOf(message[0].toInt(), message[1].toInt()))
        val count = message[3].toInt()
        val keys = List(count) { com.solana.publickey.SolanaPublicKey(message.copyOfRange(4 + 32 * it, 36 + 32 * it)).address }
        val readonly = keys.takeLast(message[2].toInt())
        assertEquals(owner, keys.first())
        assertEquals("create_associated_token+claim+delegate_pet", unsigned.action)
        assertEquals(setOf(config, pet, paid, buffer, record, metadata, hbrnAccount, ledger, fund), keys.drop(1).dropLast(readonly.size).toSet())
        assertEquals(setOf(ticket, held, system, program, delegation, OwnerTransaction.COMPUTE_BUDGET_PROGRAM, hbrnMint,
            tokenProgram, OwnerTransaction.ASSOCIATED_TOKEN_PROGRAM), readonly.toSet())
        assertEquals(5, message[4 + 32 * count + 32].toInt())
        assertTrue(unsigned.transactionBytes.size <= OwnerTransaction.MAX_WIRE_BYTES)
    }

    @Test fun actionsFromDifferentSourceProfilesRefuseToShareATransaction() {
        val bank = OwnerTransaction.canonicalBank(program, owner, pet, config)
        val talk = OwnerTransaction.historicalTalk(program, owner, pet, config)
        assertThrows(IllegalArgumentException::class.java) {
            OwnerTransaction.prepareSourceOnly(listOf(bank, talk), owner, program, config, TEST_COMPUTE_UNIT_LIMIT)
        }
        assertThrows(IllegalArgumentException::class.java) {
            OwnerTransaction.prepareSourceOnly(emptyList(), owner, program, config, TEST_COMPUTE_UNIT_LIMIT)
        }
    }

    @Test fun hatchFeeIsOfferedOnlyForARecordedDeathNotYetPaidFor() {
        val died = BigInteger.valueOf(12)
        assertTrue(OwnerOnboarding.rebirthPayable(false, died, 0, 0))
        assertFalse(OwnerOnboarding.rebirthPayable(true, died, 0, 0))
        assertFalse(OwnerOnboarding.rebirthPayable(false, BigInteger.ZERO, 0, 0))
        assertFalse(OwnerOnboarding.rebirthPayable(false, died, 1, 0))
        assertTrue(OwnerOnboarding.rebirthPayable(false, died, 1, 1))
    }

    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }
}
