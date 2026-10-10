package app.hibernal

import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger

// Buy pays SKR on L1 and counts the purchase in the Pet's Ledger; Load on the ER moves it into
// owner slots 5 and 6 (program/shop.ms), so a purchase is in transit while bought exceeds loaded.
object OwnerShop {
    const val LEDGER_BYTES = 72
    const val OWNER_ITEM_KINDS = 7
    private const val SHOP_ITEMS = 4
    private val LEDGER_TAG = byteArrayOf(0x2b, 0x29, 0x15, 0xd5.toByte(), 0xb4.toByte(), 0xb0.toByte(), 0x5f, 0x20)

    data class Holdings(val skrBalance: BigInteger, val inTransit: Long)
    data class Good(val item: Int, val tier: Int)

    // Config after its 8-byte tag: skrMint at 176, treasury at 208 (program/layout.ms Config).
    fun skrMint(config: SolanaRpc.Account) = SolanaPublicKey(config.data.copyOfRange(176, 208)).address
    fun treasury(config: SolanaRpc.Account) = SolanaPublicKey(config.data.copyOfRange(208, 240)).address

    suspend fun ledgerAddress(program: SolanaPublicKey, mint: SolanaPublicKey): String =
        ProgramDerivedAddress.find(listOf("ledger".toByteArray(), mint.bytes), program).getOrThrow().address

    // Ledger.bought per owner item kind; absent before the first Buy.
    fun bought(account: SolanaRpc.Account?, mint: SolanaPublicKey, program: SolanaPublicKey): List<Long> {
        if (account == null) return List(OWNER_ITEM_KINDS) { 0L }
        if (account.owner != program.address || account.executable || account.data.size != LEDGER_BYTES ||
            !account.data.copyOfRange(0, 8).contentEquals(LEDGER_TAG) || !account.data.copyOfRange(8, 40).contentEquals(mint.bytes)) {
            throw LivePetRead.UnsupportedLayout("LEDGER ACCOUNT NOT ACCEPTED")
        }
        return List(OWNER_ITEM_KINDS) { unsigned32(account.data, 40 + it * 4) }
    }

    fun inTransit(bought: List<Long>, loaded: List<Long>): Long {
        if (bought.size != OWNER_ITEM_KINDS || loaded.size != OWNER_ITEM_KINDS || bought.zip(loaded).any { (b, l) -> l > b }) {
            throw LivePetRead.UnsupportedLayout("PET LOADED MORE THAN ITS LEDGER BOUGHT")
        }
        return bought.zip(loaded).sumOf { (b, l) -> b - l }
    }

    // The owner's SKR token account; absent reads as an empty balance.
    fun balance(account: SolanaRpc.Account?, owner: String, skrMint: String, tokenProgram: String): BigInteger {
        if (account == null) return BigInteger.ZERO
        if (account.owner != tokenProgram || account.data.size < 72 ||
            !account.data.copyOfRange(0, 32).contentEquals(SolanaPublicKey.from(skrMint).bytes) ||
            !account.data.copyOfRange(32, 64).contentEquals(SolanaPublicKey.from(owner).bytes)) {
            throw LivePetRead.UnsupportedLayout("SKR TOKEN ACCOUNT NOT ACCEPTED")
        }
        return BigInteger(1, account.data.copyOfRange(64, 72).reversedArray())
    }

    // The cart byte holds two bits per shop item (Food, Growth, Insurance, Skin): its tier + 1, 0 when absent.
    fun cart(code: Int): List<Good> {
        require(code in 1..255) { "Shop cart $code is empty or not a byte" }
        return (0 until SHOP_ITEMS).mapNotNull { item ->
            val tier = (code ushr (item * 2)) and 3
            if (tier == 0) null else Good(item, tier - 1)
        }
    }

    suspend fun buy(owner: String, petAddress: String, mint: String, program: String, configAddress: String,
        config: SolanaRpc.Account, skrTokenProgram: String, goods: List<Good>): List<OwnerTransaction.SourceInstruction> {
        val skrMint = skrMint(config)
        val source = OwnerReward.associated(owner, skrMint, skrTokenProgram)
        val ledger = ledgerAddress(SolanaPublicKey.from(program), SolanaPublicKey.from(mint))
        return goods.map {
            OwnerTransaction.canonicalBuy(program, owner, configAddress, petAddress, ledger, skrMint, source,
                treasury(config), skrTokenProgram, OwnerTransaction.SYSTEM_PROGRAM, it.item, it.tier)
        }
    }

    private fun unsigned32(data: ByteArray, at: Int): Long =
        (0 until 4).fold(0L) { value, index -> value or ((data[at + index].toLong() and 0xff) shl (8 * index)) }
}
