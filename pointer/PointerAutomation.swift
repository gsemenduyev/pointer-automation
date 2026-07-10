import Cocoa
import Foundation
import ApplicationServices

enum AppState {
    case idle
    case running
}

let app = NSApplication.shared
let delegate = PointerAutomationAppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

final class PointerAutomationAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var toggleItem: NSMenuItem?
    private var remainingItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    private let totalTimeField = NSTextField(string: "")
    private let intervalField = NSTextField(string: "")
    private let moveModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let distanceField = NSTextField(string: "")

    private var state: AppState = .idle
    private var workerProcess: Process?
    private var countdownTimer: Timer?
    private var remainingSeconds: Int = 0
    private var didRequestAccessibilityPrompt = false
    private var didShowAccessibilityHelp = false

    private let scriptDir = URL(fileURLWithPath: Bundle.main.bundlePath)
        .deletingLastPathComponent()
        .path

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        showNotification(title: "Pointer Automation ready", message: "Use the menu bar icon to start or open Settings.")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopAutomation()
        return .terminateNow
    }

    @objc private func toggleAutomation() {
        switch state {
        case .idle:
            startAutomation()
        case .running:
            stopAutomation()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            toggleAutomation()
            return
        }

        if event.type == .rightMouseUp {
            if let menu = statusMenu, let item = statusItem {
                item.popUpMenu(menu)
            }
            return
        }

        toggleAutomation()
    }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = createSettingsWindow()
        }

        loadConfigIntoSettingsFields()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func saveSettings() {
        let total = totalTimeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let interval = intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = moveModePopup.titleOfSelectedItem ?? "small"
        let distance = distanceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let totalDouble = Double(total), totalDouble > 0 else {
            showAlert(title: "Invalid Settings", message: "TOTAL_TIME_MINUTES must be a number greater than 0.")
            return
        }
        guard let intervalInt = Int(interval), intervalInt > 0 else {
            showAlert(title: "Invalid Settings", message: "INTERVAL_SECONDS must be a positive integer.")
            return
        }
        guard mode == "small" || mode == "large" else {
            showAlert(title: "Invalid Settings", message: "MOUSE_MOVE_MODE must be small or large.")
            return
        }
        guard let distanceInt = Int(distance), distanceInt > 0 else {
            showAlert(title: "Invalid Settings", message: "MOVE_DISTANCE_PIXELS must be a positive integer.")
            return
        }

        let configPath = "\(scriptDir)/pointer_config.sh"
        let configText = """
        #!/usr/bin/env bash

        # Pointer Automation settings.
        TOTAL_TIME_MINUTES=\(totalDouble)
        INTERVAL_SECONDS=\(intervalInt)
        MOUSE_MOVE_MODE=\(mode)
        MOVE_DISTANCE_PIXELS=\(distanceInt)
        """

        do {
            try configText.write(toFile: configPath, atomically: true, encoding: .utf8)
            settingsWindow?.orderOut(nil)
            showAlert(title: "Settings Saved", message: "Configuration updated. Changes apply on next start.")
        } catch {
            showAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }

    @objc private func closeSettings() {
        settingsWindow?.orderOut(nil)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked)
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Start Automation", action: #selector(toggleAutomation), keyEquivalent: "")
        toggle.target = self
        toggleItem = toggle
        menu.addItem(toggle)

        let remaining = NSMenuItem(title: "Remaining: --:--", action: nil, keyEquivalent: "")
        remaining.isEnabled = false
        remainingItem = remaining
        menu.addItem(remaining)

        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusMenu = menu
        updateVisualState()
    }

    private func updateVisualState() {
        switch state {
        case .idle:
            toggleItem?.title = "Start Automation"
            remainingItem?.title = "Remaining: --:--"
            setStatusSymbol(systemName: "play.circle.fill", fallbackTitle: "PA")
        case .running:
            toggleItem?.title = "Stop Automation"
            remainingItem?.title = "Remaining: \(formatSeconds(remainingSeconds))"
            setStatusSymbol(systemName: "stop.circle.fill", fallbackTitle: "PA")
        }
    }

    private func setStatusSymbol(systemName: String, fallbackTitle: String) {
        guard let button = statusItem?.button else {
            return
        }

        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let image = NSImage(systemSymbolName: systemName, accessibilityDescription: "Pointer Automation")?.withSymbolConfiguration(config)
            button.image = image
            button.title = ""
            button.image?.isTemplate = true
        } else {
            button.image = nil
            button.title = fallbackTitle
        }
    }

    private func startAutomation() {
        guard ensureAccessibilityPermission() else {
            return
        }

        let configPath = "\(scriptDir)/pointer_config.sh"
        guard let configContent = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            showAlert(title: "Missing Config", message: "Could not read pointer_config.sh")
            return
        }

        guard let minutes = parseDoubleValue(named: "TOTAL_TIME_MINUTES", from: configContent), minutes > 0 else {
            showAlert(title: "Invalid Config", message: "TOTAL_TIME_MINUTES must be greater than 0.")
            return
        }

        let workerPath = "\(scriptDir)/pointer_worker.sh"
        guard FileManager.default.isReadableFile(atPath: workerPath) else {
            showAlert(title: "Missing Worker", message: "Could not find pointer_worker.sh")
            return
        }

        remainingSeconds = Int(ceil(minutes * 60.0))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [workerPath]
        process.currentDirectoryURL = URL(fileURLWithPath: scriptDir)

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.finishAutomationIfNeeded(exitCode: proc.terminationStatus)
            }
        }

        do {
            try process.run()
            workerProcess = process
            state = .running
            startCountdown()
            updateVisualState()
            showNotification(title: "Pointer Automation", message: "Automation started.")
        } catch {
            showAlert(title: "Start Failed", message: error.localizedDescription)
        }
    }

    private func finishAutomationIfNeeded(exitCode: Int32) {
        if state == .running {
            stopAutomation(showAlertOnStop: false)
            if exitCode != 0 {
                showAlert(title: "Automation Ended Early", message: "Worker exited with code \(exitCode). Check permissions and settings.")
            }
        }
    }

    private func stopAutomation(showAlertOnStop: Bool = false) {
        countdownTimer?.invalidate()
        countdownTimer = nil

        if let process = workerProcess, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    process.interrupt()
                }
            }
        }

        workerProcess = nil
        remainingSeconds = 0
        state = .idle
        updateVisualState()

        if showAlertOnStop {
            showAlert(title: "Stopped", message: "Pointer automation stopped.")
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            }
            self.remainingItem?.title = "Remaining: \(self.formatSeconds(self.remainingSeconds))"
            if self.remainingSeconds <= 0 {
                self.stopAutomation(showAlertOnStop: false)
            }
        }
    }

    private func parseDoubleValue(named key: String, from content: String) -> Double? {
        let pattern = "^\\s*\(NSRegularExpression.escapedPattern(for: key))=([0-9]+(?:\\.[0-9]+)?)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return Double(content[valueRange])
    }

    private func parseStringValue(named key: String, from content: String) -> String? {
        let pattern = "^\\s*\(NSRegularExpression.escapedPattern(for: key))=(\\S+)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return String(content[valueRange])
    }

    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        if !didRequestAccessibilityPrompt {
            didRequestAccessibilityPrompt = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        if !didShowAccessibilityHelp {
            didShowAccessibilityHelp = true
            showAlert(
                title: "Permission Required",
                message: "Enable Accessibility for PointerAutomation.app in System Settings > Privacy & Security > Accessibility, then restart the app once."
            )
        }

        return false
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let mins = s / 60
        let rem = s % 60
        return String(format: "%02d:%02d", mins, rem)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showNotification(title: String, message: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "display notification \"\(message)\" with title \"\(title)\""]
        try? task.run()
    }

    private func createSettingsWindow() -> NSWindow {
        moveModePopup.removeAllItems()
        moveModePopup.addItems(withTitles: ["small", "large"])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pointer Automation Settings"
        window.isReleasedWhenClosed = false

        let contentView = NSView()
        window.contentView = contentView

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        rootStack.addArrangedSubview(makeRow(label: "TOTAL_TIME_MINUTES", control: totalTimeField))
        rootStack.addArrangedSubview(makeRow(label: "INTERVAL_SECONDS", control: intervalField))
        rootStack.addArrangedSubview(makeRow(label: "MOUSE_MOVE_MODE", control: moveModePopup))
        rootStack.addArrangedSubview(makeRow(label: "MOVE_DISTANCE_PIXELS", control: distanceField))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(closeSettings))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(saveButton)

        rootStack.addArrangedSubview(buttons)
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        return window
    }

    private func makeRow(label: String, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        control.translatesAutoresizingMaskIntoConstraints = false
        if let textControl = control as? NSTextField {
            textControl.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }

        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        title.widthAnchor.constraint(equalToConstant: 180).isActive = true
        control.widthAnchor.constraint(equalToConstant: 180).isActive = true

        return row
    }

    private func loadConfigIntoSettingsFields() {
        let configPath = "\(scriptDir)/pointer_config.sh"
        guard let config = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return
        }

        totalTimeField.stringValue = parseStringValue(named: "TOTAL_TIME_MINUTES", from: config) ?? "0.25"
        intervalField.stringValue = parseStringValue(named: "INTERVAL_SECONDS", from: config) ?? "2"
        distanceField.stringValue = parseStringValue(named: "MOVE_DISTANCE_PIXELS", from: config) ?? "120"

        let mode = parseStringValue(named: "MOUSE_MOVE_MODE", from: config) ?? "small"
        moveModePopup.selectItem(withTitle: mode)
    }
}
