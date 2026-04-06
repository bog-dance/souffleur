import CoreGraphics
import Foundation

class HotkeyListener {
    private static let keyCodes: [String: Int64] = [
        "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106,
        "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]

    private static let tapThreshold: TimeInterval = 0.3

    private var keys: [Int64: String] = [:]
    private var pressedKey: String?
    private var pressTime: Date?
    private var _isCancelled = false
    private var _isRecording = false
    private var isToggleMode = false
    fileprivate var eventTap: CFMachPort?

    var onPress: ((String) -> Void)?
    var onRelease: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onToggleStart: ((String) -> Void)?
    var onToggleStop: ((String) -> Void)?

    var isCancelled: Bool { _isCancelled }
    var isRecording: Bool { _isRecording }

    init(config: HotkeyConfig,
         onPress: @escaping (String) -> Void,
         onRelease: @escaping (String) -> Void,
         onCancel: @escaping () -> Void,
         onToggleStart: @escaping (String) -> Void,
         onToggleStop: @escaping (String) -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
        self.onToggleStart = onToggleStart
        self.onToggleStop = onToggleStop

        if let code = Self.keyCodes[config.triggerAutoEnter.lowercased()] {
            keys[code] = "auto_enter"
        }
        if let code = Self.keyCodes[config.triggerNoEnter.lowercased()] {
            keys[code] = "no_enter"
        }
    }

    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyCallback,
            userInfo: refcon
        ) else {
            print("Error: failed to create event tap. Grant Accessibility permissions in System Settings.")
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Hotkeys registered: \(keys.values.joined(separator: ", "))")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    func resetCancel() {
        _isCancelled = false
    }

    func resetToggle() {
        isToggleMode = false
        _isRecording = false
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int64(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Escape during recording (both modes)
        if keyCode == 53 && type == .keyDown && _isRecording {
            _isCancelled = true
            _isRecording = false
            isToggleMode = false
            onCancel?()
            return nil
        }

        // Ignore if modifier keys are pressed
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard flags.intersection(modifiers).isEmpty else {
            return Unmanaged.passRetained(event)
        }

        guard let keyName = keys[keyCode] else {
            return Unmanaged.passRetained(event)
        }

        // Toggle mode: second tap stops recording
        if type == .keyDown && isToggleMode && _isRecording {
            isToggleMode = false
            _isRecording = false
            pressedKey = nil
            onToggleStop?(keyName)
            return nil
        }

        if type == .keyDown && pressedKey == nil && !_isRecording {
            pressedKey = keyName
            pressTime = Date()
            _isRecording = true
            _isCancelled = false
            onPress?(keyName)
            return nil
        } else if type == .keyUp && pressedKey == keyName {
            let holdDuration = pressTime.map { Date().timeIntervalSince($0) } ?? 1.0
            pressedKey = nil

            if holdDuration < Self.tapThreshold {
                // Short tap - enter toggle mode, keep recording
                isToggleMode = true
                onToggleStart?(keyName)
            } else {
                // Long hold - stop and transcribe (push-to-talk)
                _isRecording = false
                if !_isCancelled {
                    onRelease?(keyName)
                }
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passRetained(event) }

    let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = listener.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    return listener.handleEvent(type: type, event: event)
}
