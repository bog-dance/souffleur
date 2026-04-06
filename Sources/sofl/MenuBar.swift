import AppKit
import Combine
import Foundation

class MenuBarController {
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?

    init(stateManager: AppStateManager, onQuit: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⚪"

        let menu = NSMenu()
        menu.addItem(withTitle: "Souffleur v1.0.0", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)
        statusItem.menu = menu

        cancellable = stateManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.onStateChange(state)
            }
    }

    private func onStateChange(_ state: AppState) {
        switch state {
        case .idle:
            statusItem.button?.title = "⚪"
        case .loading:
            statusItem.button?.title = "🟡"
        case .recording:
            statusItem.button?.title = "🔴"
        case .processing:
            statusItem.button?.title = "⚡"
        case .done:
            statusItem.button?.title = "✅"
        }
    }
}
