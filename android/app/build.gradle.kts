plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
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

    // 签名配置：优先读 key.properties（本地），其次读环境变量（CI）
    val keystoreProperties = java.io.File("key.properties")
    val releaseSigning = if (keystoreProperties.exists()) {
        val props = java.util.Properties()
        keystoreProperties.inputStream().use { props.load(it) }
        signingConfigs.create("release") {
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
        }
    } else if (System.getenv("KEYSTORE_BASE64") != null) {
        val decoded = java.util.Base64.getDecoder().decode(System.getenv("KEYSTORE_BASE64"))
        val keystoreFile = java.io.File("roundtable.keystore")
        keystoreFile.writeBytes(decoded)
        signingConfigs.create("release") {
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
            storeFile = keystoreFile
            storePassword = System.getenv("STORE_PASSWORD")
        }
    } else {
        signingConfigs.getByName("debug")
    }

    buildTypes {
        release {
            signingConfig = releaseSigning
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
