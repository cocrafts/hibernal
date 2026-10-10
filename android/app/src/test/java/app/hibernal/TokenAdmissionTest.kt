package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import org.junit.Assert.*
import org.junit.Test

class TokenAdmissionTest {
    private val mint = raw(7)
    private val owner = raw(8)
    private val group = raw(9)
    private val maximum = BigInteger("18446744073709551615")
    private fun raw(value: Int) = ByteArray(32) { value.toByte() }
    private fun address(bytes: ByteArray) = SolanaPublicKey(bytes).address
    private fun account(data: ByteArray) = SolanaRpc.Account(SolanaRpc.TOKEN_2022, BigInteger.ZERO, false, data)
    private fun entry(data: ByteArray) = SolanaRpc.KeyedAccount(address(raw(10)), account(data))
    private fun put(data: ByteArray, offset: Int, bytes: ByteArray) { bytes.copyInto(data, offset) }
    private fun putNumber(data: ByteArray, offset: Int, value: BigInteger) {
        var remaining = value
        repeat(8) { data[offset + it] = remaining.toByte(); remaining = remaining.shiftRight(8) }
    }
    private fun token(amount: BigInteger = BigInteger.ONE, state: Int = 1) = ByteArray(165).also {
        put(it, 0, mint); put(it, 32, owner); putNumber(it, 64, amount); it[108] = state.toByte()
    }
    private fun baseMint() = ByteArray(82).also { it[45] = 1 }
    private fun pointer(memberAddress: ByteArray = mint) = ByteArray(64).also { put(it, 32, memberAddress) }
    private fun member(number: BigInteger = BigInteger.ONE, memberMint: ByteArray = mint, memberGroup: ByteArray = group) = ByteArray(72).also {
        put(it, 0, memberMint); put(it, 32, memberGroup); putNumber(it, 64, number)
    }
    private fun tlv(kind: Int, value: ByteArray) = ByteArray(4 + value.size).also {
        it[0] = kind.toByte(); it[1] = (kind shr 8).toByte()
        it[2] = value.size.toByte(); it[3] = (value.size shr 8).toByte(); put(it, 4, value)
    }
    private fun extended(base: ByteArray, type: Int, vararg entries: ByteArray): ByteArray {
        val header = base.copyOf(166).also { it[165] = type.toByte() }
        return entries.fold(header) { result, bytes -> result + bytes }
    }
    private fun admitted(number: BigInteger = BigInteger.ONE) = extended(baseMint(), 1, tlv(22, pointer()), tlv(23, member(number)))
    private fun held(data: ByteArray) = TokenAdmission.heldMint(entry(data), address(owner))
    private fun number(data: ByteArray) = TokenAdmission.memberNumber(address(mint), account(data), address(group))
    private fun fails(fragment: String, action: () -> Unit) {
        val error = assertThrows(SolanaRpc.Failure::class.java) { action() }
        assertTrue(error.message, error.message!!.contains(fragment))
    }

