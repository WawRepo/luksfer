import Foundation

/// Quoting for text Luksfer types into zsh or bash.
public enum ShellQuoting {
    /// Quotes `s` as one shell word for zsh and bash.
    ///
    /// Plain text gets single quotes: `it's` → `'it'\''s'`. Text with a control character
    /// (newline, tab, escape, delete...) gets ANSI-C quotes instead: `a⏎b` → `$'a\nb'`. The result
    /// never holds a raw control character, so typing it at a prompt cannot press Return early.
    public static func singleQuoted(_ s: String) -> String {
        if !s.unicodeScalars.contains(where: isControl) {
            return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        }
        var out = "$'"
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += #"\\"#
            case "'": out += #"\'"#
            case "!": out += #"\x21"#  // no history expansion, whatever the shell's options
            case "\n": out += #"\n"#
            case "\t": out += #"\t"#
            case "\r": out += #"\r"#
            case _ where isControl(scalar):
                for byte in String(scalar).utf8 { out += String(format: "\\x%02X", byte) }
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "'"
    }

    /// The line Luksfer types to move the shell to `path`, Return included. The leading space keeps
    /// it out of history (HIST_IGNORE_SPACE); Luksfer's zsh integration also drops it from history.
    /// `builtin` skips a user's `cd` alias or function (zoxide's `--cmd cd`, for example).
    public static func cdCommand(to path: String) -> String {
        cdCommandPrefix + singleQuoted(path) + "\r"
    }

    /// The start of every line `cdCommand(to:)` returns.
    public static let cdCommandPrefix = " builtin cd -- "

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
    }
}
