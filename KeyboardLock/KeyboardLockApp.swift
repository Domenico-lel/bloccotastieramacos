import AppKit
import ApplicationServices

@main
final class KeyboardLockApp: NSObject, NSApplicationDelegate {
    private enum State { case ready, countingDown, locked }

    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var actionButton: NSButton!
    private var pointerModeCheckbox: NSButton!
    private var durationPopup: NSPopUpButton!
    private var lockMenuItem: NSMenuItem!
    private var fullCleanMenuItem: NSMenuItem!
    private var unlockMenuItem: NSMenuItem!
    private var countdownTimer: Timer?
    private var automaticUnlockTimer: Timer?
    private var countdownValue = 3
    private var remainingLockSeconds = 30
    private var pendingBlocksPointer = false
    private var lockedBlocksPointer = false
    private var state: State = .ready
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
        buildStatusItem()

        keyboardLock.onEmergencyUnlock = { [weak self] in
            self?.finishUnlock(message: "Sbloccata con ESC")
        }
        keyboardLock.onEscapeHoldChanged = { [weak self] isHolding in
            guard let self, self.state == .locked else { return }
            if isHolding {
                self.detailLabel.stringValue = "Continua a tenere premuto ESC per sbloccare…"
            } else {
                self.updateInterface()
            }
        }

