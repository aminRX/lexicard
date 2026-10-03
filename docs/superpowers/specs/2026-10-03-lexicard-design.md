# Lexicard: design spec

Date: 2026-10-03 · Status: draft for review

## 1. Summary

Lexicard is a KOReader plugin for jailbroken Kindles. While reading, you hold a word, tap **Lexicard** in the dictionary popup, and Gemini writes a vocabulary card made for a Spanish-speaking English learner. After a quick preview, the note goes to the Anki deck *Reading vocabulary* through AnkiConnect, and Anki's own sync carries it to every other device, including an iPhone running AnkiMobile.

It replaces `anki.koplugin` on the author's Kindle.

## 2. Goals and non-goals

**Goals**

- One tap from a held word to a finished card, with a preview before saving.
- Cards that are correct for the sense used in the book, short enough for one phone screen, and aimed at native Spanish speakers at B1–B2 level. A single held word must still yield the whole phrasal verb or idiom ("gave" in "gave it up" → *give up*).
- Two cards per word, always: recognition (English → meaning) and production (Spanish → English).
- No card is ever lost: if Anki can't be reached, notes wait on the Kindle and are sent automatically later.
- Secrets live only in `.env`. The repository is public and contains no keys or personal data.

**Non-goals (v1)**

- Importing lookups from Amazon's built-in reader (`vocab.db`). Only cards the user chooses.
- Talking to AnkiWeb directly. AnkiWeb's terms forbid third-party clients and point to AnkiConnect instead.
- Sending cards straight to an iPhone. AnkiMobile can't run AnkiConnect; the iPhone receives cards through sync.
- Audio or image files. Pronunciation audio comes from Anki's built-in text-to-speech on the review device.
- Editing card fields on the Kindle. Details get fixed in Anki.
- Making cards without internet. Gemini needs it.

## 3. Decisions

| Decision | Choice | Why |
|---|---|---|
| Delivery | AnkiConnect over Wi-Fi; a list of URLs tried in order (today: the Mac) | The only route AnkiWeb's terms allow; the Mac's Anki is already signed in to AnkiWeb |
| When Anki is off | Persistent outbox on the Kindle, flushed automatically | The Mac is often asleep while the user reads |
| Getting cards to the phone | Call AnkiConnect `sync` after delivering | The iPhone gets new cards seconds after delivery |
| Model | `gemini-3.5-flash-lite` (pinned), falling back to `gemini-3.6-flash` with low thinking on 429, 5xx, timeout or an invalid reply | Flash-Lite is fast and has a generous free quota (about 500 requests a day, community-reported). 3.8 Flash is often overloaded and reportedly allows about 20 a day. Pinned IDs because the `-latest` aliases move to new models. |
| Output format | Structured JSON (`responseMimeType` + `responseJsonSchema`), validated again in code | Tested against the user's key on 2026-10-03 |
| Sampling | No temperature, topP or topK | Deprecated for Gemini 3.x; low values can make the model loop |
| Pronunciation | Replace the model's IPA with CMUdict when every word of the headword has exactly one entry | Language models get IPA exactly right only about half the time (PhonologyBench) |
| TLS | Verify certificates against KOReader's bundled `data/ca-bundle.crt` | KOReader's LuaSec skips verification by default |
| Name | Lexicard (`lexicard.koplugin`) | Not tied to one AI vendor |
| License | MIT; CMUdict data keeps its BSD-2-Clause notice | Permissive and compatible with both |

## 4. User experience

### 4.1 Making a card

1. Hold a word in KOReader. The dictionary popup shows a **Lexicard** button.
2. Lexicard captures the held word, its sentence, and the book's title and author, then closes the popup.
3. If Wi-Fi is off, KOReader's standard prompt offers to turn it on.
4. "Writing card…" stays on screen while Gemini works. Tapping it cancels.
5. A preview shows the card, for example:

   ```
   give up  /ɡɪv ʌp/ · give sth up · phrasal verb · B1
   rendirse / darse por vencido
   to stop trying to do something
   Example: He never gives up, even when he loses.
   From the book: "…she finally gave it up after three tries."
   Collocations: give up hope · give up smoking
   ```

   Buttons: **Cancel** · **Regenerate** · **Save**.
6. **Save** shows "Added to Reading vocabulary ✓", or "Saved on Kindle. It will be sent when Anki is reachable (3 waiting)".
7. If the headword is already in the deck, Lexicard asks "Already in your deck. Add anyway?" (**Add anyway** / **Cancel**).

### 4.2 Menu (Tools → Lexicard)

- **Send waiting cards (N)**, enabled when the outbox isn't empty.
- **Test connections**: checks Gemini with one tiny request and each AnkiConnect URL, and reports the result.
- **Update note type in Anki**: pushes the plugin's current card templates and styling to Anki.
- **About**: version, config file location, current deck and models. Never shows secrets.

