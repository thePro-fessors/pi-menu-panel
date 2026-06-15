import Cocoa
for i in 0...35 {
    if let type = CGEventType(rawValue: UInt32(i)) {
        print("\(i): \(type)")
    }
}
