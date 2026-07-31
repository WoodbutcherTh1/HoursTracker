import Foundation
import UniformTypeIdentifiers
import UIKit

/// Editable review draft populated from LLM extraction; all fields bind in the review UI.
struct PayslipReviewDraft: Equatable {
    var paymentMonth: Date?
    var payPeriodStart: Date?
    var payPeriodEnd: Date?
    var grossPay: Decimal?
    var netPay: Decimal?
    var currencyCode: String
    var employerName: String
    var employeeName: String
    var hoursRegular: Double?
    var hoursOT: Double?
    var deductionsTotal: Decimal?
    var notes: String

    /// Raw extraction kept for override diffing and persistence.
    var extraction: PayslipExtraction

    var hasPeriod: Bool {
        paymentMonth != nil || payPeriodStart != nil || payPeriodEnd != nil
    }

    var hasAmount: Bool {
        netPay != nil || grossPay != nil
    }

    /// Save gating: period/month AND (net OR gross) — design decision for Chunk 4.
    var canSave: Bool {
        hasPeriod && hasAmount
    }

    static func from(
        result: PayslipLLMStructureResult,
        extractedAt: Date = Date(),
        settings: WorkplaceSettings? = nil
    ) -> PayslipReviewDraft {
        let fields = result.fields
        let confidence = fields.confidence ?? 0
        let payPeriodStart = Self.parseFlexibleDate(fields.payPeriodStart)
        let payPeriodEnd = Self.parseFlexibleDate(fields.payPeriodEnd)
        let paymentMonth = Self.parseMonth(fields.paymentMonth)
            ?? payPeriodStart.map { Calendar.current.ht_payslipStartOfMonth(for: $0) }
            ?? payPeriodEnd.map { Calendar.current.ht_payslipStartOfMonth(for: $0) }

        let settingsEmployee = settings?.workerFullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let settingsEmployer: String = {
            guard let settings else { return "" }
            let workplace = settings.workplaceName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !workplace.isEmpty { return workplace }
            return settings.contractorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }()

        let extractedEmployer = Self.cleanedOptionalString(fields.employerName) ?? ""
        let extractedEmployee = Self.cleanedOptionalString(fields.employeeName) ?? ""
        let employer = extractedEmployer.isEmpty ? settingsEmployer : extractedEmployer
        let employee = extractedEmployee.isEmpty ? settingsEmployee : extractedEmployee

        let extraction = PayslipExtraction(
            providerName: result.providerName,
            extractedAt: extractedAt,
            confidence: confidence,
            needsManualReview: result.needsManualReview,
            rawJSON: result.rawJSON,
            grossPay: fields.grossPay.map { Decimal($0) },
            netPay: fields.netPay.map { Decimal($0) },
            currencyCode: Self.cleanedOptionalString(fields.currency) ?? "ILS",
            employerName: employer.isEmpty ? nil : employer,
            employeeName: employee.isEmpty ? nil : employee,
            employeeID: nil,
            payPeriodStart: payPeriodStart,
            payPeriodEnd: payPeriodEnd,
            paymentDate: paymentMonth,
            hoursRegular: fields.hoursRegular,
            hoursOT: fields.hoursOt,
            deductionsTotal: fields.deductionsTotal.map { Decimal($0) },
            extras: [:]
        )

        return PayslipReviewDraft(
            paymentMonth: paymentMonth,
            payPeriodStart: payPeriodStart,
            payPeriodEnd: payPeriodEnd,
            grossPay: extraction.grossPay,
            netPay: extraction.netPay,
            currencyCode: extraction.currencyCode ?? "ILS",
            employerName: employer,
            employeeName: employee,
            hoursRegular: extraction.hoursRegular,
            hoursOT: extraction.hoursOT,
            deductionsTotal: extraction.deductionsTotal,
            notes: Self.cleanedOptionalString(fields.notes) ?? "",
            extraction: extraction
        )
    }

    /// Some LLM providers emit an empty string, `"null"`, or `"N/A"` instead of a real
    /// JSON `null` for an unset field, despite the prompt asking for `null`. Treated as
    /// nil here so downstream `?? "ILS"` / Settings-fallback logic actually kicks in —
    /// previously an empty-string currency silently won the `??` over the "ILS" default
    /// because `Optional("")` is non-nil, leaving the field blank in the review form.
    private static func cleanedOptionalString(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let lowered = trimmed.lowercased()
        if lowered == "null" || lowered == "none" || lowered == "n/a" || lowered == "unknown" {
            return nil
        }
        return trimmed
    }

