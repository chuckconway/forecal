import EventKit
import Foundation

/// Finds a video-call link in an event's URL, location, or notes.
enum MeetingLink {
    private static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "facetime.apple.com", "chime.aws", "gotomeeting.com",
    ]
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func find(in event: EKEvent) -> URL? {
        let sources = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in sources {
            let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            for match in matches {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}
