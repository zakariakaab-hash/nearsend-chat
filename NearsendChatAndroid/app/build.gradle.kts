plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "app.nearsend.chat"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.nearsend.chat"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "0.2.0"
    }
    // Release signing: the upload key stays on your computer. Put these four lines in ~/.gradle/gradle.properties (never in the repo):
    //   NEARSEND_KEYSTORE=C:/path/to/nearsend-upload.jks   NEARSEND_KEYSTORE_PASSWORD=...   NEARSEND_KEY_ALIAS=upload   NEARSEND_KEY_PASSWORD=...
    val keystore = providers.gradleProperty("NEARSEND_KEYSTORE").orNull
    signingConfigs {
        if (keystore != null) create("release") {
            storeFile = file(keystore)
            storePassword = providers.gradleProperty("NEARSEND_KEYSTORE_PASSWORD").get()
            keyAlias = providers.gradleProperty("NEARSEND_KEY_ALIAS").get()
            keyPassword = providers.gradleProperty("NEARSEND_KEY_PASSWORD").get()
        }
    }
    buildTypes {
        release {
            // ponytail: no code shrinking yet (R8 needs keep rules for Tink and friends); turn on once tested on a release build.
            isMinifyEnabled = false
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.exifinterface:exifinterface:1.3.7")   // photo orientation (Apache-2.0)
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.crypto.tink:tink-android:1.14.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")   // WebSocket to the optional internet relays (Apache-2.0)
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")   // QR scanner + generator (Apache-2.0)

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")   // android.jar's org.json is stubbed in JVM unit tests
}
