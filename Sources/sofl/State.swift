import Foundation

enum AppState: Sendable {
    case idle, loading, recording, processing, postprocessing, done
}

class AppStateManager: @unchecked Sendable, ObservableObject {
    @Published var state: AppState = .idle
    @Published var statusText: String = ""

    func transition(to newState: AppState, text: String = "") {
        state = newState
        statusText = text
        if newState == .done {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if self?.state == .done { self?.state = .idle }
            }
        }
    }
}
