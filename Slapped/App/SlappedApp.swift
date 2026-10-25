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

    init() {
        // sticker images are re-shown constantly across feed, map and profiles
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(.brand)
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
    var activitySeenAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "activitySeenAt"))

    var userID: UUID? { session?.user.id }

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
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

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
            Task { _ = try? await supabase.auth.session(from: url) }
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
    }
}
