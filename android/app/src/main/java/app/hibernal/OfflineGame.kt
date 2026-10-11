package app.hibernal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.util.Log
import com.solana.publickey.SolanaPublicKey
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Debuggable builds only: made-up reads and wallet answers fed through the same native ABI as the chain, so the
// HUD can be built and debugged with no RPC, wallet or deployment. Nothing here is signed or sent.
//   adb shell am broadcast -p app.hibernal -a app.hibernal.OFFLINE --es scene newborn
// Scenes are Scene's names in lower case; `live` hands the app back to the chain.
object OfflineGame {
    private const val TAG = "HibernalOffline"
    const val ACTION = "app.hibernal.OFFLINE"
    private const val SECONDS_PER_DAY = 7200L
    private const val DAY = 10L
    private const val HBRN = 1_000_000L
    private const val STEP_MS = 1_500L
    private const val REFRESH_MS = 30_000L
    // rules/owner.ms OWNER_BANK_COOLDOWN_SECONDS (8 game hours) at SECONDS_PER_DAY.
    private const val BANK_COOLDOWN_MS = 8L * 3600 * SECONDS_PER_DAY / 86_400 * 1000
    // GameOwnerStore and WalletBridge's ABI values.
    private const val OWNER_UNSELECTED = 0
    private const val OWNER_REMEMBERED = 1
    private const val WALLET_DISCONNECTED = 0
    private const val WALLET_CONNECTING = 1
    private const val WALLET_CONNECTED = 2
    private val OWNER = ByteArray(32) { (it + 1).toByte() }

    enum class Scene { CONNECT, NO_TOKEN, SUMMON, NEWBORN, GROWN, DYING, DEAD, HEIR, UPDATING, FAILED }

    @Volatile var scene: Scene? = null
        private set
    val active: Boolean get() = scene != null

    private val scope = MainScope()
    private var script: Job? = null
    private var refresh: Job? = null
    private var pet = mutableMapOf<LivePetRead.Field, Long>()
    private var read: () -> Unit = {}
    private var sessionApproved = false
    private var bankedAtMillis = 0L
    private var label: (String?) -> Unit = {}
    private var registered = false

