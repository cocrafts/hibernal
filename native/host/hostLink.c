// Host link (see hostLink.h).

#include <stdatomic.h>
#include <pthread.h>
#include <string.h>
#include <time.h>

#include "hostLink.h"

static atomic_int s_inApp;
static atomic_int s_wallpaperPlaces;
static atomic_int s_pickerRequested;
static atomic_int s_deathNoticeSeen = -1;
static atomic_int s_deathNoticeMark = -1;
static atomic_int s_walletState;
static atomic_int s_walletRequest;
static atomic_int s_walletRevision;
static pthread_mutex_t s_walletMutex = PTHREAD_MUTEX_INITIALIZER;
static char s_walletAddress[45];
static atomic_int s_ownerActionState;
static atomic_int s_ownerActionRequest;
static atomic_int s_ownerActionRevision;
static atomic_int s_gameOwnerState;
static atomic_int s_gameOwnerRevision;
static pthread_mutex_t s_gameOwnerMutex = PTHREAD_MUTEX_INITIALIZER;
static unsigned char s_gameOwnerKey[32];
static atomic_int s_gameReadState;
static atomic_int s_gameReadRevision;
static uint64_t s_gameReadBaseSlot;
static uint64_t s_gameReadEphemeralSlot;
static int s_gameReadAdmissionHoldings = -1;
static int s_gameReadAdmissionMembers = -1;
static int s_gameReadUnclaimedMembers = -1;
static char s_gameReadDetail[128];
static int64_t s_gameReadPet[HOST_GAME_PET_FIELDS];
static int64_t s_gameReadSeats[HOST_GAME_SEATS * HOST_GAME_SEAT_FIELDS];
static int s_gameReadSeatCount;
static int64_t s_gameReadFights[HOST_GAME_FIGHT_RING * HOST_GAME_FIGHT_FIELDS];
static int s_gameReadFightCount;
static int64_t s_gameReadAt;

static int64_t hostSeconds(void) {
	struct timespec now;
#ifdef CLOCK_BOOTTIME
	clock_gettime(CLOCK_BOOTTIME, &now);
#else
	clock_gettime(CLOCK_MONOTONIC, &now);
#endif
	return (int64_t)now.tv_sec;
}

void hostSetInApp(int inApp) { atomic_store(&s_inApp, inApp); }
int hostInApp(void) { return atomic_load(&s_inApp); }

void hostSetWallpaperPlaces(int home, int lock) {
	atomic_store(&s_wallpaperPlaces, (home ? 1 : 0) | (lock ? 2 : 0));
}

int hostWallpaperPlaces(void) { return atomic_load(&s_wallpaperPlaces); }

void hostRequestWallpaperPicker(void) { atomic_store(&s_pickerRequested, 1); }
int hostTakeWallpaperPickerRequest(void) { return atomic_exchange(&s_pickerRequested, 0); }

void hostSetDeathNoticeSeen(int generation) { atomic_store(&s_deathNoticeSeen, generation); }
int hostDeathNoticeSeen(void) { return atomic_load(&s_deathNoticeSeen); }
void hostMarkDeathNoticeSeen(int generation) {
	atomic_store(&s_deathNoticeSeen, generation);
	atomic_store(&s_deathNoticeMark, generation);
}
int hostTakeDeathNoticeMark(void) { return atomic_exchange(&s_deathNoticeMark, -1); }

void hostRequestWalletConnect(void) {
	int state = atomic_load(&s_walletState);
	if (state == 1 || state == 6) return;
	atomic_store(&s_walletState, 1);
	atomic_store(&s_walletRequest, 1);
}

void hostRequestWalletDisconnect(void) {
	if (atomic_load(&s_walletState) != 2) return;
	atomic_store(&s_walletState, 6);
	atomic_store(&s_walletRequest, 2);
}

int hostTakeWalletRequest(void) { return atomic_exchange(&s_walletRequest, 0); }

void hostSetWallet(int state, const char *address) {
	pthread_mutex_lock(&s_walletMutex);
	size_t length = address ? strlen(address) : 0;
	if (state < 0 || state > 6 || (state == 2 && (length < 32 || length > 44))) {
		state = 5;
		length = 0;
	}
	if (state != 2) length = 0;
	memcpy(s_walletAddress, address ? address : "", length);
	s_walletAddress[length] = '\0';
	atomic_store(&s_walletState, state);
	atomic_fetch_add(&s_walletRevision, 1);
	pthread_mutex_unlock(&s_walletMutex);
}

int hostWalletState(void) { return atomic_load(&s_walletState); }
int hostWalletRevision(void) { return atomic_load(&s_walletRevision); }

