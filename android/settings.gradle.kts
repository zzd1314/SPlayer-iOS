pluginManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://maven.aliyun.com/repository/public")
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // 备用镜像：部分网络环境无法解析 repo.maven.apache.org
        maven("https://maven.aliyun.com/repository/public")
        maven("https://repo1.maven.org/maven2")
    }
}

rootProject.name = "SPlayerNext"
include(":app")