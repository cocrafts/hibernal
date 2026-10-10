package app.hibernal

import com.funkatronics.encoders.Base58
import com.solana.publickey.SolanaPublicKey
import com.solana.transaction.AccountMeta
import com.solana.transaction.LegacyMessage
import com.solana.transaction.Instruction
import com.solana.transaction.Transaction
import com.solana.transaction.TransactionInstruction
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder

object OwnerTransaction {
    const val MAX_WIRE_BYTES = 1232
    const val SYSTEM_PROGRAM = "11111111111111111111111111111111"
    const val DELEGATION_PROGRAM = "DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh"
    const val MAGIC_PROGRAM = "Magic11111111111111111111111111111111111111"
    const val MAGIC_CONTEXT = "MagicContext1111111111111111111111111111111"
    const val COMPUTE_BUDGET_PROGRAM = "ComputeBudget111111111111111111111111111111"
    const val ASSOCIATED_TOKEN_PROGRAM = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"
    const val COMPUTE_UNIT_PRICE_MICRO_LAMPORTS = 100_000L
    const val MAX_COMPUTE_UNIT_LIMIT = 1_400_000

    enum class SourceProfile(val sourceTree: String) {
        CANONICAL_B50E0B5("f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc"),
        HISTORICAL_D09815C6("511868044a069d6e35ddf512af5f5533cab501ac")
    }

    class SourceInstruction internal constructor(
        val sourceProfile: SourceProfile,
        val action: String,
        internal val instruction: TransactionInstruction
    )

    class SourceOnlyUnsigned internal constructor(
        transactionBytes: ByteArray,
        messageBytes: ByteArray,
        val blockhash: String,
        val owner: String,
        val program: String,
        val sourceProfile: SourceProfile,
        val action: String
    ) {
        private val envelope = transactionBytes.copyOf()
        private val message = messageBytes.copyOf()
        val transactionBytes: ByteArray get() = envelope.copyOf()
        val messageBytes: ByteArray get() = message.copyOf()

        init {
            require(envelope.size in 66..MAX_WIRE_BYTES && envelope[0] == 1.toByte() &&
                envelope.copyOfRange(1, 65).all { it == 0.toByte() } &&
                envelope.copyOfRange(65, envelope.size).contentEquals(message)) {
                "Source-only envelope must contain one zero signature and exact message"
            }
            require(message.size >= 4 && message[0] == 1.toByte() && message[1] == 0.toByte()) {
                "Source-only message must require one writable signer"
            }
        }
    }

    // Message bytes are public transaction content, so the differing offsets are safe to log.
    class WalletChangedMessage(val differences: String) : IllegalArgumentException("Wallet changed reviewed message")

    class SourceOnlyWalletReturnShape internal constructor(
        val reviewed: SourceOnlyUnsigned,
        transactionBytes: ByteArray,
        val signatureBase58: String
    ) {
        private val envelope = transactionBytes.copyOf()
        val transactionBytes: ByteArray get() = envelope.copyOf()
        val signatureBytes: ByteArray get() = envelope.copyOfRange(1, 65)
    }

    fun inspectSourceOnlyWalletReturnShape(reviewed: SourceOnlyUnsigned,
        signedPayloads: Array<ByteArray>): SourceOnlyWalletReturnShape {
        require(signedPayloads.size == 1) { "Wallet must return exactly one payload" }
        val returned = signedPayloads[0]
        require(returned.size == reviewed.transactionBytes.size && returned.size <= MAX_WIRE_BYTES) {
            "Wallet envelope length differs from reviewed envelope"
        }
        val envelope = returned.copyOf()
        require(envelope[0] == 1.toByte()) { "Wallet envelope must contain canonical one-signature prefix" }
        val message = envelope.copyOfRange(65, envelope.size)
        val expected = reviewed.messageBytes
        // Seed Vault recompiles the message and may order the accounts its own way; what it
        // signs must still mean exactly what was reviewed.
        if (!message.contentEquals(expected) && meaning(message) != meaning(expected)) {
            throw WalletChangedMessage(expected.indices.filter { message[it] != expected[it] }
                .take(48).joinToString(" ") { "$it:%02x>%02x".format(expected[it], message[it]) })
        }
        val signature = envelope.copyOfRange(1, 65)
        require(signature.any { it != 0.toByte() }) { "Wallet returned zero signature" }
        val signatureBase58 = SolanaRpc.signature(Base58.encodeToString(signature))
        return SourceOnlyWalletReturnShape(reviewed, envelope, signatureBase58)
    }

