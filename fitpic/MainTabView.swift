import SwiftUI

struct MainTabView: View {
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
    }
}

#Preview {
    MainTabView()
}