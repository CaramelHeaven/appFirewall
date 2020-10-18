//
//  HotKey.swift
//  appFirewall
//
//  Created by Sergey Fominov on 10/17/20.
//  Copyright © 2020 Doug Leith. All rights reserved.
//

/*
 FROM https://github.com/soffes/HotKey/blob/master/Sources/HotKey/KeyCombo%2BSystem.swift
 */

import AppKit
import Carbon
import Foundation

public final class HotKey {
    // MARK: - Types

    public typealias Handler = () -> Void

    // MARK: - Properties

    let identifier = UUID()

    public let keyCombo: KeyCombo
    public var keyDownHandler: Handler?
    public var keyUpHandler: Handler?
    public var isPaused = false {
        didSet {
            if isPaused {
                HotKeysController.unregister(self)
            } else {
                HotKeysController.register(self)
            }
        }
    }

    // MARK: - Initializers

    public init(keyCombo: KeyCombo, keyDownHandler: Handler? = nil, keyUpHandler: Handler? = nil) {
        self.keyCombo = keyCombo
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler

        HotKeysController.register(self)
    }

    public convenience init(carbonKeyCode: UInt32, carbonModifiers: UInt32, keyDownHandler: Handler? = nil, keyUpHandler: Handler? = nil) {
        let keyCombo = KeyCombo(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers)
        self.init(keyCombo: keyCombo, keyDownHandler: keyDownHandler, keyUpHandler: keyUpHandler)
    }

    public convenience init(key: Key, modifiers: NSEvent.ModifierFlags, keyDownHandler: Handler? = nil, keyUpHandler: Handler? = nil) {
        let keyCombo = KeyCombo(key: key, modifiers: modifiers)
        self.init(keyCombo: keyCombo, keyDownHandler: keyDownHandler, keyUpHandler: keyUpHandler)
    }

    deinit {
        HotKeysController.unregister(self)
    }
}

final class HotKeysController {
    // MARK: - Types

    final class HotKeyBox {
        let identifier: UUID
        weak var hotKey: HotKey?
        let carbonHotKeyID: UInt32
        var carbonEventHotKey: EventHotKeyRef?

        init(hotKey: HotKey, carbonHotKeyID: UInt32) {
            self.identifier = hotKey.identifier
            self.hotKey = hotKey
            self.carbonHotKeyID = carbonHotKeyID
        }
    }

    // MARK: - Properties

    static var hotKeys = [UInt32: HotKeyBox]()
    private static var hotKeysCount: UInt32 = 0

    static let eventHotKeySignature: UInt32 = {
        let string = "SSHk"
        var result: FourCharCode = 0
        for char in string.utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }()

    private static let eventSpec = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]

    private static var eventHandler: EventHandlerRef?

    // MARK: - Registration

    static func register(_ hotKey: HotKey) {
        // Don't register an already registered HotKey
        if hotKeys.values.first(where: { $0.identifier == hotKey.identifier }) != nil {
            return
        }

        // Increment the count which will become out next ID
        hotKeysCount += 1

        // Create a box for our metadata and weak HotKey
        let box = HotKeyBox(hotKey: hotKey, carbonHotKeyID: hotKeysCount)
        hotKeys[box.carbonHotKeyID] = box

        // Register with the system
        var eventHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: eventHotKeySignature, id: box.carbonHotKeyID)
        let registerError = RegisterEventHotKey(
            hotKey.keyCombo.carbonKeyCode,
            hotKey.keyCombo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )

        // Ensure registration worked
        guard registerError == noErr, eventHotKey != nil else {
            return
        }

        // Store the event so we can unregister it later
        box.carbonEventHotKey = eventHotKey

        // Setup the event handler if needed
        updateEventHandler()
    }

    static func unregister(_ hotKey: HotKey) {
        // Find the box
        guard let box = self.box(for: hotKey) else {
            return
        }

        // Unregister the hot key
        UnregisterEventHotKey(box.carbonEventHotKey)

        // Destroy the box
        box.hotKey = nil
        hotKeys.removeValue(forKey: box.carbonHotKeyID)
    }

    // MARK: - Events

    static func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
        // Ensure we have an event
        guard let event = event else {
            return OSStatus(eventNotHandledErr)
        }

        // Get the hot key ID from the event
        var hotKeyID = EventHotKeyID()
        let error = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        if error != noErr {
            return error
        }

        // Ensure we have a HotKey registered for this ID
        guard hotKeyID.signature == eventHotKeySignature,
            let hotKey = self.hotKey(for: hotKeyID.id)
        else {
            return OSStatus(eventNotHandledErr)
        }

        // Call the handler
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            if !hotKey.isPaused, let handler = hotKey.keyDownHandler {
                handler()
                return noErr
            }
        case UInt32(kEventHotKeyReleased):
            if !hotKey.isPaused, let handler = hotKey.keyUpHandler {
                handler()
                return noErr
            }
        default:
            break
        }

        return OSStatus(eventNotHandledErr)
    }

    private static func updateEventHandler() {
        if hotKeysCount == 0 || eventHandler != nil {
            return
        }

        // Register for key down and key up
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        // Install the handler
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 2, eventSpec, nil, &eventHandler)
    }

    // MARK: - Querying

    private static func hotKey(for carbonHotKeyID: UInt32) -> HotKey? {
        if let hotKey = hotKeys[carbonHotKeyID]?.hotKey {
            return hotKey
        }

        hotKeys.removeValue(forKey: carbonHotKeyID)
        return nil
    }

    private static func box(for hotKey: HotKey) -> HotKeyBox? {
        for box in hotKeys.values {
            if box.identifier == hotKey.identifier {
                return box
            }
        }

        return nil
    }
}

