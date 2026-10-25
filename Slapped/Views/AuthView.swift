import SwiftUI

struct AuthView: View {
    @Environment(AppState.self) private var app
    private enum Mode: Equatable { case signIn, signUp, verify, forgot, reset }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var agreed = false
    @State private var busy = false
    @State private var message: String?

    private var validEmail: Bool { email.contains("@") && email.contains(".") }
    private var validUsername: Bool { username.range(of: "^[a-zA-Z0-9_]{3,20}$", options: .regularExpression) != nil }

    private var canSubmit: Bool {
        switch mode {
        case .signIn: validEmail && password.count >= 6
        case .signUp: validEmail && password.count >= 6 && validUsername && agreed
        case .verify: password.count >= 6
        case .forgot: validEmail
        case .reset: true
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .signIn: "Sign in"
        case .signUp: "Start hunting"
        case .verify: "I've confirmed my email"
        case .forgot: "Send reset link"
        case .reset: "Back to sign in"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if mode == .signIn || mode == .signUp {
                    Picker("", selection: $mode) {
                        Text("Sign in").tag(Mode.signIn)
                        Text("Create account").tag(Mode.signUp)
                    }
                    .pickerStyle(.segmented)
                }

                fields

                if let notice = app.authNotice {
                    Text(notice).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if busy { ProgressView().tint(.onBrand) } else { Text(buttonTitle) }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(!canSubmit || busy)
                .opacity(canSubmit ? 1 : 0.5)

                footerLinks
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: mode) { message = nil }
        .onChange(of: app.authNotice) { _, notice in
            if notice != nil { mode = .signIn }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brand)
                .overlay(Image(systemName: "viewfinder").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.onBrand))
            Text("Slapped")
                .font(.system(size: 44, weight: .black, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var subtitle: String {
        switch mode {
        case .verify: "We sent a confirmation link to \(email). Open the email on this iPhone and tap the link. Slapped will open and sign you in."
        case .forgot: "Enter your email and we'll send you a reset link."
        case .reset: "We sent a reset link to \(email). Open the email on this iPhone and tap the link. Slapped will open so you can choose a new password."
        default: "Find stickers in the wild. Log them. Trade them."
        }
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 12) {
            switch mode {
            case .signIn, .signUp:
                if mode == .signUp {
                    field("Username", text: $username, systemImage: "at")
                }
                field("Email", text: $email, systemImage: "envelope")
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                passwordField(mode == .signUp ? "Password (6+ characters)" : "Password")
                if mode == .signUp {
                    Toggle(isOn: $agreed) {
                        Text("I agree to the [Terms of Use](\(AppConfig.termsURL.absoluteString)) and [Privacy Policy](\(AppConfig.privacyURL.absoluteString)). No offensive or abusive content.")
                            .font(.footnote)
                    }
                    .toggleStyle(CheckboxToggleStyle())
                }
            case .verify:
                EmptyView()
            case .forgot:
                field("Email", text: $email, systemImage: "envelope")
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            case .reset:
                EmptyView()
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    @ViewBuilder
    private var footerLinks: some View {
        switch mode {
        case .signIn:
            Button("Forgot password?") { mode = .forgot }.font(.subheadline)
        case .verify:
            Button("Resend email") {
                Task {
                    try? await API.resendSignUpCode(email: email)
                    message = "Sent it again. It can take a minute."
                }
            }
            .font(.subheadline)
        case .forgot, .reset:
            Button("Back to sign in") { mode = .signIn }.font(.subheadline)
        case .signUp:
            EmptyView()
        }
    }

    private func passwordField(_ title: String) -> some View {
        HStack {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
            SecureField(title, text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
        }
        .padding()
        .card()
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
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            switch mode {
            case .signIn:
                try await API.signIn(email: email, password: password)
            case .signUp:
                let signedIn = try await API.signUp(email: email, password: password, username: username)
                if !signedIn {
                    mode = .verify
                }
            case .verify:
                // works once the link has been tapped, even if it didn't reopen the app
                try await API.signIn(email: email, password: password)
            case .forgot:
                try await API.sendPasswordReset(email: email)
                mode = .reset
            case .reset:
                mode = .signIn
            }
        } catch {
            message = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("duplicate key") || text.localizedCaseInsensitiveContains("Database error saving new user") {
            return "That username is taken. Try another."
        }
        if text.localizedCaseInsensitiveContains("Email not confirmed") {
            return "Tap the link in the confirmation email first, then try again."
        }
        if text.localizedCaseInsensitiveContains("Invalid login") {
            return "Wrong email or password."
        }
        return text
    }
}

private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(configuration.isOn ? Color.brand : Color.secondary)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityLabel("Agree")
            configuration.label
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
