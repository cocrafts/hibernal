package app.hibernal

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.util.AtomicFile
import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileNotFoundException
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

// Wakes now and then, also while the phone is locked, reads the owner's Pet once and tells what
// changed since the last look. Everything happens on the phone: no server sends these.
object PetWatch {
    private const val TAG = "HibernalWatch"
    internal const val INTERVAL_MS = 30 * 60_000L
    private const val READ_TIMEOUT_MS = 45_000L
    private const val CHANNEL = "pet"
    private const val NOTIFICATION_ID = 1
    private const val HBRN_UNIT = 1_000_000L
    // GameReadState.PetFound in native/host/host.ms.
    private const val PET_FOUND = 3
    private val INSURANCE_USED = SourcePetRead.Insurance.Used.ordinal.toLong()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // What the last look saw; a look only compares Pets of the same owner and lineage.
    internal data class Seen(
        val owner: List<Byte>,
        val generation: Long,
        val life: Long,
        val hearts: Long,
        val maxHearts: Long,
        val level: Long,
        val claimable: Long,
        val inTransit: Long,
        val lastFightEpoch: Long,
        val insurance: Long,
    )

    internal data class Fight(val epoch: Long, val attackerSeat: Long, val defenderSeat: Long, val attackerWon: Boolean, val loot: Long)

