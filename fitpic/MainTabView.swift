import SwiftUI

struct MainTabView: View {
    /// Single shared source of truth for fit pics across all tabs.
    @StateObject private var store = FitPicStore()
    /// Cataloged garments.
    @StateObject private var closet = ClosetStore()
    /// Tunable knobs for the cataloging pipeline.
    @StateObject private var closetSettings = ClosetDebugSettingsStore()
    /// Drives the app-level pinch-zoom overlay.
    @StateObject private var zoomOverlay = ZoomOverlayModel()

    var body: some View {
        ZStack {
            TabView {
                DailyFeedView()
                    .tabItem {
                        Label("Daily Feed", systemImage: "house")
                    }

                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }

                ClosetView()
                    .tabItem {
                        Label("Closet", systemImage: "hanger")
                    }

                ProfileView()
                    .tabItem {
                        Label("User", systemImage: "person")
                    }
            }

            // Sits above the tab bar and all scroll content while zooming.
            ZoomOverlay(model: zoomOverlay)
        }
        .environmentObject(store)
        .environmentObject(closet)
        .environmentObject(closetSettings)
        .environmentObject(zoomOverlay)
    }
}

#Preview {
    MainTabView()
}
