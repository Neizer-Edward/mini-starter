import Foundation

func loadDotEnv(path: String = ".env") {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

    for line in content.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
       
        guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }

        let parts = trimmed.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }

        let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
        setenv(key, value, 1) 
    }
}
