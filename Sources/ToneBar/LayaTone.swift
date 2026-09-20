import Foundation
import NaturalLanguage
import LayaKit

enum LayaToneState {
    case notLoaded
    case loading
    case ready
    case unavailable
    case failed(Error)
}

actor LayaTone {
    private var agent: LayaAgent?
    private(set) var state: LayaToneState = .notLoaded
    private var lastText: String?
    private var lastScore: Double?
    private var lastBreakdown: (positive: Int, neutral: Int, negative: Int)?

    func load() async {
        guard let bundle = Self.resolveBundleURL() else {
            state = .unavailable
            return
        }

        state = .loading
        do {
            agent = try await LayaAgent(bundle: bundle)
            state = .ready
        } catch {
            state = .failed(error)
        }
    }

    func score(for text: String) throws -> Double {
        if text == lastText, let cached = lastScore {
            return cached
        }

        guard let agent else {
            throw LayaToneError.notReady
        }

        let answer = try agent.predict(state: text, question: Self.question)
        let value = try toneScore(from: answer)

        if text != lastText {
            lastText = text
            lastBreakdown = nil
        }
        lastScore = value
        return value
    }

    func breakdown(for text: String) throws -> (positive: Int, neutral: Int, negative: Int) {
        if text == lastText, let cached = lastBreakdown {
            return cached
        }

        guard let agent else {
            throw LayaToneError.notReady
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !sentences.isEmpty else {
            let empty = (positive: 0, neutral: 0, negative: 0)
            if text != lastText {
                lastText = text
                lastScore = nil
            }
            lastBreakdown = empty
            return empty
        }

        var positive = 0
        var negative = 0
        var neutral = 0
        for sentence in sentences {
            let answer = try agent.predict(state: sentence, question: Self.question)
            let value = try toneScore(from: answer)
            switch toneBucket(forScore: value) {
            case .positive:
                positive += 1
            case .negative:
                negative += 1
            case .neutral:
                neutral += 1
            }
        }

        let total = Double(sentences.count)
        let result = (
            positive: Int((Double(positive) / total * 100).rounded()),
            neutral: Int((Double(neutral) / total * 100).rounded()),
            negative: Int((Double(negative) / total * 100).rounded())
        )

        if text != lastText {
            lastText = text
            lastScore = nil
        }
        lastBreakdown = result
        return result
    }

    private func toneScore(from answer: LayaAnswer) throws -> Double {
        guard let score = answer.score else {
            throw LayaToneError.missingScore
        }
        return score - 1
    }

    private static var question: LayaQuestion {
        LayaQuestion.score(
            instructions: "What is the emotional tone of this text?",
            levels: ["negative", "neutral", "positive"]
        )
    }

    private static func resolveBundleURL() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["TONEBAR_BUNDLE"] {
            let expandedPath = (envPath as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expandedPath)
            }
        }

        let defaultURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ToneBar/laya-bundle")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: defaultURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return defaultURL
        }

        return nil
    }
}

enum LayaToneError: Error {
    case notReady
    case missingScore
}
