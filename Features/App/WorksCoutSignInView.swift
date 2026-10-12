import SwiftUI
import WorksCoutCore

/// Sign in to an account or make a new one — shared by the iOS app and the
/// Mac app. Shown in place of the sections while signed out, and as a sheet
/// when the server stops accepting the current token.
struct WorksCoutSignInView: View {
    let session: WorksCoutSessionModel
    /// Called once an account is in use again, so a sheet can close itself.
    var onDone: () -> Void = {}

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case create = "Create Account"
        var id: Self { self }
    }

    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    /// Signed out, nothing is sent with a token, so this client carries none.
    private let client = WorksCoutConfig.makeClient(token: nil)

    private var canSubmit: Bool {
        !isWorking
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BrandMark(size: 88)
                    .shadow(color: Brand.cobalt.opacity(0.25), radius: 12, y: 6)
                BrandWordmark(height: 26)

                Picker("Sign in or create an account", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(mode == .create ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }
                .textFieldStyle(.roundedBorder)

                if mode == .create {
                    Text("At least 8 characters. A new account starts empty, with the default job filters.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Error: \(errorMessage)")
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(mode.rawValue).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(!canSubmit)

                if WorksCoutConfig.buildTimeToken != nil {
                    // Her own builds carry her account's token, so getting
                    // back to it never depends on remembering a password.
                    Button("Use the Account Built Into This App") {
                        session.useBuiltInAccount()
                        onDone()
                    }
                    .frame(minHeight: 44)
                    .disabled(isWorking)
                }
            }
            .frame(maxWidth: 360)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .onChange(of: mode) { errorMessage = nil }
    }

    private func submit() async {
        guard canSubmit else { return }
        isWorking = true
        defer { isWorking = false }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let signedIn = switch mode {
            case .signIn: try await client.signIn(email: address, password: password)
            case .create: try await client.signUp(email: address, password: password)
            }
            password = ""
            session.signIn(signedIn)
            onDone()
        } catch WorksCoutAPIError.badRequest(let detail) {
            errorMessage = detail
        } catch WorksCoutAPIError.tooManyAttempts {
            errorMessage = "Too many tries. Wait a while, then try again."
        } catch WorksCoutAPIError.transport {
            errorMessage = "Couldn't reach WORKS(c)OUT. Check your connection and try again."
        } catch WorksCoutAPIError.notFound {
            errorMessage = "Accounts aren't switched on for the server yet."
        } catch {
            errorMessage = mode == .signIn ? "Couldn't sign in. Try again." : "Couldn't create the account. Try again."
        }
    }
}
