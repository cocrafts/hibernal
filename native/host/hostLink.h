// Host link: what the Android shell tells the core about the surface it draws on and the
// system wallpaper, and the one thing the core asks of the shell (open the wallpaper picker).
//
// The shell sets the surface kind on the render thread before a frame, sets the wallpaper
// places from the UI thread, and takes the picker request on the render thread after a frame.
#ifndef HOST_LINK_H
#define HOST_LINK_H

#include <stdint.h>

void hostSetInApp(int inApp);
int hostInApp(void);

void hostSetWallpaperPlaces(int home, int lock);
// Bit 0: on the home screen, bit 1: on the lock screen.
int hostWallpaperPlaces(void);

void hostRequestWallpaperPicker(void);
// 1 once per request, then 0 until the next one.
int hostTakeWallpaperPickerRequest(void);

// Whether Android lets the Pet's news through as notifications; the shell sets it on resume.
void hostSetPetNewsAllowed(int allowed);
int hostPetNewsAllowed(void);
void hostRequestPetNews(void);
// 1 once per request, then 0 until the next one.
int hostTakePetNewsRequest(void);

// The highest lineage generation whose death notice the player has seen, -1 for none. The shell
// sets it for the selected owner's Pet before that Pet's game read; the core marks a newer one,
// which the shell takes on the render thread after a frame and persists.
void hostSetDeathNoticeSeen(int generation);
int hostDeathNoticeSeen(void);
void hostMarkDeathNoticeSeen(int generation);
// The generation marked since the last take, -1 when none.
int hostTakeDeathNoticeMark(void);

void hostRequestWalletConnect(void);
void hostRequestWalletDisconnect(void);
int hostTakeWalletRequest(void);
void hostSetWallet(int state, const char *address);
int hostWalletState(void);
int hostWalletRevision(void);
int hostWalletAddressByte(int index);

// Owner action, one in flight: action 0..7 (host.ms OwnerAction), item 0..65535 (Claim's name id,
// Buy's packed cart). Ignored while Requested (1) or SentPending (5). The request is (action + 1) | item << 8.
void hostRequestOwnerAction(int action, int item);
int hostTakeOwnerActionRequest(void);
// State 0..13 is host.ms OwnerActionOutcome; anything else publishes Unknown (9).
void hostSetOwnerAction(int state);
int hostOwnerActionState(void);
int hostOwnerActionRevision(void);

// Read-only game identity, independent of wallet authorization and disconnect.
// 0: Unselected, 1: Remembered (exactly 32 bytes), 2: Failed.
// Invalid state or Remembered input clears the key and publishes Failed.
void hostSetGameOwner(int state, const unsigned char *publicKey, int length);
int hostGameOwnerState(void);
// Even revisions are stable; odd revisions mean a write is in progress.
int hostGameOwnerRevision(void);
// Returns 0 outside [0, 32), or for a cleared key.
int hostGameOwnerKeyByte(int index);

// LivePetRead.Field in the Kotlin shell and GamePetField in host.ms, in that order.
#define HOST_GAME_PET_FIELDS 70
// LivePetRead.SeatField in the Kotlin shell and GameSeatField in host.ms, in that order.
#define HOST_GAME_SEAT_FIELDS 52
#define HOST_GAME_SEATS 10
// LivePetRead.FightField in the Kotlin shell and GameFightField in host.ms, in that order.
#define HOST_GAME_FIGHT_FIELDS 26
#define HOST_GAME_FIGHT_RING 32

// State 3 (PetFound) carries exactly HOST_GAME_PET_FIELDS pet values, and either no seat values
// (not seated) or HOST_GAME_SEATS × HOST_GAME_SEAT_FIELDS in seat order with up to
// HOST_GAME_FIGHT_RING whole fights, oldest first; every other state, and an unseated read, none.
int hostSetGameRead(int ownerRevision, int state, uint64_t baseSlot, uint64_t ephemeralSlot,
	int admissionHoldings, int admissionMembers, int unclaimedMembers, const char *detail,
	const int64_t *pet, int petFields, const int64_t *seats, int seatValues,
	const int64_t *fights, int fightValues);
int hostGameReadState(void);
int hostGameReadRevision(void);
uint64_t hostGameReadBaseSlot(void);
uint64_t hostGameReadEphemeralSlot(void);
int hostGameReadAdmissionHoldings(void);
int hostGameReadAdmissionMembers(void);
int hostGameReadUnclaimedMembers(void);
int hostGameReadDetailByte(int index);
// Seconds since the last publication, on a clock that keeps counting through device sleep.
int64_t hostGameReadAgeSeconds(void);
// Returns 0 outside [0, HOST_GAME_PET_FIELDS).
int64_t hostGameReadPetField(int index);
// 0 or HOST_GAME_SEATS.
int hostGameReadSeatCount(void);
// Returns 0 outside [0, hostGameReadSeatCount()) × [0, HOST_GAME_SEAT_FIELDS).
int64_t hostGameReadSeatField(int seat, int field);
// 0 to HOST_GAME_FIGHT_RING.
int hostGameReadFightCount(void);
// Returns 0 outside [0, hostGameReadFightCount()) × [0, HOST_GAME_FIGHT_FIELDS).
int64_t hostGameReadFightField(int fight, int field);

#endif
