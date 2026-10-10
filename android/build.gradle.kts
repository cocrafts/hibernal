// Match the stable MWA SDK's Kotlin metadata without applying kotlin-android:
// AGP 9 provides built-in Kotlin and supports a higher KGP on its classpath.
buildscript {
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.10")
    }
}

plugins {
    id("com.android.application") version "9.3.2" apply false
}
