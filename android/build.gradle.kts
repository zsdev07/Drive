allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // ── Namespace + Manifest patch for tdlib ───────────────────────────────
    // tdlib 1.6.0 has two AGP 8+ incompatibilities:
    //   1. No `namespace` field in its build.gradle  → we inject it below.
    //   2. Uses package="org.naji.td.tdlib" in AndroidManifest.xml → AGP 8+
    //      forbids setting namespace via the manifest; we strip it via a task.
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null && project.name == "tdlib") {
            // Fix 1: inject namespace so AGP 8+ doesn't complain about it missing
            (androidExt as com.android.build.gradle.LibraryExtension).namespace =
                "org.naji.td.tdlib"

            // Fix 2: strip package="..." from the manifest before AGP reads it.
            // We register a task that rewrites the file in the pub cache, then
            // hook it to run before every processXxxManifest task.
            val stripManifestPackage = tasks.register("stripTdlibManifestPackage") {
                doFirst {
                    val manifests = fileTree(projectDir) {
                        include("**/AndroidManifest.xml")
                    }
                    manifests.forEach { file ->
                        val original = file.readText()
                        val patched = original.replace(
                            Regex("""(\s+)package\s*=\s*"[^"]*""""),
                            ""
                        )
                        if (patched != original) {
                            file.writeText(patched)
                            logger.lifecycle("tdlib manifest patched: removed package= from ${file.path}")
                        }
                    }
                }
            }

            // Hook before any manifest processing task
            tasks.configureEach {
                if (name.startsWith("process") && name.endsWith("Manifest")) {
                    dependsOn(stripManifestPackage)
                }
            }
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
