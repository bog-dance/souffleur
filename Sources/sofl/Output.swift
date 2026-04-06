import AppKit
import CoreGraphics
import Foundation

enum Output {
    private static let vkReturn: CGKeyCode = 36
    private static let vkV: CGKeyCode = 9

    static func outputText(_ text: String, config: OutputConfig) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        guard config.autoPaste else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulateCmdV()

            if config.autoEnter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    simulateReturn()
                }
            }
        }
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vkV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vkV, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private static func simulateReturn() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vkReturn, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vkReturn, keyDown: false) else { return }

        keyDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
