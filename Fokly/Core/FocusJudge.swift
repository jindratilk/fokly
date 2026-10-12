import CoreImage
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Observation
import Tokenizers

/// Runs the local multimodal model. One instance, kept warm during a session.
actor FocusJudge {
    private var container: ModelContainer?
    private var loadedID: String?
    /// Bumped by every unload; a load that started before it is thrown away when it lands.
    private var generation = 0
    /// At most one load in flight. Callers arriving meanwhile wait for it instead of starting
    /// another (actor methods re-enter at `await`, so without this, quick start/finish cycles
    /// stacked up several 3 GB copies).
    private var inFlight: (id: String, serial: Int, task: Task<ModelContainer, Error>)?
    private var serial = 0

    var isLoaded: Bool { container != nil }

    /// Keep MLX's reusable-buffer cache small; between checks it otherwise holds GBs.
    static func configureMemory() {
        Memory.cacheLimit = 256 * 1024 * 1024
    }

    func load(id: String, progress: @Sendable @escaping (Double) -> Void) async throws {
        if container != nil, loadedID == id { return }
        let myGeneration = generation
        let flight: (id: String, serial: Int, task: Task<ModelContainer, Error>)
        if let current = inFlight, current.id == id {
            flight = current
        } else {
            serial += 1
            let configuration = ModelConfiguration(
                id: id, revision: Prefs.pinnedRevisions[id] ?? "main", extraEOSTokens: ["<|im_end|>"])
            flight = (id, serial, Task {
                try await VLMModelFactory.shared.loadContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: configuration,
                    progressHandler: { progress($0.fractionCompleted) }
                )
            })
            inFlight = flight
        }
        defer { if inFlight?.serial == flight.serial { inFlight = nil } }
        let loaded = try await flight.task.value
        // Unloaded while we waited: drop these weights instead of keeping them around.
        guard myGeneration == generation else { throw CancellationError() }
        container = loaded
        loadedID = id
    }

    func unload() {
        generation += 1
        container = nil
        loadedID = nil
        Memory.clearCache()
    }

    func judge(_ obs: ScreenSnapshot, context: GoalContext) async throws -> Verdict {
        guard let container else { throw JudgeError.notLoaded }

        let session = ChatSession(
            container,
            instructions: Self.instructions,
            generateParameters: GenerateParameters(maxTokens: 160, temperature: 0.1),
            processing: UserInput.Processing(maxPixels: 640 * 640),
            additionalContext: ["enable_thinking": false]
        )
        let raw = try await session.respond(
            to: Self.prompt(obs, context),
            image: obs.image.map { UserInput.Image.ciImage($0) }
        )
        return try Self.parse(raw)
    }

    // MARK: - Prompting

    static let instructions = """
        You are Fokly, an on-device focus companion. The user set a goal for this focus session \
        (it may be written in any language). You see their active app, the window title, text from \
        the screen and maybe a screenshot. Decide whether what is on screen right now is work on that goal.

        How to decide:
        1. First work out the topic of the screen: what is this page, file, chat or video actually about?
        2. Relevant: the topic is the goal itself, or a tool, file, code, task list, chat or reference \
        that clearly serves the goal. Anything on the user's "also relevant" list is relevant.
        3. Not relevant: the topic has nothing to do with the goal. Games, sports, videos, social feeds, \
        news, shopping, personal chats and other projects are not relevant. Reading or "research" about \
        an unrelated topic is not relevant either. Anything on the "does not count" list is never relevant.
        4. Only when the screen shows no real content (an empty window, the desktop, a file list) \
        give the benefit of the doubt and call it relevant.

        Examples:
        Goal "Write the Q3 sales report" · Excel "Q3 revenue by region" → relevant
        Goal "Write the Q3 sales report" · YouTube "F1 race highlights" → not relevant
        Goal "Fix the checkout bug" · Wikipedia "Counter-Strike 2" → not relevant
        Goal "Fix the checkout bug" · ChatGPT chat about the checkout error → relevant
        Goal "Finish the online store" · BBC News homepage → not relevant

        Reply with JSON only, no prose:
        {"activity": "<what they are doing and its topic, max 8 words>", "relevant": true|false, \
        "confidence": 0.0-1.0, "reminder": "<if not relevant: one warm, specific sentence (max 22 words) \
        naming what they are doing and pointing back to the goal; otherwise empty>"}
        """

    static func prompt(_ obs: ScreenSnapshot, _ ctx: GoalContext) -> String {
        var p = "Goal: \(ctx.goal)\n"
        if !ctx.alsoRelevant.isEmpty { p += "Also relevant: \(ctx.alsoRelevant.joined(separator: "; "))\n" }
        if !ctx.notRelevant.isEmpty { p += "Does not count (never relevant): \(ctx.notRelevant.joined(separator: "; "))\n" }
        if !ctx.approved.isEmpty { p += "User approved as relevant: \(ctx.approved.joined(separator: "; "))\n" }
        p += "\nActive app: \(obs.appName)\n"
        if !obs.windowTitle.isEmpty { p += "Window title: \(obs.windowTitle)\n" }
        if !obs.text.isEmpty { p += "Text on screen (OCR, partial):\n\(obs.text.prefix(1500))\n" }
        if obs.image != nil { p += "\nA screenshot of the active window is attached." }
        return p
    }

    /// Keep what the model writes to one short line, so it always fits the reminder.
    static func clean(_ v: Verdict) -> Verdict {
        func tidy(_ s: String, max: Int) -> String {
            let t = s.components(separatedBy: .newlines).joined(separator: " ")
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return t.count > max ? String(t.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…" : t
        }
        return Verdict(relevant: v.relevant, confidence: min(1, max(0, v.confidence)),
                       activity: tidy(v.activity, max: 60), reminder: tidy(v.reminder, max: 180))
    }

    static func parse(_ raw: String) throws -> Verdict {
        var text = raw
        if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw JudgeError.unparseable(raw)
        }
        let json = Data(text[start...end].utf8)
        if let v = try? JSONDecoder().decode(Verdict.self, from: json) { return clean(v) }

        // Be forgiving with small models: pull the fields out by hand.
        let obj = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
        let relevant = (obj["relevant"] as? Bool) ?? !text.contains("\"relevant\": false")
        return clean(Verdict(
            relevant: relevant,
            confidence: (obj["confidence"] as? Double) ?? 0.6,
            activity: (obj["activity"] as? String) ?? "",
            reminder: (obj["reminder"] as? String) ?? ""
        ))
    }

    enum JudgeError: LocalizedError {
        case notLoaded, unparseable(String)
        var errorDescription: String? {
            switch self {
            case .notLoaded: "The model isn't loaded yet."
            case .unparseable: "The model replied in an unexpected format."
            }
        }
    }
}

