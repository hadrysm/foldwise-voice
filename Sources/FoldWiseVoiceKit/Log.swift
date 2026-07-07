// Unified logging: one subsystem (the app's bundle id), one category per area,
// so `log stream --predicate 'subsystem == "com.foldwise.voice.native"'` and
// Console.app can filter the app's output. Transcript text is interpolated
// with explicit `.private` so user speech never lands in persisted logs;
// error details are `.public` so failures are diagnosable from a `log show`.

import os

enum Log {
    private static let subsystem = "com.foldwise.voice.native"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let insert = Logger(subsystem: subsystem, category: "insert")
    static let ollama = Logger(subsystem: subsystem, category: "ollama")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
}
