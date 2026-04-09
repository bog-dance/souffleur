import Foundation

enum AppState: Sendable {
    case idle, loading, recording, processing, postprocessing, done, error
}

class AppStateManager: @unchecked Sendable, ObservableObject {
    @Published var state: AppState = .idle
    @Published var statusText: String = ""

    func transition(to newState: AppState, text: String = "") {
        state = newState
        statusText = text
        if newState == .done || newState == .error {
            let delay: Double = newState == .error ? 2.0 : 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                if self?.state == newState { self?.state = .idle }
            }
        }
    }
}