private func hotKeyEventHandler(eventHandlerCall: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    return HotKeysController.handleCarbonEvent(event)
}

public enum Key {
    // MARK: - Letters

    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    // MARK: - Numbers

    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine

    // MARK: - Symbols

    case period
    case quote
    case rightBracket
    case semicolon
    case slash
    case backslash
    case comma
    case equal
    case grave // Backtick
    case leftBracket
    case minus

    // MARK: - Whitespace

    case space
    case tab
    case `return`

    // MARK: - Modifiers

    case command
    case rightCommand
    case option
    case rightOption
    case control
    case rightControl
    case shift
    case rightShift
    case function
    case capsLock

    // MARK: - Navigation

    case pageUp
    case pageDown
    case home
    case end
    case upArrow
    case rightArrow
    case downArrow
    case leftArrow

    // MARK: - Functions

    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case f13
    case f14
    case f15
    case f16
    case f17
    case f18
    case f19
    case f20

    // MARK: - Keypad

    case keypad0
    case keypad1
    case keypad2
    case keypad3
    case keypad4
    case keypad5
    case keypad6
    case keypad7
    case keypad8
    case keypad9
    case keypadClear
    case keypadDecimal
    case keypadDivide
    case keypadEnter
    case keypadEquals
    case keypadMinus
    case keypadMultiply
    case keypadPlus

    // MARK: - Misc

    case escape
    case delete
    case forwardDelete
    case help
    case volumeUp
    case volumeDown
    case mute

    // MARK: - Initializers

