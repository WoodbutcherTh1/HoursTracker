import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

/// Upload → OCR → LLM → always-on review → confirm/cancel.
/// Temporary entry point lives on the Export tab until Chunk 5 library ships.
struct PayslipUploadReviewView: View {
    @StateObject private var viewModel: PayslipUploadViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var saveError: String?

    var onSaved: ((PayslipRecord) -> Void)?

    init(settings: WorkplaceSettings = .default, onSaved: ((PayslipRecord) -> Void)? = nil) {
        // Construct on the main actor inside init — default-arg evaluation is nonisolated.
        _viewModel = StateObject(wrappedValue: PayslipUploadViewModel(settings: settings))
        self.onSaved = onSaved
    }

    /// Test/injection seam — call only from `@MainActor` contexts.
    init(viewModel: PayslipUploadViewModel, onSaved: ((PayslipRecord) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            phaseContent
                .navigationTitle(L10n.payslipUploadTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.editCancel) {
                            viewModel.cancelAndDiscard()
                            dismiss()
                        }
                    }
                    if viewModel.phase == .review {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.payslipSave) {
                                save()
                            }
                            .disabled(!viewModel.canSave)
                        }
                    }
                }
                .confirmationDialog(
                    L10n.payslipUploadSourceTitle,
                    isPresented: $viewModel.showSourceDialog,
                    titleVisibility: .visible
                ) {
                    Button(L10n.scannerCamera) {
                        viewModel.showCamera = true
                    }
                    Button(L10n.scannerPhotoLibrary) {
                        viewModel.showPhotosPicker = true
                    }
                    Button(L10n.scannerFile) {
                        viewModel.showFileImporter = true
                    }
                    Button(L10n.editCancel, role: .cancel) {}
                }
                .photosPicker(
                    isPresented: $viewModel.showPhotosPicker,
                    selection: $photoItem,
                    matching: .images
                )
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task { await loadPhotoItem(item) }
                }
                .fileImporter(
                    isPresented: $viewModel.showFileImporter,
                    allowedContentTypes: [.pdf, .image],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        viewModel.beginImport(fileURL: url)
                    }
                }
                .fullScreenCover(isPresented: $viewModel.showCamera) {
                    CameraPickerView { image in
                        viewModel.beginImport(image: image, originalFileName: "payslip-camera.jpg")
                    }
                }
                .alert(L10n.payslipUploadFailed, isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )) {
                    Button(L10n.editCancel, role: .cancel) { saveError = nil }
                } message: {
                    Text(saveError ?? "")
                }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .pick:
            pickView
        case .processing:
            processingView
        case .review:
            reviewForm
        case .failed(let message):
            failedView(message)
        }
    }

    private var pickView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.payslipUploadSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(L10n.payslipFillModePrompt)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    viewModel.chooseAutomaticFill()
                } label: {
                    Label(L10n.payslipFillModeAuto, systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.chooseManualFill()
                } label: {
                    Label(L10n.payslipFillModeManual, systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)

            Text(L10n.payslipFillModeSettingsHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer()
        }
        .padding(.top, 40)
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(L10n.payslipAnalyzing)
                .font(.headline)
            Text(L10n.payslipAnalyzingHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(L10n.payslipUploadFailed)
                .font(.headline)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(L10n.scannerTryAgain) {
                viewModel.cancelAndDiscard()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewForm: some View {
        Form {
            Section {
                previewBlock
                confidenceRow
            }

            Section(L10n.payslipSectionPeriod) {
                optionalDateRow(
                    title: L10n.payslipPaymentMonth,
                    enabledTitle: L10n.payslipPaymentMonthEnabled,
                    date: draftBinding(\.paymentMonth)
                )
                optionalDateRow(
                    title: L10n.payslipPeriodStart,
                    enabledTitle: L10n.payslipPeriodStartEnabled,
                    date: draftBinding(\.payPeriodStart)
                )
                optionalDateRow(
                    title: L10n.payslipPeriodEnd,
                    enabledTitle: L10n.payslipPeriodEndEnabled,
                    date: draftBinding(\.payPeriodEnd)
                )
            }

            Section(L10n.payslipSectionPay) {
                decimalField(L10n.payslipGross, value: draftBinding(\.grossPay))
                decimalField(L10n.payslipNet, value: draftBinding(\.netPay))
                TextField(L10n.payslipCurrency, text: draftStringBinding(\.currencyCode))
                    .textInputAutocapitalization(.characters)
                decimalField(L10n.payslipDeductions, value: draftBinding(\.deductionsTotal))
            }

            Section(L10n.payslipSectionPeople) {
                TextField(L10n.payslipEmployer, text: draftStringBinding(\.employerName))
                TextField(L10n.payslipEmployee, text: draftStringBinding(\.employeeName))
            }

            Section(L10n.payslipSectionHours) {
                optionalDoubleField(L10n.payslipHoursRegular, value: draftBinding(\.hoursRegular))
                optionalDoubleField(L10n.payslipHoursOT, value: draftBinding(\.hoursOT))
            }

            Section(L10n.payslipSectionNotes) {
                TextField(L10n.payslipNotes, text: draftStringBinding(\.notes), axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button(L10n.payslipSave) {
                    save()
                }
                .disabled(!viewModel.canSave)
                if !viewModel.canSave {
                    Text(L10n.payslipSaveDisabledHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var previewBlock: some View {
        if let image = viewModel.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(L10n.payslipPreview)
        } else if viewModel.previewIsPDF, let staged = viewModel.staged {
            PayslipPDFThumbnail(url: viewModel.previewURL(for: staged))
                .frame(height: 180)
                .accessibilityLabel(L10n.payslipPreview)
        } else {
            Label(L10n.payslipPreviewUnavailable, systemImage: "doc")
                .foregroundStyle(.secondary)
        }
    }

    private var confidenceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.payslipConfidence)
                Spacer()
                Text("\(viewModel.confidencePercent)%")
                    .foregroundStyle(.secondary)
            }
            if viewModel.needsManualReview {
                Label(L10n.payslipNeedsReview, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func optionalDateRow(title: String, enabledTitle: String, date: Binding<Date?>) -> some View {
        Group {
            Toggle(isOn: Binding(
                get: { date.wrappedValue != nil },
                set: { enabled in
                    if enabled {
                        if date.wrappedValue == nil { date.wrappedValue = Date() }
                    } else {
                        date.wrappedValue = nil
                    }
                }
            )) {
                Text(enabledTitle)
            }
            if date.wrappedValue != nil {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { date.wrappedValue ?? Date() },
                        set: { date.wrappedValue = $0 }
                    ),
                    displayedComponents: [.date]
                )
            }
        }
    }

    private func decimalField(_ title: String, value: Binding<Decimal?>) -> some View {
        TextField(title, text: Binding(
            get: {
                guard let decimal = value.wrappedValue else { return "" }
                return NSDecimalNumber(decimal: decimal).stringValue
            },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    value.wrappedValue = nil
                } else if let number = Decimal(string: trimmed.replacingOccurrences(of: ",", with: "")) {
                    value.wrappedValue = number
                }
            }
        ))
        .keyboardType(.decimalPad)
    }

    private func optionalDoubleField(_ title: String, value: Binding<Double?>) -> some View {
        TextField(title, text: Binding(
            get: {
                guard let number = value.wrappedValue else { return "" }
                return String(number)
            },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    value.wrappedValue = nil
                } else if let number = Double(trimmed.replacingOccurrences(of: ",", with: "")) {
                    value.wrappedValue = number
                }
            }
        ))
        .keyboardType(.decimalPad)
    }

    private func draftBinding<T>(_ keyPath: WritableKeyPath<PayslipReviewDraft, T>) -> Binding<T> {
        Binding(
            get: {
                guard let draft = viewModel.draft else {
                    return PayslipReviewDraft.empty[keyPath: keyPath]
                }
                return draft[keyPath: keyPath]
            },
            set: { newValue in
                guard var draft = viewModel.draft else { return }
                draft[keyPath: keyPath] = newValue
                viewModel.draft = draft
            }
        )
    }

    private func draftStringBinding(_ keyPath: WritableKeyPath<PayslipReviewDraft, String>) -> Binding<String> {
        draftBinding(keyPath)
    }

    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.phase = .failed(L10n.payslipUploadFailed)
                return
            }
            let type: UTType
            if let uiImage = UIImage(data: data), uiImage.pngData() != nil, data.count > 8,
               data.starts(with: [0x89, 0x50]) {
                type = .png
            } else {
                type = .jpeg
            }
            viewModel.beginImport(fileData: data, originalFileName: "payslip-photo.jpg", contentType: type)
        } catch {
            viewModel.phase = .failed(error.localizedDescription)
        }
        photoItem = nil
    }

    private func save() {
        do {
            let record = try viewModel.confirmSave()
            onSaved?(record)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

extension PayslipReviewDraft {
    static var empty: PayslipReviewDraft {
        PayslipReviewDraft(
            paymentMonth: nil,
            payPeriodStart: nil,
            payPeriodEnd: nil,
            grossPay: nil,
            netPay: nil,
            currencyCode: "ILS",
            employerName: "",
            employeeName: "",
            hoursRegular: nil,
            hoursOT: nil,
            deductionsTotal: nil,
            notes: "",
            extraction: PayslipExtraction(
                providerName: "none",
                extractedAt: Date(),
                confidence: 0,
                needsManualReview: true,
                rawJSON: nil,
                grossPay: nil,
                netPay: nil,
                currencyCode: nil,
                employerName: nil,
                employeeName: nil,
                employeeID: nil,
                payPeriodStart: nil,
                payPeriodEnd: nil,
                paymentDate: nil,
                hoursRegular: nil,
                hoursOT: nil,
                deductionsTotal: nil,
                extras: [:]
            )
        )
    }
}

private struct PayslipPDFThumbnail: View {
    let url: URL

    var body: some View {
        Group {
            if let document = PDFDocument(url: url), let page = document.page(at: 0) {
                let image = render(page: page)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label(L10n.payslipPreviewUnavailable, systemImage: "doc.richtext")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func render(page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let target = CGSize(width: min(max(bounds.width, 1), 400), height: min(max(bounds.height, 1), 560))
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            ctx.cgContext.translateBy(x: 0, y: target.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            let scale = min(target.width / max(bounds.width, 1), target.height / max(bounds.height, 1))
            ctx.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}
