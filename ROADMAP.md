# ForeCal Roadmap

Ideas under consideration, not commitments. If one would help you, say so in
an issue; that's what moves an idea up.

## Potential future features

### Per-event weather
Show the forecast for an event's hour and place on the event row, not just the
day's high and low in the header. Most useful for outdoor events (soccer
practice, a run).
- Builds on: `WeatherStore` (Open-Meteo, which has hourly data) and the
  location lookup in `TravelStore`.
- Open question: which events count as outdoor? A keyword list will be wrong
  some of the time, so showing it for every in-person event may be simpler.

### Free time and conflicts
Flag overlapping events, and show open blocks in the agenda ("Free 1:15–4:30").
- Builds on: `CalendarStore.upcomingEvents`, which already skips declined and
  canceled events.
- Open question: whether tentative events and all-day events count as busy.

### Share availability
Copy a plain-text list of your open slots ("Tue 2–4, Wed after 3") to paste
into a message. It needs a visible button, not a shortcut.
- Builds on: free-time computation from the feature above, so ship that first.
- Stays read-only: it copies text and never writes to calendars.
