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

// The onnxruntime plugin is compiled against Android SDK 33, but the AndroidX libraries it pulls in need
// SDK 34+ ("checkReleaseAarMetadata" fails otherwise). Raise old library modules to SDK 36, the app's level.
subprojects {
    val raiseCompileSdk: (Project) -> Unit = { p ->
        if (p.plugins.hasPlugin("com.android.library")) {
            val android = p.extensions.findByName("android")
            val current = android?.withGroovyBuilder { "getCompileSdkVersion"() }
                ?.toString()?.filter { it.isDigit() }?.toIntOrNull() ?: 0
            if (android != null && current < 36) {
                android.withGroovyBuilder { "compileSdkVersion"(36) }
            }
        }
    }
    if (state.executed) raiseCompileSdk(this) else afterEvaluate { raiseCompileSdk(this) }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
