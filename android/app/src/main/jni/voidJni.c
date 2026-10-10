#include <jni.h>
#include <stdint.h>
#include <android/native_window_jni.h>

extern void MsMain(void);
extern int voidViewCreate(long long window, int w, int h, float scale);
extern void voidViewResize(int view, int w, int h, float scale);
extern int voidViewFrame(int view);
extern void voidViewDestroy(int view);
extern void voidEmbedDetach(void);
extern void hudPointerPush(int phase, int id, float x, float y);
extern void tiltPush(float w, float x, float y, float z);
extern void voidEmbedSetAssetRoot(const char *path);
extern void hostSetInApp(int inApp);
extern void hostSetWallpaperPlaces(int home, int lock);
extern int hostTakeWallpaperPickerRequest(void);
extern void hostSetDeathNoticeSeen(int generation);
extern int hostTakeDeathNoticeMark(void);
extern int hostTakeWalletRequest(void);
extern void hostSetWallet(int state, const char *address);
extern int hostTakeOwnerActionRequest(void);
extern void hostSetOwnerAction(int state);
extern void hostSetGameOwner(int state, const unsigned char *publicKey, int length);
extern int hostGameOwnerRevision(void);
extern int hostSetGameRead(int ownerRevision, int state, uint64_t baseSlot,
	uint64_t ephemeralSlot, int admissionHoldings, int admissionMembers,
	int unclaimedMembers, const char *detail, const int64_t *pet, int petFields,
	const int64_t *seats, int seatValues, const int64_t *fights, int fightValues);

static int g_started = 0;
static ANativeWindow *g_window = NULL;
static int g_view = 0;

