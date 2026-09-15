import AppKit

let app = NSApplication.shared
TypeStyle.register()
if CommandLine.arguments.contains("--ordered-marker-check") {
    do { try runOrderedMarkerTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--last-line-check") {
    do { try runLastLineTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--self-test") {
    do { try runSelfTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
let args = CommandLine.arguments
if args.contains("--render-edge-icon"), let i = args.firstIndex(of: "--output"), args.count > i + 1 {
    let icon = EdgeHandleButton(frame: NSRect(x: 0, y: 0, width: 44, height: 48))
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 176, pixelsHigh: 192, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = NSAffineTransform(); scale.scale(by: 4); scale.concat()
    icon.draw(icon.bounds)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[i + 1]))
    exit(0)
}
if args.contains("--notes-health-check"), let i = args.firstIndex(of: "--health-result"), args.count > i + 1 {
    let resultFile = URL(fileURLWithPath: args[i + 1])
    let permission = NotesBridge.permissionStatus()
    try? "Permission status: \(permission)\n".write(to: resultFile, atomically: true, encoding: .utf8)
    if permission != noErr { exit(0) }
    let bridge = NotesBridge()
    bridge.health { result in
        let description: String
        switch result {
        case .success: description = "Permission status: 0\nNotes scripting responds: yes\n"
        case .failure(let error): description = "Permission status: 0\nNotes scripting failed: \(error.localizedDescription)\n"
        }
        try? description.write(to: resultFile, atomically: true, encoding: .utf8)
        exit(0)
    }
    NSApp.setActivationPolicy(.accessory)
    withExtendedLifetime(bridge) { app.run() }
    exit(0)
}
let directory: URL
if let i = args.firstIndex(of: "--data-dir"), args.count > i + 1 { directory = URL(fileURLWithPath: args[i + 1]) }
else { directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeskNotes") }
if args.contains("--diagnose-current-sync"), let i = args.firstIndex(of: "--output"), args.count > i + 1 {
    diagnoseCurrentSync(directory: directory, output: URL(fileURLWithPath: args[i + 1])) { exit(0) }
    NSApp.setActivationPolicy(.accessory); app.run(); exit(0)
}
if args.contains("--diagnose-latest-sync"), let i = args.firstIndex(of: "--output"), args.count > i + 1 {
    diagnoseLatestSync(directory: directory, output: URL(fileURLWithPath: args[i + 1])) { exit(0) }
    NSApp.setActivationPolicy(.accessory); app.run(); exit(0)
}
do {
    let store = try NoteStore(directory: directory)
    if args.contains("--notes-format-probe") {
        let bridge = NotesBridge()
        runNotesFormatProbe(bridge: bridge, directory: directory) { exit(0) }
        NSApp.setActivationPolicy(.accessory)
        withExtendedLifetime(bridge) { app.run() }
        exit(0)
    }
    if args.contains("--rich-integration-check") {
        let bridge = NotesBridge()
        runRichLiveTests(bridge: bridge, directory: directory) { exit(0) }
        NSApp.setActivationPolicy(.accessory)
        withExtendedLifetime(bridge) { app.run() }
        exit(0)
    }
    if args.contains("--notes-integration-check") {
        let bridge = NotesBridge()
        runNotesIntegrationTest(bridge: bridge, directory: directory) { exit(0) }
        NSApp.setActivationPolicy(.accessory)
        withExtendedLifetime(bridge) { app.run() }
        exit(0)
    }
    let delegate = AppDelegate(store: store)
    delegate.syncEnabled = !args.contains("--offline")
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} catch {
    let alert = NSAlert(); alert.messageText = "无法打开旁白数据"; alert.informativeText = error.localizedDescription + "\n原文件仍然保留。"; alert.runModal()
    exit(1)
}
