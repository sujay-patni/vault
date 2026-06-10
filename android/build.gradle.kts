allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// biometric_storage pins kotlin.jvmToolchain(17), but this machine's
// ~/.gradle/gradle.properties disables toolchain auto-detection and only
// registers JDK 21 — so retarget plugin subprojects to the available 21
// toolchain (AGP 8.11 / Kotlin 2.2 handle Java 21 bytecode fine).
subprojects {
    // :app is already evaluated via evaluationDependsOn above (and manages
    // its own Java settings); only plugin subprojects need the retarget.
    if (name != "app") {
        afterEvaluate {
            extensions.findByType<JavaPluginExtension>()?.toolchain {
                languageVersion.set(JavaLanguageVersion.of(21))
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
