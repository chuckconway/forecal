import Testing
@testable import ForeCal

@Suite("Meeting links")
struct MeetingLinkTests {
    @Test("Finds call links in the URL, location, or notes", arguments: [
        (nil, nil, "Join: https://us02web.zoom.us/j/123456", "https://us02web.zoom.us/j/123456"),
        ("https://meet.google.com/abc-defg-hij", nil, nil, "https://meet.google.com/abc-defg-hij"),
        (nil, "https://teams.microsoft.com/l/meetup-join/1", nil, "https://teams.microsoft.com/l/meetup-join/1"),
    ] as [(String?, String?, String?, String)])
    func finds(url: String?, location: String?, notes: String?, expected: String) {
        let event = Fixtures.event(start: 10, location: location, notes: notes, url: url)
        #expect(MeetingLink.find(in: event)?.absoluteString == expected)
    }

    @Test("Ignores other links and lookalike hosts", arguments: [
        "Agenda: https://docs.google.com/document/d/1",
        "https://notzoom.us/j/123",
        "No link here",
    ])
    func ignores(notes: String) {
        #expect(MeetingLink.find(in: Fixtures.event(start: 10, notes: notes)) == nil)
    }
}

@Suite("In-person locations")
@MainActor
struct PhysicalLocationTests {
    @Test("Addresses and places get drive times", arguments: [
        "City Gym, 100 Main St",
        "San Francisco International Airport",
        "  Golden Gate Park  ",
    ])
    func places(location: String) {
        let event = Fixtures.event(start: 60, location: location)
        #expect(TravelStore.physicalLocation(of: event) == location.trimmingCharacters(in: .whitespaces))
    }

    @Test("Calls, rooms, and placeholders don't", arguments: [
        "Zoom", "Microsoft Teams Meeting", "Conference Room B", "Phone", "TBD",
        "https://example.com/event", "",
    ])
    func notPlaces(location: String) {
        #expect(TravelStore.physicalLocation(of: Fixtures.event(start: 60, location: location)) == nil)
    }

    @Test func noLocation() {
        #expect(TravelStore.physicalLocation(of: Fixtures.event(start: 60)) == nil)
    }
}