int hostWalletAddressByte(int index) {
	if (index < 0 || index >= 45) return 0;
	pthread_mutex_lock(&s_walletMutex);
	int value = (unsigned char)s_walletAddress[index];
	pthread_mutex_unlock(&s_walletMutex);
	return value;
}

void hostRequestOwnerAction(int action, int item, int tier) {
	int state = atomic_load(&s_ownerActionState);
	if (state == 1 || state == 5) return;
	if (action < 0 || action > 7 || item < 0 || item > 255 || tier < 0 || tier > 255) {
		hostSetOwnerAction(9);
		return;
	}
	atomic_store(&s_ownerActionState, 1);
	atomic_fetch_add(&s_ownerActionRevision, 1);
	atomic_store(&s_ownerActionRequest, (action + 1) | (item << 8) | (tier << 16));
}

int hostTakeOwnerActionRequest(void) { return atomic_exchange(&s_ownerActionRequest, 0); }

void hostSetOwnerAction(int state) {
	atomic_store(&s_ownerActionState, state < 0 || state > 12 ? 9 : state);
	atomic_fetch_add(&s_ownerActionRevision, 1);
}

int hostOwnerActionState(void) { return atomic_load(&s_ownerActionState); }
int hostOwnerActionRevision(void) { return atomic_load(&s_ownerActionRevision); }

void hostSetGameOwner(int state, const unsigned char *publicKey, int length) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	atomic_fetch_add(&s_gameOwnerRevision, 1);
	if (state < 0 || state > 2 || (state == 1 && (!publicKey || length != 32))) {
		state = 2;
	}
	if (state == 1) {
		memcpy(s_gameOwnerKey, publicKey, sizeof(s_gameOwnerKey));
	} else {
		memset(s_gameOwnerKey, 0, sizeof(s_gameOwnerKey));
	}
	atomic_store(&s_gameOwnerState, state);
	atomic_fetch_add(&s_gameReadRevision, 1);
	s_gameReadBaseSlot = 0;
	s_gameReadEphemeralSlot = 0;
	s_gameReadAdmissionHoldings = -1;
	s_gameReadAdmissionMembers = -1;
	s_gameReadUnclaimedMembers = -1;
	s_gameReadDetail[0] = '\0';
	memset(s_gameReadPet, 0, sizeof(s_gameReadPet));
	memset(s_gameReadSeats, 0, sizeof(s_gameReadSeats));
	s_gameReadSeatCount = 0;
	memset(s_gameReadFights, 0, sizeof(s_gameReadFights));
	s_gameReadFightCount = 0;
	s_gameReadAt = hostSeconds();
	atomic_store(&s_gameReadState, state == 1 ? 1 : 0);
	atomic_fetch_add(&s_gameReadRevision, 1);
	atomic_fetch_add(&s_gameOwnerRevision, 1);
	pthread_mutex_unlock(&s_gameOwnerMutex);
}

int hostGameOwnerState(void) { return atomic_load(&s_gameOwnerState); }
int hostGameOwnerRevision(void) { return atomic_load(&s_gameOwnerRevision); }

