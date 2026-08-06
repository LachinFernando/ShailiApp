//
//  ContentView.swift
//  Translate.Rx
//
//  Created by Shaili Betesh on 8/20/24.
//
import SwiftUI
import AVFoundation
import Alamofire
import SwiftyJSON
import Speech

struct ResponseData: Decodable {
    let questions: [String]
}

struct ApiResponse: Decodable {
    let statusCode: Int
    let data: ResponseData
    let error: [String]
}

enum TranslationLanguage: String, CaseIterable, Identifiable {
    case mandarin
    case spanish
    case hebrew

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mandarin:
            return "Mandarin"
        case .spanish:
            return "Spanish"
        case .hebrew:
            return "Hebrew"
        }
    }

    var shortLabel: String {
        switch self {
        case .mandarin:
            return "M"
        case .spanish:
            return "S"
        case .hebrew:
            return "H"
        }
    }

    var speechVoiceCode: String {
        switch self {
        case .mandarin:
            return "zh-CN"
        case .spanish:
            return "es-ES"
        case .hebrew:
            return "he-IL"
        }
    }

    var next: TranslationLanguage {
        switch self {
        case .mandarin:
            return .spanish
        case .spanish:
            return .hebrew
        case .hebrew:
            return .mandarin
        }
    }
}

