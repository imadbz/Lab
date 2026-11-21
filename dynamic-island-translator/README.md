# Dynamic Island Translator

An experiment to find out **how much a chat translator can do from the Dynamic Island** — how much text fits, what's interactive, and what iOS won't let you do.

It's a small iOS app plus a Live Activity widget. You translate a message (typed, pasted, or from the clipboard via a Shortcut) and the result appears in the island.

> **Status:** written without a Mac, so it hasn't been compiled yet. Expect the first build to need a small fix or two. Paste any Xcode errors back to Claude.

## Run it (Mac)

You need Xcode 16 or newer (26 recommended) and [Homebrew](https://brew.sh).

```bash
cd dynamic-island-translator
./run.sh          # installs XcodeGen if missing, builds, launches in an iPhone Pro simulator
./run.sh --open   # just generate + open the Xcode project (use this for a real iPhone)
```

**On a real iPhone** (needed for real translation and haptics):

1. Run `./run.sh --open`.
2. In Xcode, select the **IslandTranslator** target and the **IslandTranslatorWidget** target. On each, open *Signing & Capabilities* and pick your team (a free Apple ID works).
3. If Xcode complains the bundle ID is taken, change `dev.lab` in `project.yml` to something of yours and run `./run.sh --open` again.
4. Plug in your iPhone (14 Pro or newer) and press Run.

## What's inside

| Piece | File | What it explores |
|---|---|---|
| Live Activity UI | `Widget/TranslatorLiveActivity.swift` | Compact, minimal, expanded and Lock Screen layouts |
| Island buttons | `Shared/IslandIntents.swift` | **Copy**, **Flip** and **End** work without opening the app. **Reply** deep-links into the app |
| Activity control | `App/LiveActivityManager.swift` | Start, update, *alert* update (pops the island open), end |
| Translation | `App/LabModel.swift`, `App/Translators.swift` | Apple's on-device Translation framework, plus a mock phrasebook for the Simulator |
| Clipboard Shortcut | `App/IslandTranslatorApp.swift` | "Translate Clipboard" App Shortcut. Assign it to the Action button or Back Tap |
| Fit Lab | `App/Views.swift` | Push sample texts of any length or script; tweak the layout live; see the 4 KB payload budget |

## Experiments to run

Write down what you see. That's the point of this folder.

1. **Demo conversation.** Translate tab › *Run demo conversation* › swipe to Home within 3 s. A 6-message Spanish chat plays over ~30 s. Watch the compact view, the unread badge, and the alert "pop" on each incoming message.
2. **How much fits?** Fit Lab › push each sample › long-press the island. Find the character count where:
   - 3 lines stop fitting
   - shrink-to-fit becomes unreadable
   - Japanese, Arabic and German break differently from English
3. **Compact snippet.** Fit Lab › Compact style *Snippet*. How many characters of translation survive next to the camera?
4. **Buttons.** In the expanded island, tap *Copy*, then paste into Messages. Does it work without the app opening? Try *Flip* and *End* too.
5. **Clipboard flow.** On a device: Settings › Action Button › Shortcut › *Translate Clipboard*. Copy a foreign message in WhatsApp, press the Action button, and see how fast you get back to the chat.
6. **Minimal mode.** Start a timer in the Clock app as well. Your island should collapse to a single flag.
7. **Lock Screen.** Lock the phone. The same activity shows as a banner with working buttons.

## What we know about the island

| | |
|---|---|
| **Compact** | Two slots, one each side of the camera, roughly 40–50 pt each. Room for an icon, a flag, a badge or ~6–10 characters |
| **Minimal** | One small circle, used when another app's activity is also running |
| **Expanded** | About 370 × 160 pt. Room for ~3–4 lines of text plus a row of buttons |
| **Interactive** | Buttons and toggles only (App Intents, iOS 17+). **No text input, no keyboard** |
| **Updates** | From the app, or from a server via APNs push. Content state is capped at 4 KB. Updates are rate-limited unless you opt into frequent updates (this app does) |
| **Lifetime** | Up to 8 h active, then up to 4 h more on the Lock Screen |
| **Your own app** | The island hides your activity while your app is in the foreground |
| **Privacy wall** | An app **cannot read other apps' chats**. Incoming text has to come from you: clipboard, share sheet, screenshot OCR or a keyboard |
| **Competition** | iOS 26 has built-in Live Translation in Messages, FaceTime and Phone. To stand out, cover WhatsApp, Telegram, Instagram and others, and add things like tone or slang help |

## Next ideas

- **Keyboard extension:** type in your language and the keyboard inserts the translation into any chat app. This is the outgoing half of the product.
- **Push updates via APNs:** a server (or the keyboard) sends the translation, and the island updates without the app running.
- **Screenshot → OCR → translate:** a Shortcut that translates the last screenshot of a chat.
- **Speak button:** read the translation aloud for in-person conversations.
