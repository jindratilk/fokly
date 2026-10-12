import AppKit
import Foundation

enum Phase: Equatable {
    case idle, focusing, paused, onBreak, finished
}

/// What Fokly currently believes about the user's attention.
enum Attention: Equatable {
    case warmingUp, onTrack, drifting, away, unknown
}

/// The model's judgement of one observation.
struct Verdict: Codable, Sendable, Equatable {
    var relevant: Bool
    var confidence: Double
    var activity: String
    var reminder: String
}

struct CheckRecord: Identifiable, Equatable {
    enum Status { case onGoal, offGoal, away }
    let id = UUID()
    let date: Date
    let status: Status
    let appName: String
    let activity: String
}

/// Everything the judge needs to know about the goal.
struct GoalContext: Sendable {
    var goal: String
    var alsoRelevant: [String]
    var notRelevant: [String] = []
    var approved: [String]
}

struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var goal: String
    var start: Date
    var end: Date
    var focused: TimeInterval
    var onGoalRatio: Double?
    var nudges: Int
    /// Most frequent off-goal activities, e.g. "YouTube · Zen". Optional for older records.
    var distractions: [String]? = nil
}

/// User preferences, backed by UserDefaults so @AppStorage and the engine agree.
enum Prefs {
    static let checkInterval = "checkInterval"
    static let driftMinutes = "driftMinutes"
    static let useVision = "useVision"
    static let showMiniTimer = "showMiniTimer"
    static let playSounds = "playSounds"
    static let breakMinutes = "breakMinutes"
    static let defaultMinutes = "defaultMinutes"
    static let modelID = "modelID"
    static let onboarded = "onboarded"
    static let accentHex = "accentHex"
    static let customMinutes = "customMinutes"
    static let saveBattery = "saveBattery"
    static let tourAtPermissions = "tourAtPermissions"
    static let alsoRelevant = "alsoRelevantList"
    static let notRelevant = "notRelevantList"

    static let defaultModelID = "mlx-community/Qwen3.5-4B-4bit"

    /// Models Fokly knows, each pinned to an exact commit so the weights can't change underneath
    /// the user if the repository is updated. Any other ID typed in Settings follows "main".
    static let pinnedRevisions: [String: String] = [
        "mlx-community/Qwen3.5-4B-4bit": "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c",
        "mlx-community/Qwen3.5-2B-4bit": "674aaa7240b91e8012fcad5d791b7dfe5ba90207",
        "mlx-community/Qwen3.5-0.8B-4bit": "da28692b5f139cb0ec58a356b437486b7dac7462",
    ]

    static func register() {
        UserDefaults.standard.register(defaults: [
            checkInterval: 20.0,
            driftMinutes: 2.0,
            useVision: true,
            showMiniTimer: true,
            playSounds: true,
            breakMinutes: 5,
            defaultMinutes: 50,
            modelID: defaultModelID,
            onboarded: false,
            customMinutes: 45,
            saveBattery: true,
        ])
    }

    static var d: UserDefaults { .standard }
}