### 4.3 Errors, in plain language

- Missing `GEMINI_API_KEY`: "Lexicard needs a Gemini API key in lexicard.koplugin/.env."
- Both models busy or out of quota: "Gemini is busy or out of free quota. Try again in a minute."
- Not a learnable English word (a name, a typo, another language): "“Vin” looks like a name. No card created."
- Certificate check failed: "Secure connection failed. Is the Kindle's date and time correct?"

The plugin's interface is in English. The explanatory card fields aimed at Spanish speakers (warning, pronunciation tip) are in Spanish.

## 5. Architecture

```
Kindle (KOReader + Lexicard) ──HTTPS──► Gemini API
        │
        └─HTTP on the home network, with API key─► AnkiConnect ─► Anki desktop (Mac) ─► AnkiWeb ─► iPhone (AnkiMobile)
          (outbox on the Kindle while no AnkiConnect URL answers)
```

Every network call runs in a KOReader `Trapper` subprocess, so the e-ink screen never freezes and the user can cancel. The subprocess returns only plain strings and numbers; JSON is decoded in the main process.

### 5.1 Modules

All module names start with `lexicard_`, because KOReader plugins share one `package.loaded` table.

| File | Purpose | Depends on |
|---|---|---|
| `_meta.lua` | Plugin name, description and version | none |
| `main.lua` | Registers the dictionary button and the menu; runs the flow | the modules below |
| `lexicard_config.lua` | Reads `.env` from the plugin folder, applies defaults, validates | file I/O |
| `lexicard_context.lua` | Gets the word, sentence and book from the popup; cuts sentences safely for accented text | KOReader (thin), pure helpers |
| `lexicard_prompt.lua` | System instruction, few-shot examples, user message, JSON schema | none (pure) |
| `lexicard_gemini.lua` | Builds requests, applies the fallback policy, parses and validates replies | injected transport |
| `lexicard_ipa.lua` | Binary search in `data/cmudict-ipa.tsv` | file I/O |
| `lexicard_note.lua` | Turns a validated reply into Anki fields and tags; sanitizes HTML; builds the cloze sentence | none (pure) |
| `lexicard_notetype.lua` | The Anki note type: fields, two card templates, CSS | none (data) |
| `lexicard_anki.lua` | AnkiConnect client: ensure deck and note type, add, sync, classify errors | injected transport |
| `lexicard_outbox.lua` | Persistent queue of unsent notes and the flush algorithm | file I/O, injected sender |
| `lexicard_http.lua` | HTTP(S) POST with timeouts and certificate checks (device only) | LuaSocket, LuaSec |
| `lexicard_ui.lua` | Preview dialog, progress and info messages | KOReader widgets |

The pure modules don't touch KOReader, so they run under plain LuaJIT on a Mac for testing.

### 5.2 Configuration (`.env`)

The file lives at `lexicard.koplugin/.env` on the Kindle, copied there by the deploy script. Git ignores it; `.env.example` with placeholders is committed.

```
GEMINI_API_KEY=
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_FALLBACK_MODEL=gemini-3.6-flash
ANKICONNECT_URLS=http://192.168.x.x:8765   # comma-separated, tried in order
ANKICONNECT_API_KEY=
ANKI_DECK=Reading vocabulary
ANKI_NOTE_TYPE=Lexicard
LEARNER_NATIVE_LANGUAGE=Spanish (Mexico)
LEARNER_LEVEL=B1-B2
TLS_VERIFY=true
```

Format: `KEY=value` lines, `#` comments, optional single or double quotes, surrounding whitespace trimmed. Unknown keys are ignored. `TLS_VERIFY=false` exists only as a last resort for a Kindle with a broken clock.

## 6. Gemini

### 6.1 Request

`POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` with the `x-goog-api-key` header.

- `systemInstruction`: role, learner profile, step-by-step rules, length limits, and three complete examples (a split phrasal verb, a false friend, a word with several meanings).
- `contents`: one user turn with tagged inputs. The held occurrence is marked:

  ```
  <book>Example Book — Example Author</book>
  <sentence>After three tries, she finally ⟦gave⟧ it up.</sentence>
  <word>gave</word>
  ```

- `generationConfig`: `responseMimeType: "application/json"` and `responseJsonSchema` (6.2). The fallback model also gets `thinkingConfig: {thinkingLevel: "low"}`.
- Timeouts: 10 seconds per socket operation, 30 seconds total per model.

### 6.2 Output schema

Keys are ordered so the model reasons in the right sequence: what was written, then the full expression, then its dictionary form, then the meaning.

