//
//  AboutView.swift
//  PawLog
//
//  关于与免责声明。
//

import SwiftUI

struct AboutView: View {
    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return String(localized: "settings.about.version \(version)")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(String(localized: "settings.about.title"))
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(versionText)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.vertical, Theme.Spacing.sm)
            }

            Section(String(localized: "settings.disclaimer.title")) {
                Text(String(localized: "settings.disclaimer.body"))
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            Section {
                Text(String(localized: "summary.disclaimer"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .navigationTitle(String(localized: "settings.about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("AboutView") {
    NavigationStack {
        AboutView()
    }
}
