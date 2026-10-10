package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger

object TokenAdmission {
    fun heldMint(entry: SolanaRpc.KeyedAccount, selectedOwner: String): String? {
        key(entry.publicKey, "token account key")
        val owner = key(selectedOwner, "selected owner")
        val data = entry.account.data
        layout(entry.account, 165, 2)
        options(data, 72, 109, 129)
        check(data[108].toInt() in 1..2, "token state must be initialized or frozen")
        check(data.copyOfRange(32, 64).contentEquals(owner), "token owner differs from selected owner")
        val mint = SolanaPublicKey(data.copyOfRange(0, 32)).address
        return if (unsigned(data, 64) == BigInteger.ONE) mint else null
    }

    fun memberNumber(mintKey: String, account: SolanaRpc.Account, admissionGroup: String): BigInteger? {
        val mint = key(mintKey, "mint key")
        val group = key(admissionGroup, "admission group")
        val data = account.data
        val extensions = layout(account, 82, 1)
        options(data, 0, 46)
        check(data[45].toInt() == 1, "mint initialized flag must be 1")
        val pointer = extensions[22]
        val member = extensions[23]
        if (pointer != null) check(pointer.last - pointer.first + 1 == 64, "GroupMemberPointer length must be 64")
        if (member != null) check(member.last - member.first + 1 == 72, "TokenGroupMember length must be 72")
        if (pointer == null || member == null) return null
        val address = data.copyOfRange(pointer.first + 32, pointer.first + 64)
        if (address.all { it == 0.toByte() } || !address.contentEquals(mint)) return null
        if (!data.copyOfRange(member.first, member.first + 32).contentEquals(mint)) return null
        if (!data.copyOfRange(member.first + 32, member.first + 64).contentEquals(group)) return null
        return unsigned(data, member.first + 64)
    }

    private fun layout(account: SolanaRpc.Account, base: Int, type: Int): Map<Int, IntRange> {
        check(account.owner == SolanaRpc.TOKEN_2022, "account owner must be Token-2022")
        check(!account.executable, "token account must not be executable")
        val data = account.data
        check(data.size <= SolanaRpc.MAX_BODY_BYTES, "token data exceeds RPC body bound")
        check(data.size != 355, "multisig length 355 is not a token or mint layout")
        if (data.size == base) return emptyMap()
        check(data.size >= 166, "invalid token base or extension length")
        if (type == 1) check((82 until 165).all { data[it] == 0.toByte() }, "mint extension padding must be zero")
        check(data[165].toInt() == type, "wrong extension account type: expected $type")
        val entries = mutableMapOf<Int, IntRange>()
        var offset = 166
        while (offset < data.size) {
            if (data.size - offset < 4 || u16(data, offset) == 0) {
                check((offset until data.size).all { data[it] == 0.toByte() }, "nonzero TLV tail padding or truncated header")
                break
            }
            val kind = u16(data, offset)
            val length = u16(data, offset + 2)
            check(kind !in entries, "duplicate TLV extension type $kind")
            check(length <= data.size - offset - 4, "truncated TLV extension type $kind")
            entries[kind] = (offset + 4) until (offset + 4 + length)
            offset += 4 + length
        }
        return entries
    }

    private fun options(data: ByteArray, vararg offsets: Int) {
        for (offset in offsets) {
            check(data[offset].toInt() in 0..1 && (offset + 1..offset + 3).all { data[it] == 0.toByte() },
                "COption flag at $offset must be uint32 0 or 1")
        }
    }

    private fun unsigned(data: ByteArray, offset: Int) = BigInteger(1, data.copyOfRange(offset, offset + 8).reversedArray())
    private fun u16(data: ByteArray, offset: Int) = (data[offset].toInt() and 255) or ((data[offset + 1].toInt() and 255) shl 8)
    private fun key(text: String, field: String): ByteArray {
        check(text.length in 32..44, "$field must be canonical public key")
        try {
            val key = SolanaPublicKey.from(text)
            check(key.bytes.size == 32 && key.address == text, "$field must be canonical 32-byte public key")
            return key.bytes
        } catch (error: Exception) {
            if (error is SolanaRpc.Failure) throw error
            throw SolanaRpc.Failure("Token admission: invalid $field", error)
        }
    }
    private fun check(valid: Boolean, message: String) {
        if (!valid) throw SolanaRpc.Failure("Token admission: $message")
    }
}
