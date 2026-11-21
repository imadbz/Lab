# Dynamic Island Translator: product decisions

## It reads what's on screen, with almost no setup (2026-11-21)

Imad: "It has to just work on what's on screen ... no much config needed."

- The main way in is **screen sharing**. Open the app once, tap **Start**, confirm the system's screen broadcast sheet. From then on, in any chat app, hold the island and tap **Translate**. No Shortcut to build, no Action button to assign, no Photos permission.
- Translating is one tap on the island, not automatic. iOS doesn't let the screen broadcast extension update a Live Activity, and the app itself is suspended while another app is in front. The island's button is the one thing that wakes the app with the screen at hand. Doing it automatically would need a server sending APNs updates.
- The on-device reader is the default and needs nothing. The Claude reader stays an option for people who paste an API key.
- The screenshot Shortcut and the clipboard Shortcut stay as extras for people who want the Action button.
