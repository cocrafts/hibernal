package app.hibernal

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

// What the coach asked an owner to open and they opened, a bit per CoachLook in native/host/host.ms, per owner:
// the walk through the buttons is the player's, not the Pet's.
object CoachStore {
    private const val TAG = "HibernalCoach"

    @Volatile private var preferences: SharedPreferences? = null

    fun prepare(context: Context) {
        preferences = context.applicationContext.getSharedPreferences("coach", Context.MODE_PRIVATE)
    }

    fun seen(owner: String): Int = store().getInt(owner, 0)

    @Synchronized
    fun mark(pet: GameSync.LivePet?, looks: Int) {
        if (pet == null) {
            Log.e(TAG, "Coach looks $looks marked with no live Pet read; not persisted")
            return
        }
        val store = store()
        store.edit().putInt(pet.owner, store.getInt(pet.owner, 0) or looks).apply()
    }

    private fun store() = preferences ?: throw IllegalStateException("CoachStore used before prepare")
}
