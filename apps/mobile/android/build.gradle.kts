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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val configureSubproject: Project.() -> Unit = {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.run {
            // 1. Fix the Namespace issue
            if (namespace == null) {
                val manifestFile = sourceSets.getByName("main").manifest.srcFile
                if (manifestFile.exists()) {
                    val parser = javax.xml.parsers.DocumentBuilderFactory.newInstance().newDocumentBuilder()
                    val document = parser.parse(manifestFile)
                    val packageName = document.documentElement.getAttribute("package")
                    if (packageName.isNotEmpty()) {
                        namespace = packageName
                    }
                }
            }

            // 2. Fix the compileSdk dependency issue (Forces it to 34+)
            if (compileSdkVersion != null && (compileSdkVersion!!.replace("android-", "").toIntOrNull() ?: 0) < 34) {
                compileSdkVersion("android-34")
            }
        }
    }

    if (state.executed) {
        configureSubproject()
    } else {
        afterEvaluate { configureSubproject() }
    }
}
