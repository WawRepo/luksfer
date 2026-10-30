import AppKit
import LuksferCore

/// Typing a path: the text field, suggestions, keys, going there, and ending the edit.
extension PathBarView: NSTextFieldDelegate {
    /// Esc, a click elsewhere, or Enter on empty text.
    private func cancelAndNotify() {
        finishEditing()
        delegate?.pathBarDidEndEditing(self)
    }

    // MARK: - Going somewhere

    /// Enter: the highlighted suggestion if there is one, else the typed text.
    func goToTypedText() {
        if let index = highlighted, popup.isVisible, suggestions.indices.contains(index) {
            goToSuggestion(at: index)
            return
        }
        let text = field.stringValue
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancelAndNotify()
            return
        }
        switch PathResolver.resolve(text, relativeTo: folder, home: home) {
        case .folder(let url):
            navigate(to: url, select: nil)
        case .file(let url):
            navigate(to: url.deletingLastPathComponent(), select: url)
        case .openTerminal:
            cancelAndNotify()
            delegate?.pathBarOpenTerminal(self)
        case .notFound(let message):
            showError(message)
        }
    }

    func goToSuggestion(at index: Int) {
        guard suggestions.indices.contains(index) else { return }
        navigate(to: suggestions[index], select: nil)
    }

    private func navigate(to folder: URL, select file: URL?) {
        finishEditing()
        delegate?.pathBar(self, navigateTo: folder, select: file)
        delegate?.pathBarDidEndEditing(self)
    }

    private func showError(_ message: String) {
        hasError = true
        highlighted = nil
        suggestionGeneration += 1
        popup.show(error: message, below: self)
    }

    // MARK: - Suggestions

    /// Lists matching folders off the main thread and shows them when they arrive.
    func refreshSuggestions() {
        suggestionGeneration += 1
        let generation = suggestionGeneration
        let text = field.stringValue, base = folder, home = home
        suggestionQueue.async { [weak self] in
            let found = PathCompleter.suggestions(for: text, relativeTo: base, limit: 12, home: home)
            // Shown the way the user typed it: "~/Pro" lists "~/Projects", not the absolute path.
            let titles = found.map { String(PathCompleter.text(text, choosing: $0.lastPathComponent).dropLast()) }
            DispatchQueue.main.async {
                guard let self, self.isEditing, generation == self.suggestionGeneration else { return }
                self.showSuggestions(found, titles: titles)
            }
        }
    }

    func showSuggestions(_ found: [URL], titles: [String]) {
        suggestions = found
        suggestionTitles = titles
        highlighted = nil
        guard !found.isEmpty else { popup.close(); return }
        popup.show(suggestions: titles, highlighted: nil, below: self)
    }

    func setHighlight(_ index: Int?) {
        highlighted = index
        popup.setHighlighted(index)
    }

    /// ↑ ↓ move the highlight; ↓ also brings back a closed list.
    private func moveHighlight(by step: Int) {
        guard popup.isVisible, !hasError, !suggestions.isEmpty else {
            if step > 0 { refreshSuggestions() }
            return
        }
        let last = suggestions.count - 1
        guard let current = highlighted else {
            setHighlight(step > 0 ? 0 : last)
            return
        }
        let next = current + step
        setHighlight(next < 0 ? nil : min(next, last))
    }

    /// Tab: the highlighted suggestion, or the completion of the typed text.
    private func completeTypedText() {
        var completed: String?
        if let index = highlighted, popup.isVisible, suggestions.indices.contains(index) {
            completed = suggestionTitles[index] + "/"
        } else {
            completed = PathCompleter.complete(field.stringValue, relativeTo: folder, home: home)
        }
        guard let completed else { return }
        field.stringValue = completed
        field.currentEditor()?.selectedRange = NSRange(location: (completed as NSString).length, length: 0)
        userChangedText()
    }

    /// The text changed by typing, pasting or Tab.
    func userChangedText() {
        hasError = false
        setHighlight(nil)  // a highlight belongs to the old text; Enter must not pick it
        refreshSuggestions()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        userChangedText()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Focus moved elsewhere on purpose (a shortcut, another view took it). Clicks are caught
        // earlier by the mouse-down monitor. No delegate call, so the host does not take focus back.
        finishEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            goToTypedText()
        case #selector(NSResponder.cancelOperation(_:)):
            if popup.isVisible {
                popup.close()
                highlighted = nil
                hasError = false
            } else {
                cancelAndNotify()
            }
        case #selector(NSResponder.insertTab(_:)):
            completeTypedText()
        case #selector(NSResponder.insertBacktab(_:)):
            break
        case #selector(NSResponder.moveUp(_:)):
            moveHighlight(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            moveHighlight(by: 1)
        default:
            return false
        }
        return true
    }

    // MARK: - Click away

    func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.mouseDownWhileEditing(event)
            return event
        }
    }

    func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// A click outside the bar and its list ends typing; the click itself still goes through.
    private func mouseDownWhileEditing(_ event: NSEvent) {
        guard isEditing, event.window !== popup.content.window else { return }
        if event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)) { return }
        cancelAndNotify()
    }
}
