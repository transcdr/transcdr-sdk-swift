import Foundation

/// Display formatting shared by every screen, matching the web dashboard.
public enum Format {
    /// `1536` → `1.5 KB`.
    public static func bytes(_ bytes: Int64?, digits: Int = 1) -> String {
        guard let bytes else { return "—" }
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes) / 1024
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return "\(fixed(value, value >= 100 ? 0 : digits)) \(units[unit])"
    }

    /// `634.5` → `10:34`, `3725` → `1:02:05`.
    public static func clock(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "—" }
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let mm = h > 0 ? String(format: "%02d", m) : String(m)
        return (h > 0 ? "\(h):" : "") + "\(mm):" + String(format: "%02d", sec)
    }

    /// A short human duration from seconds: `850ms`, `42s`, `3m 12s`, `1h 4m`.
    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let ms = seconds * 1000
        if ms < 1000 { return "\(Int(ms.rounded()))ms" }
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m \(s % 60)s" }
        return "\(m / 60)h \(m % 60)m"
    }

    public static func duration(from start: Date?, to end: Date?) -> String {
        guard let start else { return "—" }
        return duration((end ?? Date()).timeIntervalSince(start))
    }

    public static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd jj:mm")
        return f.string(from: date)
    }

    public static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// A calendar date for UTC boundaries (billing periods).
    public static func utcDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// `just now`, `5 minutes ago`, `in 2 hours`, then a date past 30 days.
    public static func timeAgo(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let diff = date.timeIntervalSince(now)
        let abs = Swift.abs(diff)
        if abs < 45 { return "just now" }
        if abs >= 86_400 * 30 { return Format.date(date) }
        let (value, unit): (Int, String) =
            abs < 3600 ? (Int((diff / 60).rounded()), "minute")
            : abs < 86_400 ? (Int((diff / 3600).rounded()), "hour")
            : (Int((diff / 86_400).rounded()), "day")
        #if canImport(Darwin)
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        var c = DateComponents()
        switch unit {
        case "minute": c.minute = value
        case "hour": c.hour = value
        default: c.day = value
        }
        return f.localizedString(from: c)
        #else
        if unit == "day" && value == -1 { return "yesterday" }
        if unit == "day" && value == 1 { return "tomorrow" }
        let n = Swift.abs(value)
        let text = "\(n) \(unit)\(n == 1 ? "" : "s")"
        return value < 0 ? "\(text) ago" : "in \(text)"
        #endif
    }

    /// Cents as dollars: `$12.34`; `precise` shows sub-cent (3–4 digits).
    public static func cents(_ cents: Int?, precise: Bool = false) -> String {
        guard let cents else { return "—" }
        return currency(Double(cents) / 100, min: precise ? 3 : 2, max: precise ? 4 : 2)
    }

    /// Dollars (the API's `*_usd` fields). `precise` shows sub-cent amounts under $1.
    public static func usd(_ dollars: Double?, precise: Bool = false) -> String {
        guard let dollars, dollars.isFinite else { return "—" }
        let small = precise && Swift.abs(dollars) < 1 && dollars != 0
        return currency(dollars == 0 ? 0 : dollars, min: 2, max: small ? 4 : 2)
    }

    public static func number(_ value: Double?, digits: Int = 0) -> String {
        guard let value, value.isFinite else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? "\(value)"
    }

    public static func number(_ value: Int?) -> String { number(value.map(Double.init)) }

    /// `4.25 min`, `12.5 min`.
    public static func minutes(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(number(value, digits: value < 10 ? 2 : 1)) min"
    }

    /// `job_Zlwif1p7nBycseUQ` → `job_Zlwif1…`.
    public static func shortId(_ id: String) -> String {
        guard let underscore = id.firstIndex(of: "_") else { return id }
        let rest = id[id.index(after: underscore)...]
        return rest.isEmpty ? id : "\(id[..<underscore])_\(rest.prefix(6))…"
    }

    public static func pluralize(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number(count)) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// `YYYY-MM-DD` in the local time zone.
    public static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `12,345` below `compactFrom`, `12.3K` / `4.5M` above.
    public static func compact(_ n: Double, compactFrom: Double = 10_000) -> String {
        if Swift.abs(n) < compactFrom { return number(n) }
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (size, suffix) in units where Swift.abs(n) >= size {
            return "\(fixed(n / size, n / size >= 100 ? 0 : 1))\(suffix)"
        }
        return number(n)
    }

    /// A resolution label: `1920×1080`.
    public static func resolution(_ width: Int, _ height: Int) -> String { "\(width)×\(height)" }

    /// `59.94 fps`.
    public static func fps(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return "\(number(value, digits: 2)) fps"
    }

    static func fixed(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    /// USD, always as `$1,234.56` (the API bills in dollars whatever the
    /// device's region): at least `min` and at most `max` decimals.
    static func currency(_ dollars: Double, min: Int, max: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.decimalSeparator = "."
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        f.roundingMode = .halfUp
        let body = f.string(from: NSNumber(value: Swift.abs(dollars))) ?? fixed(Swift.abs(dollars), max)
        return (dollars < 0 ? "-$" : "$") + body
    }
}

/// Content types for uploads, by extension.
public enum MediaTypes {
    static let byExtension: [String: String] = [
        "mp4": "video/mp4", "m4v": "video/x-m4v", "mov": "video/quicktime", "mkv": "video/x-matroska",
        "webm": "video/webm", "avi": "video/x-msvideo", "ts": "video/mp2t", "m2ts": "video/mp2t", "mts": "video/mp2t",
        "mxf": "application/mxf", "flv": "video/x-flv", "wmv": "video/x-ms-wmv", "mpg": "video/mpeg", "mpeg": "video/mpeg",
        "3gp": "video/3gpp", "ogv": "video/ogg", "m4a": "audio/mp4", "mp3": "audio/mpeg", "wav": "audio/wav",
        "flac": "audio/flac", "aac": "audio/aac", "opus": "audio/opus", "srt": "application/x-subrip", "vtt": "text/vtt",
    ]

    public static func contentType(forFilename name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return byExtension[ext] ?? "application/octet-stream"
    }
}
