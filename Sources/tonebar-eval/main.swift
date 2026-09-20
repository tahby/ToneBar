import Foundation
import NaturalLanguage
import LayaKit

struct Example {
    let text: String
    let label: String
    let lang: String?
}

struct ScoredItem {
    let text: String
    let label: String
    let lang: String?
    let nlScore: Double
    let laScore: Double?
    let laProbabilities: [Double]?
}

func nlToneScore(for text: String) -> Double {
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

func bucketLabel(_ score: Double) -> String {
    if score >= 0.2 {
        return "positive"
    } else if score <= -0.2 {
        return "negative"
    } else {
        return "neutral"
    }
}

enum EvalError: Error {
    case missingScore
}

func layaPredict(_ agent: LayaAgent, _ text: String) throws -> LayaAnswer {
    let question = LayaQuestion.score(
        instructions: "What is the emotional tone of this text?",
        levels: ["negative", "neutral", "positive"]
    )
    return try agent.predict(state: text, question: question)
}

func layaScore(_ agent: LayaAgent, _ text: String) throws -> Double {
    let answer = try layaPredict(agent, text)
    guard let score = answer.score else {
        throw EvalError.missingScore
    }
    return score - 1
}

func layaArgmaxLabel(_ probabilities: [Double]) -> String {
    let labels = ["negative", "neutral", "positive"]
    var bestIdx = 0
    for i in 1..<probabilities.count where probabilities[i] > probabilities[bestIdx] {
        bestIdx = i
    }
    return labels[bestIdx]
}

func loadTSV(_ url: URL, labelIsNumeric: Bool, hasLang: Bool) throws -> [Example] {
    let content = try String(contentsOf: url, encoding: .utf8)
    var lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    guard !lines.isEmpty else { return [] }
    lines.removeFirst()

    var examples: [Example] = []
    for line in lines {
        let maxSplits = hasLang ? 2 : 1
        let expectedCount = hasLang ? 3 : 2
        let parts = line.split(separator: "\t", maxSplits: maxSplits, omittingEmptySubsequences: false)
        guard parts.count == expectedCount else { continue }
        let text = String(parts[0])
        let rawLabel = String(parts[1])
        let label = labelIsNumeric ? (rawLabel == "1" ? "positive" : "negative") : rawLabel
        let lang = hasLang ? String(parts[2]) : nil
        examples.append(Example(text: text, label: label, lang: lang))
    }
    return examples
}

func scoreAll(_ examples: [Example], agent: LayaAgent) throws -> (items: [ScoredItem], skipped: Int) {
    var items: [ScoredItem] = []
    var skipped = 0
    for example in examples {
        let nlScore = nlToneScore(for: example.text)
        var laScore: Double?
        var laProbabilities: [Double]?
        do {
            let answer = try layaPredict(agent, example.text)
            guard let score = answer.score else {
                throw EvalError.missingScore
            }
            laScore = score - 1
            laProbabilities = answer.probabilities
        } catch LayaError.tooManyTokens {
            skipped += 1
        }
        items.append(ScoredItem(text: example.text, label: example.label, lang: example.lang, nlScore: nlScore, laScore: laScore, laProbabilities: laProbabilities))
    }
    return (items, skipped)
}

func binaryMetrics(_ items: [ScoredItem], scoreFn: (ScoredItem) -> Double) -> (accuracy: Double, macroF1: Double, n: Int) {
    var tp = 0, tn = 0, fp = 0, fn = 0
    var correct = 0
    for item in items {
        let predicted = scoreFn(item) > 0 ? "positive" : "negative"
        if predicted == item.label { correct += 1 }
        switch (predicted, item.label) {
        case ("positive", "positive"): tp += 1
        case ("negative", "negative"): tn += 1
        case ("positive", "negative"): fp += 1
        case ("negative", "positive"): fn += 1
        default: break
        }
    }
    let precisionPos = tp + fp > 0 ? Double(tp) / Double(tp + fp) : 0
    let recallPos = tp + fn > 0 ? Double(tp) / Double(tp + fn) : 0
    let f1Pos = precisionPos + recallPos > 0 ? 2 * precisionPos * recallPos / (precisionPos + recallPos) : 0
    let precisionNeg = tn + fn > 0 ? Double(tn) / Double(tn + fn) : 0
    let recallNeg = tn + fp > 0 ? Double(tn) / Double(tn + fp) : 0
    let f1Neg = precisionNeg + recallNeg > 0 ? 2 * precisionNeg * recallNeg / (precisionNeg + recallNeg) : 0
    let macroF1 = (f1Pos + f1Neg) / 2
    return (items.isEmpty ? 0 : Double(correct) / Double(items.count), macroF1, items.count)
}

func threeClassMetricsByLabel(_ items: [ScoredItem], predictFn: (ScoredItem) -> String) -> (accuracy: Double, confusion: [[Int]], n: Int) {
    let labels = ["negative", "neutral", "positive"]
    var confusion = Array(repeating: Array(repeating: 0, count: 3), count: 3)
    var correct = 0
    for item in items {
        guard let truthIdx = labels.firstIndex(of: item.label) else {
            FileHandle.standardError.write("Warning: skipping item with unrecognized label '\(item.label)'\n".data(using: .utf8)!)
            continue
        }
        let predicted = predictFn(item)
        let predIdx = labels.firstIndex(of: predicted)!
        confusion[truthIdx][predIdx] += 1
        if predicted == item.label { correct += 1 }
    }
    return (items.isEmpty ? 0 : Double(correct) / Double(items.count), confusion, items.count)
}

func threeClassMetrics(_ items: [ScoredItem], scoreFn: (ScoredItem) -> Double) -> (accuracy: Double, confusion: [[Int]], n: Int) {
    threeClassMetricsByLabel(items) { bucketLabel(scoreFn($0)) }
}

func agreementRate(_ items: [ScoredItem], nlBucket: (Double) -> String, laBucket: (Double) -> String) -> (rate: Double, n: Int) {
    let usable = items.filter { $0.laScore != nil }
    guard !usable.isEmpty else { return (0, 0) }
    let matches = usable.filter { nlBucket($0.nlScore) == laBucket($0.laScore!) }.count
    return (Double(matches) / Double(usable.count), usable.count)
}

func p50Millis(_ durations: [Double]) -> Double {
    let sorted = durations.sorted()
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[mid - 1] + sorted[mid]) / 2
    } else {
        return sorted[mid]
    }
}

