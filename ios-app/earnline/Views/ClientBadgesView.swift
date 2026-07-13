import SwiftUI

/// The client's Apple Fitness-inspired award collection. Every tile embeds the
/// same real RealityKit medal used on the detail page; locked awards stay
/// visible so the next milestone and its progress are understandable.
struct ClientBadgesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let clientName: String
    let achievements: [ClientAchievement]
    @State private var rendersCollectionModels = true

    private var earnedCount: Int {
        achievements.count(where: \.isUnlocked)
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clientName)
                        .appFont(24, .semibold, relativeTo: .title2)
                        .foregroundStyle(Theme.label)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(earnedCount) of \(achievements.count) earned")
                        .appFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(achievements) { achievement in
                        NavigationLink {
                            ClientBadgeDetailView(
                                clientName: clientName,
                                achievement: achievement
                            )
                        } label: {
                            ClientBadgeTile(
                                achievement: achievement,
                                renders3DModel: rendersCollectionModels
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("client.achievement.\(achievement.kind.rawValue)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Theme.background)
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("client.achievements")
        .onAppear { rendersCollectionModels = true }
        .onDisappear { rendersCollectionModels = false }
    }
}

private struct ClientBadgeTile: View {
    let achievement: ClientAchievement
    let renders3DModel: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if renders3DModel {
                        ClientBadgeModelView(achievement: achievement)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .allowsHitTesting(false)

                if !achievement.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(Theme.surface, in: .circle)
                        .accessibilityHidden(true)
                }
            }

            Text(achievement.kind.title)
                .appFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)

            if achievement.isUnlocked {
                Text("Earned")
                    .appFont(11, .medium, relativeTo: .caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: achievement.progress.fractionComplete)
                    .tint(.secondary)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(achievement.progress.accessibilityProgress)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(achievement.kind.title)
        .accessibilityValue(
            achievement.isUnlocked
                ? String(localized: "Earned")
                : String(localized: "Locked, \(achievement.progress.accessibilityProgress)")
        )
        .accessibilityHint("Open 3D award")
    }
}

private struct ClientBadgeDetailView: View {
    let clientName: String
    let achievement: ClientAchievement

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.surface)
                    ClientBadgeModelView(achievement: achievement, isInteractive: true)
                        .frame(width: 190, height: 190)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 310)
                .accessibilityIdentifier("client.achievement3D")

                Label("Drag to rotate", systemImage: "rotate.3d")
                    .appFont(13, relativeTo: .footnote)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text(achievement.kind.title)
                        .appFont(28, .bold, design: .rounded, relativeTo: .title)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)

                    Text(achievement.kind.explanation)
                        .appFont(15, relativeTo: .body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let unlockedAt = achievement.unlockedAt {
                    LabeledContent("Earned") {
                        Text(unlockedAt.formatted(date: .long, time: .omitted))
                            .foregroundStyle(Theme.label)
                    }
                    .accessibilityIdentifier("client.achievementEarnedDate")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text(achievement.progress.accessibilityProgress)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        ProgressView(value: achievement.progress.fractionComplete)
                            .tint(.secondary)

                        ForEach(achievement.progress.metrics, id: \.kind) { metric in
                            LabeledContent(metric.kind.title) {
                                Text("\(metric.current) / \(metric.target)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("client.achievementProgress")
                }

                Text("Awarded automatically from paid income lines for \(clientName).")
                    .appFont(13, relativeTo: .footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Theme.background)
        .navigationTitle(achievement.kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ClientAchievementKind {
    var title: String {
        switch self {
        case .firstPayment: String(localized: "First payment")
        case .repeatPartner: String(localized: "Regular partner")
        case .threeProjects: String(localized: "Project explorer")
        case .threeMonthRun: String(localized: "Three-month run")
        case .yearTogether: String(localized: "One year together")
        case .coreClient: String(localized: "Core client")
        }
    }

    var explanation: String {
        switch self {
        case .firstPayment: String(localized: "Receive the first paid income line from this client.")
        case .repeatPartner: String(localized: "Complete five paid income lines together.")
        case .threeProjects: String(localized: "Complete paid work across three different projects.")
        case .threeMonthRun: String(localized: "Receive paid income in three consecutive calendar months.")
        case .yearTogether: String(localized: "Keep working together for one full year between paid income lines.")
        case .coreClient: String(localized: "Reach 25 paid income lines across at least six active months.")
        }
    }
}

private extension ClientAchievementProgress {
    var accessibilityProgress: String {
        let percentage = Int((fractionComplete * 100).rounded())
        return String(localized: "\(percentage)% complete")
    }
}

private extension ClientAchievementMetric.Kind {
    var title: String {
        switch self {
        case .paidEntries: String(localized: "Paid income lines")
        case .distinctProjects: String(localized: "Different projects")
        case .consecutiveMonths: String(localized: "Consecutive months")
        case .calendarDays: String(localized: "Days together")
        case .activeMonths: String(localized: "Active months")
        }
    }
}
