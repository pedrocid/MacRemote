import SwiftUI

/// Virtual keyboard for sending key events
struct KeyboardView: View {
    @ObservedObject var client: NetworkClient
    @State private var textInput = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Text input field
            HStack {
                TextField("Type here...", text: $textInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: textInput) { oldValue, newValue in
                        if newValue.count > oldValue.count {
                            // New character typed
                            if let char = newValue.last {
                                sendCharacter(char)
                            }
                        }
                        // Clear after sending
                        textInput = ""
                    }

                Button {
                    isTextFieldFocused.toggle()
                } label: {
                    Image(systemName: isTextFieldFocused ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.title2)
                }
            }
            .padding(.horizontal)

            // Quick keys
            VStack(spacing: 12) {
                // Function row
                HStack(spacing: 8) {
                    QuickKeyButton(label: "Esc", systemImage: nil) {
                        client.keyPress(code: KeyCodes.escape)
                    }

                    ForEach(1...12, id: \.self) { num in
                        QuickKeyButton(label: "F\(num)", systemImage: nil) {
                            client.keyPress(code: KeyCodes.functionKey(num))
                        }
                    }
                }
                .font(.caption)

                // Navigation row
                HStack(spacing: 12) {
                    QuickKeyButton(label: nil, systemImage: "arrow.left") {
                        client.keyPress(code: KeyCodes.leftArrow)
                    }
                    QuickKeyButton(label: nil, systemImage: "arrow.down") {
                        client.keyPress(code: KeyCodes.downArrow)
                    }
                    QuickKeyButton(label: nil, systemImage: "arrow.up") {
                        client.keyPress(code: KeyCodes.upArrow)
                    }
                    QuickKeyButton(label: nil, systemImage: "arrow.right") {
                        client.keyPress(code: KeyCodes.rightArrow)
                    }

                    Spacer()

                    QuickKeyButton(label: "Delete", systemImage: "delete.left") {
                        client.keyPress(code: KeyCodes.delete)
                    }
                    QuickKeyButton(label: "Return", systemImage: "return") {
                        client.keyPress(code: KeyCodes.returnKey)
                    }
                }

                // Modifier keys row
                HStack(spacing: 12) {
                    QuickKeyButton(label: "Tab", systemImage: "arrow.right.to.line") {
                        client.keyPress(code: KeyCodes.tab)
                    }
                    QuickKeyButton(label: "Space", systemImage: nil) {
                        client.keyPress(code: KeyCodes.space)
                    }
                    .frame(maxWidth: .infinity)

                    // Common shortcuts
                    QuickKeyButton(label: "⌘C", systemImage: nil) {
                        client.send(.key(code: KeyCodes.c, down: true, flags: KeyCodes.maskCommand))
                        client.send(.key(code: KeyCodes.c, down: false, flags: KeyCodes.maskCommand))
                    }
                    QuickKeyButton(label: "⌘V", systemImage: nil) {
                        client.send(.key(code: KeyCodes.v, down: true, flags: KeyCodes.maskCommand))
                        client.send(.key(code: KeyCodes.v, down: false, flags: KeyCodes.maskCommand))
                    }
                    QuickKeyButton(label: "⌘Z", systemImage: nil) {
                        client.send(.key(code: KeyCodes.z, down: true, flags: KeyCodes.maskCommand))
                        client.send(.key(code: KeyCodes.z, down: false, flags: KeyCodes.maskCommand))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func sendCharacter(_ char: Character) {
        if let keyCode = KeyCodes.code(for: char) {
            let needsShift = char.isUppercase || KeyCodes.shiftCharacters.contains(char)
            let flags: UInt64 = needsShift ? KeyCodes.maskShift : 0
            client.send(.key(code: keyCode, down: true, flags: flags))
            client.send(.key(code: keyCode, down: false, flags: flags))
        }
    }
}

struct QuickKeyButton: View {
    let label: String?
    let systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage = systemImage {
                    if let label = label {
                        Label(label, systemImage: systemImage)
                    } else {
                        Image(systemName: systemImage)
                    }
                } else if let label = label {
                    Text(label)
                }
            }
            .font(.system(.body, design: .rounded))
            .frame(minWidth: 36, minHeight: 36)
            .background(Color(.systemGray5))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

/// macOS virtual key codes
enum KeyCodes {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51

    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static let a: UInt16 = 0
    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let z: UInt16 = 6

    static let shiftCharacters: Set<Character> = Set("~!@#$%^&*()_+{}|:\"<>?")

    // CGEventFlags values (from macOS CoreGraphics)
    static let maskShift: UInt64 = 0x00020000
    static let maskCommand: UInt64 = 0x00100000
    static let maskControl: UInt64 = 0x00040000
    static let maskOption: UInt64 = 0x00080000

    static func functionKey(_ number: Int) -> UInt16 {
        switch number {
        case 1: return 122
        case 2: return 120
        case 3: return 99
        case 4: return 118
        case 5: return 96
        case 6: return 97
        case 7: return 98
        case 8: return 100
        case 9: return 101
        case 10: return 109
        case 11: return 103
        case 12: return 111
        default: return 0
        }
    }

    static func code(for character: Character) -> UInt16? {
        let char = character.lowercased().first ?? character
        let mapping: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
            "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
            "`": 50, " ": 49
        ]
        return mapping[char]
    }
}
