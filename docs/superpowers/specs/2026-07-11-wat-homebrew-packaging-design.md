# wat — packaging the apfel zsh helpers as a Homebrew product

**Date:** 2026-07-11
**Status:** Approved design, pending implementation

## Goal

Turn the personal `~/.zsh_apfel.zsh` helpers (`??`, `?!`, `?e`) into **wat**,
a shareable product installable with one command:

```
brew install max-levitskiy/tap/wat
```

plus one pasted line into `~/.zshrc` (Homebrew formulas cannot edit user
dotfiles; the caveats block prints the line).

## What wat is

A single zsh plugin file wrapping the `apfel` CLI (Apple Intelligence 3B
on-device model, available in homebrew-core):

- `?? <intent>` — natural language → one zsh command, pushed onto the
  editable prompt buffer via `print -z`; never auto-executed.
- `?! <feedback>` — regenerate the last suggestion with a correction
  (session-local memory of last question/answer).
- `?e [command]` — explain a command in 1–2 sentences (defaults to the
  last suggestion).
- 3-attempt retry on bad results (non-zero exit / empty after cleanup),
  retries at temperature 0.7, stderr `retrying (N/3)…` notices.
- Silent no-op when `apfel` is not on PATH.

The shipped file is the current `dot_zsh_apfel.zsh` from the dotfiles repo
(commit 3c0b742 lineage), renamed — no functional changes for v0.1.0.

## Architecture: two repos

### 1. `github.com/Max-Levitskiy/wat` (public) — the product

```
wat.plugin.zsh    # the plugin (renamed ~/.zsh_apfel.zsh, header updated:
                  # project name, repo URL, MIT notice; spec reference
                  # line removed — it pointed into the private dotfiles repo)
README.md         # what it is, demo, install (brew + plugin managers),
                  # requirements, usage, limitations
LICENSE           # MIT, Max Levitskiy
docs/superpowers/ # this spec + the implementation plan
```

`.plugin.zsh` naming keeps the repo directly usable by oh-my-zsh custom
plugins, zinit, antidote, etc. — documented in the README as the
alternative install path (apfel must then be installed separately).

Releases are git tags (`v0.1.0`). The formula consumes the GitHub release
tarball.

### 2. `github.com/Max-Levitskiy/homebrew-tap` (public) — the tap

```
Formula/wat.rb
README.md         # one paragraph: what this tap carries
```

Formula requirements:

- `depends_on "apfel"` — brew installs the model CLI automatically.
- `depends_on :macos`.
- `url` = `https://github.com/Max-Levitskiy/wat/archive/refs/tags/v0.1.0.tar.gz`
  with pinned `sha256`.
- Installs `wat.plugin.zsh` to `#{prefix}/share/wat/wat.plugin.zsh`
  (formula: `(share/"wat").install "wat.plugin.zsh"`).
- `caveats` prints the finish line with the prefix rendered literally at
  install time (`#{HOMEBREW_PREFIX}` in the formula — avoids a
  `$(brew --prefix)` subprocess on every shell startup):

  ```
  Add to your ~/.zshrc:
    source /opt/homebrew/share/wat/wat.plugin.zsh
  Then open a new terminal and try:  ?? list files
  ```

- `test do` block: asserts the installed file exists and sources cleanly
  in zsh (`system "zsh", "-fc", "source #{share}/wat/wat.plugin.zsh"` —
  must exit 0 whether or not apfel is present, thanks to the guard).

## README contents (product face)

- One-line pitch + short demo block (`?? kill whatever is on port 3000` →
  command appears on the prompt line).
- Requirements: Apple Silicon Mac, macOS with Apple Intelligence enabled,
  zsh, Homebrew.
- Install: brew (primary), plugin-manager/manual (secondary).
- Usage table for `??` / `?!` / `?e`.
- Honest limitations: 3B model gets things wrong — always review before
  Enter (nothing auto-executes); quote sentences containing `'` or `!`;
  English works best.
- MIT license badge/line.

## Migration of Max's own setup (dogfooding)

After publishing, in the dotfiles repo (`~/.local/share/chezmoi`):

1. `brew install max-levitskiy/tap/wat`.
2. Replace the `~/.zsh_apfel.zsh` source line in `private_dot_zshrc` with
   the brew-path line guarded the same way:
   `[[ -f /opt/homebrew/share/wat/wat.plugin.zsh ]] && source /opt/homebrew/share/wat/wat.plugin.zsh`.
3. Delete `dot_zsh_apfel.zsh` from chezmoi; `chezmoi apply` removes
   `~/.zsh_apfel.zsh`.
4. Add `wat` to the Brewfile so the second Mac gets it via brew bundle.

One source of truth: the public repo.

## Release flow (v0.1.0 and later)

1. Commit + tag `v0.1.0` in `wat`, push with tags.
2. `curl -L <tarball-url> | shasum -a 256` → pin sha in `Formula/wat.rb`.
3. Push tap. Verify from scratch: `brew install max-levitskiy/tap/wat`,
   `brew test wat`.
4. Later bumps: new tag, update formula `url`+`sha256`.

## Error handling / edge cases

- Machine without Apple Intelligence: apfel installs but inference fails →
  wat's existing retry/error path reports "no usable result"; README
  documents the requirement. No extra detection code in v0.1.0 (YAGNI).
- brew on Intel Macs: apfel formula's own requirements gate this; wat adds
  none beyond `depends_on :macos`.
- Double-sourcing (brew + plugin manager): harmless — aliases/functions
  are redefined identically.

## Out of scope (YAGNI)

- No configuration (env vars for prompts/tokens), no bash/fish support,
  no `wat` executable, no auto-editing of user zshrc, no homebrew-core
  submission for v0.1.0.

## Testing

1. Formula `test do` (file exists + sources cleanly).
2. Fresh-machine simulation: `brew uninstall wat; brew install
   max-levitskiy/tap/wat` end-to-end, then the manual `??`/`?!`/`?e`
   smoke checks in a new terminal.
3. Plugin-manager path: `zsh -fc 'source wat.plugin.zsh'` from a bare
   clone (guard keeps exit 0).
4. Existing scratchpad stub-test suite re-run against the renamed file
   before tagging.
