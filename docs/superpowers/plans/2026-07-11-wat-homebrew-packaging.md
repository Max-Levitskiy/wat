# wat Homebrew Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the apfel zsh helpers as **wat**, installable by anyone via `brew install max-levitskiy/tap/wat`, and migrate Max's own setup to the brew-installed copy.

**Architecture:** Two public GitHub repos: `Max-Levitskiy/wat` (the plugin file + README + MIT license, released as tag `v0.1.0`) and `Max-Levitskiy/homebrew-tap` (`Formula/wat.rb` consuming the release tarball, `depends_on "apfel"`). Then the dotfiles repo drops its private copy and sources the brew path.

**Tech Stack:** zsh, Homebrew formula (Ruby), gh CLI, chezmoi.

**Spec:** `docs/superpowers/specs/2026-07-11-wat-homebrew-packaging-design.md`

## Global Constraints

- Install command must be exactly: `brew install max-levitskiy/tap/wat`.
- Plugin file name: `wat.plugin.zsh` (zsh plugin-manager convention). NO functional changes to its logic for v0.1.0 — header comment change only.
- Formula: `depends_on "apfel"`, `depends_on :macos`, installs to `#{prefix}/share/wat/wat.plugin.zsh`, caveats use `#{HOMEBREW_PREFIX}` (literal path at install time — never `$(brew --prefix)`).
- License: MIT, copyright Max Levitskiy.
- GitHub pushes and repo creation are pre-authorized by the user for exactly these two public repos: `Max-Levitskiy/wat`, `Max-Levitskiy/homebrew-tap`.
- Local repo paths: `~/git/wat` (exists, spec committed), `~/git/homebrew-tap` (create).
- The canonical source being packaged: `/Users/max/.local/share/chezmoi/dot_zsh_apfel.zsh`.
- Dotfiles repo has pre-existing unrelated unstaged changes — in Task 5, `git add` only the files named there.

---

### Task 1: Product repo content — `wat.plugin.zsh`, LICENSE, README

**Files:**
- Create: `~/git/wat/wat.plugin.zsh` (copy of `/Users/max/.local/share/chezmoi/dot_zsh_apfel.zsh` with new header)
- Create: `~/git/wat/LICENSE`
- Create: `~/git/wat/README.md`
- Test: `/private/tmp/claude-501/-Users-max/a1c6de3d-1fbf-41cd-8d10-439da9934181/scratchpad/test_wat.zsh` (throwaway; not committed)

**Interfaces:**
- Consumes: `/Users/max/.local/share/chezmoi/dot_zsh_apfel.zsh` (functions `_apfel_run`/`_apfel_suggest`/`_apfel_retry`/`_apfel_explain`, aliases `??`/`?!`/`?e`, guard on missing apfel).
- Produces: `~/git/wat/wat.plugin.zsh` — the file Task 3's formula installs and Task 5 sources from the brew prefix. Repo content that Task 2 tags as `v0.1.0`.

- [ ] **Step 1: Write the failing test script**

Write to `/private/tmp/claude-501/-Users-max/a1c6de3d-1fbf-41cd-8d10-439da9934181/scratchpad/test_wat.zsh` (identical to the suite that validated the original file, retargeted):

