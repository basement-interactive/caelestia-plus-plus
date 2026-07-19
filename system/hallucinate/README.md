# hallucinate — one-shot apps dreamed up live by AI

    hallucinate "basic calculator with weird font"

There is no real application behind the window. An LLM (Gemini) invents the
whole thing on the spot: it designs the UI, and then it *is* the backend.
Press `2`, `+`, `2`, `=` and the model — not any local code — decides what the
display now reads. Every click, keystroke, toggle and slider release is sent
back to the model, which returns the next state of the app. Close the window
and it's gone forever; nothing was ever saved, nothing was ever real.

```
hallucinate "basic calculator with weird font"
hallucinate "a mood ring that guesses my feelings"
hallucinate "number guessing game, 1 to 100"
hallucinate "a fake terminal that lies about everything"
hallucinate "unit converter designed by a caffeinated goblin"
```

## How it works

```
hallucinate "concept"
   -> Gemini dreams the initial UI as constrained JSON widgets  -> Tkinter renders it
   -> user clicks / types / toggles
        -> the current UI + live values + the event are sent back to Gemini
        -> Gemini returns the COMPLETE next UI (it did the "computation")
        -> the window updates in place
   -> repeat until closed; hidden state lives in a round-tripped `memory` field
```

The model may only use a small, well-behaved widget palette — `label`,
`button`, `entry`, `text`, `checkbox`, `slider` — laid out on a grid. A narrow
vocabulary means it can only assemble things that actually render, however
weird the concept gets. Bad colours or unknown font names never crash the
window; they fall back to a dark theme.

## Design notes

- **The AI is the backend.** No arithmetic, no game logic, no state machine
  runs locally. `current_ui` (including the values you've typed) plus a
  round-tripped `memory` string are the entire state the model gets each turn —
  enough for calculators, games with a secret, converters, etc.
- **Structured output.** Gemini is pinned to a JSON schema (`responseMimeType`
  + `responseSchema`) so replies are always valid widget specs, never prose or
  markdown. Thinking is disabled — left on, the model reasons *inside* the JSON
  and runs out of output before finishing the widgets.
- **Threading.** Model calls run on a worker thread; results cross back to the
  UI through a queue drained by a main-thread poller (Tk is single-threaded and
  crashes if touched off-thread). The title shows `· hallucinating…` while a
  turn is in flight.
- **Pure standard library** apart from the HTTP call: Tkinter for the UI,
  `urllib` for Gemini. No pip, no venv.

## Latency

Every interaction is a real model round-trip (~1–4s), because *everything* is
hallucinated — pressing a digit literally asks the AI what the display should
say next. That is the point, not a bug. Flash-class models keep it snappy
enough to be fun.

## API key

The key is never committed to this repo (secret scanning blocks that, rightly).
It is resolved at runtime, in order:

1. `--api-key <key>`
2. `$GEMINI_API_KEY`
3. `~/.config/caelestia/gemini.key` (one line; `chmod 600`)

Drop your Gemini key in the file once and the command just works:

```
install -m600 /dev/stdin ~/.config/caelestia/gemini.key <<<'YOUR_GEMINI_KEY'
```

## Config

- `HALLUCINATE_MODEL` — overrides the model (default `gemini-flash-lite-latest`).
  Lite is used on purpose: it honours `thinkingBudget: 0` so there is zero
  thinking latency (~2-3s/turn). The non-lite `gemini-flash-latest` is a
  thinking model that ignores the budget — it stalls for tens of seconds and
  returns truncated UIs (a calculator with no buttons). `gemini-2.5-flash` and
  friends are already 404 for new keys, so pinning a version is avoided.
- `hallucinate --dry-run "concept"` — print the initial UI spec as JSON and
  exit, no window (handy for debugging / headless checks).

## Install

Two steps (the installer and the system scan do both automatically):

```
sudo pacman -S --needed tk
ln -sf "$HOME/.config/quickshell/caelestia/system/hallucinate/hallucinate" ~/.local/bin/hallucinate
```
