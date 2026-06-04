plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.obsidiangit.obsidian_git"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.obsidiangit.obsidian_git"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // 从环境变量加载签名信息
            val keystorePath = System.getenv("KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
            val keystorePassword = System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
            val keyAlias = System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() } ?: "release"
            val keyPassword = System.getenv("KEY_PASSWORD")?.takeIf { it.isNotBlank() }
            
            if (keystorePath != null && keystorePassword != null) {
                val keystoreFile = file(keystorePath)
                if (keystoreFile.exists()) {
                    storeFile = keystoreFile
                    storePassword = keystorePassword
                    this.keyAlias = keyAlias
                    this.keyPassword = keyPassword ?: keystorePassword
                }
            }
        }
    }

    buildTypes {
        release {
            // 如果有 release 签名配置则使用，否则使用 debug
            signingConfig = if (signingConfigs.findByName("release")?.storeFile?.exists() == true) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
