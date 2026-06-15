import Cocoa

let source = CGEventSource(stateID: .combinedSessionState)
let cgEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 100, y: 100), mouseButton: .left)!

// Try undocumented field 110
if let field = CGEventField(rawValue: 110) {
    let stage = cgEvent.getIntegerValueField(field)
    print("Stage from undocumented field: \(stage)")
} else {
    print("Field 110 not found")
}

// Try pressure
let pressure = cgEvent.getDoubleValueField(.mouseEventPressure)
print("Pressure: \(pressure)")