```zsh
#!/bin/zsh
# Tests for wat.plugin.zsh using a stub apfel. Run: zsh test_wat.zsh
set -u
SRC=${1:-/Users/max/git/wat/wat.plugin.zsh}
STUBDIR=$(mktemp -d)
typeset -g fail=0

t() { # t <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    print "ok:   $1"
  else
    print "FAIL: $1 — expected [$2], got [$3]"
    fail=1
  fi
}

cat > "$STUBDIR/apfel" <<'EOF'
#!/bin/zsh
case "${APFEL_STUB_MODE:-ok}" in
  ok)     print -r -- "ls -la" ;;
  fenced) print -r -- '```bash'; print -r -- '  `ls -la`  '; print -r -- '```' ;;
  multi)  print -r -- ""; print -r -- "line one."; print -r -- "line two." ;;
  empty)  ;;
  err)    exit 1 ;;
  flaky)
    n=$(cat "$APFEL_STUB_COUNT" 2>/dev/null || echo 0); n=$((n+1))
    echo $n > "$APFEL_STUB_COUNT"
    (( n >= 3 )) && print -r -- "ls" || exit 1 ;;
esac
EOF
chmod +x "$STUBDIR/apfel"
path=("$STUBDIR" $path)

guard=$(zsh -fc "path=(/usr/bin /bin); source $SRC; whence _apfel_suggest" 2>&1)
t "no-op guard without apfel" "" "$guard"

source "$SRC"

t "clean passthrough"      "ls -la" "$(_apfel_run sys prompt)"
t "strips fences/backticks/space" "ls -la" "$(APFEL_STUB_MODE=fenced _apfel_run sys prompt)"
t "line mode: first non-empty line" "line one." "$(APFEL_STUB_MODE=multi _apfel_run sys prompt)"
t "text mode: keeps all lines" "line one.
line two." "$(APFEL_STUB_MODE=multi _apfel_run sys prompt text)"

out=$( { APFEL_STUB_MODE=empty _apfel_run sys prompt; } 2>&1 ); rc=$?
t "empty → rc 1" "1" "$rc"
t "empty → two retry notices + final error" \
"apfel: bad result, retrying (2/3)…
apfel: bad result, retrying (3/3)…
apfel: no usable result after 3 attempts" "$out"

export APFEL_STUB_COUNT="$STUBDIR/count"
out=$( { APFEL_STUB_MODE=flaky _apfel_run sys prompt; } 2>&1 ); rc=$?
t "flaky → succeeds on 3rd attempt (rc 0)" "0" "$rc"
t "flaky → retries visible, result last" \
"apfel: bad result, retrying (2/3)…
apfel: bad result, retrying (3/3)…
ls" "$out"
unset APFEL_STUB_COUNT

_apfel_suggest "list files" >/dev/null
t "?? stores last question" "list files" "$_APFEL_LAST_Q"
t "?? stores last answer"   "ls -la"     "$_APFEL_LAST_A"

_apfel_retry "no hidden files" >/dev/null
t "?! updates last answer" "ls -la" "$_APFEL_LAST_A"

t "?e explains given command" "ls -la" "$(_apfel_explain 'tar -xzf x')"

out=$( { _apfel_suggest; } 2>&1 ); rc=$?
t "?? without args → rc 1" "1" "$rc"
t "?? without args → usage" "usage: ?? <what you want to do>" "$out"

out=$( { _APFEL_LAST_A='' _apfel_retry fix; } 2>&1 ); rc=$?
t "?! without prior ?? → rc 1" "1" "$rc"

t "?? alias" "noglob _apfel_suggest" "${aliases[??]-}"
t "?! alias" "noglob _apfel_retry"   "${aliases[?!]-}"
t "?e alias" "noglob _apfel_explain" "${aliases[?e]-}"

rm -rf "$STUBDIR"
(( fail )) && { print "\nFAILED"; exit 1 }
print "\nALL PASS"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zsh /private/tmp/claude-501/-Users-max/a1c6de3d-1fbf-41cd-8d10-439da9934181/scratchpad/test_wat.zsh`
Expected: FAIL — `source` errors, `/Users/max/git/wat/wat.plugin.zsh` does not exist.

- [ ] **Step 3: Create `wat.plugin.zsh` from the canonical source**

```bash
cp /Users/max/.local/share/chezmoi/dot_zsh_apfel.zsh /Users/max/git/wat/wat.plugin.zsh
```

Then replace ONLY the header comment block. The file currently starts with:

```zsh
# apfel shell helpers — natural language → shell command via local Apple Intelligence.
#   ?? <intent>    suggest a command, push onto the prompt line (never auto-runs)
#   ?! <feedback>  regenerate the last suggestion with a correction
#   ?e [command]   explain a command (default: the last suggestion)
# Spec: docs/superpowers/specs/2026-07-08-apfel-shell-helpers-design.md
command -v apfel >/dev/null 2>&1 || return 0
```

Replace those first 6 lines with:

