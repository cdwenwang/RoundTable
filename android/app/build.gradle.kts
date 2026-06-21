plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProps = mutableMapOf<String, String>()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreFile.forEachLine { line ->
        val eq = line.indexOf('=')
        if (eq > 0) keystoreProps[line.substring(0, eq).trim()] = line.substring(eq + 1).trim()
    }
}

android {
    namespace = "com.roundtable.round_table"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.roundtable.round_table"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                keyAlias = keystoreProps["keyAlias"]
                keyPassword = keystoreProps["keyPassword"]
                storeFile = rootProject.file(keystoreProps["storeFile"] ?: "roundtable.keystore")
                storePassword = keystoreProps["storePassword"]
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