        updateInterface()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        countdownTimer?.invalidate()
        automaticUnlockTimer?.invalidate()
        keyboardLock.unlock()
    }

    private func buildInterface() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "iBlock"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 82),
            icon.heightAnchor.constraint(equalToConstant: 82)
        ])

        let title = NSTextField(labelWithString: "iBlock")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.alignment = .center

        statusLabel = NSTextField(labelWithString: "Tastiera attiva")
        statusLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.setAccessibilityLabel("Stato della tastiera")

        detailLabel = NSTextField(wrappingLabelWithString: "Pronta per essere bloccata in sicurezza.")
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 2

        pointerModeCheckbox = NSButton(
            checkboxWithTitle: "Blocca anche mouse e trackpad",
            target: self,
            action: #selector(pointerModeChanged)
        )
        pointerModeCheckbox.font = .systemFont(ofSize: 14, weight: .medium)
        pointerModeCheckbox.setAccessibilityLabel("Blocca anche mouse e trackpad")

        let durationLabel = NSTextField(labelWithString: "Sblocco automatico dopo:")
        durationLabel.textColor = .secondaryLabelColor

        durationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        durationPopup.addItems(withTitles: ["10 secondi", "20 secondi", "30 secondi", "60 secondi"])
        durationPopup.selectItem(at: 2)
        durationPopup.isEnabled = false
        durationPopup.target = self
        durationPopup.action = #selector(durationChanged)
        durationPopup.setAccessibilityLabel("Durata della pulizia completa")

        let durationRow = NSStackView(views: [durationLabel, durationPopup])
        durationRow.orientation = .horizontal
        durationRow.alignment = .centerY
        durationRow.spacing = 10

        actionButton = NSButton(title: "BLOCCA TASTIERA", target: self, action: #selector(primaryAction))
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.font = .systemFont(ofSize: 17, weight: .semibold)
        actionButton.keyEquivalent = "\r"
        actionButton.setAccessibilityLabel("Blocca tastiera")
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let stack = NSStackView(views: [icon, title, statusLabel, detailLabel, pointerModeCheckbox, durationRow, actionButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(22, after: detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        window.contentView?.addSubview(card)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            card.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            card.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -34),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            actionButton.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "iBlock")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Mostra iBlock", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        lockMenuItem = NSMenuItem(title: "Blocca tastiera…", action: #selector(beginCountdown), keyEquivalent: "")
        fullCleanMenuItem = NSMenuItem(title: "Pulizia completa (30 secondi)…", action: #selector(beginFullCleanFromMenu), keyEquivalent: "")
        unlockMenuItem = NSMenuItem(title: "Sblocca", action: #selector(unlockKeyboard), keyEquivalent: "")
        menu.addItem(lockMenuItem)
        menu.addItem(fullCleanMenuItem)
        menu.addItem(unlockMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Esci", action: #selector(quitApplication), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func primaryAction() {
        switch state {
        case .ready: beginCountdown()
        case .countingDown: cancelCountdown()
        case .locked: unlockKeyboard()
        }
    }

    @objc private func pointerModeChanged() {
        durationPopup.isEnabled = pointerModeCheckbox.state == .on
        updateInterface()
    }

    @objc private func durationChanged() {
        fullCleanMenuItem.title = "Pulizia completa (\(selectedDuration) secondi)…"
    }

    @objc private func beginFullCleanFromMenu() {
        guard state == .ready else { return }
        pointerModeCheckbox.state = .on
        durationPopup.isEnabled = true
        beginCountdown()
    }

    @objc private func beginCountdown() {
        guard state == .ready else { return }
        guard requestAccessibilityPermission() else {
            return
        }

        countdownTimer?.invalidate()
        countdownValue = 3
        pendingBlocksPointer = pointerModeCheckbox.state == .on
        state = .countingDown
        updateInterface()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.countdownValue -= 1
            if self.countdownValue <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.activateKeyboardLock()
            } else {
                self.updateInterface()
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        pendingBlocksPointer = false
        state = .ready
        updateInterface()
    }

    private func activateKeyboardLock() {
        do {
            try keyboardLock.lock(blockPointer: pendingBlocksPointer)
            lockedBlocksPointer = pendingBlocksPointer
            state = .locked
            if lockedBlocksPointer {
                remainingLockSeconds = selectedDuration
                window.level = .floating
                startAutomaticUnlockTimer()
            }
            updateInterface()
        } catch {
            state = .ready
            updateInterface()
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Impossibile bloccare la tastiera"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func unlockKeyboard() {
        guard state == .locked else { return }
        keyboardLock.unlock()
        finishUnlock(message: "Tastiera attiva")
    }

    private func finishUnlock(message: String) {
        automaticUnlockTimer?.invalidate()
        automaticUnlockTimer = nil
        lockedBlocksPointer = false
        pendingBlocksPointer = false
        window.level = .normal
        state = .ready
        updateInterface()
        statusLabel.stringValue = message
    }

    @objc private func quitApplication() {
        countdownTimer?.invalidate()
        automaticUnlockTimer?.invalidate()
        keyboardLock.unlock()
        NSApp.terminate(nil)
    }

    private var selectedDuration: Int {
        [10, 20, 30, 60][max(0, durationPopup.indexOfSelectedItem)]
    }

    private func startAutomaticUnlockTimer() {
        automaticUnlockTimer?.invalidate()
        automaticUnlockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.state == .locked, self.lockedBlocksPointer else {
                timer.invalidate()
                return
            }
            self.remainingLockSeconds -= 1
            if self.remainingLockSeconds <= 0 {
                timer.invalidate()
                self.automaticUnlockTimer = nil
                self.keyboardLock.unlock()
                self.finishUnlock(message: "Pulizia completata")
            } else {
                self.updateInterface()
            }
        }
    }

    private func updateInterface() {
        switch state {
        case .ready:
            statusLabel.stringValue = "Tastiera attiva"
            statusLabel.textColor = .labelColor
            detailLabel.stringValue = pointerModeCheckbox.state == .on
                ? "Pulizia completa: tastiera e puntatore, sempre con timer."
                : "Pronta per bloccare soltanto la tastiera."
            actionButton.title = pointerModeCheckbox.state == .on ? "AVVIA PULIZIA COMPLETA" : "BLOCCA TASTIERA"
            actionButton.setAccessibilityLabel(pointerModeCheckbox.state == .on ? "Avvia pulizia completa" : "Blocca tastiera")
            actionButton.isEnabled = true
            pointerModeCheckbox.isEnabled = true
            durationPopup.isEnabled = pointerModeCheckbox.state == .on
            lockMenuItem?.isEnabled = true
            fullCleanMenuItem?.isEnabled = true
            unlockMenuItem?.isEnabled = false
            statusItem?.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tastiera attiva")
        case .countingDown:
            statusLabel.stringValue = "Blocco tra \(countdownValue)…"
            statusLabel.textColor = .systemOrange
            detailLabel.stringValue = "Allontana le mani dalla tastiera oppure premi Annulla."
            actionButton.title = "ANNULLA"
            actionButton.setAccessibilityLabel("Annulla il blocco")
            actionButton.isEnabled = true
            pointerModeCheckbox.isEnabled = false
            durationPopup.isEnabled = false
            lockMenuItem?.isEnabled = false
            fullCleanMenuItem?.isEnabled = false
            unlockMenuItem?.isEnabled = false
            statusItem?.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Blocco imminente")
        case .locked:
            statusLabel.stringValue = lockedBlocksPointer ? "Pulizia completa attiva" : "Tastiera bloccata"
            statusLabel.textColor = .systemRed
            detailLabel.stringValue = lockedBlocksPointer
                ? "Sblocco automatico tra \(remainingLockSeconds) secondi. ESC per 3 secondi in emergenza."
                : "Mouse e trackpad restano attivi. ESC per 3 secondi in emergenza."
            actionButton.title = lockedBlocksPointer ? "BLOCCO COMPLETO ATTIVO" : "SBLOCCA"
            actionButton.setAccessibilityLabel("Sblocca tastiera")
            actionButton.isEnabled = !lockedBlocksPointer
            pointerModeCheckbox.isEnabled = false
            durationPopup.isEnabled = false
            lockMenuItem?.isEnabled = false
            fullCleanMenuItem?.isEnabled = false
            unlockMenuItem?.isEnabled = true
            statusItem?.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Tastiera bloccata")
        }
    }

    private func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

}
