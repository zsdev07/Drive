allprojects {
    repositories {
        google()
        mavenCentral()
    }
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

// Fix: isar_flutter_libs missing namespace for AGP 8.7+
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                val namespaceMethod = androidExt.javaClass.methods.find { it.name == "getNamespace" }
                val currentNamespace = try { namespaceMethod?.invoke(androidExt) as? String } catch (e: Exception) { null }
                if (currentNamespace.isNullOrEmpty()) {
                    try {
                        val setNamespace = androidExt.javaClass.methods.find { it.name == "setNamespace" }
                        setNamespace?.invoke(androidExt, "dev.simplesoft.isar.flutter_libs")
                    } catch (e: Exception) {
                        // ignore
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
