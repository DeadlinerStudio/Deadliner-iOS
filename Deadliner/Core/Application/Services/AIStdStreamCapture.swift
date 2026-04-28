//
//  AIStdStreamCapture.swift
//  Deadliner
//

import Foundation
import Darwin

final class AIStdStreamCapture {
    static let shared = AIStdStreamCapture()

    private let queue = DispatchQueue(label: "deadliner.ai.stdout.capture")
    private var readSource: DispatchSourceRead?

    private var isStarted = false
    private var pipeReadFD: Int32 = -1
    private var pipeWriteFD: Int32 = -1
    private var stdoutBackupFD: Int32 = -1
    private var stderrBackupFD: Int32 = -1

    private var pendingLine = ""

    private init() {}

    func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true

        // Disable stdio buffering so Rust/Swift prints can be flushed immediately.
        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else {
            isStarted = false
            return
        }

        pipeReadFD = fds[0]
        pipeWriteFD = fds[1]
        stdoutBackupFD = dup(STDOUT_FILENO)
        stderrBackupFD = dup(STDERR_FILENO)

        guard stdoutBackupFD >= 0, stderrBackupFD >= 0 else {
            closeIfNeeded(pipeReadFD)
            closeIfNeeded(pipeWriteFD)
            isStarted = false
            return
        }

        // Route both stdout/stderr to the same pipe.
        _ = dup2(pipeWriteFD, STDOUT_FILENO)
        _ = dup2(pipeWriteFD, STDERR_FILENO)

        let source = DispatchSource.makeReadSource(fileDescriptor: pipeReadFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainPipe()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            self.closeIfNeeded(self.pipeReadFD)
            self.closeIfNeeded(self.pipeWriteFD)
        }
        source.resume()
        readSource = source

        AILog.log("[StdCapture] started")
    }

    private func drainPipe() {
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(pipeReadFD, &buffer, buffer.count)
            if count > 0 {
                let data = Data(buffer[0..<count])
                mirrorToOriginalConsole(data: data)
                collectForAILog(data: data)
            } else {
                break
            }
        }
    }

    private func mirrorToOriginalConsole(data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            if stdoutBackupFD >= 0 {
                _ = write(stdoutBackupFD, base, raw.count)
            }
            if stderrBackupFD >= 0 {
                _ = write(stderrBackupFD, base, raw.count)
            }
        }
    }

    private func collectForAILog(data: Data) {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

        pendingLine += chunk
        let parts = pendingLine.components(separatedBy: .newlines)

        if parts.isEmpty {
            return
        }

        for line in parts.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            AILog.log(trimmed)
        }

        pendingLine = parts.last ?? ""
    }

    private func closeIfNeeded(_ fd: Int32) {
        if fd >= 0 {
            close(fd)
        }
    }
}
