import Foundation

/// Produces Apple-style screenshot filenames and resolves collisions.
public enum SaveNamer {
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date))"
    }

    /// Returns `<folder>/<base>.png`, or `<base> (2).png`, `(3)`… when `exists` says the path is taken.
    public static func destination(
        for date: Date,
        in folder: URL,
        timeZone: TimeZone = .current,
        exists: (URL) -> Bool
    ) -> URL {
        let base = baseName(for: date, timeZone: timeZone)
        var candidate = folder.appendingPathComponent("\(base).png")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) (\(counter)).png")
            counter += 1
        }
        return candidate
    }
}
