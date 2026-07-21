import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class TimesheetScannerViewModel: ObservableObject {
    enum Phase: Equatable {
        case pick
        case processing
        case review
        case failed(String)
    }

    @Published var phase: Phase = .pick
    @Published var drafts: [ScannedSessionDraft] = []
    @Published var editingDraft: ScannedSessionDraft?
    @Published var photoItem: PhotosPickerItem?
    @Published var showFileImporter = false
    @Published var showCamera = false
    @Published var usedManualFallback = false
    @Published var processingDetails: ScannerProcessingDetails?
    @Published var showProcessingDetails = false

    private let scanner = TimesheetScannerManager.shared

    var selectedCount: Int {
        drafts.filter(\.isSelected).count
    }

    func processPhotoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        phase = .processing
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                // Still offer a blank editable draft instead of a dead-end.
                applyScanResult(
                    TimesheetScanResult(
                        drafts: [ScannedSessionDraft.blankDraft()],
                        ocrText: "",
                        usedManualFallback: true
                    )
                )
                return
            }
            let result = try await scanner.scan(image: image)
            applyScanResult(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func processCameraImage(_ image: UIImage) async {
        phase = .processing
        do {
            let result = try await scanner.scan(image: image)
            applyScanResult(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func processFile(url: URL) async {
        phase = .processing
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let result = try await scanner.scan(fileURL: url)
            applyScanResult(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func applyScanResult(_ result: TimesheetScanResult) {
        drafts = result.drafts
        usedManualFallback = result.usedManualFallback
        processingDetails = result.processingDetails
        phase = .review
    }

    func addBlankRow() {
        drafts.append(ScannedSessionDraft.blankDraft())
        usedManualFallback = true
    }

    func toggleSelection(_ draft: ScannedSessionDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index].isSelected.toggle()
    }

    func updateDraft(_ draft: ScannedSessionDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft
    }

    func reset() {
        phase = .pick
        drafts = []
        photoItem = nil
        editingDraft = nil
        usedManualFallback = false
        processingDetails = nil
        showProcessingDetails = false
    }
}

struct TimesheetScannerView: View {
    @ObservedObject var appViewModel: AppViewModel
    @StateObject private var scannerVM = TimesheetScannerViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var conflictQueue: [Date] = []
    @State private var allConflictDates: [Date] = []
    @State private var overwriteDays: Set<Date> = []
    @State private var showConflictAlert = false
    @State private var currentConflictDay: Date?
    @State private var pendingImportDrafts: [ScannedSessionDraft] = []

    private var dateFormatter: DateFormatter {
        AppLocale.makeDateFormatter(dateStyle: .medium)
    }

    private var shortDateFormatter: DateFormatter {
        AppLocale.makeDateFormatter(template: "dd/MM")
    }

    private var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    var body: some View {
        NavigationStack {
            phaseContent
                .navigationTitle(L10n.scannerTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { cancelToolbar }
                .onChange(of: scannerVM.photoItem) { _, item in
                    Task { await scannerVM.processPhotoItem(item) }
                }
                .fileImporter(
                    isPresented: $scannerVM.showFileImporter,
                    allowedContentTypes: [
                        .pdf,
                        .image,
                        .commaSeparatedText,
                        .tabSeparatedText,
                        .plainText,
                        .text
                    ],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        Task { await scannerVM.processFile(url: url) }
                    }
                }
                .fullScreenCover(isPresented: $scannerVM.showCamera) {
                    CameraPickerView { image in
                        Task { await scannerVM.processCameraImage(image) }
                    }
                }
                .sheet(item: $scannerVM.editingDraft) { draft in
                    ScannedDraftEditor(draft: draft) { updated in
                        scannerVM.updateDraft(updated)
                    }
                }
                .sheet(isPresented: $scannerVM.showProcessingDetails) {
                    if let details = scannerVM.processingDetails {
                        ScannerProcessingDetailsSheet(details: details)
                    }
                }
                .overlay { conflictOverlay }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch scannerVM.phase {
        case .pick:
            pickView
        case .processing:
            processingView
        case .review:
            reviewView
        case .failed(let message):
            failedView(message)
        }
    }

    @ToolbarContentBuilder
    private var cancelToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.editCancel) {
                dismiss()
            }
        }
        if scannerVM.phase == .review, scannerVM.processingDetails != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    scannerVM.showProcessingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel(L10n.scannerProcessingDetails)
            }
        }
    }

    @ViewBuilder
    private var conflictOverlay: some View {
        if showConflictAlert, let day = currentConflictDay {
            ImportConflictPopup(
                dates: allConflictDates,
                currentDate: day,
                onReplace: {
                    overwriteDays.insert(Calendar.current.startOfDay(for: day))
                    advanceConflictQueue()
                },
                onApplyAll: {
                    for conflictDay in allConflictDates {
                        overwriteDays.insert(Calendar.current.startOfDay(for: conflictDay))
                    }
                    conflictQueue = []
                    currentConflictDay = nil
                    showConflictAlert = false
                    commitImport()
                },
                onKeep: {
                    advanceConflictQueue()
                }
            )
            .zIndex(100)
        }
    }

    private func beginApproveFlow() {
        let selected = scannerVM.drafts.filter(\.isSelected)
        guard !selected.isEmpty else { return }
        pendingImportDrafts = selected
        overwriteDays = []
        conflictQueue = appViewModel.conflictingDays(for: selected)
        allConflictDates = conflictQueue
        if conflictQueue.isEmpty {
            commitImport()
        } else {
            presentNextConflict()
        }
    }

    private func presentNextConflict() {
        guard let next = conflictQueue.first else {
            commitImport()
            return
        }
        currentConflictDay = next
        withAnimation(.easeOut(duration: 0.18)) {
            showConflictAlert = true
        }
    }

    private func advanceConflictQueue() {
        if !conflictQueue.isEmpty {
            conflictQueue.removeFirst()
        }
        if conflictQueue.isEmpty {
            withAnimation(.easeOut(duration: 0.15)) {
                showConflictAlert = false
            }
            currentConflictDay = nil
            commitImport()
        } else {
            presentNextConflict()
        }
    }

    private func commitImport() {
        let count = appViewModel.importScannedSessions(pendingImportDrafts, overwriteDays: overwriteDays)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if count > 0 {
            appViewModel.showSuccessToast(L10n.feedbackImported(count))
        }
        dismiss()
    }

    private var pickView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.scannerSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                PhotosPicker(
                    selection: $scannerVM.photoItem,
                    matching: .images
                ) {
                    Label(
                        L10n.scannerPhotoLibrary,
                        systemImage: "photo.on.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    scannerVM.showCamera = true
                } label: {
                    Label(
                        L10n.scannerCamera,
                        systemImage: "camera.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)

                Button {
                    scannerVM.showFileImporter = true
                } label: {
                    Label(
                        L10n.scannerFile,
                        systemImage: "folder"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 40)
    }

    private var processingView: some View {
        VStack(spacing: 24) {
            ScannerSkeletonView()
            Text(L10n.scannerAnalyzing)
                .font(.headline)
            Text(L10n.scannerAnalyzingHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 48)
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            if scannerVM.usedManualFallback {
                Text(L10n.scannerFallbackBanner)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.12))
            }

            List {
                Section {
                    ForEach(scannerVM.drafts) { draft in
                        ScannedDraftRow(
                            draft: draft,
                            dateFormatter: dateFormatter,
                            timeFormatter: timeFormatter
                        ) {
                            scannerVM.toggleSelection(draft)
                        } onEdit: {
                            scannerVM.editingDraft = draft
                        }
                    }

                    Button {
                        scannerVM.addBlankRow()
                    } label: {
                        Label(
                            L10n.scannerAddRow,
                            systemImage: "plus.circle"
                        )
                    }
                } header: {
                    Text(L10n.scannerReviewHeader)
                } footer: {
                    Text(L10n.scannerReviewFooter)
                }
            }
            .listStyle(.insetGrouped)

            Button {
                beginApproveFlow()
            } label: {
                Text("\(L10n.scannerApprove) (\(scannerVM.selectedCount))")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(scannerVM.selectedCount == 0)
            .padding()
        }
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label(
                L10n.scannerFailed,
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button(L10n.scannerTryAgain) {
                scannerVM.reset()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ScannerProcessingDetailsSheet: View {
    let details: ScannerProcessingDetails
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.scannerProcessingProvider) {
                    Text(details.providerName)
                }
                Section {
                    LabeledContent(L10n.scannerProcessingAccepted) {
                        Text("\(details.acceptedCount)")
                    }
                    LabeledContent(L10n.scannerNeedsEdit) {
                        Text("\(details.reviewCount)")
                    }
                    LabeledContent(L10n.scannerProcessingRejected) {
                        Text("\(details.rejectedCount)")
                    }
                }
                if !details.notes.isEmpty {
                    Section {
                        ForEach(Array(details.notes.enumerated()), id: \.offset) { _, note in
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.scannerProcessingDetails)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.errorOK) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ScannedDraftRow: View {
    let draft: ScannedSessionDraft
    let dateFormatter: DateFormatter
    let timeFormatter: DateFormatter
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: draft.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(dateFormatter.string(from: draft.date))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if draft.needsManualReview {
                            Text(L10n.scannerNeedsEdit)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(timeFormatter.string(from: draft.clockIn)) – \(timeFormatter.string(from: draft.clockOut))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text(String(format: "%.1f h", draft.totalHours))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(draft.isSelected ? 1 : 0.45)
    }
}

struct ScannedDraftEditor: View {
    @State private var draft: ScannedSessionDraft
    let onSave: (ScannedSessionDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    init(draft: ScannedSessionDraft, onSave: @escaping (ScannedSessionDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    L10n.manualWorkDay,
                    selection: $draft.date,
                    displayedComponents: .date
                )
                DatePicker(
                    L10n.editClockIn,
                    selection: $draft.clockIn,
                    displayedComponents: [.date, .hourAndMinute]
                )
                DatePicker(
                    L10n.editClockOut,
                    selection: $draft.clockOut,
                    displayedComponents: [.date, .hourAndMinute]
                )
                TextField(
                    L10n.editNotesPlaceholder,
                    text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0.isEmpty ? nil : $0 }
                    )
                )
            }
            .navigationTitle(L10n.scannerEditRow)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissible()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.editSave) {
                        var updated = draft
                        let resolved = WorkSession.resolveClockPair(
                            clockIn: draft.clockIn,
                            clockOut: draft.clockOut
                        )
                        updated.clockIn = resolved.clockIn
                        updated.clockOut = resolved.clockOut
                        updated.needsManualReview = false
                        onSave(updated)
                        dismiss()
                    }
                    .disabled({
                        let calendar = Calendar.current
                        let inParts = calendar.dateComponents([.hour, .minute], from: draft.clockIn)
                        let outParts = calendar.dateComponents([.hour, .minute], from: draft.clockOut)
                        return inParts.hour == outParts.hour && inParts.minute == outParts.minute
                    }())
                }
            }
        }
    }
}

struct ScannerSkeletonView: View {
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 56)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.35), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .rotationEffect(.degrees(12))
                        .offset(x: shimmer ? 220 : -220)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }
    }
}
