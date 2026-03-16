import Foundation

enum URLResolver {
    static func resolve(_ input: String) -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed == "aurora://newtab" {
            return URL(string: "aurora://newtab")!
        }

        // Already a full URL with scheme
        if let url = URL(string: trimmed), let scheme = url.scheme,
           !scheme.isEmpty, url.host != nil {
            return url
        }

        // Looks like a domain (contains dot, no spaces)
        if trimmed.contains(".") && !trimmed.contains(" ") {
            let withScheme = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
            if let url = URL(string: withScheme) {
                return url
            }
        }

        // Fallback: Google search
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.google.com/search?q=\(query)")!
    }
}
