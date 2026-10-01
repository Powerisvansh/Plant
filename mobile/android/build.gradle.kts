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

// tflite_flutter 0.12.1 compiles its Kotlin/Java against JVM target 11, but
// Kotlin 2.4 defaults to 21, which fails the release build with
// "Inconsistent JVM Target Compatibility". Align every plugin subproject's
// Kotlin target with the Java target each one declares for itself.
subprojects {
    if (name == "app") return@subprojects
    plugins.withId("org.jetbrains.kotlin.android") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
            compilerOptions.jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11,
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
