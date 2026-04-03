import Foundation

enum AppConfiguration {
    private static let infoDictionary = Bundle.main.infoDictionary ?? [:]
    private static let userDefaults = UserDefaults.standard
    private static let backendOverrideKey = "seed.settings.backendBaseURL"
    private static let promptOverrideKey = "seed.settings.defaultPrompt"
    private static let autoConnectOverrideKey = "seed.settings.autoConnectOnLaunch"

    static var backendBaseURL: URL {
        let fallbackURL = "http://127.0.0.1:8787"
        let configuredURL = (userDefaults.string(forKey: backendOverrideKey) as String?)
            ?? (infoDictionary["GINXBackendBaseURL"] as? String)
        let value = configuredURL?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value, !value.isEmpty, let url = URL(string: value) else {
            return URL(string: fallbackURL)!
        }

        return url
    }

    static var defaultPrompt: String {
        let fallbackPrompt = "Transform into this character with polished cinematic detail"
        let configuredPrompt = (userDefaults.string(forKey: promptOverrideKey) as String?)
            ?? (infoDictionary["GINXDefaultPrompt"] as? String)
        let value = configuredPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : fallbackPrompt
    }

    static var autoConnectOnLaunch: Bool {
        if userDefaults.object(forKey: autoConnectOverrideKey) != nil {
            return userDefaults.bool(forKey: autoConnectOverrideKey)
        }

        return (infoDictionary["GINXAutoConnectOnLaunch"] as? Bool) ?? true
    }

    static func saveSettings(
        backendBaseURL: String,
        defaultPrompt: String,
        autoConnectOnLaunch: Bool
    ) {
        let backend = backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = defaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if backend.isEmpty {
            userDefaults.removeObject(forKey: backendOverrideKey)
        } else {
            userDefaults.set(backend, forKey: backendOverrideKey)
        }

        if prompt.isEmpty {
            userDefaults.removeObject(forKey: promptOverrideKey)
        } else {
            userDefaults.set(prompt, forKey: promptOverrideKey)
        }

        userDefaults.set(autoConnectOnLaunch, forKey: autoConnectOverrideKey)
    }

    static func resetSettings() {
        userDefaults.removeObject(forKey: backendOverrideKey)
        userDefaults.removeObject(forKey: promptOverrideKey)
        userDefaults.removeObject(forKey: autoConnectOverrideKey)
    }
}
