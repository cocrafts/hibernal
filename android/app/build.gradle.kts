plugins {
    id("com.android.application")
}

android {
    namespace = "app.hibernal"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.hibernal"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        ndk { abiFilters += "arm64-v8a" }
    }

    // The release key stays outside the repo: -PhibernalKeystore=<path> plus the three
    // passwords/alias properties, usually in ~/.gradle/gradle.properties.
    signingConfigs {
        create("release") {
            (project.findProperty("hibernalKeystore") as String?)?.let { keystore ->
                storeFile = file(keystore)
                storePassword = project.property("hibernalKeystorePassword") as String
                keyAlias = project.property("hibernalKeyAlias") as String
                keyPassword = project.property("hibernalKeyPassword") as String
            }
        }
    }
    buildTypes {
        release { signingConfig = signingConfigs.getByName("release") }
    }

    // Hibernal's assets/ and void's (font.ttf) ride in the APK;
    // VoidNative.prepare extracts them. -PvoidDir points at the void checkout.
    val voidDir = (project.findProperty("voidDir") as String?) ?: "../../vendor/void"
    sourceSets["main"].assets.srcDirs("../../assets", "$voidDir/assets")
}

dependencies {
    implementation("com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.2.0")
    implementation("io.github.funkatronics:multimult:0.2.6")
    implementation("org.bouncycastle:bcprov-jdk18on:1.79")
    implementation("androidx.activity:activity-ktx:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
