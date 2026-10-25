import SwiftUI
import Supabase

enum AppConfig {
    // Supabase dashboard → Project Settings → API
    static let supabaseURL = URL(string: "https://olvjhnxrslklpzgaqcot.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sdmpobnhyc2xrbHB6Z2FxY290Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIzMjYyMTgsImV4cCI6MjEwNzkwMjIxOH0.900SB9FDLyKktLez_oGrdpGse5Tw9ZtY5DtVFQH7JUE"
    static let storageBucket = "stickers"
    /// Email links (confirm sign-up, reset password) open the app through this URL.
    /// Must match Supabase → Authentication → URL Configuration.
    static let authCallbackURL = URL(string: "slapped://auth-callback")!
    static let termsURL = URL(string: "https://github.com/UglyError/slapped/blob/main/docs/terms.md")!
    static let privacyURL = URL(string: "https://github.com/UglyError/slapped/blob/main/docs/privacy.md")!
    static let supportURL = URL(string: "https://github.com/UglyError/slapped/issues")!
}

let supabase = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseAnonKey)

@main
struct SlappedApp: App {
    @State private var app = AppState()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        // sticker images are re-shown constantly across feed, map and profiles
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(.brand)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
final class AppState {
    var session: Session?
    var isLoading = true
    var me: ProfileStats?
    var pendingIncoming = 0
    var unseenActivity = 0
    var needsNewPassword = false
    var authNotice: String?
    var newBadge: Badge?
    var activitySeenAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "activitySeenAt"))

    var userID: UUID? { session?.user.id }

    /// Confirm-email and reset-password links open the app here.
    func handleAuthURL(_ url: URL) async {
        do {
            let newSession = try await supabase.auth.session(from: url)
            session = newSession
            isLoading = false
            authNotice = nil
            if url.absoluteString.contains("type=recovery") || API.consumeRecoveryRequest() {
                needsNewPassword = true
            }
            await refresh()
        } catch {
            authNotice = "Email confirmed. Sign in to continue."
        }
    }

    /// Picks up a session created while the app was in the background.
    func resume() async {
        guard session == nil, let current = try? await supabase.auth.session else { return }
        session = current
        isLoading = false
        await refresh()
    }

    func markActivitySeen() {
        activitySeenAt = .now
        unseenActivity = 0
        UserDefaults.standard.set(activitySeenAt.timeIntervalSince1970, forKey: "activitySeenAt")
    }

    func start() async {
        for await (event, session) in supabase.auth.authStateChanges {
            self.session = session
            if event == .passwordRecovery { needsNewPassword = true }
            isLoading = false
            if session != nil {
                await refresh()
            } else {
                me = nil
                pendingIncoming = 0
                unseenActivity = 0
            }
        }
    }

    func refresh() async {
        guard let userID else { return }
        me = try? await API.profile(userID)
        pendingIncoming = (try? await API.pendingIncomingCount(for: userID)) ?? 0
        let recent = (try? await API.activity(limit: 30)) ?? []
        unseenActivity = recent.filter { $0.createdAt > activitySeenAt }.count
        await checkNewBadges(for: userID)
    }

    /// Celebrates badges earned since the last check (silent the first time on a device).
    private func checkNewBadges(for userID: UUID) async {
        guard let badges = try? await API.badges(for: userID) else { return }
        let earned = badges.filter(\.isEarned)
        let key = "knownBadges-\(userID.uuidString)"
        let known = UserDefaults.standard.stringArray(forKey: key)
        UserDefaults.standard.set(earned.map(\.code), forKey: key)
        guard let known else { return }
        if let fresh = earned.first(where: { !known.contains($0.code) }) {
            newBadge = fresh
            try? await Task.sleep(for: .seconds(4))
            if newBadge?.code == fresh.code { newBadge = nil }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @AppStorage("seenOnboarding") private var seenOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        ZStack {
            Color.bg.ignoresSafeArea()
            if app.isLoading {
                ProgressView()
            } else if app.session == nil {
                AuthView()
            } else {
                MainTabView()
            }
        }
        .task { await app.start() }
        .onOpenURL { url in
            // confirm-email and reset-password links land here and sign the user in
            Task { await app.handleAuthURL(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.resume() } }
        }
        .fullScreenCover(isPresented: Binding(get: { app.session != nil && !seenOnboarding },
                                              set: { if !$0 { seenOnboarding = true } })) {
            OnboardingView { seenOnboarding = true }
        }
        .sheet(isPresented: $app.needsNewPassword) {
            NewPasswordView()
        }
    }
}

struct NewPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Choose a new password").font(.title2.weight(.heavy))
                SecureField("New password (6+ characters)", text: $password)
                    .textContentType(.newPassword)
                    .padding()
                    .card()
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView().tint(.onBrand) } else { Text("Save password") }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(password.count < 6 || saving)
                Spacer()
            }
            .padding(24)
            .background(Color.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
        }
    }

    private func save() async {
        saving = true
        do {
            try await API.setNewPassword(password)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @State private var tab: Tab = .feed

    enum Tab { case feed, explore, scan, map, profile }

    var body: some View {
        TabView(selection: $tab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "house.fill") }
                .tag(Tab.feed)
            ExploreView()
                .tabItem { Label("Explore", systemImage: "safari.fill") }
                .tag(Tab.explore)
            ScanView(onFinished: { tab = .feed })
                .tabItem { Label("Scan", systemImage: "viewfinder.circle.fill") }
                .tag(Tab.scan)
            StickerMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.map)
            NavigationStack {
                if let id = app.userID {
                    ProfileView(userID: id)
                        .withRoutes()
                }
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
            .badge(app.pendingIncoming)
            .tag(Tab.profile)
        }
        .task { LocationManager.shared.requestPermission() }
        .overlay(alignment: .top) {
            if let badge = app.newBadge {
                NewBadgeToast(badge: badge)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { app.newBadge = nil }
                    .sensoryFeedback(.success, trigger: badge.code)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.35), value: app.newBadge?.code)
    }
}