    fun canonicalClaim(program: String, owner: String, config: String, admissionMint: String,
        heldToken: String, pet: String, paid: String, systemProgram: String, ledger: String, nameId: Int): SourceInstruction {
        system(systemProgram)
        require(nameId in 0..255) { "Pet name id outside 0..255" }
        return canonical(program, "claim", "3ec6d6c1d59f6cd2", listOf(
            writableSigner(owner), writable(config), readonly(admissionMint), readonly(heldToken),
            writable(pet), writable(paid), readonly(systemProgram), writable(ledger)), byteArrayOf(nameId.toByte()))
    }

    fun canonicalDelegatePet(program: String, payer: String, config: String, pet: String,
        ownerProgram: String, buffer: String, delegationRecord: String, delegationMetadata: String,
        delegationProgram: String, systemProgram: String): SourceInstruction {
        require(ownerProgram == program) { "DelegatePet ownerProgram must match program" }
        require(delegationProgram == DELEGATION_PROGRAM) { "Delegation program mismatch" }
        system(systemProgram)
        return canonical(program, "delegate_pet", "824f91bdf70a6ac7", listOf(
            writableSigner(payer), readonly(config), writable(pet), readonly(ownerProgram),
            writable(buffer), writable(delegationRecord), writable(delegationMetadata),
            readonly(delegationProgram), readonly(systemProgram)))
    }

    fun canonicalOwnerEngage(program: String, owner: String, pet: String, world: String,
        ownerSessionProgramPlaceholder: String): SourceInstruction {
        require(ownerSessionProgramPlaceholder == program) { "Owner Engage requires explicit program session placeholder" }
        return canonical(program, "engage", "22945b45b47f136e", listOf(
            signer(owner), writable(pet), readonly(world), readonly(ownerSessionProgramPlaceholder)))
    }

    fun canonicalBank(program: String, owner: String, pet: String, world: String) =
        canonical(program, "bank", "34489ea3a9b80206", listOf(signer(owner), writable(pet), readonly(world)))

    fun canonicalBuy(program: String, owner: String, config: String, pet: String, ledger: String,
        skrMint: String, sourceToken: String, treasuryToken: String, tokenProgram: String,
        systemProgram: String, item: Int, tier: Int): SourceInstruction {
        system(systemProgram)
        token(tokenProgram)
        return canonical(program, "buy", "66063d1201daebea", listOf(
            writableSigner(owner), readonly(config), readonly(pet), writable(ledger), readonly(skrMint),
            writable(sourceToken), writable(treasuryToken), readonly(tokenProgram), readonly(systemProgram)),
            product(item, tier))
    }

    fun canonicalLoad(program: String, pet: String, ledger: String) =
        canonical(program, "load", "53ecbb4ce79f56ac", listOf(writable(pet), readonly(ledger)))

    fun canonicalCommitPet(program: String, owner: String, pet: String, vrfPayer: String,
        magicContext: String, magicFeeVault: String, magicProgram: String): SourceInstruction {
        require(magicProgram == MAGIC_PROGRAM && magicContext == MAGIC_CONTEXT) { "MagicBlock program/context mismatch" }
        return canonical(program, "commit_pet", "9c3fc91ca75a7165", listOf(signer(owner), writable(pet),
            writable(vrfPayer), writable(magicContext), writable(magicFeeVault), readonly(magicProgram)))
    }

    fun canonicalClaimReward(program: String, owner: String, config: String, pet: String,
        paid: String, hbrnMint: String, destinationToken: String, tokenProgram: String,
        systemProgram: String): SourceInstruction {
        system(systemProgram)
        token(tokenProgram)
        return canonical(program, "claim_reward", "955fb5f25e5a9ea2", listOf(writableSigner(owner),
            readonly(config), readonly(pet), writable(paid), writable(hbrnMint), writable(destinationToken),
            readonly(tokenProgram), readonly(systemProgram)))
    }

