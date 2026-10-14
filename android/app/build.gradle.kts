import java.io.File
import java.util.Properties

val releaseSigningPropertiesFile = rootProject.file("../KeyRel/android/keystore.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningPropertiesFile.exists()) {
        releaseSigningPropertiesFile.inputStream().use { load(it) }
    }
}
val releaseKeyAlias = releaseSigningProperties.getProperty("keyAlias")
val releaseStorePassword = releaseSigningProperties.getProperty("storePassword")
    ?: releaseSigningProperties.getProperty("password")
val releaseKeyPassword = releaseSigningProperties.getProperty("keyPassword")
    ?: releaseSigningProperties.getProperty("password")
val releaseStoreFile = releaseSigningProperties.getProperty("storeFile")?.let { path ->
    val file = File(path)
    if (file.isAbsolute) file else File(releaseSigningPropertiesFile.parentFile, path)
}
val releaseSigningConfigured = !releaseKeyAlias.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank() &&
    releaseStoreFile?.isFile == true

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aver.dba2"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
                storeFile = requireNotNull(releaseStoreFile)
                storePassword = requireNotNull(releaseStorePassword)
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aver.dba2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

tasks.matching { it.name == "assembleRelease" || it.name == "bundleRelease" }
    .configureEach {
        dependsOn("verifyReleaseSigning")
    }

tasks.register("verifyReleaseSigning") {
    doLast {
        if (!releaseSigningConfigured) {
            throw GradleException(
                "Release signing is not configured. Check KeyRel/android/keystore.properties and its storeFile."
            )
        }
    }
}

val copyNamedReleaseApk = tasks.register("copyNamedReleaseApk") {
    val standardApk = layout.buildDirectory.file("outputs/flutter-apk/app-release.apk")
    
    // Automatically read version and build number from pubspec.yaml via Flutter extension
    val versionName = flutter.versionName
    val versionCode = flutter.versionCode
    
    // Construct your dynamic filename (e.g., dba2-v1.2.0-4.apk)
    val customFileName = "dba2-v${versionName}-${versionCode}.apk"
    val namedApk = layout.buildDirectory.file("outputs/flutter-apk/$customFileName")
    
    inputs.file(standardApk)
    outputs.file(namedApk)
    
    doLast {
        val source = standardApk.get().asFile
        if (!source.isFile) {
            throw GradleException("Release APK was not found at ${source.absolutePath}")
        }
        source.copyTo(namedApk.get().asFile, overwrite = true)
        println("✅ Release APK successfully renamed to: $customFileName")
    }
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy(copyNamedReleaseApk)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
