package app.hibernal

import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class OwnerShopTest {
    private val program = SolanaPublicKey(ByteArray(32) { 3 })
    private val mint = SolanaPublicKey(ByteArray(32) { 4 })
    private val owner = SolanaPublicKey(ByteArray(32) { 5 }).address
    private val skrMint = SolanaPublicKey(ByteArray(32) { 6 }).address
    private val tokenProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

    private fun ledger(bought: List<Int>, mintBytes: ByteArray = mint.bytes): SolanaRpc.Account {
        val data = ByteArray(OwnerShop.LEDGER_BYTES)
        byteArrayOf(0x2b, 0x29, 0x15, 0xd5.toByte(), 0xb4.toByte(), 0xb0.toByte(), 0x5f, 0x20).copyInto(data)
        mintBytes.copyInto(data, 8)
        bought.forEachIndexed { index, value -> for (byte in 0 until 4) data[40 + index * 4 + byte] = (value ushr (8 * byte)).toByte() }
        return SolanaRpc.Account(program.address, BigInteger.ONE, false, data)
    }

    private fun tokenAccount(amount: Long, holder: String = owner): SolanaRpc.Account {
        val data = ByteArray(165)
        SolanaPublicKey.from(skrMint).bytes.copyInto(data)
        SolanaPublicKey.from(holder).bytes.copyInto(data, 32)
        for (byte in 0 until 8) data[64 + byte] = (amount ushr (8 * byte)).toByte()
        return SolanaRpc.Account(tokenProgram, BigInteger.ONE, false, data)
    }

    @Test fun ledgerCountsWhatIsBoughtButNotLoaded() {
        val bought = OwnerShop.bought(ledger(listOf(2, 0, 0, 1, 0, 0, 70000)), mint, program)
        assertEquals(listOf(2L, 0, 0, 1, 0, 0, 70000), bought)
        assertEquals(1L, OwnerShop.inTransit(bought, listOf(1, 0, 0, 1, 0, 0, 70000)))
        assertEquals(List(7) { 0L }, OwnerShop.bought(null, mint, program))
    }

    @Test fun foreignLedgerOrOverloadedPetIsRefused() {
        assertThrows(LivePetRead.UnsupportedLayout::class.java) {
            OwnerShop.bought(ledger(List(7) { 0 }, ByteArray(32) { 9 }), mint, program)
        }
        assertThrows(LivePetRead.UnsupportedLayout::class.java) {
            OwnerShop.inTransit(List(7) { 0L }, listOf(1L, 0, 0, 0, 0, 0, 0))
        }
    }

    @Test fun balanceReadsOnlyTheOwnersSkrAccount() {
        assertEquals(BigInteger.valueOf(200_000_000), OwnerShop.balance(tokenAccount(200_000_000), owner, skrMint, tokenProgram))
        assertEquals(BigInteger.ZERO, OwnerShop.balance(null, owner, skrMint, tokenProgram))
        assertThrows(LivePetRead.UnsupportedLayout::class.java) {
            OwnerShop.balance(tokenAccount(1, skrMint), owner, skrMint, tokenProgram)
        }
    }

    @Test fun cartCodeNamesEachGoodInOrderWithDuplicates() {
        assertEquals(listOf(OwnerShop.Good(0, 0), OwnerShop.Good(0, 0), OwnerShop.Good(2, 0)), OwnerShop.cart(1 or (1 shl 4) or (7 shl 8)))
        assertEquals(listOf(OwnerShop.Good(1, 2)), OwnerShop.cart(6))
        assertThrows(IllegalArgumentException::class.java) { OwnerShop.cart(0) }
        assertThrows(IllegalArgumentException::class.java) { OwnerShop.cart(1 or (1 shl 4) or (1 shl 8) or (1 shl 12)) }
        assertThrows(IllegalArgumentException::class.java) { OwnerShop.cart(1 shl 4) }
        assertThrows(IllegalArgumentException::class.java) { OwnerShop.cart(13) }
    }

    @Test fun buyIsOneInstructionPerGoodIntoTheTreasury() = runBlocking {
        val config = SolanaRpc.Account(program.address, BigInteger.ONE, false, ByteArray(304).also {
            SolanaPublicKey.from(skrMint).bytes.copyInto(it, 176)
            ByteArray(32) { 7 }.copyInto(it, 208)
        })
        val pet = SolanaPublicKey(ByteArray(32) { 8 }).address
        val calls = OwnerShop.buy(owner, pet, mint.address, program.address, SolanaPublicKey(ByteArray(32) { 2 }).address,
            config, tokenProgram, OwnerShop.cart(1 or (4 shl 4)))
        assertEquals(2, calls.size)
        assertEquals(OwnerShop.ledgerAddress(program, mint), calls[0].instruction.accounts[3].publicKey.base58())
        assertEquals(SolanaPublicKey(ByteArray(32) { 7 }).address, calls[0].instruction.accounts[6].publicKey.base58())
        assertEquals(OwnerReward.associated(owner, skrMint, tokenProgram), calls[1].instruction.accounts[5].publicKey.base58())
    }
}
