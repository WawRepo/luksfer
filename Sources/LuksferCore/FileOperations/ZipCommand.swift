import Foundation

/// The `/usr/bin/zip` command for Compress with several items. Run it in the items' folder.
public enum ZipCommand {
    public static let executable = URL(fileURLWithPath: "/usr/bin/zip")

    /// `--` and `./` keep a file name that starts with "-" from being read as an option:
    /// `-T` next to `-TT<command>` would make zip run the command. `-y` keeps links as links.
    public static func arguments(zip: String, names: [String]) -> [String] {
        ["-r", "-y", "-q", zip, "--"] + names.map { "./" + $0 }
    }
}
