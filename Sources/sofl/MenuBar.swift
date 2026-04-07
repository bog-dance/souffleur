import AppKit
import Combine
import Foundation

class MenuBarController {
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?

    private static func makeIcon() -> NSImage? {
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkEAQAAAAbmYxQAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAACYktHRAAAqo0jMgAAAAd0SU1FB+oEBwMoH8FPETsAAAAldEVYdGRhdGU6Y3JlYXRlADIwMjYtMDQtMDdUMDM6NDA6MzErMDA6MDBPF9r+AAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI2LTA0LTA3VDAzOjQwOjMxKzAwOjAwPkpiQgAAACh0RVh0ZGF0ZTp0aW1lc3RhbXAAMjAyNi0wNC0wN1QwMzo0MDozMSswMDowMGlfQ50AAAP9SURBVFjD7ZdvTFV1GMc/917g8i9cjGQoYUptEc7ciLZqzcSSKS4VKV2tLddGWa3li5rDubnRfJVrlRu2NqxWW5lEBEIx0f75ophQrdaaOoeCEIaLP5d7gXvvtxfnwP3D5XLPvRi96Nnufuf3O895zud+n+f3nHNsksR/yOyLDfA/EIB3H1Abm2+S5ejXgezQpalDMO6EkU9gqBL+3A39ZdB7O/SehEc+gB1rbhRQNly8D75Ogd4O6FsHV3tgoAuGvDA8Bq5BmHQBX0D5CXigGhiKMb7isBqbBPP/SgekC/ebFw3HFttyDXk3wK8tURyyjKFwKxyph8KzgCewvuAKDX4lFb83hyoZxpjTJDVvjkd7yTJQd5uUfVcEmCRjTL8ivfuohYBToVPLRX1hxCjc2bkEWz8854MdD8LIeVADqBjkBA4DHaBd4CsB/1rIKoC0wtAw0YEawe8B/wHwTYDeh5/Oge9yZHf7LdB+DL7/FPxdoGHwbzMg/MfA1w2OJlhZBFv+gG3HIa0uNIZNCn2WtTRAx73gyQT33TD+Mri/A/cd4OmB88/AYHkEmiRDpbksORdKTsLON2BLNaxqAPub5jXBsgTnz/229PDBGLb0kinnkkLnS7dKT3wkNT8t/d0WVj++2SUVkrKeSfitKOyvZQLhNTM8hwxZwAjYD0HRVdj+AlStgdWd4OgzffwEHlgRmo4BJMAG51Jh4ENIqYSqh+CHMbhYA2QALqKbCZO7Fw7YofItyLMBk+b56dTM1/mC5Xr2eYn1Us1KaaJMOrVeWuE15c+MkqabjDGvVfrs1bAc+OPsQ3+1SaW/S6+clTwVAYf2DKng49AbR2qG+cel5pqgyF6rHS4M6Mde6bUBaXy60MYCTm2d0q1VEaDSjHFFp/Tl49GL1TLQtRcl1y/mxDVb7tY9Uv7hICgzhYWlUseShYEJAAWpMQMT4QYtvdLypwIKFTRK39wZ5GuxXiKZUfMZQVWeHlb1dnOrAhXLoW4dLHMa85RTsGy16ecxdmrCFjN6kFJNOVLeJkOl6nJpqjZxZUJTFgdUY52UWyGl5UifF5uLnn8bKAzqRJt08wbpnqNS/0vm4pTliAkChUEdvSyllkj7kyV1L4ZC02Y2Pm+ptK9ZWrpT+nYayBVv0ESApJmaGb1N2rVX2jgqDe83z8XZjxL7UHQCY5B5CV5PB28S1NcHtYsbuu2j2agxdF2RNtVJP280193WQ816Y0zUWsvgTDfU2iD1OjOvNrHawn3bm39r82lYuwra3zHXLXbvhQOyAT7j8LE6mMqHvoPmOZ+FMAudMiYAJ4xuh0t7oPgaOJ5cTCCAcSAdPBng2A3JRxYbCIw0OSIcz2P/ANmq17+SFKKEAAAAAElFTkSuQmCC"
        guard let data = Data(base64Encoded: b64),
              let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }

    init(stateManager: AppStateManager, onQuit: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = Self.makeIcon() {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "S"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Souffleur v1.1.2", action: nil, keyEquivalent: "")
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
            statusItem.button?.contentTintColor = nil
        case .loading:
            statusItem.button?.contentTintColor = .systemYellow
        case .recording:
            statusItem.button?.contentTintColor = .systemRed
        case .processing:
            statusItem.button?.contentTintColor = .systemOrange
        case .done:
            statusItem.button?.contentTintColor = .systemGreen
        }
    }
}