    @Test fun heldInitializedAndFrozen() {
        assertEquals(address(mint), held(token()))
        assertEquals(address(mint), held(token(state = 2)))
        assertEquals(address(mint), held(extended(token(), 2, tlv(7, byteArrayOf()))))
    }
    @Test fun amountIsExactUnsigned64() {
        for (value in listOf(BigInteger.ZERO, BigInteger.TWO, BigInteger.ONE.shiftLeft(63), maximum)) assertNull(held(token(value)))
        assertEquals(address(mint), held(token(BigInteger.ONE)))
    }
    @Test fun serverOwnerFilterNotTrusted() {
        fails("selected owner") { TokenAdmission.heldMint(entry(token()), address(raw(11))) }
    }
    @Test fun tokenMetadataAndKeys() {
        fails("owner must") { TokenAdmission.heldMint(entry(token()).copy(account = account(token()).copy(owner = address(owner))), address(owner)) }
        fails("executable") { TokenAdmission.heldMint(entry(token()).copy(account = account(token()).copy(executable = true)), address(owner)) }
        fails("selected owner") { TokenAdmission.heldMint(entry(token()), "bad") }
        fails("token account key") { TokenAdmission.heldMint(entry(token()).copy(publicKey = "bad"), address(owner)) }
    }
    @Test fun tokenStatesStrict() {
        for (state in listOf(0, 3, 255)) fails("state") { held(token(state = state)) }
    }
    @Test fun tokenOptionsStrictFullUint32() {
        for (offset in listOf(72, 109, 129)) {
            assertEquals(address(mint), held(token().also { it[offset] = 1 }))
            fails("COption") { held(token().also { it[offset] = 2 }) }
            for (high in 1..3) fails("COption") { held(token().also { it[offset + high] = 2 }) }
        }
    }
    @Test fun tokenLengthAndTypeStrict() {
        for (length in listOf(0, 82, 164, 355)) fails(if (length == 355) "multisig" else "length") { held(token().copyOf(length)) }
        fails("type") { held(extended(token(), 1)) }
        assertEquals(address(mint), held(extended(token(), 2)))
    }
    @Test fun memberNumberZeroAndMaxPreserved() {
        for (value in listOf(BigInteger.ZERO, BigInteger.ONE, maximum)) assertEquals(value, number(admitted(value)))
    }
    @Test fun noExtraSupplyDecimalsAuthorityRules() {
        val data = admitted().also { it[44] = 9; putNumber(it, 36, maximum) }
        assertEquals(BigInteger.ONE, number(data))
        for (offset in listOf(0, 46)) assertEquals(BigInteger.ONE, number(data.copyOf().also { it[offset] = 1 }))
    }
    @Test fun mintOptionsStrictFullUint32() {
        for (offset in listOf(0, 46)) {
            fails("COption") { number(admitted().also { it[offset] = 2 }) }
            for (high in 1..3) fails("COption") { number(admitted().also { it[offset + high] = 2 }) }
        }
    }
    @Test fun initializedFlagIsExactBoolean() {
        for (flag in listOf(0, 2, 255)) fails("initialized flag") { number(admitted().also { it[45] = flag.toByte() }) }
    }
    @Test fun mintMetadataAndKeys() {
        fails("owner must") { TokenAdmission.memberNumber(address(mint), account(admitted()).copy(owner = address(owner)), address(group)) }
        fails("executable") { TokenAdmission.memberNumber(address(mint), account(admitted()).copy(executable = true), address(group)) }
        fails("mint key") { TokenAdmission.memberNumber("bad", account(admitted()), address(group)) }
        fails("admission group") { TokenAdmission.memberNumber(address(mint), account(admitted()), "bad") }
    }
    @Test fun mintLengthTypeAndPaddingStrict() {
        for (length in listOf(0, 81, 83, 165, 355)) fails(if (length == 355) "multisig" else "length") { number(baseMint().copyOf(length)) }
        fails("type") { number(extended(baseMint(), 2)) }
        for (offset in listOf(82, 100, 164)) fails("padding") { number(admitted().also { it[offset] = 1 }) }
        assertNull(number(extended(baseMint(), 1)))
        assertNull(number(baseMint()))
    }
    @Test fun missingRequiredExtensionsNotAdmitted() {
        assertNull(number(extended(baseMint(), 1, tlv(22, pointer()))))
        assertNull(number(extended(baseMint(), 1, tlv(23, member()))))
    }
    @Test fun pointerSelfAndZeroChecked() {
        for (key in listOf(ByteArray(32), raw(11))) assertNull(number(extended(baseMint(), 1, tlv(22, pointer(key)), tlv(23, member()))))
        assertEquals(BigInteger.ONE, number(admitted()))
    }
    @Test fun memberMintAndGroupChecked() {
        assertNull(number(extended(baseMint(), 1, tlv(22, pointer()), tlv(23, member(memberMint = raw(11))))))
        assertNull(number(extended(baseMint(), 1, tlv(22, pointer()), tlv(23, member(memberGroup = raw(11))))))
    }
    @Test fun requiredLengthsStrictEvenWhenOtherMissing() {
        for (length in listOf(0, 63, 65)) fails("GroupMemberPointer length") { number(extended(baseMint(), 1, tlv(22, ByteArray(length)))) }
        for (length in listOf(0, 71, 73)) fails("TokenGroupMember length") { number(extended(baseMint(), 1, tlv(23, ByteArray(length)))) }
    }
    @Test fun duplicateTypesRefusedIncludingOpaque() {
        fails("duplicate") { number(admitted() + tlv(22, pointer())) }
        fails("duplicate") { number(admitted() + tlv(500, byteArrayOf()) + tlv(500, byteArrayOf())) }
        fails("duplicate") { held(extended(token(), 2, tlv(7, byteArrayOf()), tlv(7, byteArrayOf()))) }
    }
    @Test fun truncatedTlvRefusedEvenAfterRequiredEntries() {
        fails("truncated") { number(admitted() + byteArrayOf(99, 0, 5, 0, 1)) }
        for (tail in listOf(byteArrayOf(1), byteArrayOf(1, 0), byteArrayOf(1, 0, 0))) fails("truncated") { number(admitted() + tail) }
        fails("truncated") { held(extended(token(), 2, byteArrayOf(7, 0, 2, 0, 1))) }
    }
    @Test fun unrelatedExtensionsOpaqueAndOrderIndependent() {
        val data = extended(baseMint(), 1, tlv(65535, byteArrayOf(2, 3)), tlv(23, member()), tlv(18, ByteArray(64)), tlv(22, pointer()))
        assertEquals(BigInteger.ONE, number(data))
        assertEquals(address(mint), held(extended(token(), 2, tlv(500, byteArrayOf(1, 2)))))
    }
    @Test fun allZeroTailIncludingShortPaddingAccepted() {
        for (length in listOf(1, 2, 3, 4, 32)) {
            assertEquals(BigInteger.ONE, number(admitted() + ByteArray(length)))
            assertEquals(address(mint), held(extended(token(), 2) + ByteArray(length)))
        }
        fails("tail padding") { number(admitted() + byteArrayOf(0, 0, 0, 0, 1)) }
        fails("tail padding") { number(admitted() + byteArrayOf(0, 0, 1, 0, 0)) }
    }
    @Test fun bodyBoundEnforced() {
        fails("bound") { number(ByteArray(SolanaRpc.MAX_BODY_BYTES + 1)) }
        fails("bound") { held(ByteArray(SolanaRpc.MAX_BODY_BYTES + 1)) }
    }
}
