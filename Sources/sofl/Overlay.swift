import AppKit
import Combine
import Foundation

class OverlayController {
    private var window: NSWindow?
    private var label: NSTextField?
    private var timer: Timer?
    private var loadingFrame = 0
    private var cancellable: AnyCancellable?

    private let bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"]
    private let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    init(stateManager: AppStateManager) {
        setupWindow()
        cancellable = stateManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.onStateChange(state)
            }
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 180
        let height: CGFloat = 36
        let x = (screen.frame.width - width) / 2
        let y = screen.frame.height - 100

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        win.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.contentView?.wantsLayer = true
        win.contentView?.layer?.cornerRadius = 14

        let textField = NSTextField(frame: NSRect(x: 0, y: 4, width: width, height: height - 8))
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.alignment = .center
        textField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textField.textColor = NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0)
        win.contentView?.addSubview(textField)

        window = win
        label = textField
    }

    private func onStateChange(_ state: AppState) {
        stopTimer()
        switch state {
        case .recording:
            startWaveAnimation()
        case .loading:
            startLoadingAnimation()
        case .processing:
            startProcessingAnimation()
        case .done, .idle:
            hide()
        }
    }

    private func startWaveAnimation() {
        show()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let wave = (0..<9).map { _ in self.bars.randomElement()! }.joined(separator: " ")
            self.label?.stringValue = wave
        }
    }

    private func startProcessingAnimation() {
        show()
        loadingFrame = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let spinner = self.spinnerFrames[self.loadingFrame % self.spinnerFrames.count]
            self.label?.stringValue = "\(spinner)  transcribing  \(spinner)"
            self.loadingFrame += 1
        }
    }

    private func startLoadingAnimation() {
        show()
        loadingFrame = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let spinner = self.spinnerFrames[self.loadingFrame % self.spinnerFrames.count]
            self.label?.stringValue = "\(spinner)  loading model  \(spinner)"
            self.loadingFrame += 1
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
