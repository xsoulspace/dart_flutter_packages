group = "com.xsoulspace.rustore_billing_api"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.1.10"
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://artifactory-external.vkpartner.ru/artifactory/maven")
        }
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.10.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

rootProject.allprojects {
    repositories {
        maven {
            url = uri("https://artifactory-external.vkpartner.ru/artifactory/maven")
        }
        google()
        mavenCentral()
    }
}

allprojects {
    repositories {
        maven {
            url = uri("https://artifactory-external.vkpartner.ru/artifactory/maven")
        }
        google()
        mavenCentral()

    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    compileSdk = 36

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

}

dependencies {
    val kotlinVersion = "2.1.10"
    
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlinVersion")
    implementation("androidx.annotation:annotation:1.9.1")
//    implementation(platform("ru.rustore.sdk:bom:2025.02.01"))
//    implementation("ru.rustore.sdk:billingclient")

    // RuStore SDK
    implementation("ru.rustore.sdk:billingclient:9.1.0")
    
    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
} 