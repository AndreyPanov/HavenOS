import SwiftUI

struct DiscoveryView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @State private var searchText = ""
    @State private var selectedCategory: PluginCategory = .all
    @State private var path = NavigationPath()

    private var plugins: [DiscoverablePlugin] {
        serviceManager.discoverablePlugins
    }

    private var filteredPlugins: [DiscoverablePlugin] {
        var result = plugins

        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.summary.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Find services to add to Haven")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    // Category filter
                    HStack(spacing: 8) {
                        ForEach(PluginCategory.allCases) { category in
                            CategoryChip(
                                title: category.rawValue,
                                icon: category.systemImage,
                                isSelected: selectedCategory == category
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedCategory = category
                                }
                            }
                        }
                        Spacer()
                    }

                    // Plugin grid
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 340))],
                        spacing: 16
                    ) {
                        ForEach(filteredPlugins) { plugin in
                            NavigationLink(value: plugin) {
                                DiscoveryCardView(plugin: plugin)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Discovery")
            .searchable(text: $searchText, prompt: "Search services")
            .navigationDestination(for: DiscoverablePlugin.self) { plugin in
                DiscoveryDetailView(plugin: plugin)
            }
        }
    }
}

private struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.3) : Color(.separatorColor),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DiscoveryView()
        .environment(ServiceManager())
        .frame(width: 800, height: 600)
}
