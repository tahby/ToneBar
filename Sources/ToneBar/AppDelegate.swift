import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let systemWide = AXUIElementCreateSystemWide()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var summaryLabel: NSTextField!
    private var breakdownLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var quitMenu: NSMenu?
    private var pollTimer: Timer?
    private var isTrusted = false
    private var lastReadText: String?
    private let layaTone = LayaTone()
    private var layaState: LayaToneState = .notLoaded
    private var generation = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        buildPopover()

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit ToneBar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        quitMenu = menu

        isTrusted = AXIsProcessTrusted()
        if isTrusted {
            showCurrentLayaState()
        } else {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            showAccessibilityNeeded()
        }

        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        Task {
            await layaTone.load()
            layaState = await layaTone.state
            if isTrusted {
                lastReadText = nil
                showCurrentLayaState()
            }
        }
    }

    private func buildPopover() {
        summaryLabel = NSTextField(labelWithString: "")
        summaryLabel.font = NSFont.systemFont(ofSize: 24)

        breakdownLabel = NSTextField(labelWithString: "")
        breakdownLabel.font = NSFont.systemFont(ofSize: 12)

        detailLabel = NSTextField(wrappingLabelWithString: "")
        detailLabel.font = NSFont.systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 6

        let stack = NSStackView(views: [summaryLabel, breakdownLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 300),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let contentViewController = NSViewController()
        contentViewController.view = container

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = contentViewController
    }

    private func poll() {
        if !isTrusted {
            guard AXIsProcessTrusted() else { return }
            isTrusted = true
            showCurrentLayaState()
        }

        guard let text = focusedText(), text != lastReadText else { return }
        lastReadText = text
        show(text: text)
    }

    private func focusedText() -> String? {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedRef = focusedValue,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }

        let element = unsafeDowncast(focusedRef, to: AXUIElement.self)

        var elementPid: pid_t = 0
        guard AXUIElementGetPid(element, &elementPid) == .success,
              elementPid != ProcessInfo.processInfo.processIdentifier else { return nil }

        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success else { return nil }
        return textValue as? String
    }

    private func show(text: String) {
        generation += 1
        let currentGeneration = generation

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            statusItem.button?.title = "😐"
            summaryLabel.stringValue = "😐"
            showBreakdown(positive: 0, neutral: 0, negative: 0)
            detailLabel.stringValue = "The focused text field is empty."
            return
        }

        guard case .ready = layaState else {
            showCurrentLayaState()
            return
        }

        let collapsed = trimmed.split(whereSeparator: \.isNewline).joined(separator: " ")
        let preview = collapsed.count > 180 ? String(collapsed.prefix(180)) + "…" : collapsed

        Task {
            guard let score = try? await layaTone.score(for: text) else {
                if currentGeneration == generation { showScoringFailed() }
                return
            }
            guard currentGeneration == generation else { return }

            guard let breakdown = try? await layaTone.breakdown(for: text) else {
                if currentGeneration == generation { showScoringFailed() }
                return
            }
            guard currentGeneration == generation else { return }

            let emoji = NLTone.emoji(forScore: score)
            statusItem.button?.title = emoji
            summaryLabel.stringValue = "\(emoji)  \(String(format: "%.2f", score))"
            showBreakdown(positive: breakdown.positive, neutral: breakdown.neutral, negative: breakdown.negative)
            detailLabel.stringValue = preview
        }
    }

    private func showBreakdown(positive: Int, neutral: Int, negative: Int) {
        breakdownLabel.stringValue = "Positive: \(positive)%   Neutral: \(neutral)%   Negative: \(negative)%"
    }

    private func showWaitingForText() {
        statusItem.button?.title = "😐"
        summaryLabel.stringValue = "😐"
        showBreakdown(positive: 0, neutral: 0, negative: 0)
        detailLabel.stringValue = "Waiting for text. Type in any app and the tone of the focused text field appears here."
    }

    private func showLoadingModel() {
        statusItem.button?.title = "⏳"
        summaryLabel.stringValue = "⏳"
        showBreakdown(positive: 0, neutral: 0, negative: 0)
        detailLabel.stringValue = "Loading LayaKit model…"
    }

    private func showNoBundleConfigured() {
        statusItem.button?.title = "⏳"
        summaryLabel.stringValue = "⏳"
        showBreakdown(positive: 0, neutral: 0, negative: 0)
        detailLabel.stringValue = "No LayaKit bundle found. Run: hf download aac6fef/laya-multilingual-coreml --local-dir ~/\"Library/Application Support/ToneBar/laya-bundle\""
    }

    private func showModelFailed(_ error: Error) {
        statusItem.button?.title = "⚠️"
        summaryLabel.stringValue = "⚠️"
        showBreakdown(positive: 0, neutral: 0, negative: 0)
        detailLabel.stringValue = "LayaKit model failed to load: \(error.localizedDescription)"
    }

    private func showScoringFailed() {
        statusItem.button?.title = "⚠️"
        summaryLabel.stringValue = "⚠️"
        showBreakdown(positive: 0, neutral: 0, negative: 0)
        detailLabel.stringValue = "LayaKit couldn't score this text."
    }

    private func showCurrentLayaState() {
        switch layaState {
        case .ready:
            showWaitingForText()
        case .unavailable:
            showNoBundleConfigured()
        case .failed(let error):
            showModelFailed(error)
        case .notLoaded, .loading:
            showLoadingModel()
        }
    }

    private func showAccessibilityNeeded() {
        statusItem.button?.title = "🔒"
        summaryLabel.stringValue = "🔒"
        showBreakdown(positive: 0, neutral: 0, negative: 0)
        detailLabel.stringValue = "ToneBar needs Accessibility access to read the focused text field. Grant it in System Settings › Privacy & Security › Accessibility, then tone updates start automatically."
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            if let menu = quitMenu {
                statusItem.menu = menu
                statusItem.button?.performClick(nil)
                statusItem.menu = nil
            }
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
