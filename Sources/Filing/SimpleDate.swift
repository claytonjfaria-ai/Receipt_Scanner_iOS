import Foundation

/// A plain calendar date — year/month/day, no time, no timezone. Kotlin's `LocalDate` has this
/// built in; `Foundation.Date` doesn't (it's an instant, not a calendar date), and the main plan
/// explicitly warns about exactly this category of bug: `receipts.purchased_at` is a plain SQL
/// `date` rather than `timestamptz` specifically because "a timestamp written from a
/// model-returned bare date defaults to midnight in whichever timezone the writer assumes, which
/// can silently shift the day." Using `Date` here for billing/filing dates would reintroduce that
/// same risk class on the archive-filename path. `SimpleDate` sidesteps it by not having a
/// timezone to get wrong in the first place.
struct SimpleDate: Equatable {
    let year: Int
    let month: Int
    let day: Int

    /// `YYYYMMDD` — the filing-filename convention (`BillFileNaming`).
    var compactString: String { String(format: "%04d%02d%02d", year, month, day) }

    /// `YYYY-MM-DD` — Drive's `appProperties` billing-date convention (`BillFilingService`),
    /// matching `LocalDate.toString()` on Android and this type's own `parseISO` input format.
    var iso8601String: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Parses a strict `YYYY-MM-DD` string — the shape `extract-bill`'s `billing_date` and
    /// Review's free-text field are expected to use. Deliberately simple (no `DateFormatter`,
    /// no calendar/timezone involved at all) since the whole point is to never touch a timezone.
    static func parseISO(_ text: String) -> SimpleDate? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return SimpleDate(year: year, month: month, day: day)
    }

    /// "The phone's capture date" (plan §4.4) — this is the one place a timezone is legitimately
    /// involved, since "today" for a device-local capture genuinely is a wall-clock/local-calendar
    /// concept, unlike parsing a stored value with an assumed timezone.
    static func today(calendar: Calendar = .current) -> SimpleDate {
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return SimpleDate(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }
}
