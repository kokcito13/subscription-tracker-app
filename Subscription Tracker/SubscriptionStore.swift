import Foundation
import Combine

final class SubscriptionStore: ObservableObject {
    @Published private(set) var subscriptions: [Subscription] = []

    private let saveURL: URL
    private var cancellables = Set<AnyCancellable>()

    init(filename: String = "subscriptions.json") {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = docs.appendingPathComponent(filename)

        load()

        // Persist on change
        $subscriptions
            .dropFirst()
            .sink { [weak self] subs in
                self?.save(subs)
            }
            .store(in: &cancellables)
    }

    func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode([Subscription].self, from: data)
            self.subscriptions = decoded
        } catch {
            // If loading fails (first run), use sample data
            self.subscriptions = Subscription.sampleData()
        }
    }

    func save(_ subs: [Subscription]) {
        do {
            let data = try JSONEncoder().encode(subs)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            print("Failed to save subscriptions:\(error)")
        }
    }

    // CRUD
    func add(_ subscription: Subscription) {
        subscriptions.append(subscription)
    }

    func update(_ subscription: Subscription) {
        guard let idx = subscriptions.firstIndex(of: subscription) else { return }
        subscriptions[idx] = subscription
    }

    func remove(at offsets: IndexSet) {
        // Remove at offsets without relying on SwiftUI's Array extension.
        // Iterate indices in descending order to keep removals valid.
        for index in offsets.sorted(by: >) {
            if subscriptions.indices.contains(index) {
                subscriptions.remove(at: index)
            }
        }
    }
}
