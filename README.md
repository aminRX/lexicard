# Lexicard

A KOReader plugin for learning English while you read. Hold a word, tap **Lexicard** in the dictionary popup, and Google Gemini writes a vocabulary card for that word *as it's used in your book*. After a quick preview, the card goes to your Anki deck through AnkiConnect, and Anki's sync takes it to your phone.

The cards are written for native Spanish speakers (B1–B2) by default. Hold "gave" in *"…she finally gave it up."* and you get:

```
give up   /ɡɪv ʌp/
phrasal verb · give sth up · B1

dejar / abandonar
to stop doing something you did regularly

Example: My dad gave up smoking when I was born.
Book: …she finally gave it up.
Collocations: give up smoking · give up hope
```

## What's on a card

Each word becomes two Anki cards:

- **Recognize:** the sentence from your book with the word in bold → meaning, Spanish equivalents, IPA, a new example, collocations, and a warning about false friends when there is one.
- **Produce:** the Spanish and the definition, plus an example with a blank → you recall the English word.

Gemini spots whole expressions from a single held word (phrasal verbs, idioms), picks the sense used in your sentence, and flags names and typos instead of making cards for them. Pronunciations are checked against the [CMU Pronouncing Dictionary](https://github.com/cmusphinx/cmudict). Audio comes from Anki's built-in text-to-speech on your review device.

## Requirements

- A Kindle (or other device) running KOReader 2026.07 or later.
- Anki desktop with the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on, on a computer on the same Wi-Fi as the reader.
- A free Gemini API key from <https://aistudio.google.com/apikey>.

## Install

1. Copy the `lexicard.koplugin` folder into `koreader/plugins/` on your device.
2. Copy `.env.example` to `lexicard.koplugin/.env` and fill it in (see below).
3. Restart KOReader.

### `.env`

| Key | Meaning |
|---|---|
| `GEMINI_API_KEY` | Your Gemini API key (required) |
| `ANKICONNECT_URLS` | Comma-separated AnkiConnect addresses, tried in order, e.g. `http://192.168.1.10:8765` (required) |
| `ANKICONNECT_API_KEY` | The `apiKey` set in AnkiConnect's config; leave empty if you didn't set one |
| `ANKI_DECK` | Target deck (default `Reading vocabulary`) |
| `ANKI_NOTE_TYPE` | Note type to create and use (default `Lexicard`) |
| `GEMINI_MODEL`, `GEMINI_FALLBACK_MODEL` | Defaults `gemini-3.5-flash-lite`, then `gemini-3.6-flash` |
| `LEARNER_NATIVE_LANGUAGE`, `LEARNER_LEVEL` | Defaults `Spanish (Mexico)` and `B1-B2` |
| `TLS_VERIFY` | `true` (default). Set `false` only if the device clock is broken |

### AnkiConnect

In Anki: **Tools → Add-ons → AnkiConnect → Config**.

1. Set `webBindAddress` to `0.0.0.0` so the reader can reach it over Wi-Fi.
2. Set `apiKey` to a long random string, and put the same string in `ANKICONNECT_API_KEY`.
3. Keep `webCorsOriginList` at `["http://localhost"]`. Avoid `"*"`: it lets any website you visit control Anki.
4. Restart Anki. Keep AnkiConnect up to date: old copies put new cards in the Default deck on recent Anki versions.

Lexicard creates the deck and the "Lexicard" note type the first time it connects.

## Use

- Hold a word → **Lexicard** → wait for the preview → **Save** (or **Regenerate** / **Cancel**).
- If Anki can't be reached, the card is kept on the device and sent automatically the next time it can be. You can also send waiting cards by hand.
- **Tools → Lexicard** has: *Send waiting cards*, *Test connections*, *Update note type in Anki* and *About*.

If you customized the dictionary popup's buttons before installing, enable **Lexicard** under *Customize buttons*.

## Privacy

For each card, Lexicard sends Gemini the held word, its sentence, and the book's title and author. Nothing else leaves the device. Gemini's free tier may use prompts to improve Google's products. Your keys stay in `.env`, which is never committed.

## Development

```bash
git config core.hooksPath scripts/hooks   # blocks commits that contain keys
luajit spec/runner.lua                    # all tests (no dependencies besides LuaJIT)
luajit scripts/try-card.lua gave "She finally ⟦gave⟧ it up." "Book — Author"   # one card from the Mac
luajit scripts/eval-prompt.lua            # run the prompt over eval/cases.lua (report in eval/out/)
scripts/deploy.sh --eject                 # copy to a USB-mounted Kindle
scripts/check-secrets.sh                  # scan git history before publishing
```

The design and the implementation plan are in `docs/superpowers/`.

## License

MIT. Pronunciations come from the CMU Pronouncing Dictionary; see `lexicard.koplugin/data/CMUDICT-LICENSE`.
