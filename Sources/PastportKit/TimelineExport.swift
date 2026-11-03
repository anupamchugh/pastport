import Foundation

/// A structured item ready for export into Apple Reminders or third-party task managers.
public struct TimelineReminderItem: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let notes: String
    public let dueDate: Date?
    public let url: String?

    public init(id: UUID = UUID(), title: String, notes: String, dueDate: Date? = nil, url: String? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.url = url
    }
}

/// Utilities for exporting bookings and synthesized preparation tasks to calendar and reminder formats.
public enum TimelineExport {

    /// Exports a `Booking` commitment to an RFC 5545 `.ics` iCalendar text file.
    public static func toICalendar(booking: Booking) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        let dtstamp = formatter.string(from: Date()).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        let dtstart = formatter.string(from: booking.time).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")

        let cleanTitle = escapeICS(booking.title)
        let cleanHost = escapeICS(booking.host)

        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Pastport//Timeline Booking//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        BEGIN:VEVENT
        UID:\(booking.id.uuidString)
        DTSTAMP:\(dtstamp)
        DTSTART:\(dtstart)
        SUMMARY:\(cleanTitle)
        DESCRIPTION:Booking page you visited on \(cleanHost). Pastport saw the page\\, not whether the booking went through.
        URL:\(booking.url)
        END:VEVENT
        END:VCALENDAR
        """
    }

    /// Converts an `IntentTask` into a `TimelineReminderItem` suitable for Apple Reminders.
    public static func toReminderItem(task: IntentTask, dueDate: Date? = nil) -> TimelineReminderItem {
        TimelineReminderItem(
            id: task.id,
            title: task.title,
            notes: task.reason,
            dueDate: dueDate,
            url: task.actionURL
        )
    }

    private static func escapeICS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
