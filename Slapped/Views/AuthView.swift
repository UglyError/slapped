import SwiftUI

struct AuthView: View {
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var busy = false
    @State private var message: String?

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 &&
            (!isSignUp || username.range(of: "^[a-zA-Z0-9_]{3,20}$", options: .regularExpression) != nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.brand)
                        .overlay(Image(systemName: "viewfinder").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.onBrand))
                    Text("Slapped")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                    Text("Find stickers in the wild. Log them. Trade them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                Picker("", selection: $isSignUp) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    if isSignUp {
                        field("Username", text: $username, systemImage: "at")
                            .textInputAutocapitalization(.never)
                    }
                    field("Email", text: $email, systemImage: "envelope")
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    HStack {
                        Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
                        SecureField("Password (6+ characters)", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                    }
                    .padding()
                    .card()
                }
                .autocorrectionDisabled()

                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if busy { ProgressView().tint(.onBrand) } else { Text(isSignUp ? "Start hunting" : "Sign in") }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(!canSubmit || busy)
                .opacity(canSubmit ? 1 : 0.5)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
            TextField(title, text: text)
        }
        .padding()
        .card()
    }

    private func submit() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            if isSignUp {
                let signedIn = try await API.signUp(email: email, password: password, username: username)
                if !signedIn { message = "Check your inbox to confirm your email, then sign in." }
            } else {
                try await API.signIn(email: email, password: password)
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
