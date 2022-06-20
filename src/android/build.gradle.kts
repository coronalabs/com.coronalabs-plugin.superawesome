buildscript {
    repositories {
        google()
        jcenter()
    }
    dependencies {
        classpath(kotlin("gradle-plugin", version = "1.3.70"))
        classpath("com.android.tools.build:gradle:4.2.1")
        classpath("com.beust:klaxon:5.0.1")
    }
}

allprojects {
    repositories {
        google()
        jcenter()
        // maven(url = "https:// some custom repo")
        maven ( url = "https://aa-sdk.s3-eu-west-1.amazonaws.com/android_repo" )

        val nativeDir = if (System.getProperty("os.name").toLowerCase().contains("windows")) {
            System.getenv("CORONA_ROOT")
        } else {
            "${System.getenv("HOME")}/Library/Application Support/Corona/Native/"
        }
        flatDir {
            dirs("$nativeDir/Corona/android/lib/gradle", "$nativeDir/Corona/android/lib/Corona/libs")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
