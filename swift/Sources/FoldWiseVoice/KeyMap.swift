// pynput-compatible key names ↔ macOS virtual keycodes, shared by the hotkey
// listener and the settings key recorder so modes.json stays portable between
// the Python and Swift apps.

import CoreGraphics
import Foundation

enum KeySpec {
    case keycode(CGKeyCode)
    case character(String)
}

enum KeyMap {
    static let nameToCode: [String: CGKeyCode] = [
        "alt": 58, "alt_l": 58, "alt_r": 61,
        "cmd": 55, "cmd_l": 55, "cmd_r": 54,
        "ctrl": 59, "ctrl_l": 59, "ctrl_r": 62,
        "shift": 56, "shift_l": 56, "shift_r": 60,
        "caps_lock": 57, "space": 49, "tab": 48, "enter": 36, "esc": 53,
        "backspace": 51, "delete": 117, "home": 115, "end": 119,
        "page_up": 116, "page_down": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
        "f18": 79, "f19": 80, "f20": 90,
    ]

    static let codeToName: [CGKeyCode: String] = {
        var map: [CGKeyCode: String] = [:]
        // Later entries win; insert generic names first so specific ones
        // (alt_l over alt) survive.
        for (name, code) in nameToCode.sorted(by: { $0.key.count < $1.key.count }) {
            map[code] = name
        }
        return map
    }()

    /// Which CGEventFlags bit a modifier keycode toggles (for flagsChanged).
    static let modifierFlag: [CGKeyCode: CGEventFlags] = [
        58: .maskAlternate, 61: .maskAlternate,
        55: .maskCommand, 54: .maskCommand,
        59: .maskControl, 62: .maskControl,
        56: .maskShift, 60: .maskShift,
        57: .maskAlphaShift,
    ]

    static let prettyNames: [String: String] = [
        "alt_r": "right ⌥", "alt_l": "left ⌥", "alt": "left ⌥",
        "cmd_r": "right ⌘", "cmd_l": "left ⌘", "cmd": "left ⌘",
        "ctrl_r": "right ⌃", "ctrl_l": "left ⌃", "ctrl": "left ⌃",
        "shift_r": "right ⇧", "shift_l": "left ⇧", "shift": "left ⇧",
    ]

    static func pretty(_ name: String) -> String {
        prettyNames[name] ?? name
    }

    static func parse(_ name: String) throws -> KeySpec {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let code = nameToCode[trimmed.lowercased()] {
            return .keycode(code)
        }
        if trimmed.count == 1 {
            return .character(trimmed.lowercased())
        }
        throw NSError(
            domain: "FoldWiseVoice", code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Unknown hotkey '\(name)'. Use a key name (e.g. 'alt_r', 'cmd_r', 'f19') or a single character."
            ])
    }
}
