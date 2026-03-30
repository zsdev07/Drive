allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // ── Namespace patch for tdlib ──────────────────────────────────────────
    // tdlib 1.6.0 ships an old Groovy build.gradle with no `namespace` field.
    // AGP 8+ requires namespace on every library module. We inject it here
    // via afterEvaluate so we never have to touch the pub cache (which is
    // regenerated on every `flutter pub get` / CI run anyway).
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null && project.name == "tdlib") {
            (androidExt as com.android.build.gradle.LibraryExtension).namespace =
                "com.suren.tdlib"
        }
    }
    // ──────────────────────────────────────────────────────────────────────
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
