import SwiftUI

/// Picks the workplace the app shows (History and Settings). Each workplace has
/// its own shifts, pay and settings; the optional "Merge" switch shows every
/// workplace's shifts together in History, each in its own color.
struct WorkplaceSwitcher: View {
    @ObservedObject var viewModel: AppViewModel
    var showsMergeToggle: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(viewModel.workplaceOptions) { option in
                    Button {
                        viewModel.switchWorkplace(to: option.workplaceID)
                    } label: {
                        if option.workplaceID == viewModel.activeWorkplaceKey {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.activeWorkplace.color)
                        .frame(width: 10, height: 10)
                    Text(viewModel.activeWorkplace.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
            .accessibilityLabel(L10n.workplaceSwitch)
            .accessibilityValue(viewModel.activeWorkplace.name)
            .accessibilityIdentifier("workplace.switcher")

            if showsMergeToggle {
                Spacer(minLength: 4)
                Toggle(isOn: Binding(
                    get: { viewModel.showAllWorkplaces },
                    set: { viewModel.setShowAllWorkplaces($0) }
                )) {
                    Text(L10n.workplaceMerge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .fixedSize()
                .accessibilityIdentifier("workplace.merge")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