// The dir whose assets/ holds the extracted APK assets; must be set before the first attach.
JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_setAssetRoot(JNIEnv *env, jobject thiz, jstring path) {
	(void)thiz;
	const char *p = (*env)->GetStringUTFChars(env, path, NULL);
	if (!p) return;
	voidEmbedSetAssetRoot(p);
	(*env)->ReleaseStringUTFChars(env, path, p);
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_attach(JNIEnv *env, jobject thiz, jobject surface, jint width, jint height,
	jboolean inApp) {
	(void)thiz;
	if (!g_started) { MsMain(); g_started = 1; }
	hostSetInApp(inApp ? 1 : 0);
	ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
	if (g_view) voidViewDestroy(g_view);
	g_view = voidViewCreate((long long)(intptr_t)window, (int)width, (int)height, 1.0f);
	if (g_window) ANativeWindow_release(g_window);
	g_window = window;
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_resize(JNIEnv *env, jobject thiz, jint width, jint height) {
	(void)env; (void)thiz;
	if (g_view) voidViewResize(g_view, (int)width, (int)height, 1.0f);
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_frame(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	if (g_view) voidViewFrame(g_view);
}

// Called on the UI thread, while frames run on the render thread: the pointer queue is
// guarded (src/sokol/pointer.c), and MetaScript only reads it inside a frame.
JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_touch(JNIEnv *env, jobject thiz, jint phase, jint id, jfloat x, jfloat y) {
	(void)env; (void)thiz;
	hudPointerPush((int)phase, (int)id, (float)x, (float)y);
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_rotation(JNIEnv *env, jobject thiz, jfloat w, jfloat x, jfloat y, jfloat z) {
	(void)env; (void)thiz;
	tiltPush((float)w, (float)x, (float)y, (float)z);
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_setWallpaperPlaces(JNIEnv *env, jobject thiz, jboolean home, jboolean lock) {
	(void)env; (void)thiz;
	hostSetWallpaperPlaces(home ? 1 : 0, lock ? 1 : 0);
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_setDeathNoticeSeen(JNIEnv *env, jobject thiz, jint generation) {
	(void)env; (void)thiz;
	hostSetDeathNoticeSeen(generation);
}

JNIEXPORT jint JNICALL
Java_app_hibernal_VoidNative_takeDeathNoticeMark(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	return hostTakeDeathNoticeMark();
}

JNIEXPORT jboolean JNICALL
Java_app_hibernal_VoidNative_takeWallpaperPickerRequest(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	return hostTakeWallpaperPickerRequest() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_app_hibernal_VoidNative_takeWalletRequest(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	return (jint)hostTakeWalletRequest();
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_setWalletState(JNIEnv *env, jobject thiz, jint state, jstring address) {
	(void)thiz;
	const char *p = (*env)->GetStringUTFChars(env, address, NULL);
	if (!p) return;
	hostSetWallet((int)state, p);
	(*env)->ReleaseStringUTFChars(env, address, p);
}

JNIEXPORT jint JNICALL
Java_app_hibernal_VoidNative_takeOwnerActionRequest(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	return (jint)hostTakeOwnerActionRequest();
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_setOwnerActionState(JNIEnv *env, jobject thiz, jint state) {
	(void)env; (void)thiz;
	hostSetOwnerAction((int)state);
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_setGameOwner(JNIEnv *env, jobject thiz, jint state, jbyteArray publicKey) {
	(void)thiz;
	if (state != 1 || !publicKey) {
		hostSetGameOwner((int)state, NULL, 0);
		return;
	}
	jsize length = (*env)->GetArrayLength(env, publicKey);
	if (length != 32) {
		hostSetGameOwner(2, NULL, 0);
		return;
	}
	jbyte *bytes = (*env)->GetByteArrayElements(env, publicKey, NULL);
	if (!bytes) {
		hostSetGameOwner(2, NULL, 0);
		return;
	}
	// The host copies the public key synchronously and never modifies the JVM array.
	hostSetGameOwner((int)state, (const unsigned char *)bytes, (int)length);
	(*env)->ReleaseByteArrayElements(env, publicKey, bytes, JNI_ABORT);
}

JNIEXPORT jint JNICALL
Java_app_hibernal_VoidNative_gameOwnerRevision(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	return (jint)hostGameOwnerRevision();
}

JNIEXPORT jboolean JNICALL
Java_app_hibernal_VoidNative_setGameRead(JNIEnv *env, jobject thiz, jint ownerRevision,
	jint state, jlong baseSlot, jlong ephemeralSlot, jint admissionHoldings,
	jint admissionMembers, jint unclaimedMembers, jstring detail, jlongArray pet, jlongArray seats,
	jlongArray fights) {
	(void)thiz;
	if (!detail || !pet || !seats || !fights || baseSlot < 0 || ephemeralSlot < 0) return JNI_FALSE;
	const char *text = (*env)->GetStringUTFChars(env, detail, NULL);
	if (!text) return JNI_FALSE;
	jsize petFields = (*env)->GetArrayLength(env, pet);
	jlong *values = petFields > 0 ? (*env)->GetLongArrayElements(env, pet, NULL) : NULL;
	jsize seatValues = (*env)->GetArrayLength(env, seats);
	jlong *seatData = seatValues > 0 ? (*env)->GetLongArrayElements(env, seats, NULL) : NULL;
	jsize fightValues = (*env)->GetArrayLength(env, fights);
	jlong *fightData = fightValues > 0 ? (*env)->GetLongArrayElements(env, fights, NULL) : NULL;
	if ((petFields > 0 && !values) || (seatValues > 0 && !seatData) || (fightValues > 0 && !fightData)) {
		if (values) (*env)->ReleaseLongArrayElements(env, pet, values, JNI_ABORT);
		if (seatData) (*env)->ReleaseLongArrayElements(env, seats, seatData, JNI_ABORT);
		if (fightData) (*env)->ReleaseLongArrayElements(env, fights, fightData, JNI_ABORT);
		(*env)->ReleaseStringUTFChars(env, detail, text);
		return JNI_FALSE;
	}
	int accepted = hostSetGameRead((int)ownerRevision, (int)state, (uint64_t)baseSlot,
		(uint64_t)ephemeralSlot, (int)admissionHoldings, (int)admissionMembers,
		(int)unclaimedMembers, text, (const int64_t *)values, (int)petFields,
		(const int64_t *)seatData, (int)seatValues, (const int64_t *)fightData, (int)fightValues);
	if (values) (*env)->ReleaseLongArrayElements(env, pet, values, JNI_ABORT);
	if (seatData) (*env)->ReleaseLongArrayElements(env, seats, seatData, JNI_ABORT);
	if (fightData) (*env)->ReleaseLongArrayElements(env, fights, fightData, JNI_ABORT);
	(*env)->ReleaseStringUTFChars(env, detail, text);
	return accepted ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_app_hibernal_VoidNative_detach(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	voidEmbedDetach();
	if (g_window) { ANativeWindow_release(g_window); g_window = NULL; }
}
