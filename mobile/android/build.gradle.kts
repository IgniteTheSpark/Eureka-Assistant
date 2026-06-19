import java.util.Properties

val userGradleProps = Properties()
val userPropsFile = gradle.gradleUserHomeDir.resolve("gradle.properties")
if (userPropsFile.isFile) {
    userPropsFile.reader().use { userGradleProps.load(it) }
}
val mavenRepoUrl: String = userGradleProps.getProperty(
    "MAVEN_REPO_URL",
    "http://192.168.162.106:8081/nexus/content/groups/public/",
)

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = "https://storage.googleapis.com/download.flutter.io")
        maven(url = "https://jitpack.io")
        maven {
            url = uri(mavenRepoUrl)
            isAllowInsecureProtocol = true
        }
        // Vendored ChipletRing BraveChip SDK aar (local Maven layout inside the chiplet_ring plugin).
        maven {
            url = uri("${rootProject.projectDir}/../packages/chiplet_ring/android/local-maven")
        }
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
