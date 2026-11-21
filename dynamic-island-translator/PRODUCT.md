# Dynamic Island Translator: product decisions

## It reads what's on screen, with almost no setup (2026-11-21)

Imad: "It has to just work on what's on screen ... no much config needed."

- The main way in is **screen sharing**. Open the app once, tap **Start**, confirm the system's screen broadcast sheet. From then on, in any chat app, new messages show up translated in the island. No Shortcut to build, no Action button to assign, no Photos permission.
- Translating is automatic (2026-11-21, Imad: "make it translate automatically without tapping"). While screen sharing is on, each new message from them pops up translated in the island. iOS doesn't let the screen broadcast extension update a Live Activity and suspends the app in the background, so the app keeps itself running by playing silence (`App/AutoTranslate.swift`) and checks the screen every 1.5 s. App Review would reject that; it's fine for this experiment, and the clean version is a server sending APNs updates. **Translate** on the island stays, to read the screen again on demand.
- The on-device reader is the default and needs nothing. The Claude reader stays an option for people who paste an API key.
- The screenshot Shortcut and the clipboard Shortcut stay as extras for people who want the Action button.