    /// Blank review draft for manual entry — still seeds name/workplace from Settings.
    static func manualBlank(settings: WorkplaceSettings?) -> PayslipReviewDraft {
        from(
            result: PayslipLLMStructureResult(
                fields: PayslipLLMFields(currency: "ILS", confidence: 0),
                providerName: "manual",
                needsManualReview: true
            ),
            settings: settings
        )
    }

    /// Builds overrides only for values the user changed relative to the raw extraction.
    func userOverrides(editedAt: Date = Date()) -> PayslipOverrides? {
        let extractionCurrency = extraction.currencyCode ?? "ILS"
        let extractionMonth = extraction.paymentDate
            ?? extraction.payPeriodStart.map { Calendar.current.ht_payslipStartOfMonth(for: $0) }

        let grossChanged = grossPay != extraction.grossPay
        let netChanged = netPay != extraction.netPay
        let currencyChanged = currencyCode != extractionCurrency
        let employerChanged = employerName != (extraction.employerName ?? "")
        let employeeChanged = employeeName != (extraction.employeeName ?? "")
        let startChanged = payPeriodStart != extraction.payPeriodStart
        let endChanged = payPeriodEnd != extraction.payPeriodEnd
        let monthChanged = paymentMonth != extractionMonth
        let hoursRegularChanged = hoursRegular != extraction.hoursRegular
        let hoursOTChanged = hoursOT != extraction.hoursOT
        let deductionsChanged = deductionsTotal != extraction.deductionsTotal

        let changed = grossChanged || netChanged || currencyChanged || employerChanged
            || employeeChanged || startChanged || endChanged || monthChanged
            || hoursRegularChanged || hoursOTChanged || deductionsChanged
        guard changed else { return nil }

        return PayslipOverrides(
            editedAt: editedAt,
            grossPay: grossChanged ? grossPay : nil,
            netPay: netChanged ? netPay : nil,
            currencyCode: currencyChanged ? currencyCode : nil,
            employerName: employerChanged ? (employerName.isEmpty ? nil : employerName) : nil,
            employeeName: employeeChanged ? (employeeName.isEmpty ? nil : employeeName) : nil,
            employeeID: nil,
            payPeriodStart: startChanged ? payPeriodStart : nil,
            payPeriodEnd: endChanged ? payPeriodEnd : nil,
            paymentDate: monthChanged ? paymentMonth : nil,
            hoursRegular: hoursRegularChanged ? hoursRegular : nil,
            hoursOT: hoursOTChanged ? hoursOT : nil,
            deductionsTotal: deductionsChanged ? deductionsTotal : nil,
            extras: nil
        )
    }

    var resolvedPeriodMonth: Date {
        if let paymentMonth { return Calendar.current.ht_payslipStartOfMonth(for: paymentMonth) }
        if let payPeriodStart { return Calendar.current.ht_payslipStartOfMonth(for: payPeriodStart) }
        if let payPeriodEnd { return Calendar.current.ht_payslipStartOfMonth(for: payPeriodEnd) }
        return Calendar.current.ht_payslipStartOfMonth(for: Date())
    }

    /// Snapshot the user confirmed — baked into `PayslipExtraction` so cleared fields
    /// do not fall back to raw AI values via `effective*` accessors.
    func confirmedExtraction(at date: Date = Date()) -> PayslipExtraction {
        var confirmed = extraction
        confirmed.extractedAt = date
        confirmed.needsManualReview = false
        confirmed.grossPay = grossPay
        confirmed.netPay = netPay
        confirmed.currencyCode = currencyCode.isEmpty ? nil : currencyCode
        confirmed.employerName = employerName.isEmpty ? nil : employerName
        confirmed.employeeName = employeeName.isEmpty ? nil : employeeName
        confirmed.payPeriodStart = payPeriodStart
        confirmed.payPeriodEnd = payPeriodEnd
        confirmed.paymentDate = paymentMonth
        confirmed.hoursRegular = hoursRegular
        confirmed.hoursOT = hoursOT
        confirmed.deductionsTotal = deductionsTotal
        return confirmed
    }

