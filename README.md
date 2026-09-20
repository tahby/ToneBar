# ToneBar

A tiny macOS menu bar app that shows an emoji reflecting the sentiment of whatever text you are typing right now — in any app — using [LayaKit](https://github.com/tahby/LayaKit) for on-device sentiment scoring (no network, no API keys).

ToneBar polls the system-wide focused UI element via the macOS Accessibility API a few times a second, reads its text value, scores it, and updates the status bar emoji. When the focused element doesn't expose readable text (a button, a canvas, a web view that hides its value), the last emoji stays put rather than flickering back to neutral.

## Requirements

- macOS 15+
- Apple silicon
- Xcode with Swift 6 toolchain

## Download the LayaKit model bundle

LayaKit needs a model bundle on disk. Download it with the Hugging Face CLI:

```
hf download aac6fef/laya-multilingual-coreml --local-dir ~/"Library/Application Support/ToneBar/laya-bundle"
```

ToneBar looks for a bundle in that default location. Set the `TONEBAR_BUNDLE` environment variable to point at a different bundle instead, e.g. for testing against LayaKit's own bundle:

```
TONEBAR_BUNDLE=/path/to/LayaKit/models/general swift run
```

On first launch, loading and warming the LayaKit model takes about 2-3 seconds; the status item shows ⏳ with "Loading LayaKit model…" during that time. If no bundle is found at all, the status item shows ⏳ with instructions for the `hf download` command above.

## Accessibility permission

Reading the focused text field in other apps requires Accessibility access. On first launch ToneBar prompts for it; grant it in **System Settings › Privacy & Security › Accessibility**. Until then the status item shows 🔒 and the popover explains what's missing. ToneBar picks up the permission automatically once granted — no restart needed.

**Caveat for `swift run`:** this package builds a bare executable with no app bundle or code-signing identity, so macOS cannot attribute the permission to "ToneBar". It attributes it to the parent process instead — the terminal app you ran `swift run` from (Terminal, iTerm2, Ghostty, VS Code, or the editor hosting the run). You therefore have to grant Accessibility access to *that* terminal app, which gives it, and everything else launched from it, the same access. If you'd rather not do that, wrap the binary in a proper signed `.app` bundle and grant the permission to the bundle.

## Run

```
swift run
```

Then type in Mail, Notes, Messages, a browser — anywhere. The status bar emoji tracks the tone of the focused field. Click the emoji to open a read-only popover showing the sentiment score and a preview of the text currently being analyzed.

## Quit

Right-click (or control-click) the status item and choose "Quit ToneBar" — there's no Dock icon since this is a menu bar-only app.

## NaturalLanguage

Apple's NaturalLanguage framework is still used internally, as the `NLTone` enum in `Sources/ToneBar/ToneAnalyzer.swift`, though it no longer drives the main menu bar display. It's kept around for a future evaluation tool that compares it against LayaKit.

## License

MIT. See `LICENSE`.
