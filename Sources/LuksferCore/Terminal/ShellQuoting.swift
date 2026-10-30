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

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
    }
}
