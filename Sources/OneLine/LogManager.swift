import Foundation
import Combine

final class LogManager: ObservableObject {
    @Published var lines: [String] = []
    @Published var currentFileName: String = ""
    @Published var logDirectory: URL

    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1
    private var dateCheckTimer: Timer?
    private var currentDate: String = ""

    private static let defaultDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/daily_log", isDirectory: true)
    }()

    private static let directoryKey = "logDirectory"

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.directoryKey) {
            self.logDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            self.logDirectory = Self.defaultDirectory
        }
        ensureDirectory()
        loadToday()
        startDateCheckTimer()
    }

    func setDirectory(_ url: URL) {
        logDirectory = url
        UserDefaults.standard.set(url.path, forKey: Self.directoryKey)
        ensureDirectory()
        loadToday()
    }

    func appendEntry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(trimmed)\n"

        ensureDirectory()
        let fileURL = todayFileURL()
        let isNewFile = !FileManager.default.fileExists(atPath: fileURL.path)

        if isNewFile {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()

        loadFile()

        // Switch from directory watching to file watching after first write
        if isNewFile {
            stopWatchingDirectory()
            watchFile()
        }
    }

    // MARK: - Private

    private func todayFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let name = formatter.string(from: Date())
        return logDirectory.appendingPathComponent("\(name).log")
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    private func loadToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        currentDate = formatter.string(from: Date())

        let fileURL = todayFileURL()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var display = fileURL.path
        if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        currentFileName = display

        loadFile()
        stopWatching()
        stopWatchingDirectory()

        if FileManager.default.fileExists(atPath: fileURL.path) {
            watchFile()
        } else {
            watchDirectory()
        }
    }

    private func loadFile() {
        let fileURL = todayFileURL()
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            lines = []
            return
        }
        lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - File watching

    private func watchFile() {
        stopWatching()

        let fileURL = todayFileURL()
        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.loadFile()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source.resume()
        fileMonitor = source
    }

    private func stopWatching() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    // MARK: - Directory watching (until today's file appears)

    private func watchDirectory() {
        stopWatchingDirectory()

        directoryDescriptor = open(logDirectory.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.todayFileURL().path) {
                self.stopWatchingDirectory()
                self.loadFile()
                self.watchFile()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.directoryDescriptor >= 0 {
                close(self.directoryDescriptor)
                self.directoryDescriptor = -1
            }
        }

        source.resume()
        directoryMonitor = source
    }

    private func stopWatchingDirectory() {
        directoryMonitor?.cancel()
        directoryMonitor = nil
    }

    // MARK: - Date rollover

    private func startDateCheckTimer() {
        dateCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkDateRollover()
        }
    }

    private func checkDateRollover() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let today = formatter.string(from: Date())
        if today != currentDate {
            loadToday()
        }
    }

    deinit {
        stopWatching()
        stopWatchingDirectory()
        dateCheckTimer?.invalidate()
    }
}
