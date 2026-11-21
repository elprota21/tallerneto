allprojects {
    repositories {
        // Repo local de esta VM (artefactos descargados con curl): el TLS de
        // Java hacia dl.google.com se corta en esta red; ver tools/fetch_maven.py.
        maven { url = uri("file:///home/hatch/workspace/tools/localrepo") }
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