// Service to handle API requests
class ApiService {
    func fetchData(from url: String, payload createPayload: [String: Any]) async throws -> ApiResponse {
        try await withCheckedThrowingContinuation { continuation in
            AF.request(
                url,
                method: .post,
                parameters: createPayload,
                encoding: JSONEncoding.default
            )
            .validate()
            .responseDecodable(of: ApiResponse.self) { response in
                switch response.result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

class MainAudioHandler: ObservableObject {
    @Published var canRecord = false
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var audioFileURL: URL?
    @Published var transcriptContent: String? = nil
    @Published var translatedContent: String? = nil
    @Published var selectedLanguage: TranslationLanguage = .mandarin
    @Published var isEnglishSpeakerSelected: Bool = true
    @Published var processStarted: Bool = false
    @Published var questions: [String] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var viewInstructions: Bool = true

    private var audioPlayer: AVAudioPlayer?
    private var audioRecorder: AVAudioRecorder?
    private var extractedTranscriptId: String? = nil
    private var transcriptEndpoint = "https://5ymnjpng6d.execute-api.us-east-1.amazonaws.com/GetTranscript/transcription-generation"
    private var fetchEndpoint = "https://5ymnjpng6d.execute-api.us-east-1.amazonaws.com/GetTranscript/get-translation"
    private var questionGenerationEndpoint = "https://5ymnjpng6d.execute-api.us-east-1.amazonaws.com/GetTranscript/questionGenerator"

    private let apiService = ApiService()
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        AVAudioSession.sharedInstance().requestRecordPermission() { [unowned self] allowed in
            DispatchQueue.main.async {
                self.canRecord = allowed
            }
        }
    }

    private var recordingURL: URL {
        getDocumentsDirectory().appendingPathComponent("recording.wav")
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    func recordFile() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
            canRecord = false
            fatalError()
        }

        let settings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print(error)
            isRecording = false
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        audioFileURL = recordingURL
        processStarted = true
        getTranscriptContents()
    }

    func playRecordedFile() {
        guard let audioFileURL else {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFileURL)
            audioPlayer?.play()
        } catch {
            print(error)
        }
    }

    func translateAndSpeak(script: String) {
        let languageSelection = isEnglishSpeakerSelected ? selectedLanguage.speechVoiceCode : "en-US"
        let utterance = AVSpeechUtterance(string: script)
        utterance.voice = AVSpeechSynthesisVoice(language: languageSelection)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func cycleLanguage() {
        selectedLanguage = selectedLanguage.next
    }

    func toggleSpeaker() {
        isEnglishSpeakerSelected.toggle()
    }

    func cleaner() {
        transcriptContent = nil
        translatedContent = nil
        audioFileURL = nil
        processStarted = false
        viewInstructions = true
        isProcessing = false
        isLoading = false
        questions = []
        error = nil
    }

    private func generateQuestions(user symptoms: String?) {
        isLoading = true
        error = nil

        guard let symptoms else {
            questions = [
                "Error generating the questions.",
                "Please contact support."
            ]
            isLoading = false
            viewInstructions = false
            return
        }

        Task {
            do {
                let createPayload: [String: Any] = [
                    "httpMethod": "POST",
                    "body": [
                        "symptoms": symptoms
                    ]
                ]

                let responseData = try await apiService.fetchData(from: questionGenerationEndpoint, payload: createPayload)
                DispatchQueue.main.async {
                    self.questions = responseData.data.questions
                    self.isLoading = false
                    self.viewInstructions = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                    self.viewInstructions = false
                }
            }
        }
    }

    private func pollTranscriptStatus(transcriptId: String) {
        Task { @MainActor in
            guard !transcriptId.isEmpty else {
                print("pollTranscriptStatus: transcriptId is empty")
                isProcessing = false
                return
            }

            isProcessing = true
            var attempts = 0
            let maxAttempts = 6
            let intervalNs: UInt64 = 5_000_000_000

            while true {
                let createGetPayload: [String: Any] = [
                    "httpMethod": "POST",
                    "body": [
                        "transcriptId": transcriptId
                    ]
                ]

                let request = AF.request(
                    fetchEndpoint,
                    method: .post,
                    parameters: createGetPayload,
                    encoding: JSONEncoding.default
                )

                var shouldStop = false

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    request.responseJSON { [weak self] response in
                        defer { continuation.resume() }
                        guard let self else { return }

                        switch response.result {
                        case .success(let value):
                            let json = JSON(value)
                            let status = json["data"]["translation"]["status"].string?.uppercased() ?? ""

                            switch status {
                            case "COMPLETED":
                                self.transcriptContent = json["data"]["translation"]["original_transcript"].stringValue
                                self.translatedContent = json["data"]["translation"]["translation"].stringValue
                                self.translateAndSpeak(script: self.translatedContent ?? "Error")

                                let symptoms = self.isEnglishSpeakerSelected ? self.transcriptContent : self.translatedContent
                                self.generateQuestions(user: symptoms)
                                self.isProcessing = false
                                shouldStop = true

                            case "FAILED":
                                self.transcriptContent = "Transcript Generation Failed"
                                self.isProcessing = false
                                shouldStop = true

                            default:
                                break
                            }

                        case .failure(let error):
                            print("Poll GET error:", error.localizedDescription)
                        }
                    }
                }

                if shouldStop { break }

                attempts += 1
                if attempts >= maxAttempts {
                    print("Polling timeout.")
                    isProcessing = false
                    break
                }

                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }

    func getTranscriptContents() {
        isProcessing = true

        guard let audioUrl = audioFileURL else {
            print("File not found")
            isProcessing = false
            return
        }

        do {
            let fileData = try Data(contentsOf: audioUrl)
            let base64String = fileData.base64EncodedString()

            let createPayload: [String: Any] = [
                "httpMethod": "POST",
                "body": [
                    "audio": base64String,
                    "language": selectedLanguage.rawValue
                ]
            ]

            AF.request(
                transcriptEndpoint,
                method: .post,
                parameters: createPayload,
                encoding: JSONEncoding.default
            )
            .responseJSON { response in
                switch response.result {
                case .success(let value):
                    let json = JSON(value)
                    let transcriptId = json["data"]["transcriptId"].stringValue
                    self.extractedTranscriptId = transcriptId

                    guard !transcriptId.isEmpty else {
                        self.transcriptContent = "Failed to get transcript id."
                        self.isProcessing = false
                        return
                    }

                    self.pollTranscriptStatus(transcriptId: transcriptId)

                case .failure(let error):
                    print("Error: \(error.localizedDescription)")
                    self.transcriptContent = "Transcript Generation Failed"
                    self.isProcessing = false
                }
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
            isProcessing = false
        }
    }
}

struct ListItemView: View {
    var title: String
    var content: [String]
    var loadingContent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.black)

            if loadingContent {
                HStack {
                    Spacer()
                    ProgressView("Generating questions")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(Array(content.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.blue)

                        Text(item)
                            .font(.system(size: 15))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.black, lineWidth: 2)
        )
    }
}

struct ContentView: View {
    private var guide: [String] = [
        "Use the speaker button to choose whether the next recording is in English or the translated language.",
        "Use the round language button to cycle between Mandarin, Spanish, and Hebrew.",
        "M stands for Mandarin, S stands for Spanish, and H stands for Hebrew.",
        "Tap the matching microphone area, then stop the recording to generate the transcript and translation.",
        "Use the clear button indicated by C to reset the conversation and start another recording."
    ]

    @StateObject private var audioManager = MainAudioHandler()

    private var englishPanelText: String? {
        guard audioManager.transcriptContent != nil, audioManager.translatedContent != nil else {
            return nil
        }

        return audioManager.isEnglishSpeakerSelected
            ? audioManager.transcriptContent
            : audioManager.translatedContent
    }

    private var translatedPanelText: String? {
        guard audioManager.transcriptContent != nil, audioManager.translatedContent != nil else {
            return nil
        }

        return audioManager.isEnglishSpeakerSelected
            ? audioManager.translatedContent
            : audioManager.transcriptContent
    }

    private var speakerButtonTitle: String {
        audioManager.isEnglishSpeakerSelected
            ? "Speaker: English"
            : "Speaker: \(audioManager.selectedLanguage.displayName)"
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Image("TranslateRxLogo")
                            .resizable()
                            .frame(maxWidth: 70, maxHeight: 70)
                            .scaledToFit()
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TranslateRx")
                                .font(.largeTitle)
                            Text("Selected language: \(audioManager.selectedLanguage.displayName)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 30) {
                        Text("English")
                            .font(.system(size: 18, weight: .bold))

                        if audioManager.isProcessing {
                            ProgressView("Getting transcript")
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else if let englishPanelText {
                            Text(englishPanelText)
                                .font(.system(size: 14, weight: .bold))
                        } else {
                            Text("English transcript will appear here after recording.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            if audioManager.isRecording {
                                Button("", systemImage: "stop.circle", action: {
                                    audioManager.stopRecording()
                                })
                                .foregroundColor(.black)
                                .padding()
                            } else {
                                Button("", systemImage: "mic", action: {
                                    audioManager.recordFile()
                                })
                                .foregroundColor(.black)
                                .padding()
                                .disabled(
                                    audioManager.isProcessing ||
                                    !audioManager.isEnglishSpeakerSelected ||
                                    !audioManager.canRecord
                                )
                            }

                            Spacer()

                            Text(audioManager.isEnglishSpeakerSelected ? "Active microphone" : "Waiting")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(audioManager.isEnglishSpeakerSelected ? .blue : .secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.black, lineWidth: 2.5)
                    )

                    VStack(alignment: .leading, spacing: 30) {
                        Text(audioManager.selectedLanguage.displayName)
                            .font(.system(size: 18, weight: .bold))

                        if audioManager.isProcessing {
                            ProgressView("Getting transcript")
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else if let translatedPanelText {
                            Text(translatedPanelText)
                                .font(.system(size: 14, weight: .bold))
                        } else {
                            Text("\(audioManager.selectedLanguage.displayName) translation will appear here after recording.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            if audioManager.isRecording {
                                Button("", systemImage: "stop.circle", action: {
                                    audioManager.stopRecording()
                                })
                                .foregroundColor(.black)
                                .padding()
                            } else {
                                Button("", systemImage: "mic", action: {
                                    audioManager.recordFile()
                                })
                                .foregroundColor(.black)
                                .padding()
                                .disabled(
                                    audioManager.isProcessing ||
                                    audioManager.isEnglishSpeakerSelected ||
                                    !audioManager.canRecord
                                )
                            }

                            Spacer()

                            Text(audioManager.isEnglishSpeakerSelected ? "Waiting" : "Active microphone")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(audioManager.isEnglishSpeakerSelected ? .secondary : .blue)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.black, lineWidth: 2.5)
                    )

                    HStack {
                        Spacer()
                        Button(speakerButtonTitle, action: {
                            audioManager.toggleSpeaker()
                        })
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .disabled(audioManager.processStarted)
                        Spacer()
                    }

                    if !audioManager.canRecord {
                        Text("Microphone access is required to record audio translations.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                    }

                    if audioManager.viewInstructions {
                        ListItemView(title: "Instructions", content: guide, loadingContent: audioManager.isProcessing)
                    } else {
                        ListItemView(title: "Elaborating Questions", content: audioManager.questions, loadingContent: audioManager.isLoading)
                    }
                }
            }
            .padding()

            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .fill(.blue)
                        .padding()
                        .overlay(
                            Button(action: {
                                audioManager.cycleLanguage()
                            }) {
                                VStack(spacing: 2) {
                                    Text(audioManager.selectedLanguage.shortLabel)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(audioManager.selectedLanguage.displayName.prefix(2).uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                            .disabled(audioManager.processStarted)
                        )
                        .frame(width: 75, height: 75)
                }
                .padding()

                HStack {
                    Spacer()
                    Circle()
                        .fill(.blue)
                        .padding()
                        .overlay(
                            Button(action: {
                                audioManager.cleaner()
                            }) {
                                Text("C")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .disabled(!audioManager.processStarted)
                        )
                        .frame(width: 75, height: 75)
                }
                .padding()
            }
        }
    }
}

#Preview {
    ContentView()
}
