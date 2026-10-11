package app.hibernal

import android.net.Uri
import android.util.AtomicFile
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.AdapterOperations
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.Solana
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import com.solana.mobilewalletadapter.clientlib.protocol.MobileWalletAdapterClient.AuthorizationResult
import com.solana.mobilewalletadapter.common.ProtocolContract
import com.solana.publickey.SolanaPublicKey
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

// Only the foreground Activity owns an ActivityResultSender. The renderer never starts a wallet
// intent, and a saved token is a reconnect credential, not evidence of a connected account.
class WalletBridge(private val activity: MainActivity) {
    private val sender = ActivityResultSender(activity)
    private val adapter = MobileWalletAdapter(
        connectionIdentity = ConnectionIdentity(
            // The project's configured Git origin, not an invented Hibernal website.
            identityUri = Uri.parse("https://github.com/fluctlight-kayaba/hibernal"),
            // The KTX identity requires a non-null relative URI; no hosted app icon is known.
            iconUri = Uri.EMPTY,
            identityName = "Hibernal",
        ),
    ).apply { blockchain = Solana.Devnet }

    private val authFile = AtomicFile(File(activity.noBackupFilesDir, "walletAuthToken"))
    private val sessionFile = AtomicFile(File(activity.noBackupFilesDir, "ownerSession"))

    private val ownerWallet = OwnerSigning.ConnectedWallet(
        object : OwnerSigning.Session {
            override suspend fun <T> open(
                authToken: String?, block: suspend (AdapterOperations, AuthorizationResult) -> T,
            ): TransactionResult<T> {
                adapter.authToken = authToken
                return adapter.transact(sender) { block(this, it) }
            }
        },
        object : OwnerSigning.Authorization {
            override suspend fun saved() = withContext(Dispatchers.IO) { readAuthToken() }
            override suspend fun keep(authToken: String) {
                try {
                    withContext(NonCancellable + Dispatchers.IO) { writeAuthToken(authToken) }
                } catch (error: Exception) {
                    Log.e(TAG, "Rotated wallet authorization not stored: ${error.javaClass.name}")
                }
            }
            override suspend fun forget() {
                adapter.authToken = null
                withContext(NonCancellable + Dispatchers.IO) { authFile.delete() }
            }
        },
    ) { authorization ->
        authorization.accounts.firstOrNull()?.let { publish(CONNECTED, SolanaPublicKey(it.publicKey).address) }
    }