    public init?(string: String) {
        switch string.lowercased() {
        case "a": self = .a
        case "s": self = .s
        case "d": self = .d
        case "f": self = .f
        case "h": self = .h
        case "g": self = .g
        case "z": self = .z
        case "x": self = .x
        case "c": self = .c
        case "v": self = .v
        case "b": self = .b
        case "q": self = .q
        case "w": self = .w
        case "e": self = .e
        case "r": self = .r
        case "y": self = .y
        case "t": self = .t
        case "one", "1": self = .one
        case "two", "2": self = .two
        case "three", "3": self = .three
        case "four", "4": self = .four
        case "six", "6": self = .six
        case "five", "5": self = .five
        case "equal", "=": self = .equal
        case "nine", "9": self = .nine
        case "seven", "7": self = .seven
        case "minus", "-": self = .minus
        case "eight", "8": self = .eight
        case "zero", "0": self = .zero
        case "rightBracket", "]": self = .rightBracket
        case "o": self = .o
        case "u": self = .u
        case "leftBracket", "[": self = .leftBracket
        case "i": self = .i
        case "p": self = .p
        case "l": self = .l
        case "j": self = .j
        case "quote", "\"": self = .quote
        case "k": self = .k
        case "semicolon", ";": self = .semicolon
        case "backslash", "\\": self = .backslash
        case "comma", ",": self = .comma
        case "slash", "/": self = .slash
        case "n": self = .n
        case "m": self = .m
        case "period", ".": self = .period
        case "grave", "`", "ˋ", "｀": self = .grave
        case "keypaddecimal": self = .keypadDecimal
        case "keypadmultiply": self = .keypadMultiply
        case "keypadplus": self = .keypadPlus
        case "keypadclear", "⌧": self = .keypadClear
        case "keypaddivide": self = .keypadDivide
        case "keypadenter": self = .keypadEnter
        case "keypadminus": self = .keypadMinus
        case "keypadequals": self = .keypadEquals
        case "keypad0": self = .keypad0
        case "keypad1": self = .keypad1
        case "keypad2": self = .keypad2
        case "keypad3": self = .keypad3
        case "keypad4": self = .keypad4
        case "keypad5": self = .keypad5
        case "keypad6": self = .keypad6
        case "keypad7": self = .keypad7
        case "keypad8": self = .keypad8
        case "keypad9": self = .keypad9
        case "return", "\r", "↩︎", "⏎", "⮐": self = .return
        case "tab", "\t", "⇥": self = .tab
        case "space", " ", "␣": self = .space
        case "delete", "⌫": self = .delete
        case "escape", "⎋": self = .escape
        case "command", "⌘", "": self = .command
        case "shift", "⇧": self = .shift
        case "capslock", "⇪": self = .capsLock
        case "option", "⌥": self = .option
        case "control", "⌃": self = .control
        case "rightcommand": self = .rightCommand
        case "rightshift": self = .rightShift
        case "rightoption": self = .rightOption
        case "rightcontrol": self = .rightControl
        case "function", "fn": self = .function
        case "f17", "F17": self = .f17
        case "volumeup", "🔊": self = .volumeUp
        case "volumedown", "🔉": self = .volumeDown
        case "mute", "🔇": self = .mute
        case "f18", "F18": self = .f18
        case "f19", "F19": self = .f19
        case "f20", "F20": self = .f20
        case "f5", "F5": self = .f5
        case "f6", "F6": self = .f6
        case "f7", "F7": self = .f7
        case "f3", "F3": self = .f3
        case "f8", "F8": self = .f8
        case "f9", "F9": self = .f9
        case "f11", "F11": self = .f11
        case "f13", "F13": self = .f13
        case "f16", "F16": self = .f16
        case "f14", "F14": self = .f14
        case "f10", "F10": self = .f10
        case "f12", "F12": self = .f12
        case "f15", "F15": self = .f15
        case "help", "?⃝": self = .help
        case "home", "↖": self = .home
        case "pageup", "⇞": self = .pageUp
        case "forwarddelete", "⌦": self = .forwardDelete
        case "f4", "F4": self = .f4
        case "end", "↘": self = .end
        case "f2", "F2": self = .f2
        case "pagedown", "⇟": self = .pageDown
        case "f1", "F1": self = .f1
        case "leftarrow", "←": self = .leftArrow
        case "rightarrow", "→": self = .rightArrow
        case "downarrow", "↓": self = .downArrow
        case "uparrow", "↑": self = .upArrow
        default: return nil
        }
    }

