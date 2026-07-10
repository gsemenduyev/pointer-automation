import CoreGraphics
import Foundation

enum MoveMode: String {
    case small
    case large
}

func postMove(to point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
        return
    }
    event.post(tap: .cghidEventTap)
}

func currentMouseLocation() -> CGPoint? {
    guard let event = CGEvent(source: nil) else {
        return nil
    }
    return event.location
}

func pointDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return sqrt(dx * dx + dy * dy)
}

guard let origin = currentMouseLocation() else {
    fputs("Unable to read current mouse location.\n", stderr)
    exit(1)
}

let modeArg = CommandLine.arguments.dropFirst().first ?? "small"
let mode = MoveMode(rawValue: modeArg) ?? .small
let distanceArg = CommandLine.arguments.dropFirst(2).first ?? "120"

guard let distanceValue = Double(distanceArg), distanceValue > 0 else {
    fputs("MOVE_DISTANCE_PIXELS must be a positive number.\n", stderr)
    exit(1)
}

let distance = CGFloat(distanceValue)

switch mode {
case .small:
    let p1 = CGPoint(x: origin.x + distance, y: origin.y)
    let p2 = CGPoint(x: origin.x + distance, y: origin.y + distance)
    postMove(to: p1)
    usleep(180_000)
    if let moved = currentMouseLocation(), pointDistance(moved, origin) < 0.5 {
        fputs("Pointer move appears blocked (Accessibility/Input Monitoring not granted).\n", stderr)
        exit(2)
    }
    postMove(to: p2)
    usleep(180_000)
    postMove(to: origin)
case .large:
    let pause: useconds_t = 180_000

    let p1 = CGPoint(x: origin.x + distance, y: origin.y)
    let p2 = CGPoint(x: origin.x + distance, y: origin.y + distance)
    let p3 = CGPoint(x: origin.x, y: origin.y + distance)

    postMove(to: p1)
    usleep(pause)
    if let moved = currentMouseLocation(), pointDistance(moved, origin) < 0.5 {
        fputs("Pointer move appears blocked (Accessibility/Input Monitoring not granted).\n", stderr)
        exit(2)
    }
    postMove(to: p2)
    usleep(pause)
    postMove(to: p3)
    usleep(pause)
    postMove(to: origin)
}
