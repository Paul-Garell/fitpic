import SwiftUI

struct MainTabView: View {
    /// Single shared source of truth for fit pics across all tabs.
    @StateObject private var store = FitPicStore()

    var body: some View {
        TabView {
            DailyFeedView()
                .tabItem {
                    Label("Daily Feed", systemImage: "house")
                }

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            ProfileView()
                .tabItem {
                    Label("User", systemImage: "person")
                }
        }
        .environmentObject(store)
    }
}

#Preview {
    MainTabView()
}