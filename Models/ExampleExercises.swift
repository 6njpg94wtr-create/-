import Foundation

/// Two explicitly labelled samples using the greeting in the Day 1 sample.
/// The reference ID is the existing OpenRussian noun entry, not a new dictionary row.
enum ExampleExercises {
    static let questions: [ExerciseQuestion] = [
        ExerciseQuestion(
            questionID: "sample.day1.greeting.choice.v1", type: .multipleChoice,
            prompt: "Приве́т! 更适合用于哪种场合？", correctAnswer: "informal",
            options: [ExerciseOption(id: "informal", text: "向熟悉的人打招呼"),
                      ExerciseOption(id: "formal", text: "正式公函的称呼")],
            relatedEntryID: "openrussian:noun:e58f1e8c55fa105bdd3f40e5",
            explanation: "Приве́т 是非正式的问候，常用于熟人之间。"),
        ExerciseQuestion(
            questionID: "sample.day1.greeting.input.v1", type: .textInput,
            prompt: "用俄语输入非正式问候“你好”，不加标点。", correctAnswer: "приве́т",
            relatedEntryID: "openrussian:noun:e58f1e8c55fa105bdd3f40e5",
            explanation: "答案为 приве́т；可以不输入重音符号。")
    ]
}
