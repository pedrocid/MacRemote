import SwiftUI

/// View displaying a grid of installed apps that can be launched remotely
struct AppsView: View {
    @ObservedObject var client: NetworkClient
    @State private var searchText = ""
    @AppStorage("favoriteApps") private var favoriteAppsData: Data = Data()

    private var favoriteAppIds: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: favoriteAppsData)) ?? []
        }
    }

    private func setFavoriteAppIds(_ ids: Set<String>) {
        favoriteAppsData = (try? JSONEncoder().encode(ids)) ?? Data()
    }

    private var filteredApps: [AppInfo] {
        let apps = client.apps
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var favoriteApps: [AppInfo] {
        filteredApps.filter { favoriteAppIds.contains($0.bundleId) }
    }

    private var otherApps: [AppInfo] {
        filteredApps.filter { !favoriteAppIds.contains($0.bundleId) }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "apps_search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 8)

            if client.isLoadingApps {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Text(String(localized: "apps_loading"))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                Spacer()
            } else if client.apps.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "apps_empty"))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "apps_refresh")) {
                        client.requestAppList()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        // Favorites section
                        if !favoriteApps.isEmpty {
                            Section {
                                appsGrid(apps: favoriteApps)
                            } header: {
                                Text(String(localized: "apps_favorites"))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                            }
                        }

                        // All apps section
                        Section {
                            appsGrid(apps: otherApps)
                        } header: {
                            if !favoriteApps.isEmpty {
                                Text(String(localized: "apps_all"))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .onAppear {
            if client.apps.isEmpty && !client.isLoadingApps {
                client.requestAppList()
            }
        }
    }

    private func appsGrid(apps: [AppInfo]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(apps) { app in
                AppGridItem(
                    app: app,
                    isFavorite: favoriteAppIds.contains(app.bundleId),
                    onTap: {
                        client.launchApp(bundleId: app.bundleId)
                    },
                    onToggleFavorite: {
                        var ids = favoriteAppIds
                        if ids.contains(app.bundleId) {
                            ids.remove(app.bundleId)
                        } else {
                            ids.insert(app.bundleId)
                        }
                        setFavoriteAppIds(ids)
                    }
                )
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - App Grid Item

struct AppGridItem: View {
    let app: AppInfo
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    appIcon
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(app.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label(String(localized: "apps_open"), systemImage: "arrow.up.forward.app")
            }

            Button {
                onToggleFavorite()
            } label: {
                if isFavorite {
                    Label(String(localized: "apps_remove_favorite"), systemImage: "star.slash")
                } else {
                    Label(String(localized: "apps_add_favorite"), systemImage: "star")
                }
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let iconData = app.icon,
           let uiImage = UIImage(data: iconData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Color(.systemGray5))
        }
    }
}