func measureNLLatency(_ examples: [Example]) -> Double {
    _ = nlToneScore(for: examples[0].text)
    var durations: [Double] = []
    for example in examples {
        let start = DispatchTime.now()
        _ = nlToneScore(for: example.text)
        let end = DispatchTime.now()
        durations.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
    return p50Millis(durations)
}

func measureLayaLatency(_ examples: [Example], agent: LayaAgent) throws -> Double {
    _ = try? layaScore(agent, examples[0].text)
    var durations: [Double] = []
    for example in examples {
        let start = DispatchTime.now()
        do {
            _ = try layaScore(agent, example.text)
        } catch LayaError.tooManyTokens {
            continue
        }
        let end = DispatchTime.now()
        durations.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
    return p50Millis(durations)
}

func shell(_ launchPath: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
    } catch {
        return "unknown"
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    return output.isEmpty ? "unknown" : output
}

guard let rawBundlePath = ProcessInfo.processInfo.environment["TONEBAR_BUNDLE"] else {
    FileHandle.standardError.write("Error: TONEBAR_BUNDLE environment variable is required.\n".data(using: .utf8)!)
    exit(1)
}
let bundlePath = (rawBundlePath as NSString).expandingTildeInPath
let bundleURL = URL(fileURLWithPath: bundlePath)
let bundleKind = bundlePath.lowercased().contains("ane") ? "ANE" : "General"

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let evalDir = packageRoot.appendingPathComponent("eval")

let sst2 = try loadTSV(evalDir.appendingPathComponent("sst2_validation.tsv"), labelIsNumeric: true, hasLang: false)
let handset = try loadTSV(evalDir.appendingPathComponent("handset.tsv"), labelIsNumeric: false, hasLang: true)
let nonEnglish = handset.filter { $0.lang != "en" }

let agent = try await LayaAgent(bundle: bundleURL)

let (sst2Items, sst2Skipped) = try scoreAll(sst2, agent: agent)
let (handsetItems, handsetSkipped) = try scoreAll(handset, agent: agent)
let nonEnglishItems = handsetItems.filter { $0.lang != "en" }

let nlSST2 = binaryMetrics(sst2Items) { $0.nlScore }
let laSST2Items = sst2Items.filter { $0.laScore != nil }
let laSST2 = binaryMetrics(laSST2Items) { $0.laScore! }

let nlHandset = threeClassMetrics(handsetItems) { $0.nlScore }
let laHandsetItems = handsetItems.filter { $0.laScore != nil }
let laHandset = threeClassMetrics(laHandsetItems) { $0.laScore! }
let laHandsetArgmaxItems = handsetItems.filter { $0.laProbabilities != nil }
let laHandsetArgmax = threeClassMetricsByLabel(laHandsetArgmaxItems) { layaArgmaxLabel($0.laProbabilities!) }

let nlNonEnglish = threeClassMetrics(nonEnglishItems) { $0.nlScore }
let laNonEnglishItems = nonEnglishItems.filter { $0.laScore != nil }
let laNonEnglish = threeClassMetrics(laNonEnglishItems) { $0.laScore! }

let sst2Agreement = agreementRate(sst2Items,
    nlBucket: { $0 > 0 ? "positive" : "negative" },
    laBucket: { $0 > 0 ? "positive" : "negative" })
let handsetAgreement = agreementRate(handsetItems, nlBucket: bucketLabel, laBucket: bucketLabel)

let nlLatency = measureNLLatency(handset)
let laLatency = try measureLayaLatency(handset, agent: agent)

let disagreements = handsetItems
    .filter { $0.laScore != nil }
    .sorted { abs($0.nlScore - $0.laScore!) > abs($1.nlScore - $1.laScore!) }
    .prefix(10)

let cpuBrand = shell("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd"
let todayString = dateFormatter.string(from: Date())

func pct(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

func ms(_ value: Double) -> String {
    String(format: "%.2f ms", value)
}

func confusionTable(_ confusion: [[Int]]) -> String {
    let labels = ["negative", "neutral", "positive"]
    var lines = "| true \\ pred | negative | neutral | positive |\n"
    lines += "|---|---|---|---|\n"
    for (row, label) in labels.enumerated() {
        lines += "| \(label) | \(confusion[row][0]) | \(confusion[row][1]) | \(confusion[row][2]) |\n"
    }
    return lines
}

var report = "# ToneBar Eval Results\n\n"
report += "- Machine: \(cpuBrand)\n"
report += "- macOS: \(macOSVersion)\n"
report += "- Bundle: \(bundlePath) (\(bundleKind))\n"
report += "- Date: \(todayString)\n"
report += "- SST-2 dataset size: \(sst2.count) (Laya skipped: \(sst2Skipped))\n"
report += "- Handset dataset size: \(handset.count), non-English subset: \(nonEnglish.count) (Laya skipped: \(handsetSkipped))\n"
report += "- Latency batch: \(handset.count) handset items\n\n"

var laSST2Rows = ["| LayaKit (\(bundleKind)) | \(laSST2.n) | \(pct(laSST2.accuracy)) | \(pct(laSST2.macroF1)) |"]
if let previousReport = try? String(contentsOf: evalDir.appendingPathComponent("RESULTS.md"), encoding: .utf8) {
    for line in previousReport.split(separator: "\n", omittingEmptySubsequences: true) {
        if (line.hasPrefix("| LayaKit (General)") || line.hasPrefix("| LayaKit (ANE)")) && !line.contains("(\(bundleKind))") {
            laSST2Rows.append(String(line))
        }
    }
}

report += "## SST-2 (binary, threshold 0)\n\n"
report += "| scorer | n | accuracy | macro-F1 |\n"
report += "|---|---|---|---|\n"
report += "| NLTone | \(nlSST2.n) | \(pct(nlSST2.accuracy)) | \(pct(nlSST2.macroF1)) |\n"
for row in laSST2Rows {
    report += "\(row)\n"
}
report += "\n"

report += "## Handset (3-class, ±0.2 thresholds)\n\n"
report += "| scorer | n | accuracy |\n"
report += "|---|---|---|\n"
report += "| NLTone | \(nlHandset.n) | \(pct(nlHandset.accuracy)) |\n"
report += "| LayaKit | \(laHandset.n) | \(pct(laHandset.accuracy)) |\n"
report += "| LayaKit (argmax) | \(laHandsetArgmax.n) | \(pct(laHandsetArgmax.accuracy)) |\n\n"

report += "### NLTone confusion matrix\n\n" + confusionTable(nlHandset.confusion) + "\n"
report += "### LayaKit confusion matrix\n\n" + confusionTable(laHandset.confusion) + "\n"
report += "### LayaKit (argmax) confusion matrix\n\n" + confusionTable(laHandsetArgmax.confusion) + "\n"

report += "## Non-English subset (10 items, 3-class)\n\n"
report += "| scorer | n | accuracy |\n"
report += "|---|---|---|\n"
report += "| NLTone | \(nlNonEnglish.n) | \(pct(nlNonEnglish.accuracy)) |\n"
report += "| LayaKit | \(laNonEnglish.n) | \(pct(laNonEnglish.accuracy)) |\n\n"

report += "## Agreement between NLTone and LayaKit\n\n"
report += "| dataset | n | agreement |\n"
report += "|---|---|---|\n"
report += "| SST-2 (2-class) | \(sst2Agreement.n) | \(pct(sst2Agreement.rate)) |\n"
report += "| Handset (3-class) | \(handsetAgreement.n) | \(pct(handsetAgreement.rate)) |\n\n"

report += "## Latency (p50, 1 warm-up call discarded)\n\n"
report += "| scorer | p50 |\n"
report += "|---|---|\n"
report += "| NLTone | \(ms(nlLatency)) |\n"
report += "| LayaKit | \(ms(laLatency)) |\n\n"

report += "## Top 10 handset disagreements (by |score difference|)\n\n"
report += "| text | true label | NLTone score | LayaKit score |\n"
report += "|---|---|---|---|\n"
for item in disagreements {
    let text = item.text.replacingOccurrences(of: "|", with: "\\|")
    report += "| \(text) | \(item.label) | \(String(format: "%.3f", item.nlScore)) | \(String(format: "%.3f", item.laScore!)) |\n"
}

print(report)
try report.write(to: evalDir.appendingPathComponent("RESULTS.md"), atomically: true, encoding: .utf8)
