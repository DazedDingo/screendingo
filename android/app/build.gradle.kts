import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.household.watchnext"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.household.watchnext"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Pin the debug signing config to an in-tree keystore file so CI and local
    // builds sign with the SAME key — otherwise AGP's default behaviour quietly
    // materialises a fresh ~/.android/debug.keystore if it can't read the
    // expected one, producing a DIFFERENT SHA-1 on every machine and breaking
    // Firebase-registered Google Sign-In. The keystore lives at
    // android/app/debug.keystore and is .gitignored; CI writes it from the
    // DEBUG_KEYSTORE_B64 secret before the build step.
    //
    // Play-bundle builds (the .aab uploaded to Play Console) sign with a
    // SEPARATE upload keystore stored under android/keystore/upload.jks,
    // configured via android/key.properties. The AAB workflow writes both
    // files from GitHub secrets and sets WN_PLAY_SIGNING=1 to flip the
    // release signingConfig over. Without that env var the release build
    // signs with the existing debug key — preserving the sideload-APK
    // contract so existing GitHub-Releases users keep getting updates
    // signed by the same cert.
    val usePlaySigning: Boolean = System.getenv("WN_PLAY_SIGNING") == "1"
    signingConfigs {
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (usePlaySigning) {
            create("upload") {
                val keyProps = Properties()
                val keyPropsFile = rootProject.file("key.properties")
                if (!keyPropsFile.exists()) {
                    throw GradleException(
                        "WN_PLAY_SIGNING=1 but android/key.properties is missing. " +
                            "The AAB workflow writes it from UPLOAD_KEYSTORE_* secrets."
                    )
                }
                keyPropsFile.inputStream().use { keyProps.load(it) }
                // getProperty() returns String? — non-null assertion is safe
                // here because the AAB workflow writes all four keys before
                // the build step; a missing key is a CI config bug, not a
                // runtime case to handle gracefully.
                storeFile = rootProject.file(keyProps.getProperty("storeFile")!!)
                storePassword = keyProps.getProperty("storePassword")!!
                keyAlias = keyProps.getProperty("keyAlias")!!
                keyPassword = keyProps.getProperty("keyPassword")!!
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (usePlaySigning) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.8.0"))
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-messaging")
}

flutter {
    source = "../.."
}