    // The owner's HBRN account before ClaimReward mints into it; a no-op when it exists. The owner is
    // both the payer and the wallet, and a message gives one key one set of flags.
    fun createAssociatedTokenIdempotent(owner: String, associated: String, mint: String, tokenProgram: String): SourceInstruction {
        token(tokenProgram)
        return SourceInstruction(SourceProfile.CANONICAL_B50E0B5, "create_associated_token", TransactionInstruction(
            key(ASSOCIATED_TOKEN_PROGRAM), listOf(writableSigner(owner), writable(associated),
                writableSigner(owner), readonly(mint), readonly(SYSTEM_PROGRAM), readonly(tokenProgram)),
            byteArrayOf(1)))
    }

    fun historicalTalk(program: String, owner: String, pet: String, world: String) =
        historical(program, "talk", "473058fc93ac6e8a", listOf(signer(owner), writable(pet), readonly(world)))

    fun historicalConsume(program: String, receipt: String, pet: String, world: String) =
        historical(program, "consume", "41b28d0d5f394c9a", listOf(writable(receipt), writable(pet), readonly(world)))

    fun historicalBuy(program: String, owner: String, config: String, pet: String, skrMint: String,
        sourceToken: String, treasuryToken: String, receipt: String, ownerProgram: String,
        buffer: String, delegationRecord: String, delegationMetadata: String, delegationProgram: String,
        tokenProgram: String, systemProgram: String, item: Int, tier: Int,
        effectiveReceiptNonce: BigInteger): SourceInstruction {
        require(ownerProgram == program) { "Historical Buy ownerProgram must match program" }
        require(delegationProgram == DELEGATION_PROGRAM) { "Delegation program mismatch" }
        system(systemProgram)
        token(tokenProgram)
        val arguments = product(item, tier)
        val nonce = unsigned64(effectiveReceiptNonce)
        val insuranceBase = BigInteger("18446744069414584320")
        require(if (item == 2) effectiveReceiptNonce >= insuranceBase else effectiveReceiptNonce < insuranceBase) {
            "Historical Buy nonce must match regular/insurance receipt range"
        }
        return historical(program, "buy", "66063d1201daebea", listOf(writableSigner(owner),
            readonly(config), readonly(pet), readonly(skrMint), writable(sourceToken), writable(treasuryToken),
            writable(receipt), readonly(ownerProgram), writable(buffer), writable(delegationRecord),
            writable(delegationMetadata), readonly(delegationProgram), readonly(tokenProgram), readonly(systemProgram)),
            arguments + nonce)
    }

    private data class Account(val key: String, val signer: Boolean, val writable: Boolean)
    private data class Call(val program: Account, val accounts: List<Account>, val data: String)
    private data class Meaning(val header: List<Int>, val payer: Account, val accounts: Set<Account>,
        val blockhash: String, val calls: List<Call>)

    // A legacy message as what it does: header counts, fee payer, account privileges, blockhash
    // and each instruction with its accounts resolved. Index order is not part of it.
    private fun meaning(message: ByteArray): Meaning {
        var at = 0
        fun byte(): Int { require(at < message.size) { "Message truncated" }; return message[at++].toInt() and 0xff }
        fun length(): Int {
            var value = 0
            for (shift in listOf(0, 7, 14)) {
                val part = byte()
                value = value or ((part and 0x7f) shl shift)
                if (part and 0x80 == 0) {
                    require(part != 0 || shift == 0) { "Non-canonical shortvec" }
                    return value
                }
            }
            throw IllegalArgumentException("Overlong shortvec")
        }
        fun bytes(count: Int): ByteArray {
            require(count >= 0 && at + count <= message.size) { "Message truncated" }
            return message.copyOfRange(at, at + count).also { at += count }
        }
        val header = List(3) { byte() }
        require(header[0] in 1..127) { "Versioned or unsigned message" }
        val keys = List(length()) { SolanaPublicKey(bytes(32)).address }
        val (signers, readonlySigned, readonlyUnsigned) = header
        require(signers <= keys.size && readonlySigned < signers && signers + readonlyUnsigned <= keys.size) { "Header exceeds accounts" }
        val accounts = keys.mapIndexed { index, key ->
            Account(key, index < signers,
                if (index < signers) index < signers - readonlySigned else index < keys.size - readonlyUnsigned)
        }
        require(keys.toSet().size == keys.size) { "Duplicate message account" }
        val blockhash = SolanaPublicKey(bytes(32)).address
        fun account(): Account { val index = byte(); require(index < accounts.size) { "Account index out of range" }; return accounts[index] }
        val calls = List(length()) {
            val program = account()
            Call(program, List(length()) { account() }, bytes(length()).joinToString("") { "%02x".format(it) })
        }
        require(at == message.size) { "Message has trailing bytes" }
        return Meaning(header, accounts[0], accounts.toSet(), blockhash, calls)
    }