```zsh
# wat — natural language → shell command, on-device via Apple Intelligence (apfel).
# https://github.com/Max-Levitskiy/wat  ·  MIT
#   ?? <intent>    suggest a command, push onto the prompt line (never auto-runs)
#   ?! <feedback>  regenerate the last suggestion with a correction
#   ?e [command]   explain a command (default: the last suggestion)
command -v apfel >/dev/null 2>&1 || return 0
```

Everything below the header stays byte-identical (verify: `diff <(tail -n +7 /Users/max/.local/share/chezmoi/dot_zsh_apfel.zsh) <(tail -n +7 /Users/max/git/wat/wat.plugin.zsh)` → no output).

- [ ] **Step 4: Run test to verify it passes**

Run: `zsh /private/tmp/claude-501/-Users-max/a1c6de3d-1fbf-41cd-8d10-439da9934181/scratchpad/test_wat.zsh`
Expected: 19 `ok:` lines, final `ALL PASS`, exit 0.

- [ ] **Step 5: Write LICENSE**

Write `~/git/wat/LICENSE`:

```text
MIT License

Copyright (c) 2026 Max Levitskiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 6: Write README.md**

Write `~/git/wat/README.md`:

````markdown
# wat

Natural language → shell command, right on your zsh prompt line. 100% on-device
via Apple Intelligence (the [apfel](https://apfel.franzai.com) CLI). No API keys,
no network, no telemetry.

```
$ ?? kill whatever is on port 3000
$ kill -9 $(lsof -ti :3000)▌        ← lands on your prompt line, edit or Enter
$ ?! don't use -9
$ kill $(lsof -ti :3000)▌
$ ?e
kill sends SIGTERM to the PIDs that lsof reports listening on port 3000.
```

Nothing ever auto-executes — suggestions are pushed onto your editable
command line and run only when **you** press Enter.

## Install

```sh
brew install max-levitskiy/tap/wat
```

Then add one line to your `~/.zshrc` (brew prints it too):

```sh
source /opt/homebrew/share/wat/wat.plugin.zsh
```

Open a new terminal and try `?? list files`.

<details>
<summary>Install with a zsh plugin manager instead</summary>

`wat.plugin.zsh` follows the standard plugin convention, so any manager works —
e.g. `zinit light Max-Levitskiy/wat` or clone into `$ZSH_CUSTOM/plugins/wat`
and add `wat` to your oh-my-zsh `plugins=(...)`. Install the engine separately:
`brew install apfel`.
</details>

## Requirements

- Apple Silicon Mac with Apple Intelligence enabled (macOS 15.1+)
- zsh, Homebrew

## Usage

| Command | What it does |
|---|---|
| `?? <intent>` | Suggests one zsh command, pushed onto your prompt line |
| `?! <feedback>` | Regenerates the last suggestion with your correction |
| `?e [command]` | Explains a command (no argument: explains the last suggestion) |

If the model returns garbage, wat retries up to 3 times (you'll see
`retrying (N/3)…`) before giving up.

## Honest limitations

- The on-device model is small (~3B). It gets things wrong — **always read
  the command before pressing Enter.** That's why nothing auto-executes.
- Quote sentences containing `'` or `!` (the shell parses them first):
  `?? "don't delete anything"`.
- English prompts work best.

## License

MIT © Max Levitskiy
````

- [ ] **Step 7: Commit**

```bash
cd ~/git/wat
git add wat.plugin.zsh LICENSE README.md
git commit -m "feat: wat v0.1.0 — apfel-powered ??, ?!, ?e zsh helpers"
```

---

### Task 2: Publish `Max-Levitskiy/wat` and tag v0.1.0

