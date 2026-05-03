//
//  SpeechInputService.swift
//  Deadliner
//
//  Created by Codex on 2026/4/1.
//

import AVFAudio
import Combine
import Foundation
import Speech

@MainActor
final class SpeechInputService: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case installingAssets
        case recording
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var composedText: String = ""
    @Published private(set) var helperText: String?
    @Published private(set) var lastErrorMessage: String?

    private let audioEngine = AVAudioEngine()

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var baseText: String = ""
    private var hasRecognizedSpeech: Bool = false
    private var suppressNextRecognitionError: Bool = false
    private var latestSegmentTranscript: String = ""
    private let rollbackDropThreshold = 6

    var isRecording: Bool {
        state == .recording
    }

    var isBusy: Bool {
        state != .idle
    }

    private func speechLog(_ message: String) {
        AILog.log("[Speech] \(message)")
    }

    private func stateSnapshot() -> String {
        "state=\(state) composedLen=\(composedText.count) baseLen=\(baseText.count) latestLen=\(latestSegmentTranscript.count) hasRecognized=\(hasRecognizedSpeech) suppressNextError=\(suppressNextRecognitionError)"
    }

    func startRecording(initialText: String) async throws {
        guard state == .idle else { return }

        speechLog("startRecording.begin initialLen=\(initialText.count) \(stateSnapshot())")
        state = .preparing
        baseText = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        composedText = initialText
        helperText = "正在听写..."
        lastErrorMessage = nil
        hasRecognizedSpeech = false
        suppressNextRecognitionError = false
        latestSegmentTranscript = ""

        do {
            try await requestPermissionsIfNeeded()

            let locale = resolveLocale()
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
                throw SpeechInputError.unavailable
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = request
            speechRecognizer = recognizer

            try configureAudioSession()

            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    Task { @MainActor in
                        self.speechLog("callback.result isFinal=\(result.isFinal) rawLen=\(result.bestTranscription.formattedString.count) \(self.stateSnapshot())")
                        guard self.state == .recording else {
                            self.speechLog("callback.result.ignoredNotRecording")
                            return
                        }
                        let transcript = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !transcript.isEmpty {
                            if self.shouldStartNewSegment(transcript) {
                                self.speechLog("callback.result.newSegmentDetected transcriptLen=\(transcript.count) latestLen=\(self.latestSegmentTranscript.count) composedLen=\(self.composedText.count)")
                                self.baseText = self.composedText
                                self.latestSegmentTranscript = ""
                            }
                            self.hasRecognizedSpeech = true
                            self.latestSegmentTranscript = transcript
                            self.helperText = "继续说，我在听"
                            self.composedText = self.mergeBaseTextWithTranscript(transcript)
                            self.speechLog("callback.result.applied transcriptLen=\(transcript.count) composedLen=\(self.composedText.count)")
                        } else {
                            self.speechLog("callback.result.ignoredEmpty")
                        }
                        if result.isFinal {
                            self.speechLog("callback.result.final -> finishRecognitionPipeline")
                            await self.finishRecognitionPipeline(keepText: true)
                        }
                    }
                }

                if let error {
                    Task { @MainActor in
                        self.speechLog("callback.error \(error.localizedDescription) \(self.stateSnapshot())")
                        guard self.state == .recording || self.suppressNextRecognitionError else {
                            self.speechLog("callback.error.ignoredNotRecording")
                            return
                        }
                        await self.fail(with: error)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording
            speechLog("startRecording.success \(stateSnapshot())")
        } catch {
            speechLog("startRecording.catch error=\(error.localizedDescription) \(stateSnapshot())")
            await resetPipeline()
            state = .idle
            throw error
        }
    }

    func stopRecording() async throws {
        guard isBusy else { return }

        speechLog("stopRecording.begin \(stateSnapshot())")
        // User-initiated stop should keep current composed text even if
        // recognizer returns a late cancellation error callback.
        suppressNextRecognitionError = true
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        baseText = composedText

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        helperText = nil
        if !hasRecognizedSpeech {
            lastErrorMessage = SpeechInputError.noSpeechDetected.localizedDescription
        }
        state = .idle
        speechLog("stopRecording.end \(stateSnapshot())")
    }

    func cancelRecording() async {
        speechLog("cancelRecording.begin \(stateSnapshot())")
        await resetPipeline()
        state = .idle
        speechLog("cancelRecording.end \(stateSnapshot())")
    }

    private func requestPermissionsIfNeeded() async throws {
        let micAllowed = await requestMicrophonePermission()
        guard micAllowed else {
            throw SpeechInputError.microphonePermissionDenied
        }

        let speechStatus = await requestSpeechPermission()
        guard speechStatus == .authorized else {
            throw SpeechInputError.speechPermissionDenied
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func resolveLocale() -> Locale {
        let preferredIdentifier = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        return Locale(identifier: preferredIdentifier)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetoothHFP, .duckOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func mergeBaseTextWithTranscript(_ transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return baseText }
        guard !baseText.isEmpty else { return trimmedTranscript }
        if trimmedTranscript == baseText { return baseText }
        if baseText.hasSuffix(trimmedTranscript) { return baseText }
        if trimmedTranscript.hasPrefix(baseText) { return trimmedTranscript }

        let needsNewline = !baseText.hasSuffix("\n")
        return baseText + (needsNewline ? "\n" : "") + trimmedTranscript
    }

    private func shouldStartNewSegment(_ transcript: String) -> Bool {
        guard !latestSegmentTranscript.isEmpty else { return false }
        // Recognizer occasionally resets partial transcript after long pauses.
        // When that happens, treat it as a new segment and append forward.
        if transcript.count + rollbackDropThreshold < latestSegmentTranscript.count {
            return true
        }
        if !latestSegmentTranscript.hasPrefix(transcript) && !transcript.hasPrefix(latestSegmentTranscript) {
            return transcript.count <= rollbackDropThreshold
        }
        return false
    }

    private func fail(with error: Error) async {
        speechLog("fail.begin error=\(error.localizedDescription) \(stateSnapshot())")
        if suppressNextRecognitionError {
            suppressNextRecognitionError = false
            await resetPipeline(keepText: true)
            state = .idle
            speechLog("fail.suppressed -> keepText=true \(stateSnapshot())")
            return
        }

        // Keep recognized text when transient recognition errors happen
        // (e.g. a short pause in dictation causing a task interruption).
        let keepCurrentText = hasRecognizedSpeech
            || !composedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        await resetPipeline(keepText: keepCurrentText)
        if keepCurrentText {
            lastErrorMessage = nil
        } else {
            lastErrorMessage = error.localizedDescription
        }
        state = .idle
        speechLog("fail.end keepCurrentText=\(keepCurrentText) \(stateSnapshot())")
    }

    private func finishRecognitionPipeline(keepText: Bool) async {
        speechLog("finishRecognitionPipeline.begin keepText=\(keepText) \(stateSnapshot())")
        await resetPipeline(keepText: keepText)
        state = .idle
        speechLog("finishRecognitionPipeline.end \(stateSnapshot())")
    }

    private func resetPipeline(keepText: Bool = false) async {
        speechLog("resetPipeline.begin keepText=\(keepText) \(stateSnapshot())")
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        speechRecognizer = nil
        helperText = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if !keepText {
            composedText = baseText
        }
        speechLog("resetPipeline.end keepText=\(keepText) \(stateSnapshot())")
    }
}

enum SpeechInputError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case unavailable
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "请先在系统设置中允许 Deadliner 使用麦克风。"
        case .speechPermissionDenied:
            return "请先在系统设置中允许 Deadliner 使用语音识别。"
        case .unavailable:
            return "当前设备暂时无法使用 Apple 语音输入。"
        case .noSpeechDetected:
            return "没有识别到语音内容，请再试一次。"
        }
    }
}
