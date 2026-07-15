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

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("dd/MM")
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            phaseContent
                .navigationTitle(String(localized: "scanner.title", defaultValue: "Scan Timesheet"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { cancelToolbar }
                .onChange(of: scannerVM.photoItem) { _, item in
                    Task { await scannerVM.processPhotoItem(item) }
                }
                .fileImporter(
                    isPresented: $scannerVM.showFileImporter,
                    allowedContentTypes: [.pdf, .image, .commaSeparatedText, .plainText],
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
            Button(String(localized: "edit.cancel", defaultValue: "Cancel")) {
                dismiss()
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
        appViewModel.importScannedSessions(pendingImportDrafts, overwriteDays: overwriteDays)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private var pickView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text(String(localized: "scanner.subtitle", defaultValue: "Import a photo, screenshot, or PDF of your timesheet."))
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
                        String(localized: "scanner.photoLibrary", defaultValue: "Photo Library"),
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
                        String(localized: "scanner.camera", defaultValue: "Take Photo"),
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
                        String(localized: "scanner.file", defaultValue: "Choose File (PDF / Image)"),
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
            Text(String(localized: "scanner.analyzing", defaultValue: "Analyzing timesheet…"))
                .font(.headline)
            Text(String(localized: "scanner.analyzingHint", defaultValue: "Reading dates and clock times with on-device OCR."))
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
                Text(String(localized: "scanner.fallbackBanner", defaultValue: "Couldn't auto-detect shifts. Edit the draft row(s) below, then approve."))
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
                            String(localized: "scanner.addRow", defaultValue: "Add another day"),
                            systemImage: "plus.circle"
                        )
                    }
                } header: {
                    Text(String(localized: "scanner.reviewHeader", defaultValue: "Review extracted days"))
                } footer: {
                    Text(String(localized: "scanner.reviewFooter", defaultValue: "Uncheck days to skip. Tap a row to fix OCR mistakes before importing."))
                }
            }
            .listStyle(.insetGrouped)

            Button {
                beginApproveFlow()
            } label: {
                Text("\(String(localized: "scanner.approve", defaultValue: "Approve and Add to History")) (\(scannerVM.selectedCount))")
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
                String(localized: "scanner.failed", defaultValue: "Scan Failed"),
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: "scanner.tryAgain", defaultValue: "Try Again")) {
                scannerVM.reset()
            }
            .buttonStyle(.borderedProminent)
        }
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
                            Text(String(localized: "scanner.needsEdit", defaultValue: "Edit"))
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
                    String(localized: "manual.workDay", defaultValue: "Work Day"),
                    selection: $draft.date,
                    displayedComponents: .date
                )
                DatePicker(
                    String(localized: "edit.clockIn", defaultValue: "Clock In"),
                    selection: $draft.clockIn,
                    displayedComponents: [.date, .hourAndMinute]
                )
                DatePicker(
                    String(localized: "edit.clockOut", defaultValue: "Clock Out"),
                    selection: $draft.clockOut,
                    displayedComponents: [.date, .hourAndMinute]
                )
                TextField(
                    String(localized: "edit.notesPlaceholder", defaultValue: "Optional notes"),
                    text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0.isEmpty ? nil : $0 }
                    )
                )
            }
            .navigationTitle(String(localized: "scanner.editRow", defaultValue: "Edit Day"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissible()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "edit.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "edit.save", defaultValue: "Save")) {
                        var updated = draft
                        let resolved = WorkSession.resolveClockPair(
                            clockIn: draft.clockIn,
                            clockOut: draft.clockOut
                        )
                        updated.clockIn = resolved.clockIn
                        updated.clockOut = resolved.clockOut
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
