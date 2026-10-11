package app.hibernal

import org.junit.Assert.assertEquals
import org.junit.Test

class PetWatchTest {
    private val owner = List(32) { 7.toByte() }
    private val seen = PetWatch.Seen(owner, generation = 0, life = 1, hearts = 8, maxHearts = 10, level = 3,
        claimable = 0, inTransit = 1, lastFightEpoch = 40, insurance = 0)

    @Test
    fun aNewDayTellsWhatHappenedToThePet() {
        val now = seen.copy(hearts = 6, level = 4, claimable = 11_210_000, inTransit = 0, lastFightEpoch = 41)
        val fights = listOf(
            PetWatch.Fight(epoch = 40, attackerSeat = 1, defenderSeat = 4, attackerWon = true, loot = 9_000_000),
            PetWatch.Fight(epoch = 41, attackerSeat = 2, defenderSeat = 4, attackerWon = true, loot = 120_500_000),
            PetWatch.Fight(epoch = 41, attackerSeat = 5, defenderSeat = 4, attackerWon = false, loot = 0),
            PetWatch.Fight(epoch = 41, attackerSeat = 4, defenderSeat = 7, attackerWon = true, loot = 3_000_000),
        )
        assertEquals(listOf("ROBBED BY SLOT 3: -120.50 HBRN", "HELD OFF SLOT 6", "LOST 2 HEARTS: 6/10 LEFT",
            "REACHED LEVEL 4", "A GIFT IS READY TO CLAIM", "YOUR ORDER HAS ARRIVED"), PetWatch.news(seen, now, fights, seat = 4))
    }

    private fun life(fact: SourcePetLifecycle.Fact) = fact.ordinal.toLong()

    @Test
    fun aDeathIsToldOnceByHowItEnds() {
        val starving = seen.copy(life = life(SourcePetLifecycle.Fact.INACTIVE_WITHOUT_DEATH_RECORD), hearts = 0)
        assertEquals(listOf("YOUR PET STARVED. OPEN THE APP TO HATCH ITS HEIR", "LOST 8 HEARTS: 0/10 LEFT"), PetWatch.news(seen, starving, emptyList(), 4))
        val beaten = starving.copy(lastFightEpoch = 41)
        assertEquals(listOf("YOUR PET FELL TO SLOT 3. OPEN THE APP TO HATCH ITS HEIR", "ROBBED BY SLOT 3: -1.00 HBRN", "LOST 8 HEARTS: 0/10 LEFT"),
            PetWatch.news(seen, beaten, listOf(PetWatch.Fight(41, 2, 4, attackerWon = true, loot = 1_000_000)), 4))
        val recorded = starving.copy(life = life(SourcePetLifecycle.Fact.DEATH_RECORDED))
        assertEquals(emptyList<String>(), PetWatch.news(starving, recorded, emptyList(), 4))
        val old = seen.copy(life = life(SourcePetLifecycle.Fact.INACTIVE_WITHOUT_DEATH_RECORD))
        assertEquals(listOf("YOUR PET DIED OF OLD AGE. OPEN THE APP TO HATCH ITS HEIR"), PetWatch.news(seen, old, emptyList(), 4))
        val heir = seen.copy(generation = 1, life = life(SourcePetLifecycle.Fact.CLAIMED_UNPLACED), hearts = 10)
        assertEquals(listOf("ITS HEIR HAS HATCHED"), PetWatch.news(old, heir, emptyList(), 4))
        assertEquals(listOf("YOUR PET HAS DIED", "ITS HEIR HAS HATCHED"), PetWatch.news(seen, heir, emptyList(), 4))
    }

    @Test
    fun insuranceSavingThePetIsTold() {
        val saved = seen.copy(hearts = 5, insurance = SourcePetRead.Insurance.Used.ordinal.toLong())
        assertEquals(listOf("INSURANCE SAVED YOUR PET", "LOST 3 HEARTS: 5/10 LEFT"),
            PetWatch.news(seen.copy(insurance = SourcePetRead.Insurance.Armed.ordinal.toLong()), saved, emptyList(), 4))
    }

    @Test
    fun aQuietDayOrAnotherOwnerSaysNothing() {
        assertEquals(emptyList<String>(), PetWatch.news(seen, seen, emptyList(), 4))
        val other = seen.copy(owner = List(32) { 9.toByte() }, hearts = 1)
        assertEquals(emptyList<String>(), PetWatch.news(seen, other, emptyList(), 4))
    }
}
