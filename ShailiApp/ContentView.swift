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
struct ResponseData : Decodable {
    let questions : [String]
}
struct ApiResponse : Decodable {
    let statusCode : Int
    let data : ResponseData
    let error : [String]
}
// Service to handle API requests
class ApiService {
    // Async function to perform the API request
    func fetchData(from url: String, payload createPayload: [String: Any]) async throws -> ApiResponse {
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(url, method: .post, parameters: createPayload,encoding: JSONEncoding.default).validate().responseDecodable(of: ApiResponse.self) { response in
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
class MainAudioHandler : ObservableObject {
    @Published var canRecord = false
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var audioFileURL : URL?
    @Published var transcriptContent: String? = nil
    @Published var translatedContent: String? = nil
    @Published var toggleLanguage: Bool = true
    @Published var processStarted: Bool = false
    @Published var questions: [String] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var viewInstructions: Bool = true
    private var audioPlayer : AVAudioPlayer?
    private var audioRecorder : AVAudioRecorder?
    private var transcript: String? = nil
    private var transcriptEndpoint: String = "https://5ymnjpng6d.execute-api.us-east-1.amazonaws.com/GetTranscript/mytranscriber"
    private var questionGenerationEndpoint: String = "https://5ymnjpng6d.execute-api.us-east-1.amazonaws.com/GetTranscript/questionGenerator"
    
    private let apiService = ApiService()
    private let synthesizer = AVSpeechSynthesizer()
    
    
    init() {
        //ask for record permission. IMPORTANT: Make sure you've set `NSMicrophoneUsageDescription` in your Info.plist
        AVAudioSession.sharedInstance().requestRecordPermission() { [unowned self] allowed in
            DispatchQueue.main.async {
                if allowed {
                    self.canRecord = true
                } else {
                    self.canRecord = false
                }
            }
        }
    }
    
    //the URL where the recording file will be stored
    private var recordingURL : URL {
        getDocumentsDirectory().appendingPathComponent("recording.wav")
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    
    func recordFile() {
        do {
            //set the audio session so we can record
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
        } catch {
            print(error)
            self.canRecord = false
            fatalError()
        }
        //this describes the format the that the file will be recorded in
        let settings = [
            // kAudioFormatLinearPCM - for .wav
            // kAudioFormatMPEG4AAC - for .caf and .mpfa
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            //create the recorder, pointing towards the URL from above
            audioRecorder = try AVAudioRecorder(url: recordingURL,
                                                settings: settings)
            audioRecorder?.record() //start the recording
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
        self.processStarted = true
        self.getTranscriptContents()
        
    }
    
    
    func playRecordedFile() {
        guard let audioFileURL = audioFileURL else {
            return
        }
        do {
            //create a player, again pointing towards the same URL
            self.audioPlayer = try AVAudioPlayer(contentsOf: audioFileURL)
            self.audioPlayer?.play()
        } catch {
            print(error)
        }
    }
    
    func translateAndSpeak(script: String, selectLanguage: Bool) {
        var languageSelection: String = "es-ES"
        // Translate transcriptionText from English to Spanish using an external translation API
        // let translatedText = translateToSpanish(text: transcriptionText)
        if !selectLanguage {
            languageSelection = "en-US"
        }
        
        // Use AVSpeechSynthesizer to speak the translated text
        let utterance = AVSpeechUtterance(string: script)
        utterance.voice = AVSpeechSynthesisVoice(language: languageSelection)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
    
    
    func languageToggler(){
        self.toggleLanguage = !toggleLanguage
    }
    
    
    func cleaner() {
        self.transcriptContent = nil
        self.translatedContent = nil
        self.processStarted = false
        self.viewInstructions = true
    }
    
    
    private func generateQuestions(user symptoms: String?) {
        isLoading = true
        error = nil
        if symptoms == nil {
            self.questions = [
                "Error Generating the Questions.",
                "Please Contact Support."
            ]
            self.isLoading = false
            self.viewInstructions = false
        } else {
            Task {
                do {
                    // URL of the API endpoint
                    let createPayload: [String: Any] = [
                        "httpMethod":"POST",
                        "body": [
                            "symptoms": symptoms
                        ]
                    ]
                    // Replace with your actual URL
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
        
        
    }
    
    
    func getTranscriptContents() {
        isProcessing = true
        
        // Load the .wav file from the bundle or from a file path
        // This must be changed with recording.wav
        if let audioUrl = audioFileURL {
            do {
                let fileData = try Data(contentsOf: audioUrl)
                
                // Step 2: Convert the Data to Base64 encoded string
                let base64String = fileData.base64EncodedString()
                
                // Print or use the Base64 string
                let createPayload: [String: Any] = [
                    "httpMethod":"POST",
                    "body": [
                        "audio": base64String
                    ]
                ]
                // send the p[ost request
                AF.request(
                    transcriptEndpoint,
                    method: .post,
                    parameters: createPayload,
                    encoding: JSONEncoding.default
                    
                )
                .responseJSON{
                    response in
                    switch response.result {
                    case .success(let value):
                        let json  = JSON(value)
                        let transcriptAudioContent = json["data"]["transcript"].stringValue
                        self.transcriptContent = transcriptAudioContent
                        let translatedAudioContent = json["data"]["translate"].stringValue
                        self.translatedContent = translatedAudioContent
                        // create the synthesis speaker
                        self.translateAndSpeak(script: translatedAudioContent, selectLanguage: self.toggleLanguage)
                        // select user symptoms and call the API
                        let symptoms = self.toggleLanguage ? self.transcriptContent : self.translatedContent
                        self.generateQuestions(user: symptoms)
                        self.isProcessing = false
                    case .failure(let error):
                        let message = "Error: \(error.localizedDescription)"
                        print(message)
                        self.transcriptContent = "Transcript Generation Failed"
                        self.isProcessing = false
                    }
                }
                
            } catch {
                print("Error reading file: \(error.localizedDescription)")
                self.isProcessing = false
                return
            }
        } else {
            print("File not found")
            self.isProcessing = false
            return
        }
    }
}
struct ListItemView: View {
    var title: String
    var content: [String]
    var loadingContent: Bool
    
    var body: some View {
        if loadingContent {
            HStack{
                Spacer()
                ProgressView("Generating questions")
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            .padding()
        } else {
            Text(title)
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.black)
                .padding()
            ForEach(content, id: \.self) {instructions in
                Text(instructions)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.2))
                Divider()
                
            }
        }
    }
}
    
struct ContentView: View {
    
    let appTitle: String = "TranslateRx"
    private var guide: [String] = [
        "Use the language button to toggle between languages.",
        "E stands for English and S stands for Spanish.",
        "Use respective mic button to speak up with the language you selected.",
        "After generating script and translated script, use clear button indicated by C to record another audio."
    ]
    @StateObject private var audioManager = MainAudioHandler()
    
    var body: some View {
        ZStack {
            ScrollView{
                VStack(spacing: 20){
                    //logo and title
                    HStack{
                        Image("TranslateRxLogo")
                            .resizable()
                            .frame(maxWidth: 70, maxHeight: 70)
                            .scaledToFit()
                        Spacer()
                        Text("TranslateRx")
                            .font(.largeTitle)
                    }
                    //english
                    VStack(alignment: .leading, spacing: 30){
                        Text("English")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                        if audioManager.isProcessing{
                            ProgressView("Getting transcript")
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            if audioManager.transcriptContent != nil && audioManager.translatedContent != nil {
                                Text(
                                    audioManager.toggleLanguage ? audioManager.transcriptContent ?? "Error getting the transcript" : audioManager.translatedContent ?? "Error getting the translation"
                                )
                                .font(.system(size: 14, weight: .bold))
                            }
                        }
                        HStack{
                            if !audioManager.isRecording && audioManager.canRecord{
                                Button("", systemImage: "mic", action: {
                                    audioManager.recordFile()
                                })
                                .foregroundColor(.black)
                                .padding()
                                .disabled(audioManager.isProcessing || !audioManager.toggleLanguage)
                            } else {
                                Button("", systemImage: "stop.circle", action: {
                                    audioManager.stopRecording()
                                })
                                .foregroundColor(.black)
                                .padding()
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.black, lineWidth: 2.5)
                    )
                    //spanish
                    VStack(alignment: .leading, spacing: 30){
                        Text("Spanish")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                        if audioManager.isProcessing{
                            ProgressView("Getting transcript")
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            if audioManager.transcriptContent != nil && audioManager.translatedContent != nil {
                                Text(
                                    audioManager.toggleLanguage ? audioManager.translatedContent ?? "Error getting the translation" : audioManager.transcriptContent ?? "Error getting the transcription"
                                )
                                .font(.system(size: 14, weight: .bold))
                            }
                        }
                        HStack{
                            if !audioManager.isRecording && audioManager.canRecord{
                                Button("", systemImage: "mic", action: {
                                    audioManager.recordFile()
                                })
                                .foregroundColor(.black)
                                .padding()
                                .disabled(audioManager.isProcessing || audioManager.toggleLanguage)
                            } else {
                                Button("", systemImage: "stop.circle", action: {
                                    audioManager.stopRecording()
                                })
                                .foregroundColor(.black)
                                .padding()
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.black, lineWidth: 2.5)
                    )
                    //list view
                    if audioManager.viewInstructions{
                        ListItemView(title: "Instructions", content: guide, loadingContent: audioManager.isProcessing)
                    } else {
                        ListItemView(title: "Ellaborating Questions", content: audioManager.questions, loadingContent: audioManager.isLoading)
                    }
                }
            }
            .padding()
            VStack{
                //toggle buttons
                HStack{
                    Spacer()
                    Circle()
                        .fill(.blue)
                        .padding()
                        .overlay(
                            Button(action: {
                                audioManager.languageToggler()
                            }) {
                                Text(audioManager.toggleLanguage ? "E" : "S")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                                .disabled(audioManager.processStarted)
                        )
                        .frame(width: 75, height: 75)
                }
                .padding()
                HStack{
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

