plugins {
    id("com.android.application")
}

android {
    namespace = "app.hibernal"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.hibernal"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        ndk { abiFilters += "arm64-v8a" }
    }

    // Hibernal's assets/ and void's (font.ttf) ride in the APK;
    // VoidNative.prepare extracts them. -PvoidDir points at the void checkout.
    val voidDir = (project.findProperty("voidDir") as String?) ?: "../../vendor/void"
    sourceSets["main"].assets.srcDirs("../../assets", "$voidDir/assets")
}
