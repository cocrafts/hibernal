package app.hibernal

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import java.io.DataInputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

object GameOwnerStore {
    private const val TAG = "HibernalOwner"
    private const val UNSELECTED = 0
    private const val REMEMBERED = 1
    private const val FAILED = 2
    private const val PUBLIC_KEY_LENGTH = 32

    private fun cache(context: Context) =
        AtomicFile(File(context.noBackupFilesDir, "gameOwnerPublicKey"))

    @Synchronized
    fun restore(context: Context) {
        try {
            val publicKey = read(cache(context))
            VoidNative.setGameOwner(
                if (publicKey == null) UNSELECTED else REMEMBERED,
                publicKey ?: ByteArray(0),
            )
            GameSync.select(publicKey)
            if (publicKey != null) PetWatch.schedule(context)
            Log.i(TAG, "Public owner restored: remembered=${publicKey != null}")
        } catch (error: Exception) {
            reportFailure("Read", error)
        }
    }

    @Synchronized
    fun write(context: Context, publicKey: ByteArray) {
        require(publicKey.size == PUBLIC_KEY_LENGTH) { "Invalid public key length" }
        val file = cache(context)
        val stream = file.startWrite()
        try {
            stream.write(publicKey)
            stream.fd.sync()
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
        if (read(file)?.contentEquals(publicKey) != true) {
            throw IOException("Game owner cache commit failed")
        }
        PetWatch.schedule(context)
    }

    // Disconnect logs the owner out: the game stops reading their Pet until a wallet is connected again.
    @Synchronized
    fun forget(context: Context) {
        val file = cache(context)
        file.delete()
        if (file.baseFile.exists()) throw IOException("Game owner cache could not be deleted")
        VoidNative.setGameOwner(UNSELECTED, ByteArray(0))
        GameSync.select(null)
        PetWatch.cancel(context)
        Log.i(TAG, "Public owner forgotten")
    }

    @Synchronized
    fun owner(context: Context): ByteArray? = read(cache(context))

    private fun read(file: AtomicFile): ByteArray? = try {
        file.openRead().use { stream ->
            val publicKey = ByteArray(PUBLIC_KEY_LENGTH)
            DataInputStream(stream).readFully(publicKey)
            if (stream.read() != -1) throw IOException("Game owner cache has an invalid length")
            publicKey
        }
    } catch (error: FileNotFoundException) {
        val base = file.baseFile
        val directory = base.parentFile ?: throw error
        if (base.exists() || File("${base.path}.bak").exists() ||
            File("${base.path}.new").exists() || !directory.isDirectory ||
            !directory.canRead() || !directory.canExecute()) throw error
        null
    }

    fun reportFailure(operation: String, error: Exception) {
        val detail = generateSequence<Throwable>(error) { it.cause }.take(8)
            .joinToString("; ") { it.javaClass.name }
        Log.e(TAG, "$operation game owner cache failed: $detail")
        VoidNative.setGameOwner(FAILED, ByteArray(0))
        GameSync.select(null)
    }
}
