import Foundation

/// Shared escaping for user-controlled strings in CSV / Markdown / XML exports.
enum ExportSanitizer {
    /// OWASP CSV injection mitigation: neutralize formula prefixes, then quote as needed.
    static func csvCell(_ value: String) -> String {
        var cell = value
        if let first = cell.unicodeScalars.first {
            switch first {
            case "=", "+", "-", "@", "\t", "\r":
                cell = "'" + cell
            default:
                break
            }
        }
        let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Escape pipes and neutralize leading Markdown formatting / formula characters.
    static func markdownCell(_ value: String) -> String {
        var cell = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
        if let first = cell.first {
            switch first {
            case "#", ">", "-", "*", "+", "=", "`":
                cell = "\\" + cell
            default:
                break
            }
        }
        return cell
    }

    /// For Markdown list / paragraph lines that include user names or free text.
    static func markdownInline(_ value: String) -> String {
        markdownCell(value)
    }
}