    fun attach(context: Context, show: (String?) -> Unit) {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        label = show
        show(scene?.name)
        // An Activity comes back many times in one process; the receiver is registered once.
        if (registered) return
        registered = true
        context.registerReceiver(object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val name = intent.getStringExtra("scene") ?: return Unit.also { Log.e(TAG, "No scene extra") }
                if (name == "live") return leave(context)
                val chosen = Scene.entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
                    ?: return Unit.also { Log.e(TAG, "Unknown scene $name; one of live, ${Scene.entries.joinToString { it.name.lowercase() }}") }
                enter(chosen)
            }
        }, IntentFilter(ACTION), Context.RECEIVER_EXPORTED)
    }

    private fun leave(context: Context) {
        if (!active) return
        script?.cancel()
        refresh?.cancel()
        scene = null
        label(null)
        VoidNative.setWalletState(WALLET_DISCONNECTED, "")
        VoidNative.setOwnerActionState(OwnerSigning.Outcome.IDLE.ordinal)
        GameOwnerStore.restore(context)
        Log.i(TAG, "Back to the chain")
    }

    fun enter(next: Scene) {
        script?.cancel()
        if (!active) GameSync.select(null)
        scene = next
        sessionApproved = false
        bankedAtMillis = 0L
        label(next.name)
        VoidNative.setOwnerActionState(OwnerSigning.Outcome.IDLE.ordinal)
        VoidNative.setCoachSeen(0)
        VoidNative.setDeathNoticeSeen(-1)
        if (next == Scene.CONNECT) {
            VoidNative.setWalletState(WALLET_DISCONNECTED, "")
            VoidNative.setGameOwner(OWNER_UNSELECTED, ByteArray(0))
            read = {}
        } else {
            VoidNative.setWalletState(WALLET_CONNECTED, SolanaPublicKey(OWNER).address)
            VoidNative.setGameOwner(OWNER_REMEMBERED, OWNER)
            read = when (next) {
                Scene.NO_TOKEN -> { { publish(2, "NO OWNER PET / NO TOKEN-2022 HOLDINGS", 0, 0, 0) } }
                Scene.SUMMON -> { { publish(2, "ADMISSION MEMBER MATCHED / READY TO SUMMON", 1, 1, 1) } }
                Scene.UPDATING -> { { publish(4, "Config is 304 bytes, the app reads 312") } }
                Scene.FAILED -> { { publish(5, "NETWORK") } }
                else -> { pet = petOf(next); { publishPet() } }
            }
        }
        read()
        if (refresh?.isActive != true) {
            // The HUD refuses a read older than LIVE_READ_MAX_AGE_SECONDS, as it would a stalled poller.
            refresh = scope.launch { while (true) { delay(REFRESH_MS); read() } }
        }
        Log.i(TAG, "Scene ${next.name.lowercase()}")
    }

    fun walletRequest(request: Int) {
        // WalletBridge CONNECT = 1, DISCONNECT = 2.
        script?.cancel()
        script = scope.launch {
            if (request == 1) {
                VoidNative.setWalletState(WALLET_CONNECTING, "")
                delay(STEP_MS)
                enter(Scene.SUMMON)
            } else {
                enter(Scene.CONNECT)
            }
        }
    }

    fun ownerAction(request: Int) {
        val decoded = OwnerSigning.request(request)
        script?.cancel()
        script = scope.launch {
            when (decoded.action) {
                OwnerSigning.OwnerAction.CLAIM -> {
                    signed()
                    pet = petOf(Scene.NEWBORN).apply { this[LivePetRead.Field.NAME_ID] = decoded.item.toLong() }
                    val placed = pet.toMutableMap()
                    pet.putAll(mapOf(LivePetRead.Field.LIFE to 0L, LivePetRead.Field.MEMBER to 0L,
                        LivePetRead.Field.BLOCK_STARTED to 0L, LivePetRead.Field.HARVEST to 0L))
                    scene = Scene.NEWBORN
                    read = { publishPet() }
                    read()
                    delay(4 * STEP_MS)
                    pet = placed
                    read()
                }
                OwnerSigning.OwnerAction.BANK -> {
                    val harvest = field(LivePetRead.Field.HARVEST)
                    if (harvest == 0L) return@launch outcome(OwnerSigning.Outcome.IDLE)
                    if (bankedAtMillis != 0L && System.currentTimeMillis() - bankedAtMillis < BANK_COOLDOWN_MS) {
                        return@launch outcome(OwnerSigning.Outcome.BANK_COOLING_DOWN)
                    }
                    outcome(OwnerSigning.Outcome.REQUESTED)
                    delay(STEP_MS)
                    if (!sessionApproved) {
                        outcome(OwnerSigning.Outcome.SESSION_APPROVAL)
                        delay(2 * STEP_MS)
                        sessionApproved = true
                    }
                    outcome(OwnerSigning.Outcome.SENT_PENDING)
                    delay(STEP_MS)
                    bankedAtMillis = System.currentTimeMillis()
                    pet[LivePetRead.Field.HARVEST] = harvest - harvest / 2
                    pet[LivePetRead.Field.BURROW] = field(LivePetRead.Field.BURROW) + harvest / 2
                    confirmed()
                }
                OwnerSigning.OwnerAction.CLAIM_REWARD -> {
                    signed()
                    pet[LivePetRead.Field.COMMITTED_GIFT_OWED] = field(LivePetRead.Field.GIFT_OWED)
                    pet[LivePetRead.Field.PAID_TOTAL] = field(LivePetRead.Field.GIFT_OWED)
                    confirmed()
                }
                OwnerSigning.OwnerAction.BUY -> {
                    signed()
                    pet[LivePetRead.Field.ITEMS_IN_TRANSIT] = field(LivePetRead.Field.ITEMS_IN_TRANSIT) + 1
                    confirmed()
                }
                OwnerSigning.OwnerAction.PAY_REBIRTH -> {
                    val generation = field(LivePetRead.Field.LINEAGE_GENERATION)
                    if (!OwnerOnboarding.rebirthPayable(field(LivePetRead.Field.LIFE) != 4L,
                            field(LivePetRead.Field.DIED_EPOCH).toBigInteger(), field(LivePetRead.Field.LEDGER_REBIRTHS),
                            generation.toInt())) return@launch outcome(OwnerSigning.Outcome.IDLE)
                    signed()
                    pet[LivePetRead.Field.LEDGER_REBIRTHS] = generation + 1
                    confirmed()
                    delay(4 * STEP_MS)
                    pet = petOf(Scene.HEIR)
                    scene = Scene.HEIR
                    read()
                }
                else -> outcome(OwnerSigning.Outcome.UNAVAILABLE)
            }
        }
    }

    private suspend fun signed() {
        outcome(OwnerSigning.Outcome.REQUESTED)
        delay(STEP_MS)
        outcome(OwnerSigning.Outcome.SENT_PENDING)
        delay(STEP_MS)
    }

    private fun confirmed() {
        outcome(OwnerSigning.Outcome.CONFIRMED_AWAITING_READ)
        read()
    }

    private fun outcome(outcome: OwnerSigning.Outcome) = VoidNative.setOwnerActionState(outcome.ordinal)

    private fun field(name: LivePetRead.Field) = pet[name] ?: 0L

    private fun publish(state: Int, detail: String, holdings: Int = -1, members: Int = -1, unclaimed: Int = -1) {
        VoidNative.setGameRead(VoidNative.gameOwnerRevision(), state, 1, 1, holdings, members, unclaimed, detail,
            LongArray(0), LongArray(0), LongArray(0))
    }

    private fun publishPet() {
        val values = LongArray(LivePetRead.Field.entries.size) { pet[LivePetRead.Field.entries[it]] ?: 0L }
        val seats = if (field(LivePetRead.Field.MEMBER) == 1L) seats() else LongArray(0)
        VoidNative.setGameRead(VoidNative.gameOwnerRevision(), 3, 1, 1, 1, 1, 0, "OFFLINE", values, seats, LongArray(0))
    }

    private fun petOf(scene: Scene): MutableMap<LivePetRead.Field, Long> {
        val now = System.currentTimeMillis() / 1000
        // A quarter into game day DAY, so the clock-driven lines have time on both sides.
        val genesis = now - DAY * SECONDS_PER_DAY - SECONDS_PER_DAY / 4
        val grown = scene != Scene.NEWBORN
        val pet = mutableMapOf(
            LivePetRead.Field.LIFE to 1L, LivePetRead.Field.DELEGATED to 1L, LivePetRead.Field.MEMBER to 1L,
            LivePetRead.Field.BLOCK_STARTED to 1L, LivePetRead.Field.BLOCK_EPOCH to DAY, LivePetRead.Field.WORLD_DAY to DAY,
            LivePetRead.Field.LEVEL to if (grown) 5L else 1L, LivePetRead.Field.XP to if (grown) 900L else 0L,
            LivePetRead.Field.HARVEST to 250 * HBRN, LivePetRead.Field.HEARTS to 5L, LivePetRead.Field.MAX_HEARTS to 5L,
            LivePetRead.Field.LAST_TICK_EPOCH to DAY, LivePetRead.Field.FORAGE to 12L, LivePetRead.Field.MIGHT to 10L,
            LivePetRead.Field.GRIT to 8L, LivePetRead.Field.NAME_ID to 7L,
            LivePetRead.Field.BORN_EPOCH to if (grown) 2L else DAY, LivePetRead.Field.CLAIMED_EPOCH to if (grown) 2L else DAY,
            LivePetRead.Field.GIFT_OWED to 10 * HBRN, LivePetRead.Field.COMMITTED_GIFT_OWED to 10 * HBRN,
            LivePetRead.Field.SKR_BALANCE to 500 * HBRN,
            LivePetRead.Field.WORLD_GENESIS_TIMESTAMP to genesis, LivePetRead.Field.WORLD_TOTAL_WORK_POWER to 8100L,
            LivePetRead.Field.WORLD_LIVING_PETS to 4L, LivePetRead.Field.WORLD_FLOOR_SLOTS to 10L,
            LivePetRead.Field.WORLD_SECONDS_PER_DAY to SECONDS_PER_DAY,
            LivePetRead.Field.CONFIG_HATCH_FEE_LAMPORTS to 20_000_000L,
        )
        when (scene) {
            Scene.GROWN -> pet[LivePetRead.Field.BURROW] = 120 * HBRN
            Scene.DYING -> pet.putAll(mapOf(LivePetRead.Field.LIFE to 3L, LivePetRead.Field.HEARTS to 0L,
                LivePetRead.Field.DIED_EPOCH to DAY))
            Scene.DEAD -> pet.putAll(mapOf(LivePetRead.Field.LIFE to 4L, LivePetRead.Field.HEARTS to 0L,
                LivePetRead.Field.DIED_EPOCH to DAY - 1))
            Scene.HEIR -> pet.putAll(mapOf(LivePetRead.Field.LIFE to 2L, LivePetRead.Field.LINEAGE_GENERATION to 1L,
                LivePetRead.Field.LEDGER_REBIRTHS to 1L, LivePetRead.Field.BORN_EPOCH to DAY,
                LivePetRead.Field.HARVEST to 0L))
            else -> {}
        }
        return pet
    }

    // Seat 0 is the owner's Pet; three living neighbours, one dead, the rest empty.
    private fun seats(): LongArray {
        val width = LivePetRead.SeatField.entries.size
        val seats = LongArray(LivePetRead.BLOCK_SEATS * width)
        fun put(seat: Int, field: LivePetRead.SeatField, value: Long) { seats[seat * width + field.ordinal] = value }
        for (seat in 0 until LivePetRead.BLOCK_SEATS) put(seat, LivePetRead.SeatField.GRUDGE_SLOT, 255)
        val kinds = listOf(LivePetRead.SeatKind.SELF, LivePetRead.SeatKind.LIVING, LivePetRead.SeatKind.LIVING,
            LivePetRead.SeatKind.LIVING, LivePetRead.SeatKind.DEAD)
        kinds.forEachIndexed { seat, kind ->
            val self = kind == LivePetRead.SeatKind.SELF
            put(seat, LivePetRead.SeatField.KIND, kind.ordinal.toLong())
            put(seat, LivePetRead.SeatField.LIFE, if (self) field(LivePetRead.Field.LIFE) else if (kind == LivePetRead.SeatKind.DEAD) 4 else 1)
            put(seat, LivePetRead.SeatField.LEVEL, if (self) field(LivePetRead.Field.LEVEL) else seat + 1L)
            put(seat, LivePetRead.SeatField.HEARTS, if (self) field(LivePetRead.Field.HEARTS) else if (kind == LivePetRead.SeatKind.DEAD) 0 else 4)
            put(seat, LivePetRead.SeatField.MAX_HEARTS, 5)
            put(seat, LivePetRead.SeatField.FORAGE, 10L + seat)
            put(seat, LivePetRead.SeatField.MIGHT, 8L + seat * 2)
            put(seat, LivePetRead.SeatField.GRIT, 9L + seat)
            put(seat, LivePetRead.SeatField.HARVEST, if (self) field(LivePetRead.Field.HARVEST) else seat * 40 * HBRN)
            put(seat, LivePetRead.SeatField.BURROW, if (self) field(LivePetRead.Field.BURROW) else seat * 15 * HBRN)
            put(seat, LivePetRead.SeatField.BORN_EPOCH, if (self) field(LivePetRead.Field.BORN_EPOCH) else 2)
            put(seat, LivePetRead.SeatField.LAST_TICK_EPOCH, DAY)
            put(seat, LivePetRead.SeatField.FIGHT_DAY, DAY)
            put(seat, LivePetRead.SeatField.PERSONA, seat % 3L)
            put(seat, LivePetRead.SeatField.REGION, seat % 3L)
            put(seat, LivePetRead.SeatField.NAME_ID, if (self) field(LivePetRead.Field.NAME_ID) else seat * 31L)
        }
        return seats
    }
}
