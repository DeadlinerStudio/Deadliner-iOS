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

    var isRecording: Bool {
        state == .recording
    }

    var isBusy: Bool {
        state != .idle
    }

    func startRecording(initialText: String) async throws {
        guard state == .idle else { return }

        state = .preparing
        baseText = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        composedText = initialText
        helperText = "正在听写..."
        lastErrorMessage = nil
        hasRecognizedSpeech = false

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
                        self.hasRecognizedSpeech = true
                        self.helperText = "继续说，我在听"
                        self.composedText = self.mergeBaseTextWithTranscript(result.bestTranscription.formattedString)
                        if result.isFinal {
                            await self.finishRecognitionPipeline(keepText: true)
                        }
                    }
                }

                if let error {
                    Task { @MainActor in
                        await self.fail(with: error)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording
        } catch {
            await resetPipeline()
            state = .idle
            throw error
        }
    }

    func stopRecording() async throws {
        guard isBusy else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        helperText = nil
        if !hasRecognizedSpeech {
            lastErrorMessage = SpeechInputError.noSpeechDetected.localizedDescription
        }
        state = .idle
    }

    func cancelRecording() async {
        await resetPipeline()
        state = .idle
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

        let needsNewline = !baseText.hasSuffix("\n")
        return baseText + (needsNewline ? "\n" : "") + trimmedTranscript
    }

    private func fail(with error: Error) async {
        await resetPipeline()
        lastErrorMessage = error.localizedDescription
        state = .idle
    }

    private func finishRecognitionPipeline(keepText: Bool) async {
        await resetPipeline(keepText: keepText)
        state = .idle
    }

    private func resetPipeline(keepText: Bool = false) async {
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
