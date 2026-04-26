import Foundation
import Combine
import Sparkle

@MainActor
final class UpdaterModel: ObservableObject {
    static let shared = UpdaterModel()

    @Published var automaticallyChecksForUpdates: Bool = false

    private var updater: SPUUpdater?
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    func attach(_ updater: SPUUpdater) {
        self.updater = updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        $automaticallyChecksForUpdates
            .dropFirst()
            .sink { [weak self] newValue in
                self?.updater?.automaticallyChecksForUpdates = newValue
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }
}
