package app.hibernal

import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger

object AdmissionDiscovery {
    data class Member(
        val mint: String,
        val heldTokens: List<String>,
        val memberNumber: BigInteger,
        val petAddress: String,
        val paidAddress: String,
        val claimRecordPresent: Boolean,
    )
    data class Read(val baseSlot: BigInteger, val ephemeralSlot: BigInteger?, val members: List<Member>) {
        val unclaimed: Int get() = members.count { !it.claimRecordPresent }
    }

    suspend fun read(
        base: SolanaRpc,
        ephemeral: SolanaRpc,
        holdings: SolanaRpc.ContextValue<List<SolanaRpc.KeyedAccount>>,
        owner: String,
        group: String,
        program: String,
    ): Read {
        val tokens = mutableMapOf<String, MutableList<String>>()
        for (entry in holdings.value) {
            val mint = TokenAdmission.heldMint(entry, owner) ?: continue
            tokens.getOrPut(mint) { mutableListOf() }.add(entry.publicKey)
        }
        var baseSlot = holdings.slot
        var ephemeralSlot: BigInteger? = null
        val members = mutableListOf<Member>()
        for (batch in tokens.keys.sorted().chunked(100)) {
            val accounts = base.getMultipleAccounts(batch)
            baseSlot = minOf(baseSlot, accounts.slot)
            for ((index, mint) in batch.withIndex()) {
                val account = accounts.value[index] ?: throw SolanaRpc.Failure("Held token mint unavailable")
                val number = TokenAdmission.memberNumber(mint, account, group) ?: continue
                val programKey = SolanaPublicKey.from(program)
                val mintKey = SolanaPublicKey.from(mint)
                val pet = ProgramDerivedAddress.find(listOf("pet".toByteArray(), mintKey.bytes), programKey).getOrThrow()
                val paid = ProgramDerivedAddress.find(listOf("paid".toByteArray(), mintKey.bytes), programKey).getOrThrow()
                val local = base.getMultipleAccounts(listOf(pet.address, paid.address))
                val remote = ephemeral.getAccountInfo(pet.address)
                baseSlot = minOf(baseSlot, local.slot)
                ephemeralSlot = ephemeralSlot?.let { minOf(it, remote.slot) } ?: remote.slot
                val claimed = claimRecordPresent(local.value[0], remote.value, local.value[1], mintKey.bytes, program)
                members.add(Member(mint, tokens.getValue(mint).sorted(), number, pet.address, paid.address, claimed))
            }
        }
        return Read(baseSlot, ephemeralSlot, members)
    }

    internal suspend fun claimRecordPresent(
        basePet: SolanaRpc.Account?,
        ephemeralPet: SolanaRpc.Account?,
        paid: SolanaRpc.Account?,
        mint: ByteArray,
        program: String,
    ): Boolean {
        if (mint.size != 32) throw SolanaRpc.Failure("Admission mint must be 32 bytes")
        validatePet(basePet, mint, program, true)
        validatePet(ephemeralPet, mint, program, false)
        validatePaid(paid, mint, program)
        return basePet != null || ephemeralPet != null || paid != null
    }

    private suspend fun validatePet(account: SolanaRpc.Account?, mint: ByteArray, program: String, delegatedAllowed: Boolean) {
        if (account == null) return
        val ownerMatches = account.owner == program || (delegatedAllowed && account.owner == OwnerTransaction.DELEGATION_PROGRAM)
        val tag = byteArrayOf(0xdf.toByte(), 0xde.toByte(), 0x81.toByte(), 0x59, 0x46, 0xe7.toByte(), 0x8d.toByte(), 0xb8.toByte())
        if (!ownerMatches || account.executable || account.data.size !in listOf(272, 304) ||
            !account.data.copyOfRange(0, 8).contentEquals(tag) || !account.data.copyOfRange(40, 72).contentEquals(mint)) {
            throw SolanaRpc.Failure("Admission Pet PDA identity/layout unsupported")
        }
        val derived = ProgramDerivedAddress.find(listOf("pet".toByteArray(), mint), SolanaPublicKey.from(program)).getOrThrow()
        if (derived.nonce.toInt() != (account.data[77].toInt() and 255)) {
            throw SolanaRpc.Failure("Admission Pet PDA bump mismatch")
        }
    }

    private suspend fun validatePaid(account: SolanaRpc.Account?, mint: ByteArray, program: String) {
        if (account == null) return
        val tag = byteArrayOf(0xe0.toByte(), 0x1c, 0x92.toByte(), 0xd5.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0x0b, 0x03)
        if (account.owner != program || account.executable || account.data.size != 72 ||
            !account.data.copyOfRange(0, 8).contentEquals(tag) || !account.data.copyOfRange(8, 40).contentEquals(mint)) {
            throw SolanaRpc.Failure("Admission Paid PDA identity/layout unsupported")
        }
        val derived = ProgramDerivedAddress.find(listOf("paid".toByteArray(), mint), SolanaPublicKey.from(program)).getOrThrow()
        if (derived.nonce.toInt() != (account.data[64].toInt() and 255)) {
            throw SolanaRpc.Failure("Admission Paid PDA bump mismatch")
        }
    }
}
