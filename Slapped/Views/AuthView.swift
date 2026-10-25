import SwiftUI

struct AuthView: View {
    private enum Mode: Equatable { case signIn, signUp, verify, forgot, reset }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var code = ""
    @State private var agreed = false
    @State private var busy = false
    @State private var message: String?

    private var validEmail: Bool { email.contains("@") && email.contains(".") }
    private var validUsername: Bool { username.range(of: "^[a-zA-Z0-9_]{3,20}$", options: .regularExpression) != nil }
    private var validCode: Bool { code.count >= 6 && code.allSatisfy(\.isNumber) }

    private var canSubmit: Bool {
        switch mode {
        case .signIn: validEmail && password.count >= 6
        case .signUp: validEmail && password.count >= 6 && validUsername && agreed
        case .verify: validCode
        case .forgot: validEmail
        case .reset: validCode && password.count >= 6
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .signIn: "Sign in"
        case .signUp: "Start hunting"
        case .verify: "Verify email"
        case .forgot: "Send reset code"
        case .reset: "Set new password"
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
        case .verify: "We emailed a code to \(email). Enter it below."
        case .forgot: "Enter your email and we'll send you a reset code."
        case .reset: "Enter the code from your email and choose a new password."
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
                codeField
            case .forgot:
                field("Email", text: $email, systemImage: "envelope")
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            case .reset:
                codeField
                passwordField("New password (6+ characters)")
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
            Button("Resend code") {
                Task {
                    try? await API.resendSignUpCode(email: email)
                    message = "Sent a new code."
                }
            }
            .font(.subheadline)
        case .forgot, .reset:
            Button("Back to sign in") { mode = .signIn }.font(.subheadline)
        case .signUp:
            EmptyView()
        }
    }

    private var codeField: some View {
        field("6-digit code", text: $code, systemImage: "number")
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
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
                    code = ""
                    mode = .verify
                }
            case .verify:
                try await API.verifySignUp(email: email, code: code)
            case .forgot:
                try await API.sendPasswordReset(email: email)
                code = ""
                password = ""
                mode = .reset
            case .reset:
                try await API.resetPassword(email: email, code: code, newPassword: password)
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
