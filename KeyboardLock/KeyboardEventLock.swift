import AppKit
import CoreGraphics

enum KeyboardLockError: LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        "macOS non ha consentito l'intercettazione degli eventi. Controlla i permessi Accessibilità e Monitoraggio input, quindi riapri l'app."
    }
}

final class KeyboardEventLock {
    var onEmergencyUnlock: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var escapeTimer: DispatchWorkItem?
    private var escapeIsDown = false

    func lock() throws {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            // CGEvent uses raw event type 14 for NX_SYSDEFINED media keys,
            // although CoreGraphics does not expose a named Swift case for it.
            | (1 << 14)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: KeyboardEventLock.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw KeyboardLockError.eventTapUnavailable
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw KeyboardLockError.eventTapUnavailable
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func unlock() {
        cancelEmergencyUnlock()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    deinit { unlock() }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // 53 is the hardware-independent virtual key code for Escape on macOS.
        if event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            if type == .keyDown && !escapeIsDown {
                escapeIsDown = true
                let timer = DispatchWorkItem { [weak self] in
                    guard let self, self.escapeIsDown else { return }
                    self.unlock()
                    self.onEmergencyUnlock?()
                }
                escapeTimer = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timer)
            } else if type == .keyUp {
                cancelEmergencyUnlock()
            }
        }

        // Returning nil also discards media/function-key events (volume, brightness,
        // playback, Mission Control, and similar). Pointer events are not in the mask.
        return nil
    }

    private func cancelEmergencyUnlock() {
        escapeIsDown = false
        escapeTimer?.cancel()
        escapeTimer = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<KeyboardEventLock>.fromOpaque(userInfo).takeUnretainedValue()
        return owner.handle(type: type, event: event)
    }
}