    private static func parseFlexibleDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: raw) { return date }

        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "dd.MM.yyyy", "MM/dd/yyyy", "yyyy/MM/dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return parseMonth(raw)
    }

    private static func parseMonth(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let formats = ["yyyy-MM", "MM/yyyy", "yyyy/MM", "MMMM yyyy", "MMM yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return Calendar.current.ht_payslipStartOfMonth(for: date)
            }
        }
        return nil
    }
}

@MainActor
final class PayslipUploadViewModel: ObservableObject {
    enum Phase: Equatable {
        case pick
        case processing
        case review
        case failed(String)
    }

    /// How to populate the review form after a file is chosen.
    enum FillMode: Equatable {
        /// OCR + payslip LLM/heuristic, then Settings fallbacks for name/workplace.
        case automatic
        /// Skip AI — user fills amounts; name/workplace still come from Settings.
        case manual
    }

    @Published var phase: Phase = .pick
    @Published var fillMode: FillMode = .automatic
    @Published var draft: PayslipReviewDraft?
    @Published var staged: StagedPayslipFile?
    @Published var previewImage: UIImage?
    @Published var previewIsPDF = false
    @Published var showSourceDialog = false
    @Published var showFileImporter = false
    @Published var showCamera = false
    @Published var showPhotosPicker = false

    private let store: PayslipStore
    private let scanner: TimesheetScannerManager
    private let cloudPreference: SmartScannerCloudPreferencing
    private let routerFactory: (_ includeCloud: Bool) -> PayslipLLMRouter
    private var settings: WorkplaceSettings
    private var processingTask: Task<Void, Never>?

    init(
        store: PayslipStore = .shared,
        scanner: TimesheetScannerManager = .shared,
        cloudPreference: SmartScannerCloudPreferencing = UserDefaultsSmartScannerCloudPreference.shared,
        settings: WorkplaceSettings = .default,
        routerFactory: @escaping (_ includeCloud: Bool) -> PayslipLLMRouter = { PayslipLLMRouter.default(includeCloud: $0) }
    ) {
        self.store = store
        self.scanner = scanner
        self.cloudPreference = cloudPreference
        self.settings = settings
        self.routerFactory = routerFactory
    }

    func updateSettings(_ settings: WorkplaceSettings) {
        self.settings = settings
    }

    var canSave: Bool {
        draft?.canSave == true
    }

    var needsManualReview: Bool {
        draft?.extraction.needsManualReview == true
    }

    var confidencePercent: Int {
        Int(((draft?.extraction.confidence ?? 0) * 100).rounded())
    }

    func previewURL(for staged: StagedPayslipFile) -> URL {
        store.url(forStaged: staged)
    }

    func chooseAutomaticFill() {
        fillMode = .automatic
        showSourceDialog = true
    }

    func chooseManualFill() {
        fillMode = .manual
        showSourceDialog = true
    }

    func cancelAndDiscard() {
        processingTask?.cancel()
        processingTask = nil
        if let staged {
            store.discardStaged(staged)
        }
        reset()
    }

    func reset() {
        phase = .pick
        draft = nil
        staged = nil
        previewImage = nil
        previewIsPDF = false
        showSourceDialog = false
        showFileImporter = false
        showCamera = false
        showPhotosPicker = false
        // Keep last fillMode preference for the session.
    }

    func beginImport(fileData: Data, originalFileName: String, contentType: UTType) {
        processingTask?.cancel()
        processingTask = Task { await processImport(fileData: fileData, originalFileName: originalFileName, contentType: contentType) }
    }

    func beginImport(image: UIImage, originalFileName: String = "payslip.jpg") {
        guard let data = image.jpegData(compressionQuality: 0.92) ?? image.pngData() else {
            phase = .failed(L10n.payslipUploadFailed)
            return
        }
        let type: UTType = (originalFileName as NSString).pathExtension.lowercased() == "png" ? .png : .jpeg
        beginImport(fileData: data, originalFileName: originalFileName, contentType: type)
    }