/// Main-actor face of the judge, for the UI.
@MainActor @Observable
final class ModelManager {
    enum State: Equatable {
        case idle, downloading(Double), loading, ready, failed(String)
    }

    private(set) var state: State = .idle
    private let judge = FocusJudge()
    private var loadTask: Task<Void, Never>?
    /// Bumped by unload; late results from an older prepare() are ignored.
    private var generation = 0

    var isReady: Bool { state == .ready }

    var modelName: String {
        let id = Prefs.d.string(forKey: Prefs.modelID) ?? Prefs.defaultModelID
        let name = id.split(separator: "/").last.map(String.init) ?? id
        return name.replacingOccurrences(of: #"-(\d+bit|bf16|fp16|MLX)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "-", with: " ")
    }

    /// Whether the weights are already in the local Hugging Face cache.
    var isDownloaded: Bool {
        let id = Prefs.d.string(forKey: Prefs.modelID) ?? Prefs.defaultModelID
        let snapshots = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(id.replacingOccurrences(of: "/", with: "--"))/snapshots")
        guard let revs = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else { return false }
        return revs.contains { rev in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: snapshots.appendingPathComponent(rev).path)) ?? []
            return files.contains { $0.hasSuffix(".safetensors") }
        }
    }

    func prepare() {
        guard loadTask == nil, state != .ready else { return }
        let id = Prefs.d.string(forKey: Prefs.modelID) ?? Prefs.defaultModelID
        state = .downloading(0)
        let gen = generation
        loadTask = Task {
            do {
                try await judge.load(id: id) { fraction in
                    Task { @MainActor in
                        // Progress can arrive after the load finished; never step back from .ready.
                        guard self.generation == gen, self.loadTask != nil else { return }
                        self.state = fraction < 0.999 ? .downloading(fraction) : .loading
                    }
                }
                guard gen == generation else { return }
                state = .ready
            } catch {
                guard gen == generation else { return }
                state = .failed(Self.friendly(error, id: id))
            }
            loadTask = nil
        }
    }

    /// Download and network failures surface as opaque client errors; say what to check instead.
    private static func friendly(_ error: Error, id: String) -> String {
        let raw = String(describing: error)
        if error is URLError || raw.contains("HTTPClientError") || raw.contains("NSURLErrorDomain") {
            return "Couldn't download “\(id)”. Check the name in Settings → Local Model, or your connection."
        }
        return error.localizedDescription
    }

    func unload() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        state = .idle
        Task { await judge.unload() }
    }

    func judge(_ obs: ScreenSnapshot, context: GoalContext) async throws -> Verdict {
        try await judge.judge(obs, context: context)
    }
}
