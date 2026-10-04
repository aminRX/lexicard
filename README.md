# Lexicard

A KOReader plugin for learning English while you read. Hold a word, tap **Lexicard** in the dictionary popup, and Google Gemini writes a vocabulary card for that word *in the sense it has in your book*. Save it and keep reading: the card goes to your Anki deck in the background, with a recording of the word and a picture that shows what it means. Anki's sync then takes it to your phone.

https://github.com/user-attachments/assets/1b348b2b-cc68-4b45-adc9-8850c332711b

The cards are written for native Spanish speakers (B1–B2) by default. Hold "gave" in *"…she finally gave it up."* and you get one card:

```
FRONT   give up   /ˌɡɪv ˈʌp/ · phrasal verb   ▶ audio

BACK    [picture: before → after]
        He gave up coffee.
        dejar / abandonar
        to stop doing something that you did regularly

        HOW TO USE IT
        give up + something   I gave up coffee a month ago.
        give up + -ing        My dad gave up smoking last year.

        From your book: “…she finally gave it up.”
```

## What's on a card

One English card per word:

- **Front:** the word, its IPA and part of speech, and its audio.
- **Back:**
  - **A picture that teaches the word**, like a picture dictionary. A thing is drawn big. Stopping or changing is drawn as before → after. Qualities and adjectives are drawn as a contrast. Ways of moving use dotted paths. A short caption gives the sentence the picture shows.
  - **The Spanish equivalents**, and **a short English definition**.
  - **How to use it:** 2–3 common sentence patterns, each with an everyday example.
  - **A warning**, only when there is a real trap for Spanish speakers (false friends, wrong prepositions, calques, English pairs that share one Spanish word).
  - **The sentence from your book**, small, at the bottom.

Examples and pictures come from everyday life (home, work, food, friends), never from the book's world. The book sentence is only used to pick the right meaning.

Gemini writes the card and code checks it:

- Pronunciation comes from the [CMU Pronouncing Dictionary](https://github.com/cmusphinx/cmudict) in American style, with phrasal-verb stress (/ˌɡɪv ˈʌp/). Gemini's IPA is used only for words the dictionary lacks, and only if it looks valid.
- Warnings are kept only when they are real traps. A table of common false friends and confusable pairs fills in one Gemini missed.
- Spanish equivalents are de-duplicated, and look-alikes and vulgar words are dropped.
- If the definition uses the word itself, or an example copies the book, Lexicard asks the backup model once.

Gemini spots whole expressions from a single held word (phrasal verbs, idioms), picks the sense used in your sentence, and flags names and typos instead of making cards for them.

## Requirements

- A Kindle (or other device) running KOReader 2026.07 or later.
- Anki desktop with an up-to-date [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on, on a computer on the same Wi-Fi as the reader.
- A free Gemini API key from <https://aistudio.google.com/apikey>.
- For pictures (optional, free): a Cloudflare account. Open the [Workers AI page](https://dash.cloudflare.com/?to=/:account/ai/workers-ai), choose **Use REST API**, then **Create a Workers AI API Token** (it needs Workers AI Read and Edit, nothing else). Copy the token and the **Account ID**. The free allowance covers about 95 pictures a day.

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
| `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN` | Turn pictures on (see Requirements) |
| `IMAGES` | `on` (default) or `off` |
| `IMAGE_MODEL` | Default `@cf/black-forest-labs/flux-2-klein-4b` |
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

Optional, from a clone of this repository: `python3 scripts/anki-deck-preset.py` gives the deck its own options preset. Other decks are untouched.

### Upgrading to v0.3

The first card you save after upgrading adds fields to the "Lexicard" note type (`Usage`, `Image`, `Caption`) and switches it to one English card. Cards you already have keep their content and history. If you had the old Spanish→English cards, they stay, but new words don't get one.

Optional, from a clone of this repository, with Anki open: `luajit scripts/upgrade-v0.3.lua` deletes the old Spanish→English cards and gives your existing words usage patterns and a picture. Try `--dry-run` first.

Either way, Anki treats the change as structural and asks for a **one-time full sync**. On the computer press **Sync** and choose **Upload to AnkiWeb**; on your phone choose **Download from AnkiWeb**. Sync your phone *before* upgrading so no reviews are lost.

## Use

- Hold a word → **Lexicard** → wait for the preview → **Save** (or **Regenerate** / **Cancel**).
- Save returns to your book at once. The audio and picture are made while you read, and a short notice appears when the card is in Anki.
- If Anki can't be reached, the card's text waits on the device and is sent automatically the next time Anki can be reached. Audio and pictures are never stored on the reader: they are made at the moment the card is sent.
- **Tools → Lexicard** has: *Send waiting cards*, *Test connections*, *Update note type in Anki* and *About*.

If you customized the dictionary popup's buttons before installing, enable **Lexicard** under *Customize buttons*.

## Privacy

For each card, Lexicard sends Gemini the held word, its sentence, and the book's title and author. When the card is sent, Gemini gets the word again to make the audio. With pictures on, Cloudflare gets one English description of an everyday scene, never the book text. Nothing else leaves the device, and nothing heavy stays on it. Gemini's free tier may use prompts to improve Google's products. Your keys stay in `.env`, which is never committed.

## Development

```bash
git config core.hooksPath scripts/hooks     # blocks commits that contain keys
luajit spec/runner.lua                      # all tests (no dependencies besides LuaJIT)
luajit scripts/try-card.lua gave "She finally ⟦gave⟧ it up." "Book — Author" --image   # one card + picture, saved in eval/out/
EVAL_LABEL=mine EVAL_DELAY=5 luajit scripts/eval-prompt.lua   # scored run over eval/cases.lua (eval/out/)
scripts/deploy.sh --eject                   # copy to a USB-mounted Kindle
scripts/check-secrets.sh                    # scan git history before publishing
```

The designs, implementation plans and evaluation results are in `docs/superpowers/`.

## License

MIT. Pronunciations come from the CMU Pronouncing Dictionary; see `lexicard.koplugin/data/CMUDICT-LICENSE`.