    func beginImport(fileURL: URL) {
        processingTask?.cancel()
        processingTask = Task {
            let accessed = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { fileURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: fileURL)
                let contentType = try resolvedContentType(for: fileURL)
                await processImport(
                    fileData: data,
                    originalFileName: fileURL.lastPathComponent,
                    contentType: contentType
                )
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func confirmSave() throws -> PayslipRecord {
        guard let draft, let staged, draft.canSave else {
            throw PayslipUploadError.cannotSaveIncomplete
        }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = try store.commitStaged(
            staged,
            periodMonth: draft.resolvedPeriodMonth,
            periodStartDay: nil,
            periodLabel: nil,
            extraction: draft.confirmedExtraction(),
            userOverrides: draft.userOverrides(),
            reviewState: .confirmed,
            notes: notes.isEmpty ? nil : notes
        )
        self.staged = nil
        reset()
        return record
    }

    /// Processes a payslip binary end-to-end (stage → OCR → LLM → review draft).
    func processImport(fileData: Data, originalFileName: String, contentType: UTType) async {
        // Discard any previous orphan before staging a new one.
        if let staged {
            store.discardStaged(staged)
            self.staged = nil
        }

        phase = .processing
        do {
            let stagedFile = try store.stageFile(
                fileData: fileData,
                originalFileName: originalFileName,
                contentType: contentType
            )
            if Task.isCancelled {
                store.discardStaged(stagedFile)
                return
            }
            staged = stagedFile
            updatePreview(fileData: fileData, contentType: contentType)

            if fillMode == .manual {
                draft = PayslipReviewDraft.manualBlank(settings: settings)
                phase = .review
                return
            }

            // Resolve providers before OCR runs so the cloud opt-in is captured
            // regardless of whether OCR later succeeds, finds no text, or throws —
            // callers observing routerFactory must see a consistent includeCloud
            // value on every path, not just the happy path.
            let includeCloud = cloudPreference.isEnabled
            let router = routerFactory(includeCloud)

            let ocrText: String
            if contentType.conforms(to: .pdf) {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("payslip-ocr-\(stagedFile.id.uuidString).pdf")
                try fileData.write(to: temp, options: .atomic)
                defer { try? FileManager.default.removeItem(at: temp) }
                ocrText = try await scanner.extractOCRText(fromFileURL: temp)
            } else if let image = UIImage(data: fileData) {
                ocrText = try await scanner.extractOCRText(from: image)
            } else {
                ocrText = try await scanner.extractOCRText(fromFileURL: store.url(forStaged: stagedFile))
            }

            if Task.isCancelled {
                store.discardStaged(stagedFile)
                staged = nil
                return
            }

            // OCR can succeed with no error yet find no recognizable text (blurry photo,
            // blank page, all-image PDF page that didn't OCR). Surface that explicitly
            // instead of silently continuing to an empty-looking review draft — that
            // looked like "AI didn't fill anything in" with no explanation.
            guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                store.discardStaged(stagedFile)
                staged = nil
                phase = .failed(L10n.payslipUploadNoTextFound)
                return
            }

            let result = await router.extractPayslip(ocrText: ocrText)

            if Task.isCancelled {
                store.discardStaged(stagedFile)
                staged = nil
                return
            }

            // Auto-fill from OCR/AI, then backfill worker/employer from Settings when missing.
            draft = PayslipReviewDraft.from(result: result, settings: settings)
            phase = .review
        } catch {
            if let staged {
                store.discardStaged(staged)
                self.staged = nil
            }
            phase = .failed(error.localizedDescription)
        }
    }

    private func updatePreview(fileData: Data, contentType: UTType) {
        if contentType.conforms(to: .pdf) {
            previewIsPDF = true
            previewImage = nil
        } else if let image = UIImage(data: fileData) {
            previewIsPDF = false
            previewImage = image
        } else {
            previewIsPDF = false
            previewImage = nil
        }
    }

    private func resolvedContentType(for fileURL: URL) throws -> UTType {
        if let contentType = try fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType
        }
        if let type = UTType(filenameExtension: fileURL.pathExtension) {
            return type
        }
        throw PayslipStoreError.unsupportedFileType
    }
}

enum PayslipUploadError: LocalizedError {
    case cannotSaveIncomplete

    var errorDescription: String? {
        switch self {
        case .cannotSaveIncomplete:
            return L10n.payslipSaveDisabledHint
        }
    }
}
