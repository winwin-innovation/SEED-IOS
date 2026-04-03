import Foundation

enum AppConfiguration {
    private static let infoDictionary = Bundle.main.infoDictionary ?? [:]

    static let backendBaseURL: URL = {
        let fallbackURL = "http://127.0.0.1:8787"
        let configuredURL = infoDictionary["GINXBackendBaseURL"] as? String
        let value = configuredURL?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value, !value.isEmpty, let url = URL(string: value) else {
            return URL(string: fallbackURL)!
        }

        return url
    }()

    static let defaultPrompt: String = {
        let fallbackPrompt = "Transform into this character with polished cinematic detail"
        let configuredPrompt = infoDictionary["GINXDefaultPrompt"] as? String
        let value = configuredPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : fallbackPrompt
    }()

    static let autoConnectOnLaunch: Bool = {
        (infoDictionary["GINXAutoConnectOnLaunch"] as? Bool) ?? true
    }()
}