    public init?(carbonKeyCode: UInt32) {
        switch carbonKeyCode {
        case UInt32(kVK_ANSI_A): self = .a
        case UInt32(kVK_ANSI_S): self = .s
        case UInt32(kVK_ANSI_D): self = .d
        case UInt32(kVK_ANSI_F): self = .f
        case UInt32(kVK_ANSI_H): self = .h
        case UInt32(kVK_ANSI_G): self = .g
        case UInt32(kVK_ANSI_Z): self = .z
        case UInt32(kVK_ANSI_X): self = .x
        case UInt32(kVK_ANSI_C): self = .c
        case UInt32(kVK_ANSI_V): self = .v
        case UInt32(kVK_ANSI_B): self = .b
        case UInt32(kVK_ANSI_Q): self = .q
        case UInt32(kVK_ANSI_W): self = .w
        case UInt32(kVK_ANSI_E): self = .e
        case UInt32(kVK_ANSI_R): self = .r
        case UInt32(kVK_ANSI_Y): self = .y
        case UInt32(kVK_ANSI_T): self = .t
        case UInt32(kVK_ANSI_1): self = .one
        case UInt32(kVK_ANSI_2): self = .two
        case UInt32(kVK_ANSI_3): self = .three
        case UInt32(kVK_ANSI_4): self = .four
        case UInt32(kVK_ANSI_6): self = .six
        case UInt32(kVK_ANSI_5): self = .five
        case UInt32(kVK_ANSI_Equal): self = .equal
        case UInt32(kVK_ANSI_9): self = .nine
        case UInt32(kVK_ANSI_7): self = .seven
        case UInt32(kVK_ANSI_Minus): self = .minus
        case UInt32(kVK_ANSI_8): self = .eight
        case UInt32(kVK_ANSI_0): self = .zero
        case UInt32(kVK_ANSI_RightBracket): self = .rightBracket
        case UInt32(kVK_ANSI_O): self = .o
        case UInt32(kVK_ANSI_U): self = .u
        case UInt32(kVK_ANSI_LeftBracket): self = .leftBracket
        case UInt32(kVK_ANSI_I): self = .i
        case UInt32(kVK_ANSI_P): self = .p
        case UInt32(kVK_ANSI_L): self = .l
        case UInt32(kVK_ANSI_J): self = .j
        case UInt32(kVK_ANSI_Quote): self = .quote
        case UInt32(kVK_ANSI_K): self = .k
        case UInt32(kVK_ANSI_Semicolon): self = .semicolon
        case UInt32(kVK_ANSI_Backslash): self = .backslash
        case UInt32(kVK_ANSI_Comma): self = .comma
        case UInt32(kVK_ANSI_Slash): self = .slash
        case UInt32(kVK_ANSI_N): self = .n
        case UInt32(kVK_ANSI_M): self = .m
        case UInt32(kVK_ANSI_Period): self = .period
        case UInt32(kVK_ANSI_Grave): self = .grave
        case UInt32(kVK_ANSI_KeypadDecimal): self = .keypadDecimal
        case UInt32(kVK_ANSI_KeypadMultiply): self = .keypadMultiply
        case UInt32(kVK_ANSI_KeypadPlus): self = .keypadPlus
        case UInt32(kVK_ANSI_KeypadClear): self = .keypadClear
        case UInt32(kVK_ANSI_KeypadDivide): self = .keypadDivide
        case UInt32(kVK_ANSI_KeypadEnter): self = .keypadEnter
        case UInt32(kVK_ANSI_KeypadMinus): self = .keypadMinus
        case UInt32(kVK_ANSI_KeypadEquals): self = .keypadEquals
        case UInt32(kVK_ANSI_Keypad0): self = .keypad0
        case UInt32(kVK_ANSI_Keypad1): self = .keypad1
        case UInt32(kVK_ANSI_Keypad2): self = .keypad2
        case UInt32(kVK_ANSI_Keypad3): self = .keypad3
        case UInt32(kVK_ANSI_Keypad4): self = .keypad4
        case UInt32(kVK_ANSI_Keypad5): self = .keypad5
        case UInt32(kVK_ANSI_Keypad6): self = .keypad6
        case UInt32(kVK_ANSI_Keypad7): self = .keypad7
        case UInt32(kVK_ANSI_Keypad8): self = .keypad8
        case UInt32(kVK_ANSI_Keypad9): self = .keypad9
        case UInt32(kVK_Return): self = .return
        case UInt32(kVK_Tab): self = .tab
        case UInt32(kVK_Space): self = .space
        case UInt32(kVK_Delete): self = .delete
        case UInt32(kVK_Escape): self = .escape
        case UInt32(kVK_Command): self = .command
        case UInt32(kVK_Shift): self = .shift
        case UInt32(kVK_CapsLock): self = .capsLock
        case UInt32(kVK_Option): self = .option
        case UInt32(kVK_Control): self = .control
        case UInt32(kVK_RightCommand): self = .rightCommand
        case UInt32(kVK_RightShift): self = .rightShift
        case UInt32(kVK_RightOption): self = .rightOption
        case UInt32(kVK_RightControl): self = .rightControl
        case UInt32(kVK_Function): self = .function
        case UInt32(kVK_F17): self = .f17
        case UInt32(kVK_VolumeUp): self = .volumeUp
        case UInt32(kVK_VolumeDown): self = .volumeDown
        case UInt32(kVK_Mute): self = .mute
        case UInt32(kVK_F18): self = .f18
        case UInt32(kVK_F19): self = .f19
        case UInt32(kVK_F20): self = .f20
        case UInt32(kVK_F5): self = .f5
        case UInt32(kVK_F6): self = .f6
        case UInt32(kVK_F7): self = .f7
        case UInt32(kVK_F3): self = .f3
        case UInt32(kVK_F8): self = .f8
        case UInt32(kVK_F9): self = .f9
        case UInt32(kVK_F11): self = .f11
        case UInt32(kVK_F13): self = .f13
        case UInt32(kVK_F16): self = .f16
        case UInt32(kVK_F14): self = .f14
        case UInt32(kVK_F10): self = .f10
        case UInt32(kVK_F12): self = .f12
        case UInt32(kVK_F15): self = .f15
        case UInt32(kVK_Help): self = .help
        case UInt32(kVK_Home): self = .home
        case UInt32(kVK_PageUp): self = .pageUp
        case UInt32(kVK_ForwardDelete): self = .forwardDelete
        case UInt32(kVK_F4): self = .f4
        case UInt32(kVK_End): self = .end
        case UInt32(kVK_F2): self = .f2
        case UInt32(kVK_PageDown): self = .pageDown
        case UInt32(kVK_F1): self = .f1
        case UInt32(kVK_LeftArrow): self = .leftArrow
        case UInt32(kVK_RightArrow): self = .rightArrow
        case UInt32(kVK_DownArrow): self = .downArrow
        case UInt32(kVK_UpArrow): self = .upArrow
        default: return nil
        }
    }

