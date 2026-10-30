import Foundation

/// What the text typed into the path bar asks for.
public enum PathInput: Equatable {
    /// Open this folder.
    case folder(URL)
    /// Open the parent folder and select this file.
    case file(URL)
    /// "term", "terminal" or "cmd": open a terminal in the current folder.
    case openTerminal
    /// Nothing is there; the message to show, e.g. "No folder or file at ~/foo".
    case notFound(String)
}
