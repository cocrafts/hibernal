package app.hibernal

import com.solana.publickey.ProgramDerivedAddress
import com.solana.publickey.SolanaPublicKey
import java.math.BigInteger

// Buy pays SKR on L1 and counts the purchase in the Pet's Ledger; Load on the ER moves it into
// owner slots 5 and 6 (program/shop.ms), so a purchase is in transit while bought exceeds loaded.
object OwnerShop {
    const val LEDGER_BYTES = 76
    const val OWNER_ITEM_KINDS = 7
    private const val SHOP_ITEMS = 4
    const val CART_GOODS = 3
    private val LEDGER_TAG = byteArrayOf(0x2b, 0x29, 0x15, 0xd5.toByte(), 0xb4.toByte(), 0xb0.toByte(), 0x5f, 0x20)

    data class Holdings(val skrBalance: BigInteger, val inTransit: Long, val rebirths: Long, val hatchFeeLamports: Long)
    data class Good(val item: Int, val tier: Int)

    // Config after its 8-byte tag: skrMint at 176, treasury at 208 (program/layout.ms Config).
    fun skrMint(config: SolanaRpc.Account) = SolanaPublicKey(config.data.copyOfRange(176, 208)).address
    fun treasury(config: SolanaRpc.Account) = SolanaPublicKey(config.data.copyOfRange(208, 240)).address
    fun hatchFeeLamports(config: SolanaRpc.Account): Long =
        (0 until 8).fold(0L) { value, index -> value or ((config.data[304 + index].toLong() and 0xff) shl (8 * index)) }
            .also { if (it < 0) throw LivePetRead.UnsupportedLayout("HATCH FEE PAST INT64") }

    suspend fun ledgerAddress(program: SolanaPublicKey, mint: SolanaPublicKey): String =
        ProgramDerivedAddress.find(listOf("ledger".toByteArray(), mint.bytes), program).getOrThrow().address

    // Ledger.bought per owner item kind; absent before the first Buy.
    fun bought(account: SolanaRpc.Account?, mint: SolanaPublicKey, program: SolanaPublicKey): List<Long> {
        val data = ledger(account, mint, program) ?: return List(OWNER_ITEM_KINDS) { 0L }
        return List(OWNER_ITEM_KINDS) { unsigned32(data, 40 + it * 4) }
    }

    // Ledger.rebirths: hatch fees paid for this mint's heirs; absent before the first payment.
    fun rebirths(account: SolanaRpc.Account?, mint: SolanaPublicKey, program: SolanaPublicKey): Long =
        ledger(account, mint, program)?.let { unsigned32(it, 72) } ?: 0L

    private fun ledger(account: SolanaRpc.Account?, mint: SolanaPublicKey, program: SolanaPublicKey): ByteArray? {
        if (account == null) return null
        if (account.owner != program.address || account.executable || account.data.size != LEDGER_BYTES ||
            !account.data.copyOfRange(0, 8).contentEquals(LEDGER_TAG) || !account.data.copyOfRange(8, 40).contentEquals(mint.bytes)) {
            throw LivePetRead.UnsupportedLayout("LEDGER ACCOUNT NOT ACCEPTED")
        }
        return account.data
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

    // packedCart in native/hud/ownerGoods.ms: 4 bits per good, item * 3 + tier + 1, in cart order.
    fun cart(code: Int): List<Good> {
        require(code > 0 && code ushr (4 * CART_GOODS) == 0) { "Shop cart $code is empty or holds more than $CART_GOODS goods" }
        val values = (0 until CART_GOODS).map { (code ushr (4 * it)) and 15 }.dropLastWhile { it == 0 }
        require(values.none { it == 0 || it > SHOP_ITEMS * 3 }) { "Shop cart $code has a gap or an unknown good" }
        return values.map { Good((it - 1) / 3, (it - 1) % 3) }
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
