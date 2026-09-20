import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Top section: Profile header
                    ProfileHeaderView()
                    
                    // Middle section: Stats
                    ProfileStatsView()
                    
                    // Bottom section: Under construction
                    UnderConstructionView()
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

struct ProfileHeaderView: View {
    var body: some View {
        VStack(spacing: 16) {
            // Profile picture/avatar placeholder
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("User Profile")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Member since September 2026")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .primary.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

struct ProfileStatsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Stats")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                StatCard(title: "Days", value: "365", color: .green)
                StatCard(title: "Photos", value: "1,024", color: .blue)
                StatCard(title: "Streak", value: "30", color: .orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .primary.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.05))
        )
    }
}

struct UnderConstructionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Under Construction")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("More features coming soon!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .primary.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

#Preview {
    ProfileView()
}