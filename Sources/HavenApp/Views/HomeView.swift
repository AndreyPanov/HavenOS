import SwiftUI

struct HomeView: View {
    @State private var searchText = ""
    @State private var path = NavigationPath()

    private var services: [InstalledService] {
        MockData.installedServices
    }

    private var filteredServices: [InstalledService] {
        if searchText.isEmpty { return services }
        return services.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.serviceDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var runningCount: Int {
        services.filter { $0.status == .running }.count
    }

    private var stoppedCount: Int {
        services.filter { $0.status == .stopped || $0.status == .failed }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Installed Services")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    // Summary stats
                    HStack(spacing: 24) {
                        StatItem(label: "Installed", value: "\(services.count)", color: .primary)
                        StatItem(label: "Running", value: "\(runningCount)", color: .green)
                        StatItem(label: "Stopped", value: "\(stoppedCount)", color: .secondary)
                    }
                    .padding(.bottom, 4)

                    // Service grid
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 360))],
                        spacing: 16
                    ) {
                        ForEach(filteredServices) { service in
                            NavigationLink(value: service) {
                                ServiceCardView(service: service)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Haven")
            .searchable(text: $searchText, prompt: "Search services")
            .navigationDestination(for: InstalledService.self) { service in
                ServiceDetailView(service: service)
            }
        }
    }
}

private struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HomeView()
        .frame(width: 800, height: 600)
}
