import SwiftUI

// MARK: - Navigation

enum Route: Hashable {
    case recordAndTranslate
    case imageTranslation
}

// MARK: - App Entry (use HomePageView as your root view)

struct HomePageView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onRecordAndTranslate: { path.append(Route.recordAndTranslate) },
                onImageTranslation: { path.append(Route.imageTranslation) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .recordAndTranslate:
                    ContentView()
                case .imageTranslation:
                    ImageTranslateView()
                }
            }
        }
    }
}

// MARK: - Home Screen (matches your mock)

struct HomeView: View {
    let onRecordAndTranslate: () -> Void
    let onImageTranslation: () -> Void

    private let usageSteps: [String] = [
        "Tap Record and Translate to record a conversation and get live translation support.",
        "Use the language control in the audio screen to switch between Mandarin, Spanish, and Hebrew.",
        "Choose Image Translation to upload or capture a photo, then translate the detected text.",
        "Use the clear or done actions in each screen to reset and start another translation."
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                Text("TranslateRX")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.black)

                Spacer().frame(height: 10)

                // Image placeholder box
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.6), lineWidth: 1)
                        .frame(width: 220, height: 220)

                    Image("TranslateRxLogo")
                        .resizable()
                        .frame(maxWidth: 150, maxHeight: 150)
                        .scaledToFit()
                }

                Spacer().frame(height: 18)

                // Buttons
                VStack(spacing: 18) {
                    CapsuleActionButton(title: "Record and Translate", action: onRecordAndTranslate)
                    CapsuleActionButton(title: "Image Translation", action: onImageTranslation)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("How To Use")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.black)

                    ForEach(Array(usageSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.blue)

                            Text(step)
                                .font(.system(size: 14))
                                .foregroundStyle(.black.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Button Style

struct CapsuleActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(Color.blue.opacity(0.25), lineWidth: 2)
        )
        .shadow(color: Color.blue.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Destination Screens

struct RecordAndTranslateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Record and Translate")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your recording UI goes here.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.white.ignoresSafeArea())
    }
}

struct ImageTranslationView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Image Translation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your image translation UI goes here.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Image")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.white.ignoresSafeArea())
    }
}

// MARK: - Preview

#Preview {
    HomePageView()
}
//
//  HomePageView.swift
//  ShailiApp
//
//  Created by Lachin Fernando on 2026-01-07.
//
