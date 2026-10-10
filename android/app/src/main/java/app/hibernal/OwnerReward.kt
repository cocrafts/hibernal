package app.hibernal

import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger

// ClaimReward pays Pet.giftOwed minus Paid.total from the Pet's L1 copy, which a delegated Pet
// only updates on CommitPet (ER). The step is chosen from both copies at the tap, so a repeated
// tap commits or claims only what is still owed; the program's Paid ledger refuses the rest.
object OwnerReward {
    enum class Step { CLAIM, COMMIT, NOTHING_OWED }

    fun step(committedGiftOwed: BigInteger, liveGiftOwed: BigInteger, paidTotal: BigInteger): Step = when {
        committedGiftOwed > paidTotal -> Step.CLAIM
        liveGiftOwed > paidTotal -> Step.COMMIT
        else -> Step.NOTHING_OWED
    }

    // Config: hbrnMint at 72, validator at 144 (program/layout.ms Config after its 8-byte tag).
    fun hbrnMint(config: SolanaRpc.Account) = SolanaPublicKey(config.data.copyOfRange(72, 104)).address
    fun validator(config: SolanaRpc.Account) = SolanaPublicKey(config.data.copyOfRange(144, 176)).address

    suspend fun claim(owner: String, petAddress: String, mint: String, program: String, config: String,
        hbrnMint: String, tokenProgram: String): List<OwnerTransaction.SourceInstruction> {
        val destination = associated(owner, hbrnMint, tokenProgram)
        return listOf(
            OwnerTransaction.createAssociatedTokenIdempotent(owner, destination, hbrnMint, tokenProgram),
            OwnerTransaction.canonicalClaimReward(program, owner, config, petAddress,
                derived(program, listOf("paid".toByteArray(), bytes(mint))), hbrnMint, destination, tokenProgram,
                OwnerTransaction.SYSTEM_PROGRAM))
    }

    suspend fun commit(owner: String, petAddress: String, program: String, validator: String) =
        OwnerTransaction.canonicalCommitPet(program, owner, petAddress,
            derived(program, listOf("vrf-payer".toByteArray())), OwnerTransaction.MAGIC_CONTEXT,
            derived(OwnerTransaction.DELEGATION_PROGRAM, listOf("magic-fee-vault".toByteArray(), bytes(validator))),
            OwnerTransaction.MAGIC_PROGRAM)

    suspend fun associated(owner: String, mint: String, tokenProgram: String) =
        derived(OwnerTransaction.ASSOCIATED_TOKEN_PROGRAM, listOf(bytes(owner), bytes(tokenProgram), bytes(mint)))

    private suspend fun derived(program: String, seeds: List<ByteArray>): String =
        ProgramDerivedAddress.find(seeds, SolanaPublicKey.from(program)).getOrThrow().address

    private fun bytes(address: String) = SolanaPublicKey.from(address).bytes
}
