import Foundation
import Observation

@MainActor
@Observable
final class JournalViewModel {
    enum LoadState {
        case loading
        case loaded([JournalEntry])
        case empty
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private let journalService: JournalServing

    init(journalService: JournalServing) {
        self.journalService = journalService
    }

    var entries: [JournalEntry] {
        if case .loaded(let entries) = state { return entries }
        return []
    }

    func load() async {
        state = .loading
        let cached = await journalService.cachedEntries()
        if !cached.isEmpty {
            state = .loaded(cached)
        }
        await fetchEntries(preserveCurrentOnFailure: !cached.isEmpty)
    }

    func refresh() async {
        await fetchEntries(preserveCurrentOnFailure: !entries.isEmpty)
    }

    private func fetchEntries(preserveCurrentOnFailure: Bool) async {
        do {
            let entries = try await journalService.fetchEntries()
            state = entries.isEmpty ? .empty : .loaded(entries)
        } catch is CancellationError {
        } catch {
            if !preserveCurrentOnFailure {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