int hostGameOwnerKeyByte(int index) {
	if (index < 0 || index >= 32) return 0;
	pthread_mutex_lock(&s_gameOwnerMutex);
	int value = s_gameOwnerKey[index];
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int hostSetGameRead(int ownerRevision, int state, uint64_t baseSlot, uint64_t ephemeralSlot,
	int admissionHoldings, int admissionMembers, int unclaimedMembers, const char *detail,
	const int64_t *pet, int petFields, const int64_t *seats, int seatValues,
	const int64_t *fights, int fightValues) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	if (atomic_load(&s_gameOwnerRevision) != ownerRevision ||
		atomic_load(&s_gameOwnerState) != 1 || ownerRevision % 2 != 0) {
		pthread_mutex_unlock(&s_gameOwnerMutex);
		return 0;
	}
	atomic_fetch_add(&s_gameReadRevision, 1);
	if (state < 1 || state > 5 || admissionHoldings < -1 || admissionMembers < -1 ||
		unclaimedMembers < -1 || admissionMembers > admissionHoldings || unclaimedMembers > admissionMembers ||
		((state >= 2 && state <= 4) && (!baseSlot || !ephemeralSlot || unclaimedMembers < 0)) ||
		(state == 3 ? (!pet || petFields != HOST_GAME_PET_FIELDS) : petFields != 0) ||
		(state == 3 && seatValues != 0 ? (!seats || seatValues != HOST_GAME_SEATS * HOST_GAME_SEAT_FIELDS)
			: seatValues != 0) ||
		(seatValues != 0 ? (fightValues < 0 || fightValues % HOST_GAME_FIGHT_FIELDS != 0 ||
			fightValues > HOST_GAME_FIGHT_RING * HOST_GAME_FIGHT_FIELDS || (fightValues != 0 && !fights))
			: fightValues != 0)) {
		state = 5;
		baseSlot = ephemeralSlot = 0;
		admissionHoldings = admissionMembers = unclaimedMembers = -1;
		detail = "INVALID RPC SNAPSHOT";
		seatValues = 0;
		fightValues = 0;
	}
	size_t length = detail ? strlen(detail) : 0;
	if (length >= sizeof(s_gameReadDetail)) length = sizeof(s_gameReadDetail) - 1;
	memcpy(s_gameReadDetail, detail ? detail : "", length);
	s_gameReadDetail[length] = '\0';
	s_gameReadBaseSlot = baseSlot;
	s_gameReadEphemeralSlot = ephemeralSlot;
	s_gameReadAdmissionHoldings = admissionHoldings;
	s_gameReadAdmissionMembers = admissionMembers;
	s_gameReadUnclaimedMembers = unclaimedMembers;
	if (state == 3) {
		memcpy(s_gameReadPet, pet, sizeof(s_gameReadPet));
	} else {
		memset(s_gameReadPet, 0, sizeof(s_gameReadPet));
	}
	if (seatValues != 0) {
		memcpy(s_gameReadSeats, seats, sizeof(s_gameReadSeats));
		s_gameReadSeatCount = HOST_GAME_SEATS;
	} else {
		memset(s_gameReadSeats, 0, sizeof(s_gameReadSeats));
		s_gameReadSeatCount = 0;
	}
	memset(s_gameReadFights, 0, sizeof(s_gameReadFights));
	if (fightValues != 0) memcpy(s_gameReadFights, fights, (size_t)fightValues * sizeof(int64_t));
	s_gameReadFightCount = fightValues / HOST_GAME_FIGHT_FIELDS;
	s_gameReadAt = hostSeconds();
	atomic_store(&s_gameReadState, state);
	atomic_fetch_add(&s_gameReadRevision, 1);
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return 1;
}

int hostGameReadState(void) { return atomic_load(&s_gameReadState); }
int hostGameReadRevision(void) { return atomic_load(&s_gameReadRevision); }

uint64_t hostGameReadBaseSlot(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	uint64_t value = s_gameReadBaseSlot;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

uint64_t hostGameReadEphemeralSlot(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	uint64_t value = s_gameReadEphemeralSlot;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int hostGameReadAdmissionHoldings(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	int value = s_gameReadAdmissionHoldings;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int hostGameReadAdmissionMembers(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	int value = s_gameReadAdmissionMembers;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int hostGameReadUnclaimedMembers(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	int value = s_gameReadUnclaimedMembers;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int hostGameReadDetailByte(int index) {
	if (index < 0 || index >= (int)sizeof(s_gameReadDetail)) return 0;
	pthread_mutex_lock(&s_gameOwnerMutex);
	int value = (unsigned char)s_gameReadDetail[index];
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int64_t hostGameReadAgeSeconds(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	int64_t value = hostSeconds() - s_gameReadAt;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int64_t hostGameReadPetField(int index) {
	if (index < 0 || index >= HOST_GAME_PET_FIELDS) return 0;
	pthread_mutex_lock(&s_gameOwnerMutex);
	int64_t value = s_gameReadPet[index];
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int hostGameReadSeatCount(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	int value = s_gameReadSeatCount;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int64_t hostGameReadSeatField(int seat, int field) {
	if (field < 0 || field >= HOST_GAME_SEAT_FIELDS) return 0;
	pthread_mutex_lock(&s_gameOwnerMutex);
	int64_t value = seat >= 0 && seat < s_gameReadSeatCount ?
		s_gameReadSeats[seat * HOST_GAME_SEAT_FIELDS + field] : 0;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int hostGameReadFightCount(void) {
	pthread_mutex_lock(&s_gameOwnerMutex);
	int value = s_gameReadFightCount;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}

int64_t hostGameReadFightField(int fight, int field) {
	if (field < 0 || field >= HOST_GAME_FIGHT_FIELDS) return 0;
	pthread_mutex_lock(&s_gameOwnerMutex);
	int64_t value = fight >= 0 && fight < s_gameReadFightCount ?
		s_gameReadFights[fight * HOST_GAME_FIGHT_FIELDS + field] : 0;
	pthread_mutex_unlock(&s_gameOwnerMutex);
	return value;
}
