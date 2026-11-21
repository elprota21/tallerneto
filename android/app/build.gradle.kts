plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tallerneto.mecanico"
    // Mismo arreglo que la app de RutaNeto en esta VM: el SDK local
    // trae las plataformas 34 y 35 (sin la 36 de flutter.compileSdkVersion)
    // y el mínimo que exigen los plugins de package_info_plus es 35.
    compileSdk = 35
    buildToolsVersion = "34.0.0"
    // NDK local del proyecto (enlace a la copia de la app de RutaNeto:
    // el SDK de la VM no trae NDK y Java no puede bajarlo en esta red).
    ndkVersion = "28.2.13676358"
    ndkPath = file("../../.ndk/android-ndk-r28c").absolutePath

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tallerneto.mecanico"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "TallerNeto"
    }

    // Firma PERMANENTE de producción: una sola llave para TODOS los
    // releases, guardada SOLO en local en app/firma/ (tallerneto.jks +
    // clave.txt; NUNCA se sube a GitHub). Sin esta firma exacta,
    // Android rechaza las actualizaciones por «firma distinta».
    signingConfigs {
        create("release") {
            val firmaDir = file("../../firma")
            storeFile = file("../../firma/tallerneto.jks")
            storePassword = File(firmaDir, "clave.txt").readText().trim()
            keyAlias = "tallerneto"
            keyPassword = storePassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
