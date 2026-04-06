import Foundation

enum AppState: Sendable {
    case idle, loading, recording, processing, done
}

class AppStateManager: @unchecked Sendable, ObservableObject {
    @Published var state: AppState = .idle

    func transition(to newState: AppState) {
        state = newState
        if newState == .done {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if self?.state == .done { self?.state = .idle }
            }
        }
    }
}
