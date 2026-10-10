package app.hibernal

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

// The highest lineage generation whose death notice was shown, per owner and Pet, so another
// wallet or Pet on this phone starts unseen.
object DeathNoticeStore {
    private const val TAG = "HibernalDeathNotice"
    private const val NONE = -1

    @Volatile private var preferences: SharedPreferences? = null

    fun prepare(context: Context) {
        preferences = context.applicationContext.getSharedPreferences("deathNotice", Context.MODE_PRIVATE)
    }

    fun seen(owner: String, pet: String): Int = store().getInt(key(owner, pet), NONE)

    @Synchronized
    fun mark(pet: GameSync.LivePet?, generation: Int) {
        if (pet == null) {
            Log.e(TAG, "Death notice $generation marked with no live Pet read; not persisted")
            return
        }
        val key = key(pet.owner, pet.address)
        val store = store()
        if (generation > store.getInt(key, NONE)) store.edit().putInt(key, generation).apply()
    }

    private fun key(owner: String, pet: String) = "$owner/$pet"

    private fun store() = preferences ?: throw IllegalStateException("DeathNoticeStore used before prepare")
}
