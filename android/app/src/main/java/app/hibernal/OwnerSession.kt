package app.hibernal

import android.util.AtomicFile
import com.funkatronics.encoders.Base58
import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import com.solana.transaction.AccountMeta
import com.solana.transaction.Instruction
import com.solana.transaction.LegacyMessage
import com.solana.transaction.TransactionInstruction
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.FileNotFoundException
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import org.bouncycastle.math.ec.rfc8032.Ed25519

// A key kept on the phone that the owner approves once on L1 (the session-keys program's CreateSessionV2), so the
// app signs Bank and Engage on the ER itself: a phone wallet refuses ER transactions (docs/OPERATIONS.md). The
// program takes it only for this owner's Pet and only until validUntil (program/owner.ms sessionOf).
object OwnerSession {
    const val SESSION_KEYS_PROGRAM = "KeyspM2ssCJbqUhQ4k7sveSiY4WjnYsrXkC8oDbwde5"
    private const val CREATE_SESSION_V2 = "dfe96c0741c2eb26"
    private const val ENGAGE = "22945b45b47f136e"
    private const val BANK = "34489ea3a9b80206"
    // The session-keys program refuses validUntil past its own clock + 7 days; the margin covers the phone's clock.
    const val VALID_SECONDS = 7L * 24 * 3600 - 600
    private const val CREATE_COMPUTE_UNITS = 20_000
    // rules/owner.ms ownerBanked: half the harvest, once per OWNER_BANK_COOLDOWN_SECONDS of game time.
    const val OWNER_BANK_COOLDOWN_SECONDS = 8L * 3600
    private const val EPOCH_SECONDS = 86_400L

    class Signer(private val seed: ByteArray) {
        init { require(seed.size == Ed25519.SECRET_KEY_SIZE) { "Session seed must be 32 bytes" } }
        val publicKey: ByteArray = ByteArray(Ed25519.PUBLIC_KEY_SIZE).also { Ed25519.generatePublicKey(seed, 0, it, 0) }
        val address: String get() = SolanaPublicKey(publicKey).address
        fun sign(message: ByteArray) = ByteArray(Ed25519.SIGNATURE_SIZE).also { Ed25519.sign(seed, 0, message, 0, message.size, it, 0) }
        internal fun seed() = seed.copyOf()
    }

    fun newSigner() = Signer(ByteArray(Ed25519.SECRET_KEY_SIZE).also(SecureRandom()::nextBytes))

    // An approved key: usable for this owner and program until validUntil (unix seconds).
    class Approved(val owner: String, val program: String, val signer: Signer, val validUntil: Long) {
        fun usable(owner: String, program: String, nowSeconds: Long) =
            owner == this.owner && program == this.program && nowSeconds < validUntil
    }

    suspend fun token(program: String, signer: String, owner: String): String =
        ProgramDerivedAddress.find(listOf("session_token_v2".toByteArray(), key(program).bytes, key(signer).bytes, key(owner).bytes),
            key(SESSION_KEYS_PROGRAM)).getOrThrow().address

    // L1, owner pays: slot 0 the owner's signature (the wallet's), slot 1 the session key's, signed here.
    fun createSession(owner: String, signer: Signer, program: String, token: String, validUntil: Long,
        blockhash: String): ByteArray {
        // No top-up: the ER charges the session key nothing (measured on Cq4i, 2026-10-11).
        val data = bytes(CREATE_SESSION_V2) + byteArrayOf(0, 1) + u64(validUntil) + byteArrayOf(0)
        val create = TransactionInstruction(key(SESSION_KEYS_PROGRAM), listOf(
            AccountMeta(key(token), false, true), AccountMeta(key(signer.address), true, true),
            AccountMeta(key(owner), true, true), AccountMeta(key(owner), true, false),
            AccountMeta(key(program), false, false), AccountMeta(key(OwnerTransaction.SYSTEM_PROGRAM), false, false)), data)
        val budget = key(OwnerTransaction.COMPUTE_BUDGET_PROGRAM)
        val limit = TransactionInstruction(budget, emptyList(),
            byteArrayOf(2) + ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(CREATE_COMPUTE_UNITS).array())
        val price = TransactionInstruction(budget, emptyList(),
            byteArrayOf(3) + u64(OwnerTransaction.COMPUTE_UNIT_PRICE_MICRO_LAMPORTS))
        return signed(compile(listOf(key(owner), key(signer.address)), listOf(limit, price, create), blockhash), signer, 1)
    }

    // ER, the session key alone signs and pays (the ER charges nothing).
    fun engage(signer: Signer, program: String, pet: String, world: String, token: String, blockhash: String) =
        onEphemeral(ENGAGE, signer, program, pet, world, token, blockhash)

    fun bank(signer: Signer, program: String, pet: String, world: String, token: String, blockhash: String) =
        onEphemeral(BANK, signer, program, pet, world, token, blockhash)

