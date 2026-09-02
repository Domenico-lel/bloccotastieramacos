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
    var onEscapeHoldChanged: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var escapeTimer: DispatchWorkItem?
    private var escapeIsDown = false

    func lock(blockPointer: Bool = false) throws {
        guard eventTap == nil else { return }

        var mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            // CGEvent uses raw event type 14 for NX_SYSDEFINED media keys,
            // although CoreGraphics does not expose a named Swift case for it.
            | (CGEventMask(1) << 14)

        if blockPointer {
            let pointerEvents: [CGEventType] = [
                .leftMouseDown, .leftMouseUp,
                .rightMouseDown, .rightMouseUp,
                .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                .scrollWheel,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged
            ]
            for eventType in pointerEvents {
                mask |= CGEventMask(1) << eventType.rawValue
            }

            // AppKit exposes trackpad gestures with raw event types that do not all
            // have named CoreGraphics cases. Including them prevents system gestures
            // from escaping the full-cleaning mode on older Intel trackpads.
            let gestureEventRawValues: [UInt32] = [18, 19, 20, 29, 30, 31, 32, 34, 37, 38]
            for rawValue in gestureEventRawValues {
                mask |= CGEventMask(1) << rawValue
            }
        }

        guard let tap = CGEvent.tapCreate(
            // HID level is required to suppress pointer events reliably before
            // WindowServer turns trackpad input into application/system gestures.
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
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
        if (type == .keyDown || type == .keyUp),
           event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            if type == .keyDown && !escapeIsDown {
                escapeIsDown = true
                DispatchQueue.main.async { [weak self] in
                    self?.onEscapeHoldChanged?(true)
                }
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

        // Returning nil discards every event included in the active mask.
        return nil
    }

    private func cancelEmergencyUnlock() {
        let wasHolding = escapeIsDown
        escapeIsDown = false
        escapeTimer?.cancel()
        escapeTimer = nil
        if wasHolding {
            DispatchQueue.main.async { [weak self] in
                self?.onEscapeHoldChanged?(false)
            }
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<KeyboardEventLock>.fromOpaque(userInfo).takeUnretainedValue()
        return owner.handle(type: type, event: event)
    }
}
