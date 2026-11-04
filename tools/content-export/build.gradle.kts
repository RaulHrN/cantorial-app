// Exports the app's text content (exercises, studies, tips, lessons) to JSON for the iOS app.
// Run from the repository root: gradle -p tools/content-export run
plugins {
    kotlin("jvm") version "2.1.0"
    application
}

repositories { mavenCentral() }

sourceSets {
    main {
        kotlin.srcDir("../../app/src/main/java/com/raulhrn/vox/core")
    }
}

application {
    mainClass.set("ExportContentKt")
}

tasks.named<JavaExec>("run") {
    workingDir = rootDir.resolve("../..")
    args("ios/CantorialCore/Sources/CantorialCore/Resources/content.json")
}