| Key | Type | Rule |
|---|---|---|
| `status` | `ok` / `proper_noun` / `not_english` / `unclear` | Anything but `ok` stops with a message |
| `surface` | string | The held word as written |
| `expression_in_text` | string | The whole expression as written (`gave it up`) |
| `headword` | string | Dictionary form (`give up`) |
| `pos` | enum | noun, verb, adjective, adverb, phrasal verb, idiom, preposition, conjunction, other |
| `pattern` | string | Usage pattern with sb/sth (`give sth up`) |
| `register` | enum | neutral, informal, formal, literary, slang, old-fashioned, offensive |
| `cefr` | enum | A1 to C2 |
| `definition` | string | Simple English, at most 15 words, never uses the headword |
| `spanish` | array, 1 to 3 | Natural Mexican-Spanish equivalents for this sense |
| `context` | string | The author's own words, at most 25, shortened with "…", expression wrapped in `<b>` |
| `example` | string | A new everyday sentence, at most 15 words, expression in `<b>`, a different situation from the book |
| `collocations` | array, 0 to 3 | Only common, real word partners; empty when unsure |
| `warning` | string | False friend or typical Spanish-speaker mistake, in Spanish, at most 20 words; empty if none |
| `pron_tip` | string | Pronunciation trap for Spanish speakers, in Spanish, at most 15 words; empty if none |
| `ipa` | string | General American, between slashes |

### 6.3 Validation in code

- Required and non-empty: `headword`, `definition`, `spanish`, `example`, `ipa`. `context` may be empty when the book gives none.
- HTML: only `<b>` and `</b>` survive in `context` and `example`; everything else is escaped. All other fields are plain text and escaped.
- If `example` has no `<b>`, Lexicard bolds the first case-insensitive match of the headword, if any.
- The cloze sentence is `example` with its `<b>…</b>` span replaced by `_____`.
- A reply that isn't valid JSON or fails validation counts as a failure: Lexicard retries once with the fallback model, then shows an error.

### 6.4 Pronunciation from CMUdict

- A build step on the Mac converts CMUdict's ARPAbet entries into General American IPA, placing stress marks at the start of the stressed syllable (maximal-onset rule). It writes a sorted `word<TAB>ipa1|ipa2` file of about 3.5 MB to `lexicard.koplugin/data/`.
- On the Kindle, `lexicard_ipa.lua` binary-searches that file instead of loading it into memory.
- If every word of the headword has exactly one entry, the card uses the dictionary IPA, words joined by spaces, with no stress mark on one-syllable words. Otherwise (heteronyms like *record*, unknown words, names) it keeps Gemini's IPA.

## 7. The Anki note type "Lexicard"

Fields, in order (the first is the one Anki checks for duplicates):

`Headword, POS, Pattern, IPA, Spanish, Definition, Context, Example, Cloze, Collocations, Warning, PronTip, Book, CEFR`

`Pattern` holds the usage pattern plus the register when it isn't neutral (`give sth up · informal`).

**Card 1, Recognize (English → meaning)**

- Front: the book sentence with the expression in bold, the headword, and `{{tts en_US:Headword}}`.
- Back: the front, then IPA · pattern · part of speech, the Spanish equivalents, the definition, the warning (highlighted, if any), the example, collocations and the pronunciation tip behind `{{hint:…}}`, and the book in small type.

**Card 2, Produce (Spanish → English)**

- Front: the Spanish equivalents, the definition, the part of speech, and the cloze sentence.
- Back: the headword, IPA, `{{tts en_US:Headword}}`, the example, the book sentence and the warning.

Both cards are always created. Optional fields sit inside `{{#Field}}…{{/Field}}`, so empty ones disappear. The CSS supports Anki's night mode and fits one phone screen.

Tags: `lexicard`, `book::<title_slug>`, `cefr::<level>`.

On the first successful connection, Lexicard creates the deck and the note type if they're missing (AnkiConnect `createDeck` and `createModel`, desktop only). **Update note type in Anki** pushes later template and CSS changes (`updateModelTemplates`, `updateModelStyling`).

## 8. Delivery and the outbox

- Every AnkiConnect request is `{action, version: 6, key: ANKICONNECT_API_KEY, params}`.
- Reachability: `version` with a 3-second timeout, trying each URL in order. The first that answers is used.
- Adding: `addNote` with `allowDuplicate: false`, `duplicateScope: "deck"` and `duplicateScopeOptions: {deckName, checkChildren: false, checkAllModels: false}`. **Add anyway** resends with `allowDuplicate: true`.
- After one or more successful adds: `sync`, best effort, errors ignored.
- Error classes: unreachable (network error or timeout) goes to the outbox; duplicate is reported to the user; anything else is shown and the note stays in the outbox.
- The outbox is `koreader/settings/lexicard_outbox.json`, a JSON array of `{id, created_at, note, attempts, last_error}`. It's written to a temporary file and then renamed, so a crash or flat battery can't corrupt it.
- Flushing goes oldest first and stops at the first "unreachable". Items that succeed, or turn out to be duplicates, are removed, and the user sees a summary such as "Sent 3 · 1 already in deck".
- Flushes happen after every successful save, when KOReader reports a network connection, and from the menu. The automatic flush on connection is silent unless it actually sends something.

