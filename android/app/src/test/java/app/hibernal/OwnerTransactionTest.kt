package app.hibernal

import com.solana.publickey.SolanaPublicKey
import com.solana.transaction.AccountMeta
import com.solana.transaction.Message
import com.solana.transaction.TransactionInstruction
import java.math.BigInteger
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

internal const val TEST_COMPUTE_UNIT_LIMIT = 1234

class OwnerTransactionTest {
    private val program = address(90)
    private val owner = address(1)
    private val blockhash = address(91)
    private val system = OwnerTransaction.SYSTEM_PROGRAM
    private val delegation = OwnerTransaction.DELEGATION_PROGRAM
    private val token = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    private val magic = OwnerTransaction.MAGIC_PROGRAM
    private val context = OwnerTransaction.MAGIC_CONTEXT
    private val budget = OwnerTransaction.COMPUTE_BUDGET_PROGRAM

    @Test fun bankHasIndependentFullWireGoldenAndOwnerFirstWritableSigner() {
        val source = OwnerTransaction.canonicalBank(program, owner, address(2), address(3))
        val prepared = OwnerTransaction.prepareSourceOnly(source, owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
        val message = byteArrayOf(1, 0, 3, 5) + raw(1) + raw(2) + raw(3) + raw(90) + SolanaPublicKey.from(budget).bytes + raw(91) +
            byteArrayOf(3) + byteArrayOf(4, 0, 5) + hex("02d2040000") + byteArrayOf(4, 0, 9) + hex("03a086010000000000") +
            byteArrayOf(3, 3, 0, 1, 2, 8) + hex("34489ea3a9b80206")
        assertArrayEquals(message, prepared.messageBytes)
        assertArrayEquals(byteArrayOf(1) + ByteArray(64) + message, prepared.transactionBytes)
        assertEquals(owner, prepared.owner)
        assertEquals(program, prepared.program)
        assertEquals(blockhash, prepared.blockhash)
        assertEquals("bank", prepared.action)
        assertEquals(OwnerTransaction.SourceProfile.CANONICAL_B50E0B5, prepared.sourceProfile)
        assertEquals("f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc", prepared.sourceProfile.sourceTree)
    }

    @Test fun sourceOnlyPreviewKeepsUnknownFeeFailureAndInclusiveExpiry() {
        val unsigned = OwnerTransaction.prepareSourceOnly(
            OwnerTransaction.canonicalBank(program, owner, address(2), address(3)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
        val preview = OwnerPreflight.SourceOnlyPreview(unsigned, SolanaRpc.DEVNET,
            BigInteger.valueOf(42), BigInteger.valueOf(100), BigInteger.valueOf(100),
            SolanaRpc.ContextValue(BigInteger.valueOf(42), null),
            SolanaRpc.ContextValue(BigInteger.valueOf(42), SolanaRpc.Simulation("AccountNotFound", null, null)))
        assertFalse(preview.expired)
        assertNull(preview.fee.value)
        assertEquals("AccountNotFound", preview.simulation.value.error)
        assertEquals(SolanaRpc.DEVNET, preview.endpoint)
        assertTrue(preview.copy(observedBlockHeight = BigInteger.valueOf(101)).expired)
    }

    @Test fun everyCanonicalBuilderHasExactWireAccountOrderPrivilegesAndDiscriminator() {
        verify(OwnerTransaction.canonicalClaim(program, owner, address(2), address(3), address(4), address(5), address(6), system, address(7), 255),
            "claim", "3ec6d6c1d59f6cd2ff", listOf(owner to "WS", address(2) to "W", address(3) to "R",
                address(4) to "R", address(5) to "W", address(6) to "W", system to "R", address(7) to "W"))
        verify(OwnerTransaction.canonicalDelegatePet(program, owner, address(2), address(3), program, address(4), address(5), address(6), delegation, system),
            "delegate_pet", "824f91bdf70a6ac7", listOf(owner to "WS", address(2) to "R", address(3) to "W",
                program to "R", address(4) to "W", address(5) to "W", address(6) to "W", delegation to "R", system to "R"))
        verify(OwnerTransaction.canonicalOwnerEngage(program, owner, address(2), address(3), program),
            "engage", "22945b45b47f136e", listOf(owner to "S", address(2) to "W", address(3) to "R", program to "R"))
        verify(OwnerTransaction.canonicalBank(program, owner, address(2), address(3)),
            "bank", "34489ea3a9b80206", listOf(owner to "S", address(2) to "W", address(3) to "R"))
        verify(buy(0, 2), "buy", "66063d1201daebea0002", listOf(owner to "WS", address(2) to "R",
            address(3) to "R", address(4) to "W", address(5) to "R", address(6) to "W", address(7) to "W", token to "R", system to "R"))
        verify(OwnerTransaction.canonicalLoad(program, address(2), address(3)),
            "load", "53ecbb4ce79f56ac", listOf(address(2) to "W", address(3) to "R"))
        verify(OwnerTransaction.canonicalCommitPet(program, owner, address(2), address(3), context, address(4), magic),
            "commit_pet", "9c3fc91ca75a7165", listOf(owner to "S", address(2) to "W", address(3) to "W",
                context to "W", address(4) to "W", magic to "R"))
        verify(OwnerTransaction.canonicalClaimReward(program, owner, address(2), address(3), address(4), address(5), address(6), token, system),
            "claim_reward", "955fb5f25e5a9ea2", listOf(owner to "WS", address(2) to "R", address(3) to "R",
                address(4) to "W", address(5) to "W", address(6) to "W", token to "R", system to "R"))
    }

    @Test fun payerIsMessageOnlyForPermissionlessLoadAndConsume() {
        val load = parse(OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalLoad(program, address(2), address(3)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT))
        assertEquals(listOf(address(2), address(3)), load.instructionAccounts)
        assertEquals(owner, load.keys.first())
        val consume = OwnerTransaction.historicalConsume(program, address(2), address(3), address(4))
        verify(consume, "consume", "41b28d0d5f394c9a", listOf(address(2) to "W", address(3) to "W", address(4) to "R"))
        assertEquals(OwnerTransaction.SourceProfile.HISTORICAL_D09815C6, consume.sourceProfile)
    }

    @Test fun legacyTalkAndBuyAreExplicitlySeparateFromCanonicalBuy() {
        verify(OwnerTransaction.historicalTalk(program, owner, address(2), address(3)),
            "talk", "473058fc93ac6e8a", listOf(owner to "S", address(2) to "W", address(3) to "R"))
        val nonce = BigInteger("72623859790382856")
        val legacy = legacyBuy(1, 2, nonce)
        verify(legacy, "buy", "66063d1201daebea01020807060504030201", listOf(owner to "WS", address(2) to "R",
            address(3) to "R", address(4) to "R", address(5) to "W", address(6) to "W", address(7) to "W",
            program to "R", address(8) to "W", address(9) to "W", address(10) to "W", delegation to "R", token to "R", system to "R"))
        val canonicalWire = parse(OwnerTransaction.prepareSourceOnly(buy(1, 2), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT))
        val legacyWire = parse(OwnerTransaction.prepareSourceOnly(legacy, owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT))
        assertEquals(10, canonicalWire.data.size)
        assertEquals(18, legacyWire.data.size)
        assertEquals(9, canonicalWire.instructionAccounts.size)
        assertEquals(14, legacyWire.instructionAccounts.size)
        assertEquals(OwnerTransaction.SourceProfile.HISTORICAL_D09815C6, legacy.sourceProfile)
        assertEquals("511868044a069d6e35ddf512af5f5533cab501ac", legacy.sourceProfile.sourceTree)
    }

    @Test fun shopRangesAndNonceUnsignedLittleEndianBounds() {
        for (item in 0..3) {
            val maximum = listOf(2, 2, 0, 1)[item]
            for (tier in 0..maximum) assertArrayEquals(byteArrayOf(item.toByte(), tier.toByte()), buy(item, tier).instruction.data.copyOfRange(8, 10))
            refuses { buy(item, -1) }
            refuses { buy(item, maximum + 1) }
            refuses { buy(item, 256) }
        }
        for (item in listOf(-1, 4, 256)) refuses { buy(item, 0) }
        val maximumNonce = BigInteger("18446744073709551615")
        val wire = parse(OwnerTransaction.prepareSourceOnly(legacyBuy(2, 0, maximumNonce), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT))
        assertArrayEquals(ByteArray(8) { 0xff.toByte() }, wire.data.copyOfRange(10, 18))
        assertArrayEquals(ByteArray(8), legacyBuy(0, 0, BigInteger.ZERO).instruction.data.copyOfRange(10, 18))
        assertArrayEquals(hex("fffffffffeffffff"), legacyBuy(0, 0, BigInteger("18446744069414584319")).instruction.data.copyOfRange(10, 18))
        assertArrayEquals(hex("00000000ffffffff"), legacyBuy(2, 0, BigInteger("18446744069414584320")).instruction.data.copyOfRange(10, 18))
        refuses { legacyBuy(-1, 0, BigInteger.ZERO) }
        refuses { legacyBuy(3, 2, BigInteger.ZERO) }
        refuses { legacyBuy(0, 0, BigInteger.valueOf(-1)) }
        refuses { legacyBuy(2, 0, maximumNonce + BigInteger.ONE) }
        refuses { legacyBuy(0, 0, BigInteger("18446744069414584320")) }
        refuses { legacyBuy(2, 0, BigInteger.ZERO) }
    }

    @Test fun sdk031BuilderOmitsProgramReadonlyCountAndDoesNotMergeSignerPrivileges() {
        val bank = OwnerTransaction.canonicalBank(program, owner, address(2), address(3)).instruction
        val sdk = Message.Builder().setRecentBlockhash(blockhash).addInstruction(bank).build()
        assertEquals(1, sdk.readOnlyNonSigners.toInt())
        assertEquals(2, sdk.accounts.count { it.address == address(3) || it.address == program })
        val duplicatePayer = Message.Builder().setRecentBlockhash(blockhash).addInstruction(
            TransactionInstruction(bank.programId, listOf(AccountMeta(SolanaPublicKey.from(owner), true, true)) + bank.accounts, bank.data)).build()
        assertEquals(1, duplicatePayer.readOnlyAccounts.toInt())
        val prepared = parse(OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalBank(program, owner, address(2), address(3)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT))
        assertEquals(3, prepared.readonlyNonsigners)
        assertEquals(0, prepared.readonlySigners)
    }

    @Test fun malformedKeysAliasesProgramsAndMissingPayerRefused() {
        for (invalid in listOf("", "1", "0".repeat(32), "1".repeat(33), address(1) + " ", "1" + address(1))) {
            refuses { OwnerTransaction.canonicalBank(program, invalid, address(2), address(3)) }
            refuses { OwnerTransaction.prepareSourceOnly(buy(0, 0), owner, program, invalid, TEST_COMPUTE_UNIT_LIMIT) }
        }
        refuses { OwnerTransaction.canonicalBank(program, owner, owner, address(3)) }
        refuses { OwnerTransaction.canonicalBank(program, owner, program, address(3)) }
        refuses { OwnerTransaction.canonicalOwnerEngage(program, owner, address(2), address(3), address(4)) }
        refuses { OwnerTransaction.canonicalDelegatePet(program, owner, address(2), address(3), address(4), address(5), address(6), address(7), delegation, system) }
        refuses { OwnerTransaction.canonicalDelegatePet(program, owner, address(2), address(3), program, address(5), address(6), address(7), address(8), system) }
        refuses { OwnerTransaction.canonicalClaim(program, owner, address(2), address(3), address(4), address(5), address(6), address(7), address(8), 0) }
        refuses { OwnerTransaction.canonicalClaim(program, owner, address(2), address(3), address(4), address(5), address(6), system, address(7), 256) }
        refuses { OwnerTransaction.canonicalCommitPet(program, owner, address(2), address(3), context, address(4), address(5)) }
        refuses { OwnerTransaction.canonicalBuy(program, owner, address(2), address(3), address(4), address(5), address(6), address(7), address(8), system, 0, 0) }
        refuses { OwnerTransaction.prepareSourceOnly(buy(0, 0), "", program, blockhash, TEST_COMPUTE_UNIT_LIMIT) }
        refuses { OwnerTransaction.prepareSourceOnly(buy(0, 0), owner, address(80), blockhash, TEST_COMPUTE_UNIT_LIMIT) }
        refuses { OwnerTransaction.prepareSourceOnly(buy(0, 0), address(80), program, blockhash, TEST_COMPUTE_UNIT_LIMIT) }
        refuses { OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalLoad(program, owner, address(2)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT) }
    }

    @Test fun additionalSignerAndOversizeWireRefusedWithExact1232Boundary() {
        val bank = OwnerTransaction.canonicalBank(program, owner, address(2), address(3))
        fun modified(accounts: List<AccountMeta> = bank.instruction.accounts, data: ByteArray = bank.instruction.data) =
            OwnerTransaction.SourceInstruction(bank.sourceProfile, bank.action,
                TransactionInstruction(bank.instruction.programId, accounts, data))
        val extraSigner = AccountMeta(SolanaPublicKey.from(address(4)), true, true)
        refuses { OwnerTransaction.prepareSourceOnly(modified(bank.instruction.accounts + extraSigner), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT) }
        val atLimit = OwnerTransaction.prepareSourceOnly(modified(data = ByteArray(943)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
        assertEquals(1232, atLimit.transactionBytes.size)
        assertEquals(943, parse(atLimit).data.size)
        refuses { OwnerTransaction.prepareSourceOnly(modified(data = ByteArray(944)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT) }
        refuses { OwnerTransaction.prepareSourceOnly(modified(data = ByteArray(1233)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT) }
    }

    private fun buy(item: Int, tier: Int) = OwnerTransaction.canonicalBuy(program, owner, address(2), address(3), address(4),
        address(5), address(6), address(7), token, system, item, tier)
    private fun legacyBuy(item: Int, tier: Int, nonce: BigInteger) = OwnerTransaction.historicalBuy(program, owner,
        address(2), address(3), address(4), address(5), address(6), address(7), program, address(8), address(9),
        address(10), delegation, token, system, item, tier, nonce)

    private fun verify(source: OwnerTransaction.SourceInstruction, action: String, dataHex: String, expected: List<Pair<String, String>>) {
        val unsigned = OwnerTransaction.prepareSourceOnly(source, owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
        val wire = parse(unsigned)
        assertEquals(action, unsigned.action)
        assertEquals(program, wire.program)
        assertEquals(expected.map { it.first }, wire.instructionAccounts)
        assertArrayEquals(hex(dataHex), wire.data)
        assertArrayEquals(MessageDigest.getInstance("SHA-256").digest("global:$action".toByteArray()).copyOf(8), wire.data.copyOf(8))
        val privileges = expected.associate { it.first to if (it.first == owner) "WS" else it.second } + (owner to "WS") + (program to "R") + (budget to "R")
        assertEquals(privileges.keys, wire.keys.toSet())
        for ((key, privilege) in privileges) assertEquals("$action $key", privilege, wire.privileges(key))
        assertEquals(1, wire.requiredSignatures)
        assertEquals(0, wire.readonlySigners)
        assertEquals(owner, wire.keys.first())
        assertArrayEquals(raw(91), wire.blockhash)
    }

    private data class Wire(val requiredSignatures: Int, val readonlySigners: Int, val readonlyNonsigners: Int,
        val keys: List<String>, val blockhash: ByteArray, val program: String, val instructionAccounts: List<String>, val data: ByteArray) {
        fun privileges(key: String): String {
            val index = keys.indexOf(key)
            return if (index < requiredSignatures) {
                if (index < requiredSignatures - readonlySigners) "WS" else "S"
            } else if (index < keys.size - readonlyNonsigners) "W" else "R"
        }
    }

    private fun parse(unsigned: OwnerTransaction.SourceOnlyUnsigned): Wire {
        val bytes = unsigned.transactionBytes
        var offset = 0
        fun byte(): Int { assertTrue(offset < bytes.size); return bytes[offset++].toInt() and 255 }
        fun take(count: Int): ByteArray { assertTrue(offset + count <= bytes.size); return bytes.copyOfRange(offset, offset + count).also { offset += count } }
        fun shortvec(): Int {
            var result = 0
            var shift = 0
            do {
                val next = byte()
                result = result or ((next and 127) shl shift)
                shift += 7
                assertTrue(shift <= 21)
            } while (next and 128 != 0)
            return result
        }
        val signatures = shortvec()
        assertEquals(1, signatures)
        assertArrayEquals(ByteArray(64 * signatures), take(64 * signatures))
        assertArrayEquals(unsigned.messageBytes, bytes.copyOfRange(offset, bytes.size))
        val required = byte()
        val readonlySigners = byte()
        val readonlyNonsigners = byte()
        val keys = List(shortvec()) { SolanaPublicKey(take(32)).address }
        assertEquals(keys.size, keys.distinct().size)
        val hash = take(32)
        assertEquals(3, shortvec())
        for (expected in listOf(byteArrayOf(2) + littleEndian(TEST_COMPUTE_UNIT_LIMIT.toLong(), 4),
                byteArrayOf(3) + littleEndian(OwnerTransaction.COMPUTE_UNIT_PRICE_MICRO_LAMPORTS, 8))) {
            assertEquals(budget, keys[byte()])
            assertEquals(0, shortvec())
            assertArrayEquals(expected, take(shortvec()))
        }
        val programIndex = byte()
        val indices = take(shortvec()).map { it.toInt() and 255 }
        val data = take(shortvec())
        assertEquals(bytes.size, offset)
        assertTrue(bytes.size <= 1232)
        assertEquals(signatures, required)
        return Wire(required, readonlySigners, readonlyNonsigners, keys, hash, keys[programIndex], indices.map { keys[it] }, data)
    }

    @Test fun computeBudgetLeadsWithExactLimitAndPrice() {
        val prepared = OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalBank(program, owner, address(2), address(3)),
            owner, program, blockhash, 200_000)
        val message = prepared.messageBytes
        val instructions = message.copyOfRange(4 + 5 * 32 + 32, message.size)
        assertArrayEquals(byteArrayOf(3, 4, 0, 5, 2, 0x40, 0x0d, 3, 0, 4, 0, 9, 3, 0xa0.toByte(), 0x86.toByte(), 1, 0, 0, 0, 0, 0),
            instructions.copyOf(21))
        refuses { OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalBank(program, owner, address(2), address(3)), owner, program, blockhash, 0) }
        refuses { OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalBank(program, owner, address(2), address(3)), owner, program, blockhash,
            OwnerTransaction.MAX_COMPUTE_UNIT_LIMIT + 1) }
        refuses { OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalBank(program, owner, address(2), budget), owner, program, blockhash, 1) }
        refuses { OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalBank(program, budget, address(2), address(3)), budget, program, blockhash, 1) }
    }

    @Test fun simulatedUnitsGainRoundedUpTwentyPercentWithinTheCap() {
        assertEquals(540, OwnerTransaction.computeUnitLimitFor(BigInteger.valueOf(450)))
        assertEquals(542, OwnerTransaction.computeUnitLimitFor(BigInteger.valueOf(451)))
        assertEquals(0, OwnerTransaction.computeUnitLimitFor(BigInteger.ZERO))
        assertEquals(1_399_998, OwnerTransaction.computeUnitLimitFor(BigInteger.valueOf(1_166_665)))
        assertEquals(1_400_000, OwnerTransaction.computeUnitLimitFor(BigInteger.valueOf(1_166_666)))
        assertEquals(1_400_000, OwnerTransaction.computeUnitLimitFor(BigInteger.valueOf(1_166_667)))
        assertEquals(1_400_000, OwnerTransaction.computeUnitLimitFor(BigInteger.valueOf(1_400_000)))
        refuses { OwnerTransaction.computeUnitLimitFor(BigInteger.valueOf(-1)) }
    }

    private fun littleEndian(value: Long, width: Int) = ByteArray(width) { (value shr (8 * it)).toByte() }
    private fun refuses(block: () -> Unit) { assertThrows(IllegalArgumentException::class.java) { block() } }
    private fun raw(value: Int) = ByteArray(32) { value.toByte() }
    private fun address(value: Int) = SolanaPublicKey(raw(value)).address
    private fun hex(value: String) = value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
