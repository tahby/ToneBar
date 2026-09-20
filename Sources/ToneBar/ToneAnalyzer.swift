import Foundation
import NaturalLanguage

enum ToneAnalyzer {
    static func emoji(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "😐"
        }
        return emoji(forScore: score(for: text))
    }

    static func score(for text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        let tags = tagger.tags(in: fullRange, unit: .paragraph, scheme: .sentimentScore)

        var total = 0.0
        var count = 0
        for (tag, _) in tags {
            if let value = tag.flatMap({ Double($0.rawValue) }) {
                total += value
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0.0
    }

    static func emoji(forScore score: Double) -> String {
        if score.isNaN {
            return "😐"
        } else if score <= -0.6 {
            return "😡"
        } else if score <= -0.2 {
            return "🙁"
        } else if score < 0.2 {
            return "😐"
        } else if score < 0.6 {
            return "🙂"
        } else {
            return "😄"
        }
    }

    static func breakdown(for text: String) -> (positive: Int, neutral: Int, negative: Int) {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !sentences.isEmpty else {
            return (0, 0, 0)
        }

        var positive = 0
        var negative = 0
        var neutral = 0
        for sentence in sentences {
            let value = score(for: sentence)
            if value >= 0.2 {
                positive += 1
            } else if value <= -0.2 {
                negative += 1
            } else {
                neutral += 1
            }
        }

        let total = Double(sentences.count)
        return (
            positive: Int((Double(positive) / total * 100).rounded()),
            neutral: Int((Double(neutral) / total * 100).rounded()),
            negative: Int((Double(negative) / total * 100).rounded())
        )
    }
}
