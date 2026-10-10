package app.hibernal

import com.solana.publickey.SolanaPublicKey
import com.solana.mobilewalletadapter.clientlib.protocol.MobileWalletAdapterClient
import com.solana.transaction.TransactionInstruction
import org.junit.Assert.*
import org.junit.Test

class OwnerTransactionWalletReturnTest {
    private val owner = address(1)
    private val program = address(90)
    private val blockhash = address(91)
    private val profile = OwnerTransaction.SourceProfile.CANONICAL_B50E0B5
    private val signature = hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
    private val message = byteArrayOf(1, 0, 3, 5) + raw(1) + raw(2) + raw(3) + raw(90) +
        SolanaPublicKey.from(OwnerTransaction.COMPUTE_BUDGET_PROGRAM).bytes + raw(91) +
        byteArrayOf(3) + byteArrayOf(4, 0, 5) + hex("02d2040000") + byteArrayOf(4, 0, 9) + hex("03a086010000000000") +
        byteArrayOf(3, 3, 0, 1, 2, 8) + hex("34489ea3a9b80206")
    private val unsignedGolden = byteArrayOf(1) + ByteArray(64) + message
    private val returnedGolden = byteArrayOf(1) + signature + message

    @Test fun bankReturnHasIndependentEnvelopeAndCanonicalSignatureGolden() {
        val reviewed = bank()
        assertArrayEquals(unsignedGolden, reviewed.transactionBytes)
        assertArrayEquals(message, reviewed.messageBytes)
        val shape = inspect(reviewed, returnedGolden)
        assertSame(reviewed, shape.reviewed)
        assertArrayEquals(returnedGolden, shape.transactionBytes)
        assertArrayEquals(signature, shape.signatureBytes)
        assertEquals("5awYiUvGiDFA33EJjj4TXJG44a5afJc8QjWRpGgQiu6b23jCr7yndW2fmp9ujwqJVe32J456wV3VF78Asb1obnTc", shape.signatureBase58)
        assertEquals(owner, shape.reviewed.owner)
        assertEquals(program, shape.reviewed.program)
        assertEquals(blockhash, shape.reviewed.blockhash)
        assertEquals(profile, shape.reviewed.sourceProfile)
        assertEquals("bank", shape.reviewed.action)
    }

    @Test fun actualMwa22SignPayloadsResultFeedsRawEnvelopeGuardWithoutTransactionDeserialization() {
        val result = MobileWalletAdapterClient.SignPayloadsResult(arrayOf(returnedGolden.copyOf()))
        val shape = OwnerTransaction.inspectSourceOnlyWalletReturnShape(bank(), result.signedPayloads)
        assertArrayEquals(returnedGolden, shape.transactionBytes)
        result.signedPayloads[0].fill(0)
        assertArrayEquals(returnedGolden, shape.transactionBytes)
    }

