import AppKit
import ApplicationServices

@main
final class KeyboardLockApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusLabel: NSTextField!
    private var lockButton: NSButton!
    private var unlockButton: NSButton!
    private let keyboardLock = KeyboardEventLock()

    static func main() {
        let app = NSApplication.shared
        let delegate = KeyboardLockApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildInterface()
        keyboardLock.onEmergencyUnlock = { [weak self] in
            self?.setLocked(false, message: "Sbloccata con ESC")
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildInterface() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 270),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blocco Tastiera"
        window.center()
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "Blocco Tastiera")
        title.font = .systemFont(ofSize: 25, weight: .bold)
        title.alignment = .center

        statusLabel = NSTextField(labelWithString: "Tastiera attiva")
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        lockButton = NSButton(title: "BLOCCA TASTIERA", target: self, action: #selector(lockKeyboard))
        lockButton.bezelStyle = .rounded
        lockButton.controlSize = .large
        lockButton.font = .systemFont(ofSize: 18, weight: .semibold)
        lockButton.keyEquivalent = "\r"
        lockButton.heightAnchor.constraint(equalToConstant: 54).isActive = true

        unlockButton = NSButton(title: "Sblocca", target: self, action: #selector(unlockKeyboard))
        unlockButton.bezelStyle = .rounded
        unlockButton.controlSize = .large
        unlockButton.isEnabled = false
        unlockButton.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let hint = NSTextField(wrappingLabelWithString: "Mouse e trackpad restano attivi. In emergenza, tieni premuto ESC per 3 secondi.")
        hint.alignment = .center
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        let stack = NSStackView(views: [title, statusLabel, lockButton, unlockButton, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -36),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 25),
            lockButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            unlockButton.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func lockKeyboard() {
        guard requestAccessibilityPermission() else {
            showPermissionAlert()
            return
        }

        do {
            try keyboardLock.lock()
            setLocked(true, message: "Tastiera bloccata")
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Impossibile bloccare la tastiera"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func unlockKeyboard() {
        keyboardLock.unlock()
        setLocked(false, message: "Tastiera attiva")
    }

    private func setLocked(_ locked: Bool, message: String) {
        statusLabel.stringValue = message
        statusLabel.textColor = locked ? .systemRed : .secondaryLabelColor
        lockButton.isEnabled = !locked
        unlockButton.isEnabled = locked
    }

    private func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Autorizzazione necessaria"
        alert.informativeText = "Abilita Blocco Tastiera in Impostazioni di Sistema > Privacy e sicurezza > Accessibilità, poi premi di nuovo BLOCCA TASTIERA. Se richiesto, abilitala anche in Monitoraggio input."
        alert.addButton(withTitle: "Apri Accessibilità")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