## 9. Security and privacy

- Secrets live only in `.env`, which git ignores. `.env.example` holds placeholders.
- A committed pre-commit hook (`scripts/hooks/pre-commit`, enabled through `core.hooksPath`) blocks commits that add `.env` or anything that looks like a Gemini key (`AIza…`, `AQ.…`) or a filled-in API key. The whole history is scanned again before every push to the public repository.
- No personal data in the repository: no IP addresses, emails, or book text beyond short self-written examples. Prompt-evaluation output is git-ignored.
- Commits carry the author's name with their GitHub no-reply address, keeping the personal email private.
- AnkiConnect on the Mac gets an `apiKey`, and `"*"` comes out of `webCorsOriginList`. Today any website open on the Mac could control Anki. KOReader's requests carry no Origin header, so they keep working. The key travels as plain HTTP on the home network.
- Gemini's free tier may use prompts to improve Google's products. Lexicard sends only the word, its sentence and the book's title and author.

## 10. Development workflow

- **Device access is by USB** (the user's choice). The test loop: deploy while the Kindle is mounted, eject it, restart KOReader, test on the Kindle with Wi-Fi on, and plug it back in to read the log if something fails. SSH (KOReader's built-in server) remains an option later, not a requirement.
- `scripts/deploy.sh` copies `lexicard.koplugin/` and `.env` to `/Volumes/Kindle/koreader/plugins/`, without macOS `._*` files.
- `scripts/logs.sh` prints the Lexicard lines from `/Volumes/Kindle/koreader/crash.log`.
- `scripts/build-ipa-dict.lua` regenerates `data/cmudict-ipa.tsv` from CMUdict.
- `scripts/try-card.lua` runs the real prompt against Gemini from the Mac and prints the card. With `--send`, it adds the card to a scratch deck through the Mac's AnkiConnect.

## 11. Testing

- **Unit tests** (busted on LuaJIT, on the Mac): `.env` parsing, sentence cutting, request shape, reply validation and sanitizing, note mapping and cloze, IPA lookup and ARPAbet→IPA conversion, AnkiConnect error classification with a fake transport, and outbox flushing with a fake sender and a simulated crash.
- **Prompt evaluation:** 12 self-written inputs (split phrasal verb, false friends, a word with several meanings, an idiom, an irregular past tense, a literary word, slang, a name, a typo, and so on) run through both models. Results are reviewed by hand before settling the defaults. Output is git-ignored.
- **End to end on the Mac:** `try-card --send` creates a card in a scratch deck, checks it with `notesInfo`, then deletes it.
- **On the Kindle:** hold a word in an EPUB, check that the card appears in *Reading vocabulary* and then on the iPhone after sync. Offline path: close Anki, save two cards, reopen Anki, turn Wi-Fi on, and check both arrive.

## 12. Rollout and replacing anki.koplugin

1. Harden AnkiConnect (API key, CORS). This needs an Anki restart.
2. Deploy Lexicard next to the old plugin and run the on-device tests.
3. Back up `plugins/anki.koplugin` and its settings files (`anki_profiles.lua`, `ankiconnect.lua`, `anki.koplugin_notes.json` and their `.old` copies) to the Mac, outside the repository.
4. Recreate the old plugin's one unsent note ("ruthlessness") as a Lexicard card.
5. Delete the old plugin and its settings files from the Kindle.
6. Publish the repository on GitHub after a final secret scan.

## 13. Repository layout

```
lexicard/
├── lexicard.koplugin/        # what gets copied to the Kindle
│   ├── _meta.lua, main.lua, lexicard_*.lua
│   └── data/cmudict-ipa.tsv, data/CMUDICT-LICENSE
├── spec/                     # busted tests
├── scripts/                  # deploy, logs, build-ipa-dict, try-card, hooks/
├── eval/                     # prompt-evaluation inputs (output git-ignored)
├── docs/superpowers/specs/   # this document
├── .env.example, .gitignore, README.md, LICENSE
```

## 14. Later (not in v1)

- An always-on machine running Anki and AnkiConnect, such as a home server, becomes one more entry in `ANKICONNECT_URLS`, so cards arrive even when the Mac is off.
- Listing the plugin in the KOReader AppStore (GitHub topic `koreader-plugin`).
