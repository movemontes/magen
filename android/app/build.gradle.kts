import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Mesmo número do Mac (montar-app.sh) e do Windows (windows/magen_win/version.py).
val magenVersion = "1.3"
val magenCode = 13

// Peças que vêm de fora da pasta android/ e são copiadas na hora de montar:
// - Archivo (licença aberta) de Resources/fonts;
// - Clash Grotesk de windows/fontes-privadas (a licença proíbe pôr o arquivo no GitHub);
// - versículos de windows/magen_win/data (uma lista só para Windows e Android).
val generatedRes = layout.buildDirectory.dir("generated/magen/res")
val generatedAssets = layout.buildDirectory.dir("generated/magen/assets")
val copyMagenFiles by tasks.registering {
    val root = rootProject.projectDir.parentFile
    inputs.files(
        File(root, "Resources/fonts/Archivo-Variable.ttf"),
        File(root, "windows/magen_win/data/versiculos.json"),
    )
    outputs.dirs(generatedRes, generatedAssets)
    doLast {
        val font = generatedRes.get().dir("font").asFile.apply { mkdirs() }
        File(root, "Resources/fonts/Archivo-Variable.ttf").copyTo(File(font, "archivo.ttf"), overwrite = true)
        val clash = File(root, "windows/fontes-privadas")
        for ((from, to) in listOf("ClashGrotesk-Medium.otf" to "clash_medium.otf",
                                  "ClashGrotesk-Semibold.otf" to "clash_semibold.otf")) {
            val f = File(clash, from)
            if (f.exists()) f.copyTo(File(font, to), overwrite = true)
            else logger.warn("Sem $from em windows/fontes-privadas: o app usa a Archivo no lugar.")
        }
        val assets = generatedAssets.get().asFile.apply { mkdirs() }
        File(root, "windows/magen_win/data/versiculos.json").copyTo(File(assets, "versiculos.json"), overwrite = true)
        File(root, "Resources/icone/mateus.png").copyTo(File(assets, "mateus.png"), overwrite = true)
    }
}

// A chave que assina o .apk fica em android/chave-privada (fora do Git). Sem ela, monta com a de teste.
val keyProps = Properties().apply {
    val f = rootProject.file("chave-privada/assinatura.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "io.github.movemontes.magen"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.movemontes.magen"
        minSdk = 26
        targetSdk = 35
        versionCode = magenCode
        versionName = magenVersion
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    sourceSets["main"].res.srcDir(generatedRes)
    sourceSets["main"].assets.srcDir(generatedAssets)

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

// As telas leem o estado do porteiro direto (não é "estado do Compose") e redesenham a cada aviso.
// Por isso o Compose não pode pular uma página só porque recebeu o mesmo objeto.
composeCompiler {
    featureFlags = setOf(org.jetbrains.kotlin.compose.compiler.gradle.ComposeFeatureFlag.StrongSkipping.disabled())
}

tasks.named("preBuild") { dependsOn(copyMagenFiles) }

// Depois de montar, copia o .apk para android/dist com o nome que a atualização procura.
tasks.register<Copy>("magenApk") {
    dependsOn("assembleRelease")
    from(layout.buildDirectory.dir("outputs/apk/release")) { include("*.apk") }
    into(rootProject.file("dist"))
    rename { "Magen-$magenVersion-android.apk" }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.core:core-ktx:1.13.1")
    testImplementation("junit:junit:4.13.2")
}