    public var carbonKeyCode: UInt32 {
        switch self {
        case .a: return UInt32(kVK_ANSI_A)
        case .s: return UInt32(kVK_ANSI_S)
        case .d: return UInt32(kVK_ANSI_D)
        case .f: return UInt32(kVK_ANSI_F)
        case .h: return UInt32(kVK_ANSI_H)
        case .g: return UInt32(kVK_ANSI_G)
        case .z: return UInt32(kVK_ANSI_Z)
        case .x: return UInt32(kVK_ANSI_X)
        case .c: return UInt32(kVK_ANSI_C)
        case .v: return UInt32(kVK_ANSI_V)
        case .b: return UInt32(kVK_ANSI_B)
        case .q: return UInt32(kVK_ANSI_Q)
        case .w: return UInt32(kVK_ANSI_W)
        case .e: return UInt32(kVK_ANSI_E)
        case .r: return UInt32(kVK_ANSI_R)
        case .y: return UInt32(kVK_ANSI_Y)
        case .t: return UInt32(kVK_ANSI_T)
        case .one: return UInt32(kVK_ANSI_1)
        case .two: return UInt32(kVK_ANSI_2)
        case .three: return UInt32(kVK_ANSI_3)
        case .four: return UInt32(kVK_ANSI_4)
        case .six: return UInt32(kVK_ANSI_6)
        case .five: return UInt32(kVK_ANSI_5)
        case .equal: return UInt32(kVK_ANSI_Equal)
        case .nine: return UInt32(kVK_ANSI_9)
        case .seven: return UInt32(kVK_ANSI_7)
        case .minus: return UInt32(kVK_ANSI_Minus)
        case .eight: return UInt32(kVK_ANSI_8)
        case .zero: return UInt32(kVK_ANSI_0)
        case .rightBracket: return UInt32(kVK_ANSI_RightBracket)
        case .o: return UInt32(kVK_ANSI_O)
        case .u: return UInt32(kVK_ANSI_U)
        case .leftBracket: return UInt32(kVK_ANSI_LeftBracket)
        case .i: return UInt32(kVK_ANSI_I)
        case .p: return UInt32(kVK_ANSI_P)
        case .l: return UInt32(kVK_ANSI_L)
        case .j: return UInt32(kVK_ANSI_J)
        case .quote: return UInt32(kVK_ANSI_Quote)
        case .k: return UInt32(kVK_ANSI_K)
        case .semicolon: return UInt32(kVK_ANSI_Semicolon)
        case .backslash: return UInt32(kVK_ANSI_Backslash)
        case .comma: return UInt32(kVK_ANSI_Comma)
        case .slash: return UInt32(kVK_ANSI_Slash)
        case .n: return UInt32(kVK_ANSI_N)
        case .m: return UInt32(kVK_ANSI_M)
        case .period: return UInt32(kVK_ANSI_Period)
        case .grave: return UInt32(kVK_ANSI_Grave)
        case .keypadDecimal: return UInt32(kVK_ANSI_KeypadDecimal)
        case .keypadMultiply: return UInt32(kVK_ANSI_KeypadMultiply)
        case .keypadPlus: return UInt32(kVK_ANSI_KeypadPlus)
        case .keypadClear: return UInt32(kVK_ANSI_KeypadClear)
        case .keypadDivide: return UInt32(kVK_ANSI_KeypadDivide)
        case .keypadEnter: return UInt32(kVK_ANSI_KeypadEnter)
        case .keypadMinus: return UInt32(kVK_ANSI_KeypadMinus)
        case .keypadEquals: return UInt32(kVK_ANSI_KeypadEquals)
        case .keypad0: return UInt32(kVK_ANSI_Keypad0)
        case .keypad1: return UInt32(kVK_ANSI_Keypad1)
        case .keypad2: return UInt32(kVK_ANSI_Keypad2)
        case .keypad3: return UInt32(kVK_ANSI_Keypad3)
        case .keypad4: return UInt32(kVK_ANSI_Keypad4)
        case .keypad5: return UInt32(kVK_ANSI_Keypad5)
        case .keypad6: return UInt32(kVK_ANSI_Keypad6)
        case .keypad7: return UInt32(kVK_ANSI_Keypad7)
        case .keypad8: return UInt32(kVK_ANSI_Keypad8)
        case .keypad9: return UInt32(kVK_ANSI_Keypad9)
        case .return: return UInt32(kVK_Return)
        case .tab: return UInt32(kVK_Tab)
        case .space: return UInt32(kVK_Space)
        case .delete: return UInt32(kVK_Delete)
        case .escape: return UInt32(kVK_Escape)
        case .command: return UInt32(kVK_Command)
        case .shift: return UInt32(kVK_Shift)
        case .capsLock: return UInt32(kVK_CapsLock)
        case .option: return UInt32(kVK_Option)
        case .control: return UInt32(kVK_Control)
        case .rightCommand: return UInt32(kVK_RightCommand)
        case .rightShift: return UInt32(kVK_RightShift)
        case .rightOption: return UInt32(kVK_RightOption)
        case .rightControl: return UInt32(kVK_RightControl)
        case .function: return UInt32(kVK_Function)
        case .f17: return UInt32(kVK_F17)
        case .volumeUp: return UInt32(kVK_VolumeUp)
        case .volumeDown: return UInt32(kVK_VolumeDown)
        case .mute: return UInt32(kVK_Mute)
        case .f18: return UInt32(kVK_F18)
        case .f19: return UInt32(kVK_F19)
        case .f20: return UInt32(kVK_F20)
        case .f5: return UInt32(kVK_F5)
        case .f6: return UInt32(kVK_F6)
        case .f7: return UInt32(kVK_F7)
        case .f3: return UInt32(kVK_F3)
        case .f8: return UInt32(kVK_F8)
        case .f9: return UInt32(kVK_F9)
        case .f11: return UInt32(kVK_F11)
        case .f13: return UInt32(kVK_F13)
        case .f16: return UInt32(kVK_F16)
        case .f14: return UInt32(kVK_F14)
        case .f10: return UInt32(kVK_F10)
        case .f12: return UInt32(kVK_F12)
        case .f15: return UInt32(kVK_F15)
        case .help: return UInt32(kVK_Help)
        case .home: return UInt32(kVK_Home)
        case .pageUp: return UInt32(kVK_PageUp)
        case .forwardDelete: return UInt32(kVK_ForwardDelete)
        case .f4: return UInt32(kVK_F4)
        case .end: return UInt32(kVK_End)
        case .f2: return UInt32(kVK_F2)
        case .pageDown: return UInt32(kVK_PageDown)
        case .f1: return UInt32(kVK_F1)
        case .leftArrow: return UInt32(kVK_LeftArrow)
        case .rightArrow: return UInt32(kVK_RightArrow)
        case .downArrow: return UInt32(kVK_DownArrow)
        case .upArrow: return UInt32(kVK_UpArrow)
        }
    }
}