**Files:**
- No file changes — GitHub publication of `~/git/wat` (must contain Task 1's commit).

**Interfaces:**
- Consumes: `~/git/wat` repo with `wat.plugin.zsh`, LICENSE, README committed.
- Produces: public repo `github.com/Max-Levitskiy/wat`; tag `v0.1.0`; release tarball URL `https://github.com/Max-Levitskiy/wat/archive/refs/tags/v0.1.0.tar.gz` and its sha256 — Task 3's formula needs both.

- [ ] **Step 1: Create the public repo and push**

```bash
cd ~/git/wat
git branch -M main
gh repo create Max-Levitskiy/wat --public --source . --push \
  --description "Natural language → zsh command on your prompt line, on-device via Apple Intelligence"
```

Expected: repo created, `main` pushed. Verify: `gh repo view Max-Levitskiy/wat --json url -q .url` → `https://github.com/Max-Levitskiy/wat`.

- [ ] **Step 2: Tag and push v0.1.0**

```bash
cd ~/git/wat
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 3: Compute the release tarball sha256**

```bash
curl -sL https://github.com/Max-Levitskiy/wat/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
```

Expected: a 64-hex-char digest. Record it — Task 3 pins it in the formula. If curl returns an empty/tiny file (<1 KB), the tag hasn't propagated yet; wait ~30 s and retry.

---

### Task 3: Tap repo with `Formula/wat.rb`, publish

**Files:**
- Create: `~/git/homebrew-tap/Formula/wat.rb`
- Create: `~/git/homebrew-tap/README.md`

**Interfaces:**
- Consumes: v0.1.0 tarball URL + sha256 from Task 2.
- Produces: public repo `github.com/Max-Levitskiy/homebrew-tap` making `brew install max-levitskiy/tap/wat` resolve — Task 4 installs from it.

- [ ] **Step 1: Create the tap repo skeleton**

```bash
mkdir -p ~/git/homebrew-tap/Formula
cd ~/git/homebrew-tap
git init -b main
```

- [ ] **Step 2: Write the formula**

Write `~/git/homebrew-tap/Formula/wat.rb`, replacing `SHA256_FROM_TASK_2` with the digest recorded in Task 2 Step 3 (the only permitted substitution):

```ruby
class Wat < Formula
  desc "Natural language -> zsh command on your prompt line, via Apple Intelligence"
  homepage "https://github.com/Max-Levitskiy/wat"
  url "https://github.com/Max-Levitskiy/wat/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "SHA256_FROM_TASK_2"
  license "MIT"

  depends_on "apfel"
  depends_on :macos

  def install
    (share/"wat").install "wat.plugin.zsh"
  end

  def caveats
    <<~EOS
      Add to your ~/.zshrc:
        source #{HOMEBREW_PREFIX}/share/wat/wat.plugin.zsh
      Then open a new terminal and try:  ?? list files
    EOS
  end

  test do
    assert_predicate share/"wat/wat.plugin.zsh", :exist?
    system "zsh", "-fc", "source #{share}/wat/wat.plugin.zsh"
  end
end
```

- [ ] **Step 3: Write the tap README**

Write `~/git/homebrew-tap/README.md`:

```markdown
# homebrew-tap

Personal Homebrew tap.

| Formula | Description |
|---|---|
| [`wat`](https://github.com/Max-Levitskiy/wat) | Natural language → zsh command on your prompt line, on-device via Apple Intelligence |

```sh
brew install max-levitskiy/tap/wat
```
```

- [ ] **Step 4: Style-check the formula**

```bash
brew style ~/git/homebrew-tap/Formula/wat.rb
```

Expected: no offenses. Fix any reported style issues before committing.

- [ ] **Step 5: Commit and publish**

```bash
cd ~/git/homebrew-tap
git add Formula/wat.rb README.md
git commit -m "feat: add wat 0.1.0 formula"
gh repo create Max-Levitskiy/homebrew-tap --public --source . --push \
  --description "Personal Homebrew tap"
```

Expected: repo created and pushed. Verify: `gh repo view Max-Levitskiy/homebrew-tap --json url -q .url`.

---

### Task 4: End-to-end install verification

**Files:**
- No file changes — verifies the published product.

**Interfaces:**
- Consumes: published tap + release from Tasks 2–3.
- Produces: verified `brew install max-levitskiy/tap/wat`; `/opt/homebrew/share/wat/wat.plugin.zsh` on disk — the exact path Task 5 sources.

- [ ] **Step 1: Install from the tap**

```bash
brew install max-levitskiy/tap/wat
```

Expected: tap auto-added, formula installs (apfel dependency already satisfied on this machine), caveats block prints the `source /opt/homebrew/share/wat/wat.plugin.zsh` line.

- [ ] **Step 2: Run brew's formula test + audit**

```bash
brew test wat
brew audit --strict max-levitskiy/tap/wat
```

Expected: `brew test` exits 0. `brew audit --strict` reports no errors (style-level notes acceptable if brew style passed in Task 3; errors are not).

- [ ] **Step 3: Verify the installed file behaves**

```bash
zsh -fc 'source /opt/homebrew/share/wat/wat.plugin.zsh; whence _apfel_suggest && print GUARD_OK'
zsh /private/tmp/claude-501/-Users-max/a1c6de3d-1fbf-41cd-8d10-439da9934181/scratchpad/test_wat.zsh /opt/homebrew/share/wat/wat.plugin.zsh
```

Expected: first command prints `_apfel_suggest` then `GUARD_OK`; second run of the stub suite against the INSTALLED file: 19 ok, `ALL PASS`.

---

### Task 5: Migrate Max's dotfiles to the brew-installed wat

**Files:**
- Modify: `/Users/max/.local/share/chezmoi/private_dot_zshrc:183` (the `~/.zsh_apfel.zsh` source line)
- Delete: `/Users/max/.local/share/chezmoi/dot_zsh_apfel.zsh`
- Modify: `/Users/max/.local/share/chezmoi/Brewfile` (add tap + wat under `# --- taps ---` and the formulae section)

**Interfaces:**
- Consumes: verified install at `/opt/homebrew/share/wat/wat.plugin.zsh` (Task 4).
- Produces: dotfiles sourcing only the brew copy; `~/.zsh_apfel.zsh` gone; Brewfile provisioning wat (and transitively apfel) on both Macs.

- [ ] **Step 1: Update the zshrc source line**

In `/Users/max/.local/share/chezmoi/private_dot_zshrc`, replace:

```zsh
[[ -f ~/.zsh_apfel.zsh ]] && source ~/.zsh_apfel.zsh
```

with:

```zsh
[[ -f /opt/homebrew/share/wat/wat.plugin.zsh ]] && source /opt/homebrew/share/wat/wat.plugin.zsh
```

- [ ] **Step 2: Remove the old managed file and its deployed copy**

```bash
chezmoi forget --force ~/.zsh_apfel.zsh   # removes dot_zsh_apfel.zsh from the source dir
rm ~/.zsh_apfel.zsh                       # removes the deployed copy
chezmoi apply ~/.zshrc
```

Verify: `grep -c zsh_apfel ~/.zshrc` → 0; `grep -c wat.plugin ~/.zshrc` → 1; `ls ~/.zsh_apfel.zsh` → No such file.

- [ ] **Step 3: Add wat to the Brewfile**

In `/Users/max/.local/share/chezmoi/Brewfile`: under the `# --- taps ---` section add:

```ruby
tap "max-levitskiy/tap"
```

and in the formulae section (alphabetical placement among existing `brew` lines) add:

```ruby
brew "max-levitskiy/tap/wat"
```

- [ ] **Step 4: Verify a fresh interactive shell works end-to-end**

```bash
zsh -ic 'whence _apfel_suggest && print -r -- "${aliases[??]-missing}"'
```

Expected: prints `_apfel_suggest` and `noglob _apfel_suggest` (loaded via the brew path), no `command not found` noise.

- [ ] **Step 5: Commit and push dotfiles**

```bash
cd /Users/max/.local/share/chezmoi
git add private_dot_zshrc Brewfile
git rm --cached dot_zsh_apfel.zsh 2>/dev/null; git add -u dot_zsh_apfel.zsh 2>/dev/null
git status --short   # confirm ONLY: M private_dot_zshrc, M Brewfile, D dot_zsh_apfel.zsh
git commit -m "Migrate apfel helpers to brew-installed wat (max-levitskiy/tap/wat)"
git push origin main
```

Note: `chezmoi forget` already deleted the file from the working tree; the `git rm --cached`/`git add -u` pair just stages that deletion regardless of which state it's in. Do not stage the pre-existing unrelated changes (`.chezmoi.toml.tmpl`, `dot_npmrc.tmpl`, `dot_zshenv*`, `dot_terraformrc.tmpl`).