    @Test fun everyReviewedMessageByteMutationRefusedIncludingPayerBlockhashAccountsProgramAndArgs() {
        val reviewed = bank()
        for (index in 65 until returnedGolden.size) {
            val mutated = returnedGolden.copyOf()
            mutated[index] = (mutated[index].toInt() xor 1).toByte()
            assertThrows("message byte $index", IllegalArgumentException::class.java) { inspect(reviewed, mutated) }
        }
        val buy = OwnerTransaction.prepareSourceOnly(OwnerTransaction.canonicalBuy(program, owner,
            address(2), address(3), address(4), address(5), address(6), address(7), SolanaRpc.TOKEN_2022,
            OwnerTransaction.SYSTEM_PROGRAM, 0, 2), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
        val original = byteArrayOf(1) + signature + buy.messageBytes
        for (index in original.size - 2 until original.size) {
            val mutated = original.copyOf()
            mutated[index] = (mutated[index].toInt() xor 1).toByte()
            refuses { inspect(buy, mutated) }
        }
    }

    @Test fun walletReorderOfReadonlyAccountsIsAcceptedAndItsOwnMessageSent() {
        val reordered = byteArrayOf(1, 0, 3, 5) + raw(1) + raw(2) + raw(3) +
            SolanaPublicKey.from(OwnerTransaction.COMPUTE_BUDGET_PROGRAM).bytes + raw(90) + raw(91) +
            byteArrayOf(3) + byteArrayOf(3, 0, 5) + hex("02d2040000") + byteArrayOf(3, 0, 9) + hex("03a086010000000000") +
            byteArrayOf(4, 3, 0, 1, 2, 8) + hex("34489ea3a9b80206")
        val shape = inspect(bank(), byteArrayOf(1) + signature + reordered)
        assertArrayEquals(byteArrayOf(1) + signature + reordered, shape.transactionBytes)
    }

    @Test fun walletReorderThatMovesPrivilegesOrRetargetsAnInstructionIsRefused() {
        val swappedWritable = byteArrayOf(1, 0, 3, 5) + raw(1) + raw(3) + raw(2) + raw(90) +
            SolanaPublicKey.from(OwnerTransaction.COMPUTE_BUDGET_PROGRAM).bytes + raw(91) +
            byteArrayOf(3) + byteArrayOf(4, 0, 5) + hex("02d2040000") + byteArrayOf(4, 0, 9) + hex("03a086010000000000") +
            byteArrayOf(3, 3, 0, 2, 1, 8) + hex("34489ea3a9b80206")
        refuses { inspect(bank(), byteArrayOf(1) + signature + swappedWritable) }
        val retargeted = message.copyOf().also { it[it.size - 11] = 2 }
        refuses { inspect(bank(), byteArrayOf(1) + signature + retargeted) }
    }

    @Test fun everyTruncationAndAppendedTrailingBytesRefused() {
        val reviewed = bank()
        for (size in 0 until returnedGolden.size) {
            refuses { inspect(reviewed, returnedGolden.copyOf(size)) }
        }
        for (suffix in listOf(byteArrayOf(0), ByteArray(64), ByteArray(1233))) {
            refuses { inspect(reviewed, returnedGolden + suffix) }
        }
    }

    @Test fun payloadCountsSignatureCountsVersionedHeaderAndOverlongShortvecRefused() {
        val reviewed = bank()
        refuses { OwnerTransaction.inspectSourceOnlyWalletReturnShape(reviewed, emptyArray()) }
        refuses { OwnerTransaction.inspectSourceOnlyWalletReturnShape(reviewed, arrayOf(returnedGolden, returnedGolden)) }
        for (count in listOf(0, 2, 127, 128, 129, 255)) {
            val mutated = returnedGolden.copyOf()
            mutated[0] = count.toByte()
            refuses { inspect(reviewed, mutated) }
        }
        refuses { inspect(reviewed, byteArrayOf(0x81.toByte(), 0) + signature + message) }
        refuses { inspect(reviewed, byteArrayOf(2) + signature + signature + message) }
        val versioned = returnedGolden.copyOf()
        versioned[65] = 0x80.toByte()
        refuses { inspect(reviewed, versioned) }
    }

    @Test fun zeroSignatureRefusedButLeadingZerosRetainCanonical64ByteEncoding() {
        val reviewed = bank()
        refuses { inspect(reviewed, unsignedGolden) }
        val leadingZeros = ByteArray(64).also { it[63] = 1 }
        val shape = inspect(reviewed, byteArrayOf(1) + leadingZeros + message)
        assertEquals("1".repeat(63) + "2", shape.signatureBase58)
        assertArrayEquals(leadingZeros, shape.signatureBytes)
    }

    @Test fun shapeMatchDoesNotVerifyCryptographicSignatureOrWalletAuthorization() {
        val invalidForBank = ByteArray(64) { 0xff.toByte() }
        val shape = inspect(bank(), byteArrayOf(1) + invalidForBank + message)
        assertArrayEquals(invalidForBank, shape.signatureBytes)
        assertArrayEquals(message, shape.reviewed.messageBytes)
    }

    @Test fun reviewedEnvelopeAndMessageAreImmutableAcrossInputAndGetterMutation() {
        val envelopeInput = unsignedGolden.copyOf()
        val messageInput = message.copyOf()
        val reviewed = OwnerTransaction.SourceOnlyUnsigned(envelopeInput, messageInput,
            blockhash, owner, program, profile, "bank")
        envelopeInput.fill(0)
        messageInput.fill(0)
        reviewed.transactionBytes.fill(0)
        reviewed.messageBytes.fill(0)
        assertArrayEquals(unsignedGolden, reviewed.transactionBytes)
        assertArrayEquals(message, reviewed.messageBytes)
        assertArrayEquals(returnedGolden, inspect(reviewed, returnedGolden).transactionBytes)
        val changedReview = returnedGolden.copyOf()
        changedReview[69] = 99
        refuses { inspect(reviewed, changedReview) }
    }

    @Test fun sourceInstructionMutationAfterPreparationCannotRewriteReview() {
        val source = OwnerTransaction.canonicalBank(program, owner, address(2), address(3))
        val reviewed = OwnerTransaction.prepareSourceOnly(source, owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
        source.instruction.data.fill(0)
        assertArrayEquals(message, reviewed.messageBytes)
        assertArrayEquals(unsignedGolden, reviewed.transactionBytes)
        assertArrayEquals(returnedGolden, inspect(reviewed, returnedGolden).transactionBytes)
    }

    @Test fun returnedPayloadAndShapeAreImmutableAcrossWalletInputAndGetterMutation() {
        val reviewed = bank()
        val walletBytes = returnedGolden.copyOf()
        val walletPayloads = arrayOf(walletBytes)
        val shape = OwnerTransaction.inspectSourceOnlyWalletReturnShape(reviewed, walletPayloads)
        walletBytes.fill(0)
        walletPayloads[0] = byteArrayOf()
        shape.transactionBytes.fill(0)
        shape.signatureBytes.fill(0)
        assertArrayEquals(returnedGolden, shape.transactionBytes)
        assertArrayEquals(signature, shape.signatureBytes)
        assertArrayEquals(unsignedGolden, shape.reviewed.transactionBytes)
    }

    @Test fun inconsistentUnsignedReviewCannotBeConstructed() {
        fun construct(envelope: ByteArray, messageBytes: ByteArray) =
            OwnerTransaction.SourceOnlyUnsigned(envelope, messageBytes, blockhash, owner, program, profile, "bank")
        refuses { construct(returnedGolden, message) }
        refuses { construct(unsignedGolden, message + byteArrayOf(0)) }
        refuses { construct(byteArrayOf(1), byteArrayOf()) }
        refuses { construct(ByteArray(1233), message) }
        val twoSigners = message.copyOf().also { it[0] = 2 }
        refuses { construct(byteArrayOf(1) + ByteArray(64) + twoSigners, twoSigners) }
        val readonlyPayer = message.copyOf().also { it[1] = 1 }
        refuses { construct(byteArrayOf(1) + ByteArray(64) + readonlyPayer, readonlyPayer) }
    }

    @Test fun exact1232ByteReturnAllowedAnd1233Refused() {
        val source = OwnerTransaction.canonicalBank(program, owner, address(2), address(3))
        val limitSource = OwnerTransaction.SourceInstruction(profile, "bank",
            TransactionInstruction(source.instruction.programId, source.instruction.accounts, ByteArray(943)))
        val reviewed = OwnerTransaction.prepareSourceOnly(limitSource, owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
        val atLimit = byteArrayOf(1) + signature + reviewed.messageBytes
        assertEquals(1232, atLimit.size)
        assertArrayEquals(atLimit, inspect(reviewed, atLimit).transactionBytes)
        refuses { inspect(reviewed, atLimit + byteArrayOf(0)) }
    }

    private fun bank() = OwnerTransaction.prepareSourceOnly(
        OwnerTransaction.canonicalBank(program, owner, address(2), address(3)), owner, program, blockhash, TEST_COMPUTE_UNIT_LIMIT)
    private fun inspect(reviewed: OwnerTransaction.SourceOnlyUnsigned, bytes: ByteArray) =
        OwnerTransaction.inspectSourceOnlyWalletReturnShape(reviewed, arrayOf(bytes))
    private fun refuses(block: () -> Unit) { assertThrows(IllegalArgumentException::class.java) { block() } }
    private fun raw(value: Int) = ByteArray(32) { value.toByte() }
    private fun address(value: Int) = SolanaPublicKey(raw(value)).address
    private fun hex(value: String) = value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