extension Key: CustomStringConvertible {
    public var description: String {
        switch self {
        case .a: return "A"
        case .s: return "S"
        case .d: return "D"
        case .f: return "F"
        case .h: return "H"
        case .g: return "G"
        case .z: return "Z"
        case .x: return "X"
        case .c: return "C"
        case .v: return "V"
        case .b: return "B"
        case .q: return "Q"
        case .w: return "W"
        case .e: return "E"
        case .r: return "R"
        case .y: return "Y"
        case .t: return "T"
        case .one, .keypad1: return "1"
        case .two, .keypad2: return "2"
        case .three, .keypad3: return "3"
        case .four, .keypad4: return "4"
        case .six, .keypad6: return "6"
        case .five, .keypad5: return "5"
        case .equal: return "="
        case .nine, .keypad9: return "9"
        case .seven, .keypad7: return "7"
        case .minus: return "-"
        case .eight, .keypad8: return "8"
        case .zero, .keypad0: return "0"
        case .rightBracket: return "]"
        case .o: return "O"
        case .u: return "U"
        case .leftBracket: return "["
        case .i: return "I"
        case .p: return "P"
        case .l: return "L"
        case .j: return "J"
        case .quote: return "\""
        case .k: return "K"
        case .semicolon: return ";"
        case .backslash: return "\\"
        case .comma: return ","
        case .slash: return "/"
        case .n: return "N"
        case .m: return "M"
        case .period: return "."
        case .grave: return "`"
        case .keypadDecimal: return "."
        case .keypadMultiply: return "𝗑"
        case .keypadPlus: return "+"
        case .keypadClear: return "⌧"
        case .keypadDivide: return "/"
        case .keypadEnter: return "↩︎"
        case .keypadMinus: return "-"
        case .keypadEquals: return "="
        case .return: return "↩︎"
        case .tab: return "⇥"
        case .space: return "␣"
        case .delete: return "⌫"
        case .escape: return "⎋"
        case .command, .rightCommand: return "⌘"
        case .shift, .rightShift: return "⇧"
        case .capsLock: return "⇪"
        case .option, .rightOption: return "⌥"
        case .control, .rightControl: return "⌃"
        case .function: return "fn"
        case .f17: return "F17"
        case .volumeUp: return "🔊"
        case .volumeDown: return "🔉"
        case .mute: return "🔇"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f3: return "F3"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f11: return "F11"
        case .f13: return "F13"
        case .f16: return "F16"
        case .f14: return "F14"
        case .f10: return "F10"
        case .f12: return "F12"
        case .f15: return "F15"
        case .help: return "?⃝"
        case .home: return "↖"
        case .pageUp: return "⇞"
        case .forwardDelete: return "⌦"
        case .f4: return "F4"
        case .end: return "↘"
        case .f2: return "F2"
        case .pageDown: return "⇟"
        case .f1: return "F1"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .downArrow: return "↓"
        case .upArrow: return "↑"
        }
    }
}

