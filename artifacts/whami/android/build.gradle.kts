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

// Force consistent JVM target across all subprojects (fixes plugin compilation mismatches)
subprojects {
    val configureAndroid = Action<Project> {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
                val setSourceCompatibility = compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java)
                val setTargetCompatibility = compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java)
                setSourceCompatibility.invoke(compileOptions, JavaVersion.VERSION_17)
                setTargetCompatibility.invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (e: Exception) {
                // Not an Android extension or method doesn't exist
            }
        }

        tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }

        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }

    if (state.executed) {
        configureAndroid.execute(this)
    } else {
        afterEvaluate {
            configureAndroid.execute(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
