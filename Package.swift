// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RussianWordsCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "RussianWordsCore", targets: ["RussianWordsCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite3"])]),
        .target(
            name: "RussianWordsCore",
            dependencies: ["CSQLite"],
            path: ".",
            exclude: ["CSQLite", "Data", "Resources", "Tests", "Scripts", "docs", "Features", "UI", "RussianWords.xcodeproj", "MainAppView.swift", "RussianWordsApp.swift", "README.md", "Services/SpeechServices.swift", "Services/TranslationHistoryStore.swift"],
            sources: ["Models/ExampleExercises.swift", "Models/ExerciseModels.swift", "Services/ExerciseGrader.swift", "Services/ExerciseStore.swift", "Models/LearningModels.swift", "Models/DailyCourse.swift", "Services/CourseLoader.swift", "Services/CourseProgressStore.swift", "Models/DictionaryEntry.swift", "Services/LearningStore.swift", "Services/DictionaryRepository.swift", "Services/TranslationService.swift"]
        ),
        .testTarget(name: "RussianWordsCoreTests", dependencies: ["RussianWordsCore"], path: "Tests", sources: ["LearningCoreTests.swift", "DictionaryRepositoryTests.swift", "TranslationServiceTests.swift", "DailyCourseTests.swift", "ExerciseTests.swift"])
    ]
)