extension KeyCombo {
    /// All system key combos
    ///
    /// - returns: array of key combos
    public static func systemKeyCombos() -> [KeyCombo] {
        var unmanagedGlobalHotkeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanagedGlobalHotkeys) == noErr,
            let globalHotkeys = unmanagedGlobalHotkeys?.takeRetainedValue() else {
            assertionFailure("Unable to get system-wide hotkeys")
            return []
        }

        return (0..<CFArrayGetCount(globalHotkeys)).compactMap { i in
            let hotKeyInfo = unsafeBitCast(CFArrayGetValueAtIndex(globalHotkeys, i), to: NSDictionary.self)
            guard (hotKeyInfo[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true,
                let keyCode = (hotKeyInfo[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value,
                let modifiers = (hotKeyInfo[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value else {
                return nil
            }

            let keyCombo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers)

            // Several of these aren’t valid key combos. Filter them out so consumers don’t have to think about this.
            return keyCombo.isValid ? keyCombo : nil
        }
    }

    /// All key combos in the application’s main window
    ///
    /// - returns: array of key combos
    public static func mainMenuKeyCombos() -> [KeyCombo] {
        guard let menu = NSApp.mainMenu else {
            return []
        }

        return keyCombos(in: menu)
    }

    /// Recursively find key combos in a menu
    ///
    /// - parameter menu: menu to search
    ///
    /// - returns: array of key combos
    public static func keyCombos(in menu: NSMenu) -> [KeyCombo] {
        var keyCombos = [KeyCombo]()

        for item in menu.items {
            if let key = Key(string: item.keyEquivalent) {
                keyCombos.append(KeyCombo(key: key, modifiers: item.keyEquivalentModifierMask))
            }

            if let submenu = item.submenu {
                keyCombos += self.keyCombos(in: submenu)
            }
        }

        return keyCombos
    }

    /// Standard application key combos
    ///
    /// - returns: array of key combos
    public static func standardKeyCombos() -> [KeyCombo] {
        return [
            // Application
            KeyCombo(key: .comma, modifiers: .command),
            KeyCombo(key: .h, modifiers: .command),
            KeyCombo(key: .h, modifiers: [.command, .option]),
            KeyCombo(key: .q, modifiers: .command),

            // File
            KeyCombo(key: .n, modifiers: .command),
            KeyCombo(key: .o, modifiers: .command),
            KeyCombo(key: .w, modifiers: .command),
            KeyCombo(key: .s, modifiers: .command),
            KeyCombo(key: .s, modifiers: [.command, .shift]),
            KeyCombo(key: .r, modifiers: .command),
            KeyCombo(key: .p, modifiers: [.command, .shift]),
            KeyCombo(key: .p, modifiers: .command),

            // Edit
            KeyCombo(key: .z, modifiers: .command),
            KeyCombo(key: .z, modifiers: [.command, .shift]),
            KeyCombo(key: .x, modifiers: .command),
            KeyCombo(key: .c, modifiers: .command),
            KeyCombo(key: .v, modifiers: .command),
            KeyCombo(key: .v, modifiers: [.command, .option, .shift]),
            KeyCombo(key: .a, modifiers: .command),
            KeyCombo(key: .f, modifiers: .command),
            KeyCombo(key: .f, modifiers: [.command, .option]),
            KeyCombo(key: .g, modifiers: .command),
            KeyCombo(key: .g, modifiers: [.command, .shift]),
            KeyCombo(key: .e, modifiers: .command),
            KeyCombo(key: .j, modifiers: .command),
            KeyCombo(key: .semicolon, modifiers: [.command, .shift]),
            KeyCombo(key: .semicolon, modifiers: .command),

            // Format
            KeyCombo(key: .t, modifiers: .command),
            KeyCombo(key: .b, modifiers: .command),
            KeyCombo(key: .i, modifiers: .command),
            KeyCombo(key: .u, modifiers: .command),
            KeyCombo(key: .equal, modifiers: [.command, .shift]),
            KeyCombo(key: .minus, modifiers: .command),
            KeyCombo(key: .c, modifiers: [.command, .shift]),
            KeyCombo(key: .c, modifiers: [.command, .option]),
            KeyCombo(key: .v, modifiers: [.command, .option]),
            KeyCombo(key: .leftBracket, modifiers: [.command, .shift]),
            KeyCombo(key: .backslash, modifiers: [.command, .shift]),
            KeyCombo(key: .rightBracket, modifiers: [.command, .shift]),
            KeyCombo(key: .c, modifiers: [.command, .control]),
            KeyCombo(key: .v, modifiers: [.command, .control]),

            // View
            KeyCombo(key: .t, modifiers: [.command, .option]),
            KeyCombo(key: .s, modifiers: [.command, .control]),
            KeyCombo(key: .f, modifiers: [.command, .control]),

            // Window
            KeyCombo(key: .m, modifiers: .command),

            // Help
            KeyCombo(key: .slash, modifiers: [.command, .shift]),
        ]
    }
}

public struct KeyCombo: Equatable {
    // MARK: - Properties

    public var carbonKeyCode: UInt32
    public var carbonModifiers: UInt32

    public var key: Key? {
        get {
            return Key(carbonKeyCode: carbonKeyCode)
        }

        set {
            carbonKeyCode = newValue?.carbonKeyCode ?? 0
        }
    }

    public var modifiers: NSEvent.ModifierFlags {
        get {
            return NSEvent.ModifierFlags(carbonFlags: carbonModifiers)
        }

        set {
            carbonModifiers = modifiers.carbonFlags
        }
    }

    public var isValid: Bool {
        return carbonKeyCode >= 0
    }

    // MARK: - Initializers

    public init(carbonKeyCode: UInt32, carbonModifiers: UInt32 = 0) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    public init(key: Key, modifiers: NSEvent.ModifierFlags = []) {
        self.carbonKeyCode = key.carbonKeyCode
        self.carbonModifiers = modifiers.carbonFlags
    }

    // MARK: - Converting Keys

    public static func carbonKeyCodeToString(_ carbonKeyCode: UInt32) -> String? {
        return nil
    }
}

extension KeyCombo {
    public var dictionary: [String: Any] {
        return [
            "keyCode": Int(carbonKeyCode),
            "modifiers": Int(carbonModifiers),
        ]
    }

    public init?(dictionary: [String: Any]) {
        guard let keyCode = dictionary["keyCode"] as? Int,
            let modifiers = dictionary["modifiers"] as? Int
        else {
            return nil
        }

        self.init(carbonKeyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
    }
}

extension KeyCombo: CustomStringConvertible {
    public var description: String {
        var output = modifiers.description

        if let keyDescription = key?.description {
            output += keyDescription
        }

        return output
    }
}

extension NSEvent.ModifierFlags {
    public var carbonFlags: UInt32 {
        var carbonFlags: UInt32 = 0

        if contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }

        if contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }

        if contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }

        if contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }

        return carbonFlags
    }

    public init(carbonFlags: UInt32) {
        self.init()

        if carbonFlags & UInt32(cmdKey) == UInt32(cmdKey) {
            insert(.command)
        }

        if carbonFlags & UInt32(optionKey) == UInt32(optionKey) {
            insert(.option)
        }

        if carbonFlags & UInt32(controlKey) == UInt32(controlKey) {
            insert(.control)
        }

        if carbonFlags & UInt32(shiftKey) == UInt32(shiftKey) {
            insert(.shift)
        }
    }
}

extension NSEvent.ModifierFlags: CustomStringConvertible {
    public var description: String {
        var output = ""

        if contains(.control) {
            output += Key.control.description
        }

        if contains(.option) {
            output += Key.option.description
        }

        if contains(.shift) {
            output += Key.shift.description
        }

        if contains(.command) {
            output += Key.command.description
        }

        return output
    }
}