    fun computeUnitLimitFor(consumed: BigInteger): Int {
        require(consumed.signum() >= 0) { "Negative compute units" }
        val withMargin = (consumed * BigInteger.valueOf(12) + BigInteger.valueOf(9)) / BigInteger.TEN
        return withMargin.min(BigInteger.valueOf(MAX_COMPUTE_UNIT_LIMIT.toLong())).toInt()
    }

    fun prepareSourceOnly(source: SourceInstruction, owner: String, program: String,
        recentBlockhash: String, computeUnitLimit: Int): SourceOnlyUnsigned =
        prepareSourceOnly(listOf(source), owner, program, recentBlockhash, computeUnitLimit)

    fun prepareSourceOnly(sources: List<SourceInstruction>, owner: String, program: String,
        recentBlockhash: String, computeUnitLimit: Int): SourceOnlyUnsigned {
        require(sources.isNotEmpty()) { "No action to prepare" }
        require(sources.all { it.sourceProfile == sources.first().sourceProfile }) { "Actions mix source profiles" }
        require(computeUnitLimit in 1..MAX_COMPUTE_UNIT_LIMIT) { "Compute unit limit outside 1..$MAX_COMPUTE_UNIT_LIMIT" }
        val payer = key(owner)
        val programKey = key(program)
        val budgetKey = key(COMPUTE_BUDGET_PROGRAM)
        val blockhash = key(recentBlockhash)
        val instructions = sources.map { it.instruction }
        val accounts = instructions.flatMap { it.accounts }
        val associatedKey = key(ASSOCIATED_TOKEN_PROGRAM)
        require(instructions.all { it.programId == programKey || it.programId == associatedKey }) { "Instruction program mismatch" }
        val programKeys = instructions.map { it.programId }.distinct()
        require(payer != budgetKey && programKey != budgetKey && accounts.none { it.publicKey == budgetKey }) {
            "Action aliases the compute budget program"
        }
        require(payer != programKey) { "Fee payer cannot be program" }
        require(accounts.none { it.isSigner && it.publicKey != payer }) { "Additional signer refused" }
        require(accounts.none { it.publicKey == payer && !it.isSigner }) { "Fee payer aliases nonsigner action account" }
        require(instructions.all { it.accounts.size <= 32 && it.data.size <= MAX_WIRE_BYTES }) { "Instruction exceeds unsigned bounds" }
        val writableKeys = accounts.filter { it.isWritable }.map { it.publicKey }
        val readonlyKeys = accounts.filter { !it.isWritable }.map { it.publicKey } + programKeys + budgetKey
        val keys = (listOf(payer) + writableKeys + readonlyKeys).distinct()
        val readonlyCount = keys.count { it != payer && it !in writableKeys }
        val budgetIndex = keys.indexOf(budgetKey).toUByte()
        val limitData = byteArrayOf(2) + ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(computeUnitLimit).array()
        val priceData = byteArrayOf(3) + ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(COMPUTE_UNIT_PRICE_MICRO_LAMPORTS).array()
        val message = LegacyMessage(1u, 0u, readonlyCount.toUByte(), keys, blockhash, listOf(
            Instruction(budgetIndex, byteArrayOf(), limitData),
            Instruction(budgetIndex, byteArrayOf(), priceData)) + instructions.map { instruction ->
            Instruction(keys.indexOf(instruction.programId).toUByte(),
                instruction.accounts.map { keys.indexOf(it.publicKey).toByte() }.toByteArray(),
                instruction.data.copyOf()) })
        val messageBytes = message.serialize()
        require(message.signatureCount.toInt() == 1 && message.readOnlyAccounts.toInt() == 0 &&
            message.accounts.first() == payer && messageBytes[0].toInt() == 1 && messageBytes[1].toInt() == 0) {
            "Unsigned message must require only writable owner fee payer at key0"
        }
        val transactionBytes = Transaction(message).serialize()
        require(transactionBytes.size <= MAX_WIRE_BYTES) { "Unsigned transaction exceeds 1232 bytes" }
        require(transactionBytes[0].toInt() == 1 && transactionBytes.copyOfRange(1, 65).all { it == 0.toByte() } &&
            transactionBytes.copyOfRange(65, transactionBytes.size).contentEquals(messageBytes)) {
            "Unsigned envelope must contain exactly one zero signature and unchanged message"
        }
        return SourceOnlyUnsigned(transactionBytes, messageBytes, recentBlockhash, owner, program,
            sources.first().sourceProfile, sources.joinToString("+") { it.action })
    }

