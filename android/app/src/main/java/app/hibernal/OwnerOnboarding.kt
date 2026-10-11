package app.hibernal

import java.math.BigInteger
import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey

// Summon: the admission ticket's Pet is claimed and delegated in one transaction, or only
// delegated when an earlier Claim landed without it. The L1 Pet account decides, read at the tap.
// The Claim transaction also opens the owner's HBRN account, so every deposit is paid at Summon.
object OwnerOnboarding {
    const val ASSOCIATED_TOKEN_PROGRAM = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

    enum class Step { CLAIM_AND_DELEGATE, DELEGATE, ALREADY_DELEGATED }

    fun step(pet: SolanaRpc.Account?, program: String): Step = when (pet?.owner) {
        null -> Step.CLAIM_AND_DELEGATE
        program -> Step.DELEGATE
        OwnerTransaction.DELEGATION_PROGRAM -> Step.ALREADY_DELEGATED
        else -> throw SolanaRpc.Failure("Pet account owned by ${pet.owner}")
    }

    suspend fun instructions(step: Step, owner: String, ticket: String, program: String, config: String, nameId: Int,
        hbrnMint: String, hbrnTokenProgram: String): List<OwnerTransaction.SourceInstruction> {
        val pet = petAddress(ticket, program)
        val delegate = OwnerTransaction.canonicalDelegatePet(program, owner, config, pet, program,
            derived(program, "buffer", pet), derived(OwnerTransaction.DELEGATION_PROGRAM, "delegation", pet),
            derived(OwnerTransaction.DELEGATION_PROGRAM, "delegation-metadata", pet),
            OwnerTransaction.DELEGATION_PROGRAM, OwnerTransaction.SYSTEM_PROGRAM)
        return when (step) {
            Step.CLAIM_AND_DELEGATE -> listOf(OwnerTransaction.createAssociatedTokenIdempotent(owner,
                OwnerReward.associated(owner, hbrnMint, hbrnTokenProgram), hbrnMint, hbrnTokenProgram),
                OwnerTransaction.canonicalClaim(program, owner, config, ticket,
                heldToken(owner, ticket), pet, derived(program, "paid", ticket), OwnerTransaction.SYSTEM_PROGRAM,
                derived(program, "ledger", ticket), revenue(program), nameId), delegate)
            Step.DELEGATE -> listOf(delegate)
            Step.ALREADY_DELEGATED -> throw IllegalStateException("Pet is already delegated")
        }
    }

    // The hatch fee's destination (program Claim and PayRebirth `fund`).
    suspend fun revenue(program: String): String =
        ProgramDerivedAddress.find(listOf("revenue".toByteArray()), SolanaPublicKey.from(program)).getOrThrow().address

    // PayRebirth charges whatever the Pet's state, so the app offers it only for a recorded death not yet paid for.
    fun rebirthPayable(alive: Boolean, diedEpoch: BigInteger, rebirths: Long, lineageGeneration: Int) =
        !alive && diedEpoch.signum() != 0 && rebirths <= lineageGeneration

    suspend fun payRebirth(owner: String, ticket: String, program: String, config: String) =
        OwnerTransaction.canonicalPayRebirth(program, owner, config, petAddress(ticket, program),
            derived(program, "ledger", ticket), revenue(program), OwnerTransaction.SYSTEM_PROGRAM)

    suspend fun petAddress(ticket: String, program: String) = derived(program, "pet", ticket)

    suspend fun heldToken(owner: String, ticket: String): String = ProgramDerivedAddress.find(
        listOf(bytes(owner), bytes(SolanaRpc.TOKEN_2022), bytes(ticket)),
        SolanaPublicKey.from(ASSOCIATED_TOKEN_PROGRAM)).getOrThrow().address

    private suspend fun derived(program: String, seed: String, key: String): String =
        ProgramDerivedAddress.find(listOf(seed.toByteArray(), bytes(key)), SolanaPublicKey.from(program)).getOrThrow().address

    private fun bytes(address: String) = SolanaPublicKey.from(address).bytes
}
