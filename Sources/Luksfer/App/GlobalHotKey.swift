import Carbon.HIToolbox

/// ⌥⌘Space from any app, Luksfer included. A Carbon hot key needs no permission: macOS tells
/// Luksfer about this one key only, and never shows it the other keys.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    /// False when another app (a second Luksfer, for example) has the key already.
    @discardableResult
    func register() -> Bool {
        guard ref == nil else { return true }
        if handler == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, me in
                guard let me else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(me).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        let id = EventHotKeyID(signature: 0x4C4B5346 /* LKSF */, id: 1)
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(),
                                   OptionBits(kEventHotKeyExclusive), &ref) == noErr
    }

    func unregister() {
        guard let ref else { return }
        UnregisterEventHotKey(ref)
        self.ref = nil
    }
}
