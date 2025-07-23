group = "com.xsoulspace.rustore_billing_api"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "1.9.10"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://artifactory-external.vkpartner.ru/artifactory/vkid-sdk-andorid/") }
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 21
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    testOptions {
        unitTests.all {
            it.useJUnitPlatform()

            it.testLogging {
                events("passed", "skipped", "failed", "standardOut", "standardError")
                outputs.upToDateWhen { false }
                showStandardStreams = true
            }
        }
    }
}

dependencies {
    val kotlinVersion = "1.9.10"
    
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlinVersion")
    implementation("androidx.annotation:annotation:1.7.0")
    
    // RuStore SDK
    implementation("ru.rustore.sdk:billingclient:9.1.0")
    
    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
} 