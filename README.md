# Lexicard

A KOReader plugin for learning English while you read. Hold a word, tap **Lexicard** in the dictionary popup, and Google Gemini writes a vocabulary card for that word *as it's used in your book*. After a quick preview, the card goes to your Anki deck through AnkiConnect, with a natural-sounding recording of the word, and Anki's sync takes it to your phone.

https://github.com/user-attachments/assets/1b348b2b-cc68-4b45-adc9-8850c332711b

The cards are written for native Spanish speakers (B1–B2) by default. Hold "gave" in *"…she finally gave it up."* and you get:

```
give up   /ˌɡɪv ˈʌp/
phrasal verb · give sth up

dejar / abandonar
to stop doing something that you did regularly

Example: I gave up coffee a month ago.
Book: …she finally gave it up.
Collocations: give up smoking · give up hope
```

## What's on a card

Each word becomes two Anki cards:

- **Recognize (English → meaning).** Front: the word and its audio, with the book sentence one tap away (shown directly for phrasal verbs and idioms, where the meaning depends on it). Back: Spanish equivalents, a short English definition, IPA · part of speech · pattern · register, a warning about real traps for Spanish speakers (✗ … → ✓ …), a pronunciation tip when there is a real trap, the book sentence and the book title.
- **Produce (Spanish → English).** Front: "Say it in English", the Spanish, the definition, the part of speech, and a new example with first-letter hints (*I g____ ____ coffee a month ago.*). Back: the word with its audio, IPA · pattern, the full example, collocations, warning and tip.

Gemini writes the card and code checks it:

- Pronunciation comes from the [CMU Pronouncing Dictionary](https://github.com/cmusphinx/cmudict) in American style, with phrasal-verb stress (/ˌɡɪv ˈʌp/); Gemini's IPA is used only for words the dictionary lacks, and only if it looks valid.
- Warnings are kept only when they are real Spanish-speaker traps (false friends, wrong prepositions, calques, English pairs that share one Spanish word, register). A table of common false friends and confusable pairs fills in a warning Gemini missed.
- Pronunciation tips must quote a sound from the IPA and never talk about spelling.
- Spanish equivalents are de-duplicated, and look-alikes and vulgar words are dropped.
- If the definition uses the word itself, or the example copies the book, Lexicard asks the backup model once.

Gemini spots whole expressions from a single held word (phrasal verbs, idioms), picks the sense used in your sentence, and flags names and typos instead of making cards for them.

## Requirements

- A Kindle (or other device) running KOReader 2026.07 or later.
- Anki desktop with an up-to-date [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on, on a computer on the same Wi-Fi as the reader.
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
| `GEMINI_THINKING` | Thinking level for the main model: `low` (recommended) or empty for the model default |
| `AUDIO` | `word` (default), `word+example` or `off` |
| `TTS_MODEL`, `TTS_VOICE` | Defaults `gemini-3.8-flash-lite-tts` and `Kore` |
| `LEARNER_NATIVE_LANGUAGE`, `LEARNER_LEVEL` | Defaults `Spanish (Mexico)` and `B1-B2` |
| `TLS_VERIFY` | `true` (default). Set `false` only if the device clock is broken |

### AnkiConnect

In Anki: **Tools → Add-ons → AnkiConnect → Config**.

1. Set `webBindAddress` to `0.0.0.0` so the reader can reach it over Wi-Fi.
2. Set `apiKey` to a long random string, and put the same string in `ANKICONNECT_API_KEY`.
3. Keep `webCorsOriginList` at `["http://localhost"]`. Avoid `"*"`: it lets any website you visit control Anki.
4. Restart Anki. Keep AnkiConnect up to date: old copies put new cards in the Default deck on recent Anki versions.

Lexicard creates the deck and the "Lexicard" note type the first time it connects.

Optional, from a clone of this repository: `python3 scripts/anki-deck-preset.py` gives the deck its own options preset that keeps a word's two cards off the same day (sibling burying) and shows the Recognize card first. Other decks are untouched.

### Upgrading from v0.1

The first card you save after upgrading adds three fields (`Register`, `ContextOpen`, `Audio`) to the "Lexicard" note type. Anki treats that as a structural change and asks for a **one-time full sync**: on the computer press **Sync** and choose **Upload to AnkiWeb**; on your phone choose **Download from AnkiWeb**. Sync your phone *before* upgrading so no reviews are lost. Lexicard tells you when Anki couldn't sync.

## Use

- Hold a word → **Lexicard** → wait for the preview → **Save** (or **Regenerate** / **Cancel**).
- If Anki can't be reached, the card is kept on the device and sent automatically the next time it can be. You can also send waiting cards by hand.
- **Tools → Lexicard** has: *Send waiting cards*, *Test connections*, *Update note type in Anki* and *About*.

If you customized the dictionary popup's buttons before installing, enable **Lexicard** under *Customize buttons*.

## Privacy

For each card, Lexicard sends Gemini the held word, its sentence, and the book's title and author; when you save, it sends the word again to generate the audio. Nothing else leaves the device. Gemini's free tier may use prompts to improve Google's products. Your keys stay in `.env`, which is never committed.

## Development

```bash
git config core.hooksPath scripts/hooks     # blocks commits that contain keys
luajit spec/runner.lua                      # all tests (no dependencies besides LuaJIT)
luajit scripts/try-card.lua gave "She finally ⟦gave⟧ it up." "Book — Author"   # one card from the Mac
EVAL_LABEL=mine EVAL_DELAY=5 luajit scripts/eval-prompt.lua   # scored run over eval/cases.lua (eval/out/)
scripts/deploy.sh --eject                   # copy to a USB-mounted Kindle
scripts/check-secrets.sh                    # scan git history before publishing
```

The designs, implementation plans and evaluation results are in `docs/superpowers/`.

## License

MIT. Pronunciations come from the CMU Pronouncing Dictionary; see `lexicard.koplugin/data/CMUDICT-LICENSE`.
