import os

/// Central loggers. Never log tokens, auth headers, or account details.
enum AppLog {
    static let refresh = Logger(subsystem: "com.qdock", category: "refresh")
}
