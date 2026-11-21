# Dynamic Island Translator

An experiment to find out **how much a chat translator can do from the Dynamic Island** — how much text fits, what's interactive, and what iOS won't let you do.

It's a small iOS app plus a Live Activity widget. iOS won't let an app read another app's chats, so **the input is a screenshot**: you take one inside WhatsApp (one press of the Action button), and the latest incoming message shows up translated in the island. With the AI reader you also get a tone note and replies you can copy with one tap.

> **Status (2026-11-21):** builds with no errors or warnings on Xcode 27.2 and runs in the iPhone 18 Pro simulator (iOS 27.2). Verified there: the 4 tabs, the demo conversation (compact island with flag and unread badge, alert pops it open), Fit Lab pushes, and the on-device screenshot reader (Vision OCR with the mock translation engine). **Not verified yet:** the Claude reader (no request sent), Apple Translation, haptics, the Action button and background Shortcut runs, all of which need a real iPhone or an API key.

### Simulator notes

- Xcode 27 has no Simulator.app, so `./run.sh` runs the simulator without a window. Drive it with `xcrun simctl` or Xcode's device window.
- The expanded island fits the header, one line of original text, **one** line of translation and the button row. With *Shrink text to fit* on, longer text shrinks onto that one line and then truncates: the 146-character *Long message* showed 63 characters, the 36-character *Japanese* sample 34. Letting the text wrap to *Max lines* pushes the buttons out of the island.
- *Use my latest screenshot* only finds images Photos tags as screenshots. A PNG added with `simctl addmedia` gets that tag only if it carries the XMP `exif:UserComment` "Screenshot" that real iPhone screenshots have (EXIF alone wasn't enough).

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
| Island buttons | `Shared/IslandIntents.swift` | **Copy**, **Flip**, **End** and **reply chips** work without opening the app. **Reply** deep-links into the app |
| Activity control | `App/LiveActivityManager.swift` | Start, update, *alert* update (pops the island open), end |
| **Screenshot readers** | `App/ScreenReading.swift` | On-device: Vision OCR, then them/me guessed from bubble margins, then translation |
| **Claude reader** | `App/ClaudeClient.swift` | One API call (structured output): whole chat translated, a tone/slang note, 2–3 suggested replies in their language |
| **Shortcut action** | `App/ScreenIntents.swift` | "Translate Screenshot". Chain it after "Take Screenshot" and put it on the Action button |
| Screen tab | `App/ScreenView.swift` | Pick or grab the latest screenshot, compare the two readers, see timing |
| Translation | `App/LabModel.swift`, `App/Translators.swift` | Engines: Apple on-device (works in the background on iOS 26+), Claude, or a mock phrasebook for the Simulator |
| Clipboard Shortcut | `App/IslandTranslatorApp.swift` | "Translate Clipboard" App Shortcut. Assign it to the Action button or Back Tap |
| Fit Lab | `App/Views.swift` | Push sample texts of any length or script; tweak the layout live; see the 4 KB payload budget |

## The screenshot flow

```
WhatsApp ── Action button ──▶ Shortcut: Take Screenshot ─▶ Translate Screenshot (runs in background)
                                                              │
                         ┌────────────────────────────────────┴───────────────────────┐
                 On-device OCR                                                  Claude AI reader
     Vision text → bubble side → Apple Translation                 image → structured JSON (Opus 5.5, effort low)
       free · offline · private · no replies                     translation + tone note + suggested replies
                         └────────────────────────────────────┬───────────────────────┘
                                                              ▼
                                Dynamic Island: 🇪🇸→🇬🇧 translation · 💡 note · [reply 1] [reply 2]
                                       tap a chip → reply (in Spanish) copied → paste in WhatsApp
```

**Set it up on the phone:**
1. Screen tab → paste your Anthropic API key (it's saved in the Keychain). Skip this to use on-device only.
2. In the Shortcuts app, create a shortcut: **Take Screenshot** → **Translate Screenshot** (pick the reader).
3. Assign it to Settings › Action Button, or Accessibility › Touch › Back Tap.
4. For on-device background translation, translate once in the app first so iOS downloads the language pair.

**Privacy and cost:** the Claude reader sends the screenshot to the Anthropic API, and the shortcut sends whatever is on screen. Use on-device mode for sensitive chats. Expect roughly 1–2¢ per screenshot with `claude-opus-5-5` at effort `low` (an estimate, not measured). Change `model` and `effort` in `App/ClaudeClient.swift`. Refusal fallbacks are on (`fallbacks: "default"`), so a false-positive safety decline gets retried on another model.

## Experiments to run

Write down what you see. That's the point of this folder.

0. **Screenshot readers, head to head.** Take 5 real chat screenshots (WhatsApp, iMessage, Instagram, a group chat, one with slang or emoji). In the Screen tab, run each through both readers and note:
   - Did on-device get the them/me sides right? Did it pick the right "latest" message?
   - How long did each take? (shown next to the result)
   - Were Claude's notes and suggested replies actually useful, or just noise?
   - Then run the Action-button shortcut from inside WhatsApp. Did the island update without the app opening? How many seconds from press to translation?

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
| **Privacy wall** | An app **cannot read other apps' chats**. Incoming text has to come from you: a screenshot (what this app uses), the clipboard, the share sheet or a keyboard |
| **Background work** | A Shortcut-triggered App Intent can update the island from the background. Developers report that *starting* a new activity from the background sometimes fails, so the first run may need the app open |
| **Competition** | iOS 26 has built-in Live Translation in Messages, FaceTime and Phone. To stand out, cover WhatsApp, Telegram, Instagram and others, and add things like tone or slang help |

## Next ideas

- **Keyboard extension:** type in your language and the keyboard inserts the translation into any chat app. This is the outgoing half of the product.
- **Push updates via APNs:** a server (or the keyboard) sends the translation, and the island updates without the app running.
- **Screen-recording / broadcast extension:** live OCR of the chat without taking screenshots. Heavier and more intrusive, but it's the only way to make translation continuous.
- **Reply in your language:** type in English in the island-launched reply screen, and Claude rewrites it in their language in the right register.
- **Speak button:** read the translation aloud for in-person conversations.
