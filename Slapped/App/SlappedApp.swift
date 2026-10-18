import SwiftUI
import Supabase

enum AppConfig {
    // Supabase dashboard → Project Settings → API
    static let supabaseURL = URL(string: "https://olvjhnxrslklpzgaqcot.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sdmpobnhyc2xrbHB6Z2FxY290Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIzMjYyMTgsImV4cCI6MjEwNzkwMjIxOH0.900SB9FDLyKktLez_oGrdpGse5Tw9ZtY5DtVFQH7JUE"
    static let storageBucket = "stickers"
}

let supabase = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseAnonKey)

@main
struct SlappedApp: App {
    @State private var app = AppState()

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

    var userID: UUID? { session?.user.id }

    func start() async {
        for await (_, session) in supabase.auth.authStateChanges {
            self.session = session
            isLoading = false
            if session != nil {
                await refresh()
            } else {
                me = nil
                pendingIncoming = 0
            }
        }
    }

    func refresh() async {
        guard let userID else { return }
        me = try? await API.profile(userID)
        pendingIncoming = (try? await API.pendingIncomingCount(for: userID)) ?? 0
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
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
