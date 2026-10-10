package app.hibernal

import com.solana.publickey.SolanaPublicKey
import org.junit.Assert.*
import org.junit.Test

class AdmissionServiceTest {
    private val owner = SolanaPublicKey(ByteArray(32) { 8 }).address
    private val ticket = SolanaPublicKey(ByteArray(32) { 9 }).address

    private fun refused(status: Int, body: String) =
        assertThrows(AdmissionService.Failure::class.java) { AdmissionService.answer(status, body, owner) }

    @Test fun issuedAndAlreadyBothNameTheTicket() {
        assertEquals(AdmissionService.Answer.Ticket(ticket, issued = true), AdmissionService.answer(200,
            """{"status":"issued","owner":"$owner","sgt":"x","ticket":"$ticket","signature":"s","skr":"200","lamports":"20000000"}""", owner))
        assertEquals(AdmissionService.Answer.Ticket(ticket, issued = false),
            AdmissionService.answer(200, """{"status":"already","owner":"$owner","ticket":"$ticket"}""", owner))
    }

    @Test fun noSeekerGenesisTokenIsAnAnswerNotAFailure() {
        assertEquals(AdmissionService.Answer.NoSeekerGenesisToken,
            AdmissionService.answer(403, """{"error":"NoSeekerGenesisToken"}""", owner))
    }

    @Test fun anythingElseFailsLoud() {
        refused(200, """{"status":"issued","owner":"$ticket","ticket":"$ticket"}""")
        refused(200, """{"status":"pending","owner":"$owner","ticket":"$ticket"}""")
        refused(200, """{"status":"issued","owner":"$owner","ticket":"not-a-key"}""")
        refused(200, """{"status":"issued","owner":"$owner"}""")
        refused(403, """{"error":"Other"}""")
        refused(400, """{"error":"BadOwner"}""")
        refused(500, """{"error":"AdmitFailed","detail":"rpc"}""")
        refused(502, "<html>bad gateway</html>")
    }

    @Test fun commitAnswersCommittedTooSoonOrNothingAndFailsLoudOtherwise() {
        assertEquals(AdmissionService.CommitAnswer.Committed,
            AdmissionService.commitAnswer(200, """{"status":"committed","giftOwed":"5","signature":"s"}"""))
        assertEquals(AdmissionService.CommitAnswer.TooSoon(3600),
            AdmissionService.commitAnswer(429, """{"error":"TooSoon","retryAfterSeconds":3600}"""))
        assertEquals(AdmissionService.CommitAnswer.NothingToClaim,
            AdmissionService.commitAnswer(409, """{"error":"NothingToClaim"}"""))
        for ((status, body) in listOf(429 to """{"error":"TooSoon"}""", 404 to """{"error":"NoPet"}""",
            400 to """{"error":"BadMint"}""", 500 to """{"error":"CommitFailed"}""", 200 to """{"status":"queued"}""", 502 to "<html/>")) {
            assertThrows(AdmissionService.Failure::class.java) { AdmissionService.commitAnswer(status, body) }
        }
    }
}
