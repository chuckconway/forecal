<img src="docs/icon.png" width="96" alt="ForeCal icon">

# ForeCal

A menu bar calendar for macOS that looks ahead: your events, the weather, and
when to leave.

ForeCal is free, open source, and read-only. It shows what's in the calendars
you already have in macOS Calendar (iCloud, Google, Exchange, CalDAV) and never
changes them.

<p align="center">
  <img src="docs/panel-light.png" width="340" alt="ForeCal in light mode: a month grid above a scrolling agenda with weather and leave-by times">
  &nbsp;
  <img src="docs/panel-dark.png" width="340" alt="ForeCal in dark mode">
</p>

## Features

- **Menu bar countdown.** The menu bar shows what's next: "Leave in 12m" when
  it's time to drive somewhere, the next event's countdown within 30 minutes,
  or when the current event ends.
- **Leave-by times.** In-person events in the next two days get an Apple Maps
  drive time from where you are, and a "Leave by 8:33 AM · 42 min" badge.
  A Directions button opens the route in Maps.
- **Weather.** Each day in the agenda shows its forecast high, low, and chance
  of rain, 16 days out.
- **Join buttons.** Events with a Zoom, Google Meet, Teams, Webex, FaceTime,
  Whereby, Chime, or GoToMeeting link get a one-click Join button.
- **Month grid and agenda, in sync.** Scroll the agenda and the grid follows;
  click a day and the agenda jumps to it. Day headers stay pinned while you
  scroll, and hovering an event rings its day in the grid in the event's
  calendar color.
- **A now line** in today's list, with the time until your next event.
- **Your choice of calendars and today color,** from the gear menu.

## Install

Download `ForeCal.zip` from the
[latest release](https://github.com/chuckconway/forecal/releases/latest),
unzip it, and drag ForeCal to your Applications folder. It's signed and
notarized, so it opens without warnings. Requires macOS 14 Sonoma or later.

The first time it runs, ForeCal asks for access to your calendars and your
location. Location is optional: without it you get no weather or drive times.

## Privacy

ForeCal has no server, account, analytics, or tracking. Two things leave your
Mac:

- **Weather:** your location, rounded to about 1 km, goes to
  [Open-Meteo](https://open-meteo.com).
- **Drive times:** your location and the addresses of in-person events in the
  next two days go to Apple Maps.

Event titles, notes, attendees, and everything else stay on your Mac.

## Build from source

You need Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/chuckconway/forecal.git
cd forecal
./build.sh --install   # builds build/ForeCal.app, copies it to ~/Applications, and opens it
```

By default, local builds are signed ad hoc, which macOS treats as a new app
each time: expect the calendar and location prompts again after every rebuild.
To keep permissions across rebuilds, create a self-signed code-signing
certificate in Keychain Access and put its name in a `.signing-identity` file
at the repo root (it's gitignored).

Run the tests with `./test.sh`. They cover the logic with rules behind it: the
menu bar countdown, which events count as in person, meeting links, weather
decoding, and how multi-day events land on days. It works with full Xcode or
just the Command Line Tools.

`./build.sh --release` runs the tests, then signs with a Developer ID certificate, notarizes, and
writes `build/ForeCal.zip`. It expects a `notarytool` keychain profile named
`ForeCal`.

### Screenshots without your own data

`build/ForeCal.app/Contents/MacOS/ForeCal --snapshot <dir>` renders the panel
offscreen with sample events, in light and dark, and writes PNGs to `<dir>`. It
never touches your calendars or asks for permissions. The screenshots in this
README come from it.

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## License

[MIT](LICENSE). Weather data by [Open-Meteo](https://open-meteo.com), licensed
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
