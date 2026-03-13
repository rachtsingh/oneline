import SwiftUI
import AppKit

struct ReadlineTextField: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> ReadlineNSTextField {
        let field = ReadlineNSTextField()
        field.delegate = context.coordinator
        field.font = font
        field.textColor = textColor
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.onSubmit = onSubmit
        return field
    }

    func updateNSView(_ nsView: ReadlineNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.font = font
        nsView.textColor = textColor
        nsView.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ReadlineTextField

        init(_ parent: ReadlineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

class ReadlineNSTextField: NSTextField {
    var onSubmit: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control) else {
            return super.performKeyEquivalent(with: event)
        }

        guard let editor = currentEditor() as? NSTextView else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "u":
            // Kill line backward (Ctrl+U)
            let range = NSRange(location: 0, length: editor.selectedRange().location)
            editor.setSelectedRange(range)
            editor.delete(nil)
            return true
        case "w":
            // Kill word backward (Ctrl+W)
            editor.deleteWordBackward(nil)
            return true
        case "a":
            // Move to beginning (Ctrl+A)
            editor.moveToBeginningOfLine(nil)
            return true
        case "e":
            // Move to end (Ctrl+E)
            editor.moveToEndOfLine(nil)
            return true
        case "k":
            // Kill to end of line (Ctrl+K)
            editor.deleteToEndOfLine(nil)
            return true
        case "f":
            // Forward one char (Ctrl+F)
            editor.moveForward(nil)
            return true
        case "b":
            // Back one char (Ctrl+B)
            editor.moveBackward(nil)
            return true
        case "d":
            // Delete forward (Ctrl+D)
            editor.deleteForward(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        if let movement = notification.userInfo?["NSTextMovement"] as? Int,
           movement == NSReturnTextMovement {
            onSubmit?()
        }
    }
}