    private fun onEphemeral(discriminator: String, signer: Signer, program: String, pet: String, world: String,
        token: String, blockhash: String): ByteArray {
        val instruction = TransactionInstruction(key(program), listOf(AccountMeta(key(signer.address), true, false),
            AccountMeta(key(pet), false, true), AccountMeta(key(world), false, false), AccountMeta(key(token), false, false)),
            bytes(discriminator))
        return signed(compile(listOf(key(signer.address)), listOf(instruction), blockhash), signer, 0)
    }

    // The wallet may sign only slot 0 and must leave the message and the session key's signature as they were.
    fun walletSigned(sent: ByteArray, returned: ByteArray): ByteArray {
        val signatures = sent[0].toInt()
        val messageAt = 1 + signatures * Ed25519.SIGNATURE_SIZE
        require(returned.size == sent.size && returned[0] == sent[0]) { "Wallet changed the transaction shape" }
        require(returned.copyOfRange(messageAt, returned.size).contentEquals(sent.copyOfRange(messageAt, sent.size))) {
            "Wallet changed the message"
        }
        require(returned.copyOfRange(1 + Ed25519.SIGNATURE_SIZE, messageAt).contentEquals(sent.copyOfRange(1 + Ed25519.SIGNATURE_SIZE, messageAt))) {
            "Wallet changed another signer's signature"
        }
        // Key 0 follows the 3-byte header and the one-byte key count.
        val owner = returned.copyOfRange(messageAt + 4, messageAt + 36)
        require(Ed25519.verify(returned, 1, owner, 0, returned, messageAt, returned.size - messageAt)) { "Wallet signature does not verify" }
        return returned
    }

    fun signature(transaction: ByteArray): String = Base58.encodeToString(transaction.copyOfRange(1, 1 + Ed25519.SIGNATURE_SIZE))

    fun load(file: AtomicFile): Approved? = try {
        file.openRead().use { stream ->
            DataInputStream(stream).run {
                fun key() = SolanaPublicKey(ByteArray(32).also(::readFully)).address
                val owner = key()
                val program = key()
                Approved(owner, program, Signer(ByteArray(32).also(::readFully)), readLong())
            }
        }
    } catch (error: FileNotFoundException) {
        null
    } catch (error: EOFException) {
        null
    }

    fun save(file: AtomicFile, approved: Approved) {
        val stream = file.startWrite()
        try {
            DataOutputStream(stream).run {
                write(key(approved.owner).bytes)
                write(key(approved.program).bytes)
                write(approved.signer.seed())
                writeLong(approved.validUntil)
                flush()
            }
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    // Legacy message: the signers first, all writable, then writable accounts, then the rest.
    private fun compile(signers: List<SolanaPublicKey>, instructions: List<TransactionInstruction>, blockhash: String): ByteArray {
        val metas = instructions.flatMap { it.accounts }
        require(metas.none { it.isSigner && it.publicKey !in signers }) { "Unlisted signer" }
        val writable = metas.filter { it.isWritable }.map { it.publicKey }
        val keys = (signers + writable + metas.map { it.publicKey } + instructions.map { it.programId }).distinct()
        val readonly = keys.count { it !in signers && it !in writable }
        val message = LegacyMessage(signers.size.toUByte(), 0u, readonly.toUByte(), keys, key(blockhash), instructions.map { instruction ->
            Instruction(keys.indexOf(instruction.programId).toUByte(),
                instruction.accounts.map { keys.indexOf(it.publicKey).toByte() }.toByteArray(), instruction.data) })
        val serialized = message.serialize()
        val transaction = byteArrayOf(signers.size.toByte()) + ByteArray(signers.size * Ed25519.SIGNATURE_SIZE) + serialized
        require(transaction.size <= OwnerTransaction.MAX_WIRE_BYTES) { "Transaction exceeds 1232 bytes" }
        return transaction
    }

    private fun signed(transaction: ByteArray, signer: Signer, slot: Int): ByteArray {
        val messageAt = 1 + transaction[0] * Ed25519.SIGNATURE_SIZE
        signer.sign(transaction.copyOfRange(messageAt, transaction.size))
            .copyInto(transaction, 1 + slot * Ed25519.SIGNATURE_SIZE)
        return transaction
    }

    private fun u64(value: Long): ByteArray {
        require(value >= 0) { "Negative uint64" }
        return ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(value).array()
    }

    private fun bytes(hex: String) = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    private fun key(address: String) = SolanaPublicKey.from(address)

    // program/layout.ms gameSecondsAt.
    fun gameSeconds(genesis: BigInteger, secondsPerDay: BigInteger, unixSeconds: Long): BigInteger {
        val unix = BigInteger.valueOf(unixSeconds)
        if (unix < genesis) return BigInteger.ZERO
        return (unix - genesis) * BigInteger.valueOf(EPOCH_SECONDS) / secondsPerDay
    }

    fun bankCoolingDown(ownerBankedAt: BigInteger, gameNow: BigInteger) =
        gameNow < ownerBankedAt + BigInteger.valueOf(OWNER_BANK_COOLDOWN_SECONDS)
}
