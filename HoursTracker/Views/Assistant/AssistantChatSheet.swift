import SwiftUI
import UIKit

/// The assistant conversation, presented as a sheet over whatever tab you were on rather
/// than as a destination you navigate away to — asking "how many hours this month?"
/// shouldn't cost you your place in the app.
struct AssistantChatSheet: View {
    @ObservedObject var viewModel: AppViewModel

    @StateObject private var chat = AssistantChatViewModel()
    @StateObject private var payslipLibrary = PayslipLibraryViewModel()
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    /// One presentation slot rather than two `.sheet` modifiers on the same view —
    /// stacking those is a long-standing way to get a sheet that silently never appears.
    private enum Route: Identifiable {
        case share(ShareableFile)
        case payslip(PayslipRecord)

        var id: String {
            switch self {
            case let .share(file): return "share-\(file.id.uuidString)"
            case let .payslip(record): return "payslip-\(record.id.uuidString)"
            }
        }
    }

    @State private var route: Route?

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    transcript
                    composer
                }
            }
            .navigationTitle(L10n.assistantTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.assistantClear) { chat.clear() }
                        .foregroundStyle(theme.accent)
                        .disabled(chat.messages.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone) { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .sheet(item: $route) { route in
                switch route {
                case let .share(file):
                    ShareSheet(items: [file.url])
                case let .payslip(record):
                    NavigationStack {
                        PayslipDetailView(
                            record: record,
                            sourceURL: payslipLibrary.sourceURL(for: record),
                            onDelete: {
                                do {
                                    try payslipLibrary.delete(record)
                                    return true
                                } catch {
                                    return false
                                }
                            }
                        )
                    }
                }
            }
            .onAppear {
                // A key may have been added in Settings since this sheet last existed.
                chat.refreshConfiguration()
                payslipLibrary.reload()
            }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty {
                        AssistantWelcomeView(
                            accent: theme.accent,
                            workerName: viewModel.settings.workerFullName
                        ) { suggestion in
                            inputFocused = false
                            chat.ask(suggestion, viewModel: viewModel)
                        }
                        .padding(.top, 12)
                    }

                    ForEach(chat.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }

                    if chat.isThinking {
                        AssistantThinkingBubble(accent: theme.accent)
                            .id(Self.thinkingAnchor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: chat.isThinking) { _, _ in
                scrollToEnd(proxy)
            }
        }
    }

    private static let thinkingAnchor = "assistant.thinking"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if chat.isThinking {
                proxy.scrollTo(Self.thinkingAnchor, anchor: .bottom)
            } else if let last = chat.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AssistantMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.accent.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(theme.accent.opacity(0.45), lineWidth: 1)
                            )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant:
            AssistantAnswerBubble(
                answer: message.answer ?? .plain(message.text),
                accent: theme.accent,
                onShare: { url in route = .share(ShareableFile(url: url)) },
                onOpenPayslip: { record in route = .payslip(record) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 10) {
                TextField(L10n.assistantInputPlaceholder, text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .tint(theme.accent)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { chat.send(viewModel: viewModel) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(HomeNeon.card)
                            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    )

                Button {
                    inputFocused = false
                    chat.send(viewModel: viewModel)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(chat.canSend ? .black : .white.opacity(0.35))
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(chat.canSend ? theme.accent : HomeNeon.card)
                        )
                }
                .buttonStyle(ScalePressButtonStyle())
                .disabled(!chat.canSend)
                .accessibilityLabel(L10n.assistantSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(appBackground.background)
    }
}

// MARK: - Answer bubble

/// One assistant reply. The headline, the scope line, every row, and every attachment
/// come from `AssistantEngine` — this view only lays them out.
struct AssistantAnswerBubble: View {
    let answer: AssistantAnswer
    var accent: Color = HomeNeon.accent
    var onShare: (URL) -> Void = { _ in }
    var onOpenPayslip: (PayslipRecord) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(answer.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let scope = answer.scope, !scope.isEmpty {
                Text(scope)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(accent.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }

            if !answer.rows.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(answer.rows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer(minLength: 12)
                            Text(row.value)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if let note = answer.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let attachment = answer.attachment {
                attachmentView(attachment)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HomeNeon.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .frame(maxWidth: 320, alignment: .leading)
    }

    @ViewBuilder
    private func attachmentView(_ attachment: AssistantAnswer.Attachment) -> some View {
        switch attachment {
        case let .document(url, fileName):
            AssistantDocumentCard(fileName: fileName, accent: accent) { onShare(url) }
        case let .payslip(record, fileURL):
            AssistantPayslipCard(
                record: record,
                sourceURL: fileURL,
                accent: accent,
                onOpen: { onOpenPayslip(record) },
                onShare: { onShare(fileURL) }
            )
        }
    }
}

/// A generated report, shown as a card you can share straight from the conversation —
/// the same `ShareSheet` the Export tab uses, not a bare file path.
struct AssistantDocumentCard: View {
    let fileName: String
    var accent: Color = HomeNeon.accent
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(fileName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent))
            }
            .buttonStyle(ScalePressButtonStyle())
            .accessibilityLabel(AppLocale.tr("history.exportShift"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

/// A payslip the user already uploaded. Retrieval, not generation: the thumbnail is the
/// real first page from `PayslipThumbnailCache`, View opens the real
/// `PayslipDetailView`, and Share hands over the original file they imported.
struct AssistantPayslipCard: View {
    let record: PayslipRecord
    let sourceURL: URL
    var accent: Color = HomeNeon.accent
    var cache: PayslipThumbnailCache = .shared
    let onOpen: () -> Void
    let onShare: () -> Void

    @State private var thumbnail: UIImage?
    @State private var didRequest = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 8) {
                Text(record.periodLabel ?? HistoryPeriodHelper.monthTitle(for: record.effectivePeriodMonth))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        Text(L10n.assistantView)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(accent))
                    }
                    .buttonStyle(ScalePressButtonStyle())

                    Button(action: onShare) {
                        Label(AppLocale.tr("history.exportShift"), systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(ScalePressButtonStyle())
                    .accessibilityLabel(AppLocale.tr("history.exportShift"))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .onAppear(perform: loadThumbnail)
    }

    private var thumbnailView: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.35))
            .frame(width: 46, height: 60)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "doc.text")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func loadThumbnail() {
        guard !didRequest else { return }
        didRequest = true
        if let cached = cache.cachedImage(for: record.id) {
            thumbnail = cached
            return
        }
        cache.thumbnail(for: record, sourceURL: sourceURL) { image in
            thumbnail = image
        }
    }
}

/// Three dots while the router is deciding which tool to run. The assistant genuinely
/// waits on the network here, so the wait is shown rather than hidden.
struct AssistantThinkingBubble: View {
    var accent: Color = HomeNeon.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(accent.opacity(phase == index ? 0.95 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Text(L10n.assistantThinking)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HomeNeon.card)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = (phase + 1) % 3
            }
        }
        .accessibilityLabel(L10n.assistantThinking)
    }
}
