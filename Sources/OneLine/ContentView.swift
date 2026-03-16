import SwiftUI

struct ContentView: View {
    @StateObject private var logManager = LogManager()
    @ObservedObject private var slackManager = SlackManager.shared
    @State private var inputText = ""

    @Environment(\.colorScheme) private var colorScheme

    private var timestampColor: Color {
        colorScheme == .dark
            ? Color(red: 0x71/255.0, green: 0x89/255.0, blue: 0xD1/255.0)
            : Color(red: 0x11/255.0, green: 0x29/255.0, blue: 0x70/255.0)
    }
    private var textColor: Color {
        colorScheme == .dark
            ? Color(red: 0xB0/255.0, green: 0xB8/255.0, blue: 0xC8/255.0)
            : Color(red: 0x7A/255.0, green: 0x7A/255.0, blue: 0x7A/255.0)
    }
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0x00/255.0, green: 0x26/255.0, blue: 0x47/255.0)
            : Color(.windowBackgroundColor)
    }

    private func robotoMono(_ size: CGFloat) -> Font {
        .custom("Roboto Mono", size: size)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar showing current file
            HStack {
                Text(logManager.currentFileName)
                    .font(robotoMono(12))
                    .foregroundColor(.secondary)
                Spacer()
                slackMenuButton
                Button {
                    chooseDirectory()
                } label: {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Change log directory")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Log viewer
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logManager.lines.enumerated()), id: \.offset) { index, line in
                            logLineView(line)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: logManager.lines.count) { _, newCount in
                    if newCount > 0 {
                        withAnimation {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input field
            ReadlineTextField(
                text: $inputText,
                font: NSFont(name: "Roboto Mono", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular),
                textColor: colorScheme == .dark ? NSColor(calibratedRed: 0xB0/255.0, green: 0xB8/255.0, blue: 0xC8/255.0, alpha: 1) : NSColor(calibratedRed: 0x3C/255.0, green: 0x3C/255.0, blue: 0x3C/255.0, alpha: 1)
            ) {
                let entry = inputText
                logManager.appendEntry(entry)
                slackManager.updateStatus(text: entry)
                inputText = ""
            }
            .frame(height: 20)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(backgroundColor)
        .onAppear {
            applyWindowBackground()
        }
        .onChange(of: colorScheme) { _, _ in
            applyWindowBackground()
        }
    }

    private func applyWindowBackground() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            if colorScheme == .dark {
                window.backgroundColor = NSColor(calibratedRed: 0x00/255.0, green: 0x26/255.0, blue: 0x47/255.0, alpha: 1)
            } else {
                window.backgroundColor = .windowBackgroundColor
            }
        }
    }

    @ViewBuilder
    private func logLineView(_ line: String) -> some View {
        let parsed = parseLine(line)
        HStack(alignment: .top, spacing: 0) {
            Text(parsed.timestamp)
                .foregroundColor(timestampColor)
            Text(" ")
            Text(parsed.message)
                .foregroundColor(textColor)
            Spacer()
        }
        .font(robotoMono(13))
        .tracking(-13 * 0.05)
        .textSelection(.enabled)
    }

    private func parseLine(_ line: String) -> (timestamp: String, message: String) {
        // Expected format: [HH:mm:ss] message
        guard line.hasPrefix("["),
              let closeBracket = line.firstIndex(of: "]") else {
            return ("", line)
        }
        let timestamp = String(line[line.startIndex...closeBracket])
        let rest = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .init(charactersIn: " "))
        return (timestamp, rest)
    }

    @ViewBuilder
    private var slackMenuButton: some View {
        Menu {
            if slackManager.isAuthenticated {
                if slackManager.isPaused {
                    Text("Syncing paused")
                } else {
                    Button("Pause Slack syncing for 1 day") {
                        slackManager.pauseForOneDay()
                    }
                }
                Divider()
                Button("Remove Slack connection") {
                    slackManager.disconnect()
                }
            } else {
                Button("Connect to Slack") {
                    slackManager.startOAuth()
                }
            }
        } label: {
            Image(systemName: "bubble.left")
                .foregroundColor(slackManager.isAuthenticated && !slackManager.isPaused ? .accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(slackManager.isAuthenticated ? "Slack options" : "Connect to Slack")
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a directory for daily log files"
        if panel.runModal() == .OK, let url = panel.url {
            logManager.setDirectory(url)
        }
    }
}
