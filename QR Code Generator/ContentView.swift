//
//  ContentView.swift
//  QR Code Generator
//
//  Created by Rob Witte on 1/16/26.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct ContentView: View {
    enum QRType: String, CaseIterable, Identifiable {
        case url = "URL"
        case email = "E-mail"

        var id: String { rawValue }
    }

    @State private var selectedType: QRType = .url

    // URL
    @State private var urlText: String = "https://unicorninnovationlabs.com"

    // Email
    @State private var emailTo: String = ""
    @State private var emailSubject: String = ""
    @State private var emailBody: String = ""

    private enum Field: Hashable {
        case url
        case emailTo
        case emailSubject
        case emailBody
    }

    @FocusState private var focusedField: Field?

    @State private var qrImage: UIImage?

    @State private var lastPayload: String?

    @State private var showShare = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    mainContent
                }
            } else {
                NavigationView {
                    mainContent
                }
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Type", selection: $selectedType) {
                    ForEach(QRType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedType) { _ in
                    focusedField = nil
                    qrImage = nil
                    lastPayload = nil
                    showShare = false
                }

                if selectedType == .url {
                    TextField("URL", text: $urlText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .padding(.horizontal)
                } else {
                    VStack(spacing: 10) {
                        TextField("To (required)", text: $emailTo)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .emailTo)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .padding(.horizontal)

                        TextField("Subject (optional)", text: $emailSubject)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .emailSubject)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal)

                        TextField("Body (optional)", text: $emailBody, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .emailBody)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal)
                    }
                }

                Button("Generate") {
                    generate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerate)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(.top)

                    HStack(spacing: 12) {
                        Button("Test") { testPayload() }
                        Button("Share") { showShare = true }
                        Button("New") { reset() }
                    }
                    .buttonStyle(.bordered)
                } else {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView("No QR Code Yet", systemImage: "qrcode")
                            .padding(.top)
                    } else {
                        Text("No QR Code Yet")
                            .foregroundStyle(.secondary)
                            .padding(.top)
                    }
                }

            }
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .modifier(KeyboardDismissModifier())
        .onTapGesture { focusedField = nil }
        .navigationTitle("QR Code Generator")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let qrImage {
                ShareSheet(items: [qrImage])
            }
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private var canGenerate: Bool {
        switch selectedType {
        case .url:
            return !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .email:
            return !emailTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func generate() {
        let payload: String
        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.prepare()

        switch selectedType {
        case .url:
            let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                alertMessage = "Enter a URL first."
                showAlert = true
                return
            }
            payload = trimmed

        case .email:
            let to = emailTo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !to.isEmpty else {
                alertMessage = "Enter a recipient email address."
                showAlert = true
                return
            }

            // Build a mailto: URI with optional subject/body
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = to

            var items: [URLQueryItem] = []
            let subject = emailSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            if !subject.isEmpty {
                items.append(URLQueryItem(name: "subject", value: subject))
            }
            let body = emailBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                items.append(URLQueryItem(name: "body", value: body))
            }
            if !items.isEmpty {
                components.queryItems = items
            }

            payload = components.string ?? "mailto:\(to)"
        }

        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else {
            alertMessage = "Failed to generate QR."
            showAlert = true
            return
        }

        // Scale up without blurring
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            alertMessage = "Failed to render QR."
            showAlert = true
            return
        }

        qrImage = UIImage(cgImage: cg)
        lastPayload = payload
        focusedField = nil
        haptic.impactOccurred(intensity: 1.0)
    }

    private func reset() {
        qrImage = nil
        lastPayload = nil
        // Keep type selection; clear inputs for a fresh start
        urlText = ""
        emailTo = ""
        emailSubject = ""
        emailBody = ""
        focusedField = nil
    }

    private func testPayload() {
        guard let payload = lastPayload, !payload.isEmpty else {
            alertMessage = "Nothing to test yet. Generate a QR code first."
            showAlert = true
            return
        }
        guard let url = URL(string: payload) else {
            alertMessage = "The generated link is not a valid URL."
            showAlert = true
            return
        }

        // Dismiss keyboard if any field is still focused
        focusedField = nil

        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            alertMessage = "This device can't open the generated link."
            showAlert = true
        }
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollDismissesKeyboard(.interactively)
        } else {
            content
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
