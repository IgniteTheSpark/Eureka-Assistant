group = "com.eureka.chiplet_ring"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        // Local Maven repo containing the vendored ChipletRing aar.
        maven {
            url = uri("${rootDir}/local-maven")
        }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.eureka.chiplet_ring"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // ChipletRing BraveChip SDK vendored via local-maven repo (AGP forbids direct aar fileTree in library modules).
    api("com.lm.sdk:ChipletRing:1.3.3@aar")
    // st25sdk: plain jar, allowed directly in library modules.
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    // The bare aar declares no transitive deps; these are the SDK's runtime requirements
    // (mirrors the official demo app). BLEService.onCreate needs LocalBroadcastManager;
    // device/data flows use greenDAO + gson. Network libs (okhttputils/retrofit) omitted —
    // the local BLE/audio path doesn't need them and com.zhy:okhttputils is jcenter-only.
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")
    implementation("org.greenrobot:greendao:3.3.0")
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("org.jetbrains:annotations:15.0")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
