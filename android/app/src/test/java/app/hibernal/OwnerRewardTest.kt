package app.hibernal

import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

// Expected addresses computed independently with @solana/kit getProgramDerivedAddress; the HBRN
// mint and validator are the devnet Config's (Config hbrnMint == PDA ["mint"]).
class OwnerRewardTest {
    private val program = "B1zQCgVyS3qVUKCzRv6Rje79mou45fHuz7dc415ukh1o"
    private val config = "BaP5CCGgVDFeF6G82BmvAtTAq6H5KrzMQSSWWzy7NvG6"
    private val owner = "2gLSTf4M2Lynf9YAkUBbywQcc3yog15YRDXzDKs5Z5zL"
    private val mint = "39oc3g26wCkGXNfgrMaJ3hoXzbxVXDVnMFptHhkvTB4v"
    private val pet = "AbhFiZKgbMyWtEaVBBd98XdtTdNsj26CNgbm6LATSVPx"
    private val paid = "AygW7WBGQ1SyzWioZNDTpHSyP9vcA75BmYs51UUY37os"
    private val hbrn = "9AezGNDJtUjvT22DT6Ls2e4mnqE8d1gnKk88z8PsoN8p"
    private val validator = "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57"
    private val vrfPayer = "58zfpqWKLLz48rbxw3TkLi72hS1wWEdcrSsUx4AbuVLT"
    private val feeVault = "5SRuhQybZ3FqmymaxoipqnieGZ5bNnrQqYwUZSRoCCZQ"
    private val destination = "J3eRd2JAavjNHpNX69PMwfPh3aNvd2SAoTeXtZFv3hoH"
    private val token = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    private val system = OwnerTransaction.SYSTEM_PROGRAM
    private fun n(value: Long) = BigInteger.valueOf(value)
    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }

    @Test fun stepClaimsWhatL1HoldsCommitsWhatOnlyTheErHoldsAndNeverRepays() {
        assertEquals(OwnerReward.Step.NOTHING_OWED, OwnerReward.step(n(0), n(0), n(0)))
        assertEquals(OwnerReward.Step.COMMIT, OwnerReward.step(n(0), n(500), n(0)))
        assertEquals(OwnerReward.Step.CLAIM, OwnerReward.step(n(500), n(500), n(0)))
        assertEquals(OwnerReward.Step.NOTHING_OWED, OwnerReward.step(n(500), n(500), n(500)))
        assertEquals(OwnerReward.Step.COMMIT, OwnerReward.step(n(500), n(800), n(500)))
    }

    @Test fun configFieldsComeFromTheirOffsets() {
        val data = ByteArray(304)
        com.solana.publickey.SolanaPublicKey.from(hbrn).bytes.copyInto(data, 72)
        com.solana.publickey.SolanaPublicKey.from(validator).bytes.copyInto(data, 144)
        val account = SolanaRpc.Account(program, BigInteger.ONE, false, data)
        assertEquals(hbrn, OwnerReward.hbrnMint(account))
        assertEquals(validator, OwnerReward.validator(account))
    }

    @Test fun claimCreatesTheHbrnAccountThenClaimsInOneTransaction() = runBlocking {
        val (create, claim) = OwnerReward.claim(owner, pet, mint, program, config, hbrn, token)
        assertEquals(OwnerTransaction.ASSOCIATED_TOKEN_PROGRAM, create.instruction.programId.address)
        assertEquals(listOf(owner, destination, owner, hbrn, system, token), create.instruction.accounts.map { it.publicKey.address })
        assertEquals("01", create.instruction.data.toHex())
        assertEquals(listOf(owner, config, pet, paid, hbrn, destination, token, system), claim.instruction.accounts.map { it.publicKey.address })
        assertEquals(listOf(true, false, false, true, true, true, false, false), claim.instruction.accounts.map { it.isWritable })
        assertEquals("955fb5f25e5a9ea2", claim.instruction.data.toHex())
        val unsigned = OwnerTransaction.prepareSourceOnly(listOf(create, claim), owner, program, config, TEST_COMPUTE_UNIT_LIMIT)
        assertEquals("create_associated_token+claim_reward", unsigned.action)
        val message = unsigned.messageBytes
        assertEquals(listOf(1, 0), listOf(message[0].toInt(), message[1].toInt()))
        val count = message[3].toInt()
        val keys = List(count) { com.solana.publickey.SolanaPublicKey(message.copyOfRange(4 + 32 * it, 36 + 32 * it)).address }
        val readonly = keys.takeLast(message[2].toInt())
        assertEquals(owner, keys.first())
        assertEquals(setOf(paid, hbrn, destination), keys.drop(1).dropLast(readonly.size).toSet())
        assertEquals(setOf(config, pet, token, system, program, OwnerTransaction.ASSOCIATED_TOKEN_PROGRAM,
            OwnerTransaction.COMPUTE_BUDGET_PROGRAM), readonly.toSet())
    }

    @Test fun commitNamesTheVrfPayerAndTheValidatorFeeVault() = runBlocking {
        val commit = OwnerReward.commit(owner, pet, program, validator)
        assertEquals(listOf(owner, pet, vrfPayer, OwnerTransaction.MAGIC_CONTEXT, feeVault, OwnerTransaction.MAGIC_PROGRAM),
            commit.instruction.accounts.map { it.publicKey.address })
        assertEquals(listOf(true, false, false, false, false, false), commit.instruction.accounts.map { it.isSigner })
        assertEquals("9c3fc91ca75a7165", commit.instruction.data.toHex())
    }

    @Test fun anotherProgramStaysRefused() {
        val foreign = OwnerTransaction.canonicalBank(program, owner, pet, config)
        assertThrows(IllegalArgumentException::class.java) {
            OwnerTransaction.prepareSourceOnly(listOf(foreign), owner, system, config, TEST_COMPUTE_UNIT_LIMIT)
        }
    }
}
