import SwiftUI

struct DailyFeedView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("Daily Feed")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Spacer()
                
                Text("Daily feed content will go here")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    DailyFeedView()
}