    // Called on the UI thread after the render loop consumes a native request.
    fun request(request: Int) {
        if (request != CONNECT && request != DISCONNECT) return
        if (interactionPending) return
        if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            publish(REJECTED)
            return
        }
        interactionPending = true
        publish(if (request == CONNECT) CONNECTING else DISCONNECTING)
        activity.lifecycleScope.launch {
            try {
                adapter.authToken = withContext(Dispatchers.IO) { readAuthToken() }
                // Do not queue an association intent when the user has left the app during IO.
                if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                    publish(REJECTED)
                    return@launch
                }
                if (request == CONNECT) connect() else disconnect()
            } catch (error: CancellationException) {
                publish(REJECTED)
                throw error
            } catch (error: Exception) {
                reportFailure(if (request == CONNECT) "Connect" else "Disconnect", error)
            } finally {
                interactionPending = false
            }
        }
    }

    fun requestOwnerAction(request: Int) {
        val decoded = OwnerSigning.request(request)
        when (decoded.action) {
            OwnerSigning.OwnerAction.CLAIM -> ownerInteraction { summon(decoded.item) }
            OwnerSigning.OwnerAction.CLAIM_REWARD -> ownerInteraction { reward() }
            OwnerSigning.OwnerAction.BUY -> ownerInteraction { buy(decoded.item) }
            OwnerSigning.OwnerAction.BANK -> ownerInteraction { bank() }
            OwnerSigning.OwnerAction.PAY_REBIRTH -> ownerInteraction { payRebirth() }
            else -> {
                Log.i(TAG, "${decoded.action} unavailable: no validated deployment profile prepares its transaction")
                publishOwnerAction(OwnerSigning.Outcome.UNAVAILABLE)
            }
        }
    }

    fun signOwnerAction(preview: OwnerPreflight.SourceOnlyPreview) {
        ownerInteraction { signAndConfirm(preview, null) }
    }

    private fun ownerInteraction(block: suspend () -> Unit) {
        if (interactionPending || !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            publishOwnerAction(OwnerSigning.Outcome.CANCELLED)
            return
        }
        interactionPending = true
        publishOwnerAction(OwnerSigning.Outcome.REQUESTED)
        activity.lifecycleScope.launch {
            try {
                block()
            } catch (error: CancellationException) {
                publishOwnerAction(OwnerSigning.Outcome.CANCELLED)
                throw error
            } catch (error: IOException) {
                Log.e(TAG, "Owner action preflight failed: ${error.javaClass.name}: ${error.message}")
                publishOwnerAction(OwnerSigning.Outcome.UNAVAILABLE)
            } catch (error: LivePetRead.UnsupportedLayout) {
                Log.e(TAG, "Owner action read refused: ${error.message}")
                publishOwnerAction(OwnerSigning.Outcome.UNAVAILABLE)
            } catch (error: Exception) {
                logFailure("Sign", error, rejected = false)
                publishOwnerAction(OwnerSigning.Outcome.WALLET_FAILED)
            } finally {
                interactionPending = false
            }
        }
    }

    private suspend fun summon(nameId: Int) {
        val ownerKey = withContext(Dispatchers.IO) { GameOwnerStore.owner(activity) }
        if (ownerKey == null) {
            publishOwnerAction(OwnerSigning.Outcome.NO_WALLET)
            return
        }
        val owner = SolanaPublicKey(ownerKey).address
        val answer = try {
            AdmissionService.admit(owner)
        } catch (error: AdmissionService.Failure) {
            Log.e(TAG, "Admission failed: ${error.message}")
            publishOwnerAction(OwnerSigning.Outcome.ADMISSION_FAILED)
            return
        }
        val ticket = when (answer) {
            is AdmissionService.Answer.Ticket -> answer.mint
            AdmissionService.Answer.NoSeekerGenesisToken -> {
                publishOwnerAction(OwnerSigning.Outcome.NO_SEEKER_GENESIS_TOKEN)
                return
            }
        }
        val rpc = SolanaRpc(SolanaRpc.DEVNET)
        val pet = rpc.getAccountInfo(OwnerOnboarding.petAddress(ticket, GameSync.PROGRAM)).value
        val step = OwnerOnboarding.step(pet, GameSync.PROGRAM)
        if (step == OwnerOnboarding.Step.ALREADY_DELEGATED) {
            publishOwnerAction(OwnerSigning.Outcome.IDLE)
            GameSync.select(ownerKey)
            return
        }
        val config = rpc.getAccountInfo(GameSync.CONFIG).value ?: throw SolanaRpc.Failure("Config missing on L1")
        val hbrnMint = OwnerReward.hbrnMint(config)
        val hbrnTokenProgram = rpc.getAccountInfo(hbrnMint).value?.owner ?: throw SolanaRpc.Failure("HBRN mint missing on L1")
        val preview = OwnerPreflight.inspectSourceOnly(rpc, OwnerOnboarding.instructions(step, owner, ticket, GameSync.PROGRAM,
            GameSync.CONFIG, nameId, hbrnMint, hbrnTokenProgram), owner, GameSync.PROGRAM)
        preview.simulation.value.error?.let { error ->
            Log.e(TAG, "Summon simulation failed: $error ${preview.simulation.value.logs?.takeLast(6)}")
            publishOwnerAction(OwnerSigning.Outcome.FAILED_ON_CHAIN)
            return
        }
        signAndConfirm(preview, ownerKey)
    }

    private suspend fun reward() {
        val ownerKey = withContext(Dispatchers.IO) { GameOwnerStore.owner(activity) }
        val pet = GameSync.livePet
        if (ownerKey == null || pet == null) {
            publishOwnerAction(OwnerSigning.Outcome.NO_WALLET)
            return
        }
        val owner = SolanaPublicKey(ownerKey).address
        val program = SolanaPublicKey.from(GameSync.PROGRAM)
        val base = SolanaRpc(SolanaRpc.DEVNET)
        val ephemeral = SolanaRpc(SolanaRpc.DEVNET_ER)
        val paidAddress = LivePetRead.paidAddress(program, SolanaPublicKey.from(pet.mint))
        val (config, committed, paid) = base.getMultipleAccounts(listOf(GameSync.CONFIG, pet.address, paidAddress)).value
        val live = ephemeral.getAccountInfo(pet.address).value
        if (config == null || committed == null) throw SolanaRpc.Failure("Config or Pet missing on L1")
        val delegation = SolanaPublicKey.from(OwnerTransaction.DELEGATION_PROGRAM)
        val committedRecord = SourcePetRead.decodeSourceOnly(committed,
            if (committed.owner == delegation.address) delegation else program, LivePetRead.PROFILE, SolanaPublicKey(ownerKey))
        val liveGift = live?.let { SourcePetRead.decodeSourceOnly(it, program, LivePetRead.PROFILE, SolanaPublicKey(ownerKey)).pet.giftOwed }
            ?: committedRecord.pet.giftOwed
        val paidTotal = LivePetRead.paidTotal(paid, committedRecord.mint, program)
        when (OwnerReward.step(committedRecord.pet.giftOwed, liveGift, paidTotal)) {
            OwnerReward.Step.CLAIM -> {}
            // The game commits and pays for it, so the wallet signs on L1 only: it refuses an ER transaction.
            OwnerReward.Step.COMMIT -> when (val answer = AdmissionService.commit(pet.mint)) {
                AdmissionService.CommitAnswer.Committed -> if (!committedOnL1(base, pet.address, delegation, program, ownerKey) { it.pet.giftOwed > paidTotal }) {
                    publishOwnerAction(OwnerSigning.Outcome.CONFIRMED_AWAITING_READ)
                    GameSync.select(ownerKey)
                    return
                }
                is AdmissionService.CommitAnswer.TooSoon -> {
                    Log.i(TAG, "Gift commit too soon; retry in ${answer.retryAfterSeconds} s")
                    publishOwnerAction(OwnerSigning.Outcome.GIFT_TOO_SOON)
                    return
                }
                AdmissionService.CommitAnswer.NothingToCommit -> {
                    publishOwnerAction(OwnerSigning.Outcome.IDLE)
                    GameSync.select(ownerKey)
                    return
                }
            }
            OwnerReward.Step.NOTHING_OWED -> {
                publishOwnerAction(OwnerSigning.Outcome.IDLE)
                GameSync.select(ownerKey)
                return
            }
        }
        val hbrnMint = OwnerReward.hbrnMint(config)
        val tokenProgram = base.getAccountInfo(hbrnMint).value?.owner ?: throw SolanaRpc.Failure("HBRN mint missing")
        val preview = OwnerPreflight.inspectSourceOnly(base, OwnerReward.claim(owner, pet.address, pet.mint, GameSync.PROGRAM,
            GameSync.CONFIG, hbrnMint, tokenProgram), owner, GameSync.PROGRAM)
        preview.simulation.value.error?.let { error ->
            Log.e(TAG, "Claim simulation failed: $error ${preview.simulation.value.logs?.takeLast(6)}")
            publishOwnerAction(OwnerSigning.Outcome.FAILED_ON_CHAIN)
            return
        }
        signAndConfirm(preview, ownerKey)
    }

    // The commit lands on L1 about a second after the ER; a few spaced reads, then the next poll takes over.
    private suspend fun committedOnL1(base: SolanaRpc, pet: String, delegation: SolanaPublicKey, program: SolanaPublicKey,
        ownerKey: ByteArray, shows: (SourcePetRead.SourceOnlyDecodedPet) -> Boolean): Boolean {
        repeat(COMMIT_READS) {
            delay(COMMIT_READ_GAP_MS)
            val account = base.getAccountInfo(pet).value ?: return@repeat
            val record = SourcePetRead.decodeSourceOnly(account, if (account.owner == delegation.address) delegation else program,
                LivePetRead.PROFILE, SolanaPublicKey(ownerKey))
            if (shows(record)) return true
        }
        return false
    }

    private suspend fun buy(cartCode: Int) {
        val ownerKey = withContext(Dispatchers.IO) { GameOwnerStore.owner(activity) }
        val pet = GameSync.livePet
        if (ownerKey == null || pet == null) {
            publishOwnerAction(OwnerSigning.Outcome.NO_WALLET)
            return
        }
        val owner = SolanaPublicKey(ownerKey).address
        val base = SolanaRpc(SolanaRpc.DEVNET)
        val config = base.getAccountInfo(GameSync.CONFIG).value ?: throw SolanaRpc.Failure("Config missing on L1")
        val skrTokenProgram = base.getAccountInfo(OwnerShop.skrMint(config)).value?.owner
            ?: throw SolanaRpc.Failure("SKR mint missing on L1")
        val preview = OwnerPreflight.inspectSourceOnly(base, OwnerShop.buy(owner, pet.address, pet.mint, GameSync.PROGRAM,
            GameSync.CONFIG, config, skrTokenProgram, OwnerShop.cart(cartCode)), owner, GameSync.PROGRAM)
        preview.simulation.value.error?.let { error ->
            Log.e(TAG, "Buy simulation failed: $error ${preview.simulation.value.logs?.takeLast(6)}")
            publishOwnerAction(OwnerSigning.Outcome.FAILED_ON_CHAIN)
            return
        }
        signAndConfirm(preview, ownerKey)
    }

    // The heir hatches once the operator sees the paid Ledger (ops Rebirth on the ER, then Place).
    private suspend fun payRebirth() {
        val ownerKey = withContext(Dispatchers.IO) { GameOwnerStore.owner(activity) }
        val pet = GameSync.livePet
        if (ownerKey == null || pet == null) {
            publishOwnerAction(OwnerSigning.Outcome.NO_WALLET)
            return
        }
        val owner = SolanaPublicKey(ownerKey).address
        val base = SolanaRpc(SolanaRpc.DEVNET)
        val program = SolanaPublicKey.from(GameSync.PROGRAM)
        val mint = SolanaPublicKey.from(pet.mint)
        val live = SolanaRpc(SolanaRpc.DEVNET_ER).getAccountInfo(pet.address).value
            ?: throw SolanaRpc.Failure("Pet missing on the ER")
        val record = SourcePetRead.decodeSourceOnly(live, program, LivePetRead.PROFILE, SolanaPublicKey(ownerKey))
        val rebirths = OwnerShop.rebirths(base.getAccountInfo(OwnerShop.ledgerAddress(program, mint)).value, mint, program)
        if (!OwnerOnboarding.rebirthPayable(record.pet.alive, record.diedEpoch, rebirths, record.pet.lineageGeneration)) {
            Log.i(TAG, "Rebirth not payable: alive=${record.pet.alive} died=${record.diedEpoch} paid=$rebirths " +
                "generation=${record.pet.lineageGeneration}")
            publishOwnerAction(OwnerSigning.Outcome.IDLE)
            return
        }
        // PayRebirth refuses (6050) until the L1 copy shows the death; the game's /commit service carries it there at once.
        val delegation = SolanaPublicKey.from(OwnerTransaction.DELEGATION_PROGRAM)
        val deathOnL1: (SourcePetRead.SourceOnlyDecodedPet) -> Boolean = { !it.pet.alive && it.diedEpoch.signum() != 0 }
        val committed = base.getAccountInfo(pet.address).value ?: throw SolanaRpc.Failure("Pet missing on L1")
        if (!deathOnL1(SourcePetRead.decodeSourceOnly(committed, if (committed.owner == delegation.address) delegation else program,
                LivePetRead.PROFILE, SolanaPublicKey(ownerKey)))) {
            when (val answer = AdmissionService.commit(pet.mint)) {
                // Nothing is paid yet, so a slow L1 copy must not read as CONFIRMED ("PAID") on the R.I.P screen.
                AdmissionService.CommitAnswer.Committed -> if (!committedOnL1(base, pet.address, delegation, program, ownerKey, deathOnL1)) {
                    throw SolanaRpc.Failure("Death committed but not yet on L1")
                }
                is AdmissionService.CommitAnswer.TooSoon -> throw SolanaRpc.Failure("Death commit refused as too soon (${answer.retryAfterSeconds} s)")
                AdmissionService.CommitAnswer.NothingToCommit -> throw SolanaRpc.Failure("Commit service sees no death to carry to L1")
            }
        }
        val preview = OwnerPreflight.inspectSourceOnly(base,
            OwnerOnboarding.payRebirth(owner, pet.mint, GameSync.PROGRAM, GameSync.CONFIG), owner, GameSync.PROGRAM)
        preview.simulation.value.error?.let { error ->
            Log.e(TAG, "Rebirth simulation failed: $error ${preview.simulation.value.logs?.takeLast(6)}")
            publishOwnerAction(OwnerSigning.Outcome.FAILED_ON_CHAIN)
            return
        }
        signAndConfirm(preview, ownerKey)
    }

    // Half the harvest into the burrow, signed by the session key on the ER. The first time, and after the key
    // expires, the wallet approves a new key on L1 first.
    private suspend fun bank() {
        val ownerKey = withContext(Dispatchers.IO) { GameOwnerStore.owner(activity) }
        val pet = GameSync.livePet
        if (ownerKey == null || pet == null) {
            publishOwnerAction(OwnerSigning.Outcome.NO_WALLET)
            return
        }
        val owner = SolanaPublicKey(ownerKey).address
        val program = SolanaPublicKey.from(GameSync.PROGRAM)
        val ephemeral = SolanaRpc(SolanaRpc.DEVNET_ER)
        val world = LivePetRead.worldAddress(program)
        val (live, worldAccount) = ephemeral.getMultipleAccounts(listOf(pet.address, world)).value
        if (live == null || worldAccount == null) throw SolanaRpc.Failure("Pet or World missing on the ER")
        val record = SourcePetRead.decodeSourceOnly(live, program, LivePetRead.PROFILE, SolanaPublicKey(ownerKey)).pet
        val clock = SourceWorldRead.decodeSourceOnlyWorld(worldAccount, program, LivePetRead.PROFILE)
        val gameNow = OwnerSession.gameSeconds(clock.genesisTimestamp, clock.secondsPerDay, System.currentTimeMillis() / 1000)
        if (record.harvest.signum() == 0) {
            publishOwnerAction(OwnerSigning.Outcome.IDLE)
            return
        }
        if (OwnerSession.bankCoolingDown(record.ownerBankReadyAt, gameNow)) {
            publishOwnerAction(OwnerSigning.Outcome.BANK_COOLING_DOWN)
            return
        }
        val session = approvedSession(owner) ?: return
        val token = OwnerSession.token(GameSync.PROGRAM, session.signer.address, owner)
        val blockhash = ephemeral.getLatestBlockhash().value
        val transaction = OwnerSession.bank(session.signer, GameSync.PROGRAM, pet.address, world, token, blockhash.blockhash)
        val signature = OwnerSession.signature(transaction)
        try {
            ephemeral.sendTransaction(transaction, signature)
        } catch (error: SolanaRpc.RemoteFailure) {
            Log.e(TAG, "Bank refused: ${error.message}")
            publishOwnerAction(OwnerSigning.Outcome.FAILED_ON_CHAIN)
            return
        }
        publishOwnerAction(OwnerSigning.Outcome.SENT_PENDING)
        val outcome = OwnerSigning.confirm(signature, blockhash.lastValidBlockHeight, OwnerSigning.chain(ephemeral), { error ->
            Log.w(TAG, "Bank RPC: ${error.javaClass.name}: ${error.message}")
        }) {}
        publishOwnerAction(outcome)
        if (outcome == OwnerSigning.Outcome.CONFIRMED_AWAITING_READ) GameSync.select(ownerKey)
    }

    // The kept session key for this owner, or a new one the wallet approves now on L1; null when it did not.
    private suspend fun approvedSession(owner: String): OwnerSession.Approved? {
        val kept = withContext(Dispatchers.IO) { OwnerSession.load(sessionFile) }
        val now = System.currentTimeMillis() / 1000
        // An hour's margin so a key does not expire between the check and the ER.
        if (kept != null && kept.usable(owner, GameSync.PROGRAM, now + 3600)) return kept
        val signer = OwnerSession.newSigner()
        val validUntil = now + OwnerSession.VALID_SECONDS
        val base = SolanaRpc(SolanaRpc.DEVNET)
        val token = OwnerSession.token(GameSync.PROGRAM, signer.address, owner)
        val blockhash = base.getLatestBlockhash()
        val unsigned = OwnerSession.createSession(owner, signer, GameSync.PROGRAM, token, validUntil, blockhash.value.blockhash)
        val simulation = base.simulateTransaction(unsigned, blockhash.slot).value
        simulation.error?.let { error ->
            Log.e(TAG, "Session simulation failed: $error ${simulation.logs?.takeLast(6)}")
            publishOwnerAction(OwnerSigning.Outcome.FAILED_ON_CHAIN)
            return null
        }
        if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            publishOwnerAction(OwnerSigning.Outcome.CANCELLED)
            return null
        }
        val ownerBytes = SolanaPublicKey.from(owner).bytes
        val result = ownerWallet.run { operations, authorization ->
            if (authorization.accounts.none { it.publicKey.contentEquals(ownerBytes) }) throw OwnerSigning.OwnerNotAuthorized()
            operations.signTransactions(arrayOf(unsigned)).signedPayloads.single()
        }
        val signed = when (result) {
            is TransactionResult.Success -> OwnerSession.walletSigned(unsigned, result.payload)
            is TransactionResult.NoWalletFound -> { publishOwnerAction(OwnerSigning.Outcome.NO_WALLET); return null }
            is TransactionResult.Failure -> {
                val cancelled = OwnerSigning.remoteCode(result.e) == ProtocolContract.ERROR_NOT_SIGNED
                logFailure("Session", result.e, cancelled)
                publishOwnerAction(if (cancelled) OwnerSigning.Outcome.CANCELLED else OwnerSigning.Outcome.WALLET_FAILED)
                return null
            }
        }
        publishOwnerAction(OwnerSigning.Outcome.SENT_PENDING)
        val signature = OwnerSession.signature(signed)
        val outcome = OwnerSigning.confirm(signature, blockhash.value.lastValidBlockHeight, OwnerSigning.chain(base), { error ->
            Log.w(TAG, "Session RPC: ${error.javaClass.name}: ${error.message}")
        }) { base.sendTransaction(signed, signature) }
        if (outcome != OwnerSigning.Outcome.CONFIRMED_AWAITING_READ) {
            publishOwnerAction(outcome)
            return null
        }
        val approved = OwnerSession.Approved(owner, GameSync.PROGRAM, signer, validUntil)
        withContext(NonCancellable + Dispatchers.IO) { OwnerSession.save(sessionFile, approved) }
        Log.i(TAG, "Session key approved until $validUntil")
        return approved
    }

    // On every return to the app, with a kept key: the program takes at most one a round and three a day,
    // and refuses the rest, which costs nothing on the ER.
    // Reads the Pet and World once, sends only when the program would take it, and looks again when the next round
    // begins; a failed look retries after ENGAGE_RETRY_MS.
    fun engage() {
        val now = System.currentTimeMillis()
        if (now < nextEngageLookMillis) return
        nextEngageLookMillis = now + ENGAGE_RETRY_MS
        observerScope.launch {
            try {
                val ownerKey = GameOwnerStore.owner(activity) ?: return@launch
                val pet = GameSync.livePet ?: return@launch
                val owner = SolanaPublicKey(ownerKey).address
                val session = OwnerSession.load(sessionFile)?.takeIf { it.usable(owner, GameSync.PROGRAM, now / 1000) } ?: return@launch
                val program = SolanaPublicKey.from(GameSync.PROGRAM)
                val ephemeral = SolanaRpc(SolanaRpc.DEVNET_ER)
                val world = LivePetRead.worldAddress(program)
                val (live, worldAccount) = ephemeral.getMultipleAccounts(listOf(pet.address, world)).value
                if (live == null || worldAccount == null) throw SolanaRpc.Failure("Pet or World missing on the ER")
                val record = SourcePetRead.decodeSourceOnly(live, program, LivePetRead.PROFILE, SolanaPublicKey(ownerKey)).pet
                val clock = SourceWorldRead.decodeSourceOnlyWorld(worldAccount, program, LivePetRead.PROFILE)
                val gameNow = OwnerSession.gameSeconds(clock.genesisTimestamp, clock.secondsPerDay, now / 1000)
                nextEngageLookMillis = OwnerSession.nextRoundUnix(clock.genesisTimestamp, clock.secondsPerDay, gameNow) * 1000
                val tail = record.sourceTail as SourcePetRead.SourceTail.Canonical
                if (OwnerSession.engageTaken(tail.engagedToday, tail.engagedRound, gameNow)) {
                    Log.i(TAG, "Engage already taken this round")
                    return@launch
                }
                val token = OwnerSession.token(GameSync.PROGRAM, session.signer.address, owner)
                val transaction = OwnerSession.engage(session.signer, GameSync.PROGRAM, pet.address, world, token,
                    ephemeral.getLatestBlockhash().value.blockhash)
                ephemeral.sendTransaction(transaction, OwnerSession.signature(transaction))
                Log.i(TAG, "Engaged")
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                Log.i(TAG, "Engage not taken: ${error.javaClass.simpleName}: ${error.message}")
            }
        }
    }

    // A confirmed transaction for rediscoverOwner restarts its discovery so the new Pet is read.
    private suspend fun signAndConfirm(preview: OwnerPreflight.SourceOnlyPreview, rediscoverOwner: ByteArray?) {
        if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            publishOwnerAction(OwnerSigning.Outcome.CANCELLED)
            return
        }
        when (val answer = OwnerSigning.sign(preview, ownerWallet)) {
            is OwnerSigning.WalletAnswer.Signed -> {
                publishOwnerAction(OwnerSigning.Outcome.SENT_PENDING)
                val chain = OwnerSigning.chain(SolanaRpc(preview.endpoint))
                observerScope.launch {
                    val outcome = OwnerSigning.confirm(answer.shape, preview.lastValidBlockHeight, chain, { error ->
                        Log.w(TAG, "Owner action RPC: ${error.javaClass.name}: ${error.message}")
                    })
                    publishOwnerAction(outcome)
                    if (outcome == OwnerSigning.Outcome.CONFIRMED_AWAITING_READ && rediscoverOwner != null) {
                        GameSync.select(rediscoverOwner)
                    }
                }
            }
            is OwnerSigning.WalletAnswer.Refused -> {
                answer.error?.let { logFailure("Sign", it, answer.outcome == OwnerSigning.Outcome.CANCELLED) }
                publishOwnerAction(answer.outcome)
            }
        }
    }

    private suspend fun connect() {
        val result = adapter.connect(sender)
        // The SDK converts some coroutine cancellations into Failure; do not accept a result
        // from an Activity that has been destroyed, including during configuration changes.
        coroutineContext.ensureActive()
        when (result) {
            is TransactionResult.Success -> {
                val authorization = result.authResult
                val account = authorization.accounts.firstOrNull()
                    ?: throw IllegalStateException("Wallet returned no selected account")
                val publicKey = account.publicKey
                if (publicKey.size != PUBLIC_KEY_LENGTH) {
                    val error = IllegalStateException("Wallet returned an invalid public key length")
                    GameOwnerStore.reportFailure("Select", error)
                    throw error
                }
                val address = SolanaPublicKey(publicKey).address
                rememberGameOwner(publicKey)
                withContext(Dispatchers.IO) { writeAuthToken(authorization.authToken) }
                publish(CONNECTED, address)
            }
            is TransactionResult.NoWalletFound -> publish(NO_WALLET)
            is TransactionResult.Failure -> {
                if (OwnerSigning.remoteCode(result.e) == ProtocolContract.ERROR_AUTHORIZATION_FAILED) {
                    // A rejected/expired saved authorization must not trap the next explicit
                    // retry in reauthorization. Retry will ask the wallet to authorize afresh.
                    adapter.authToken = null
                    withContext(Dispatchers.IO) { authFile.delete() }
                }
                reportFailure("Connect", result.e)
            }
        }
    }

    private suspend fun disconnect() {
        try {
            withContext(NonCancellable + Dispatchers.IO) { GameOwnerStore.forget(activity) }
        } catch (error: Exception) {
            GameOwnerStore.reportFailure("Forget", error)
        }
        if (adapter.authToken == null) {
            publish(DISCONNECTED)
            return
        }
        val result = try {
            // Unlike simply forgetting the address, this sends deauthorize to the wallet.
            adapter.disconnect(sender)
        } finally {
            // Forget local credentials even when the wallet is missing or refuses the request.
            // In those cases report the failure; do not claim remote revocation succeeded.
            adapter.authToken = null
            withContext(NonCancellable + Dispatchers.IO) { authFile.delete() }
        }
        coroutineContext.ensureActive()
        when (result) {
            is TransactionResult.Success -> publish(DISCONNECTED)
            is TransactionResult.NoWalletFound -> publish(NO_WALLET)
            is TransactionResult.Failure -> reportFailure("Disconnect", result.e)
        }
    }

    private fun readAuthToken(): String? = try {
        authFile.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() }.takeIf { it.isNotEmpty() }
    } catch (error: FileNotFoundException) {
        if (authFile.baseFile.exists()) throw error
        null
    }

    private fun writeAuthToken(token: String) {
        val stream = authFile.startWrite()
        try {
            stream.write(token.toByteArray(Charsets.UTF_8))
            authFile.finishWrite(stream)
        } catch (error: Exception) {
            authFile.failWrite(stream)
            throw error
        }
    }

    private suspend fun rememberGameOwner(publicKey: ByteArray) {
        try {
            withContext(Dispatchers.IO) { GameOwnerStore.write(activity, publicKey) }
            coroutineContext.ensureActive()
            VoidNative.setGameOwner(GAME_OWNER_REMEMBERED, publicKey)
            GameSync.select(publicKey)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            coroutineContext.ensureActive()
            GameOwnerStore.reportFailure("Write", error)
        }
    }

    private fun reportFailure(operation: String, error: Exception) {
        val causes = generateSequence<Throwable>(error) { it.cause }.take(8).toList()
        val code = OwnerSigning.remoteCode(error)
        val rejected = code == ProtocolContract.ERROR_AUTHORIZATION_FAILED ||
            code == ProtocolContract.ERROR_NOT_SIGNED || causes.any {
                it is InterruptedException ||
                    (it is CancellationException && it !is TimeoutCancellationException)
            }
        logFailure(operation, error, rejected)
        publish(if (rejected) REJECTED else FAILED)
    }

    private fun logFailure(operation: String, error: Exception, rejected: Boolean) {
        val causes = generateSequence<Throwable>(error) { it.cause }.take(8).toList()
        val code = OwnerSigning.remoteCode(error)
        // Exception messages, JSON-RPC data and result.toString() may contain credentials.
        // Record the real exception types/code/frames, never auth tokens or private payloads.
        val detail = causes.joinToString("; ") { it.javaClass.name } +
            ((error as? OwnerTransaction.WalletChangedMessage)?.let { " message offsets ${it.differences}" } ?: "")
        if (rejected) {
            Log.i(TAG, "$operation rejected/cancelled: $detail; code=$code")
        } else {
            Log.e(TAG, "$operation failed: $detail; code=$code\n${error.stackTrace.joinToString("\n")}")
        }
    }

    private fun publish(state: Int, address: String = "") {
        VoidNative.setWalletState(state, address)
    }

    private fun publishOwnerAction(outcome: OwnerSigning.Outcome) {
        VoidNative.setOwnerActionState(outcome.ordinal)
    }

    companion object {
        private const val TAG = "HibernalWallet"
        private const val COMMIT_READS = 6
        private const val COMMIT_READ_GAP_MS = 2_000L
        private const val ENGAGE_RETRY_MS = 5 * 60_000L
        @Volatile private var nextEngageLookMillis = 0L
        private const val CONNECT = 1
        private const val DISCONNECT = 2
        private const val DISCONNECTED = 0
        private const val CONNECTING = 1
        private const val CONNECTED = 2
        private const val NO_WALLET = 3
        private const val REJECTED = 4
        private const val FAILED = 5
        private const val DISCONNECTING = 6

        private const val GAME_OWNER_REMEMBERED = 1
        private const val PUBLIC_KEY_LENGTH = 32

        // Main-thread only; shared across Activity recreation so old/new lifecycles cannot
        // overlap wallet interactions while the old lifecycle coroutine is being cancelled.
        private var interactionPending = false

        // Confirmation outlives the Activity: the transaction is already sent.
        private val observerScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    }
}
