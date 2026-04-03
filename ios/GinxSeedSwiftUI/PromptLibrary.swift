import Foundation

@MainActor
final class PromptLibrary: ObservableObject {
    @Published private(set) var presets: [String]
    @Published private(set) var recentPrompts: [String]

    private let presetsKey = "seed.promptLibrary.presets"
    private let recentsKey = "seed.promptLibrary.recents"
    private let userDefaults = UserDefaults.standard

    init() {
        presets = userDefaults.stringArray(forKey: presetsKey) ?? []
        recentPrompts = userDefaults.stringArray(forKey: recentsKey) ?? []
    }

    func savePreset(_ prompt: String) {
        let value = normalized(prompt)
        guard !value.isEmpty else { return }

        presets.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        presets.insert(value, at: 0)
        presets = Array(presets.prefix(8))
        persist()
    }

    func registerRecent(_ prompt: String) {
        let value = normalized(prompt)
        guard !value.isEmpty else { return }

        recentPrompts.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        recentPrompts.insert(value, at: 0)
        recentPrompts = Array(recentPrompts.prefix(6))
        persist()
    }

    func removePreset(_ prompt: String) {
        presets.removeAll { $0 == prompt }
        persist()
    }

    private func normalized(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persist() {
        userDefaults.set(presets, forKey: presetsKey)
        userDefaults.set(recentPrompts, forKey: recentsKey)
    }
}
