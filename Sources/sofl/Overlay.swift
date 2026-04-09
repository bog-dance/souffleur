import AppKit
import Combine
import Foundation

class OverlayController {
    private var window: NSWindow?
    private var label: NSTextField?
    private var progressLabel: NSTextField?
    private var timer: Timer?
    private var loadingFrame = 0
    private var cancellables: Set<AnyCancellable> = []
    private var currentText = ""
    private var currentState: AppState = .idle

    private let bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"]
    private let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    init(stateManager: AppStateManager) {
        setupWindow()
        stateManager.$state
            .combineLatest(stateManager.$statusText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, text in
                guard let self = self else { return }
                let stateChanged = self.currentState != state
                self.currentText = text
                self.currentState = state
                if stateChanged {
                    self.onStateChange(state)
                }
            }
            .store(in: &cancellables)
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 180
        let height: CGFloat = 52
        let x = (screen.frame.width - width) / 2
        let y = screen.frame.height - 100

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.contentView?.wantsLayer = true
        win.contentView?.layer?.cornerRadius = 10
        win.contentView?.layer?.masksToBounds = true
        win.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor

        let textField = NSTextField(frame: NSRect(x: 0, y: 16, width: width, height: 28))
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.alignment = .center
        textField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textField.textColor = NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0)
        win.contentView?.addSubview(textField)

        let progField = NSTextField(frame: NSRect(x: 0, y: 2, width: width, height: 14))
        progField.isEditable = false
        progField.isBordered = false
        progField.backgroundColor = .clear
        progField.alignment = .center
        progField.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        progField.textColor = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        progField.stringValue = ""
        win.contentView?.addSubview(progField)

        window = win
        label = textField
        progressLabel = progField
    }

    private func onStateChange(_ state: AppState) {
        stopTimer()
        progressLabel?.stringValue = ""
        switch state {
        case .recording:
            startWaveAnimation()
        case .loading:
            startSpinnerAnimation("loading")
        case .processing:
            startSpinnerAnimation("transcribing")
        case .postprocessing:
            startSpinnerAnimation("postprocess")
        case .error:
            showError()
        case .done, .idle:
            hide()
        }
    }

    private func startWaveAnimation() {
        show()
        progressLabel?.stringValue = ""
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let wave = (0..<9).map { _ in self.bars.randomElement()! }.joined(separator: " ")
            self.label?.stringValue = wave
        }
    }

    private func startSpinnerAnimation(_ fallbackText: String) {
        show()
        loadingFrame = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let spinner = self.spinnerFrames[self.loadingFrame % self.spinnerFrames.count]
            self.label?.stringValue = "\(spinner)  \(fallbackText)  \(spinner)"
            self.progressLabel?.stringValue = self.currentText
            self.loadingFrame += 1
        }
    }

    private func showError() {
        show()
        label?.textColor = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        label?.stringValue = "⚠  error"
        progressLabel?.stringValue = currentText
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.label?.textColor = NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0)
        }
    }

    private func show() {
        window?.orderFront(nil)
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