    private fun canonical(program: String, action: String, discriminator: String, accounts: List<AccountMeta>,
        arguments: ByteArray = byteArrayOf()) = instruction(SourceProfile.CANONICAL_B50E0B5, program, action, discriminator, accounts, arguments)

    private fun historical(program: String, action: String, discriminator: String, accounts: List<AccountMeta>,
        arguments: ByteArray = byteArrayOf()) = instruction(SourceProfile.HISTORICAL_D09815C6, program, action, discriminator, accounts, arguments)

    private fun instruction(profile: SourceProfile, program: String, action: String, discriminator: String,
        accounts: List<AccountMeta>, arguments: ByteArray): SourceInstruction {
        require(accounts.map { it.publicKey }.distinct().size == accounts.size) { "Action account aliases refused" }
        val bytes = discriminator.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        require(bytes.size == 8) { "Instruction discriminator must be 8 bytes" }
        val programKey = key(program)
        val programAccountIndex = when {
            action == "delegate_pet" -> 3
            action == "engage" -> 3
            action == "buy" && profile == SourceProfile.HISTORICAL_D09815C6 -> 7
            else -> -1
        }
        require(accounts.withIndex().none { it.value.publicKey == programKey && it.index != programAccountIndex }) {
            "Program aliases action account"
        }
        return SourceInstruction(profile, action, TransactionInstruction(programKey, accounts, bytes + arguments))
    }

    private fun product(item: Int, tier: Int): ByteArray {
        require(item in 0..3) { "Shop item outside 0..3" }
        val maximumTier = when (item) { 0, 1 -> 2; 2 -> 0; 3 -> 1; else -> error("Unsupported shop item: $item") }
        require(tier in 0..maximumTier) { "Shop tier invalid for item $item" }
        return byteArrayOf(item.toByte(), tier.toByte())
    }

    private fun unsigned64(value: BigInteger): ByteArray {
        require(value.signum() >= 0 && value.bitLength() <= 64) { "Nonce outside uint64" }
        return ByteArray(8) { value.shiftRight(it * 8).toByte() }
    }

    private fun system(address: String) { require(address == SYSTEM_PROGRAM) { "System program mismatch" } }
    private fun token(address: String) {
        require(address == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" ||
            address == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb") { "Token program mismatch" }
    }
    private fun readonly(address: String) = AccountMeta(key(address), false, false)
    private fun writable(address: String) = AccountMeta(key(address), false, true)
    private fun signer(address: String) = AccountMeta(key(address), true, false)
    private fun writableSigner(address: String) = AccountMeta(key(address), true, true)
    private fun key(address: String): SolanaPublicKey {
        require(address.length in 32..44) { "Key must be canonical base58" }
        val key = SolanaPublicKey.from(address)
        require(key.bytes.size == 32 && key.address == address) { "Key must be canonical 32 bytes" }
        return key
    }
}