    fun schedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + INTERVAL_MS, wake(context))
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(wake(context))
    }

    private fun wake(context: Context): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, PetWatchReceiver::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    internal fun look(context: Context, finish: () -> Unit) {
        scope.launch {
            try {
                val owner = GameOwnerStore.owner(context) ?: return@launch
                check(context, owner)
                schedule(context)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                Log.w(TAG, "Look failed: ${error.javaClass.simpleName}")
                schedule(context)
            } finally {
                finish()
            }
        }
    }

    private suspend fun check(context: Context, owner: ByteArray) {
        var read: GameSync.Publication? = null
        withTimeout(READ_TIMEOUT_MS) {
            GameSync.Poll(owner, SolanaRpc(SolanaRpc.DEVNET), SolanaRpc(SolanaRpc.DEVNET_ER),
                SystemClock::elapsedRealtime, Random.Default, shown = true) { read = it; true }.cycle()
        }
        val now = read?.takeIf { it.state == PET_FOUND }?.let { seenOf(owner, it) } ?: return
        val store = store(context)
        val before = load(store)
        save(store, now)
        Log.i(TAG, "Looked: hearts=${now.hearts} level=${now.level} fightEpoch=${now.lastFightEpoch}")
        if (before == null) return
        val lines = news(before, now, fightsOf(read!!), mySeat(read!!))
        if (lines.isNotEmpty()) notify(context, lines)
    }

    internal fun seenOf(owner: ByteArray, read: GameSync.Publication): Seen {
        fun field(name: LivePetRead.Field) = read.pet[name.ordinal]
        val fights = fightsOf(read)
        return Seen(owner.toList(), field(LivePetRead.Field.LINEAGE_GENERATION), field(LivePetRead.Field.LIFE),
            field(LivePetRead.Field.HEARTS), field(LivePetRead.Field.MAX_HEARTS), field(LivePetRead.Field.LEVEL),
            field(LivePetRead.Field.COMMITTED_GIFT_OWED) - field(LivePetRead.Field.PAID_TOTAL),
            field(LivePetRead.Field.ITEMS_IN_TRANSIT), fights.maxOfOrNull { it.epoch } ?: 0L, field(LivePetRead.Field.INSURANCE))
    }

    internal fun fightsOf(read: GameSync.Publication): List<Fight> =
        read.fights.chunked(LivePetRead.FightField.entries.size).map {
            Fight(it[LivePetRead.FightField.EPOCH.ordinal], it[LivePetRead.FightField.ATTACKER_SEAT.ordinal],
                it[LivePetRead.FightField.DEFENDER_SEAT.ordinal], it[LivePetRead.FightField.ATTACKER_WON.ordinal] != 0L,
                it[LivePetRead.FightField.LOOT.ordinal])
        }

    internal fun mySeat(read: GameSync.Publication): Long = read.seats.chunked(LivePetRead.SeatField.entries.size)
        .indexOfFirst { it[LivePetRead.SeatField.KIND.ordinal] == LivePetRead.SeatKind.SELF.ordinal.toLong() }.toLong()

    private fun dead(seen: Seen) = seen.life >= SourcePetLifecycle.Fact.INACTIVE_WITHOUT_DEATH_RECORD.ordinal

    // Fights land when the Block turns its day, all of a day's at once, so a later epoch is a new fight.
    internal fun news(before: Seen, now: Seen, fights: List<Fight>, seat: Long): List<String> {
        if (before.owner != now.owner || now.generation < before.generation) return emptyList()
        // Only old age leaves an heir (rules/life.ms agedOut); it hatches when the chain records the death at dusk.
        if (now.generation > before.generation) {
            return listOfNotNull("YOUR PET DIED OF OLD AGE".takeIf { !dead(before) }, "ITS HEIR HAS HATCHED")
        }
        val lines = mutableListOf<String>()
        if (dead(now) && !dead(before)) {
            lines += if (now.hearts > 0) "YOUR PET DIED OF OLD AGE. ITS HEIR IS COMING" else "YOUR PET IS GONE"
        }
        if (now.insurance == INSURANCE_USED && before.insurance != INSURANCE_USED) lines += "INSURANCE SAVED YOUR PET"
        fights.filter { it.epoch > before.lastFightEpoch && it.defenderSeat == seat }.forEach {
            val slot = it.attackerSeat + 1
            lines += if (it.attackerWon) "ROBBED BY SLOT $slot: -${hbrn(it.loot)} HBRN" else "HELD OFF SLOT $slot"
        }
        if (now.hearts < before.hearts) lines += "LOST ${before.hearts - now.hearts} HEARTS: ${now.hearts}/${now.maxHearts} LEFT"
        if (now.level > before.level) lines += "REACHED LEVEL ${now.level}"
        if (now.claimable > before.claimable) lines += "A GIFT IS READY TO CLAIM"
        if (now.inTransit < before.inTransit) lines += "YOUR ORDER HAS ARRIVED"
        return lines
    }

    private fun hbrn(baseUnits: Long): String = "%d.%02d".format(baseUnits / HBRN_UNIT, baseUnits % HBRN_UNIT / (HBRN_UNIT / 100))

    private fun notify(context: Context, lines: List<String>) {
        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            Log.i(TAG, "Notifications not allowed; ${lines.size} lines kept quiet")
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Your Pet", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val text = lines.joinToString("\n")
        manager.notify(NOTIFICATION_ID, android.app.Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(lines.first())
            .setContentText(lines.drop(1).joinToString(" · ").ifEmpty { null })
            .setStyle(android.app.Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build())
    }

    private fun store(context: Context) = AtomicFile(File(context.noBackupFilesDir, "petWatch"))

    private fun load(file: AtomicFile): Seen? = try {
        file.openRead().use { stream ->
            DataInputStream(stream).run {
                val owner = ByteArray(32).also(::readFully).toList()
                Seen(owner, readLong(), readLong(), readLong(), readLong(), readLong(), readLong(), readLong(), readLong(), readLong())
            }
        }
    } catch (error: FileNotFoundException) {
        null
    } catch (error: EOFException) {
        null
    }

    private fun save(file: AtomicFile, seen: Seen) {
        val stream = file.startWrite()
        try {
            DataOutputStream(stream).run {
                write(seen.owner.toByteArray())
                with(seen) { listOf(generation, life, hearts, maxHearts, level, claimable, inTransit, lastFightEpoch, insurance) }
                    .forEach(::writeLong)
                flush()
            }
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }
}

class PetWatchReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        PetWatch.look(context.applicationContext) { pending.finish() }
    }
}
