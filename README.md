# wat

Natural language → shell command, right on your zsh prompt line. Two engines:

- `??` runs 100% on-device via Apple Intelligence (the [apfel](https://apfel.franzai.com)
  CLI). No API keys, no network, no telemetry.
- `?` asks Claude through the [Claude Code](https://claude.com/claude-code) CLI. It is
  smarter and sees your current directory, but it goes over the network.

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

Open a new terminal and try `?? list files`. Each engine's commands are defined
only when its CLI is installed: `brew install apfel` for `??`, Claude Code
(logged in) for `?`.

<details>
<summary>Install with a zsh plugin manager instead</summary>

`wat.plugin.zsh` follows the standard plugin convention, so any manager works —
e.g. `zinit light Max-Levitskiy/wat` or clone into `$ZSH_CUSTOM/plugins/wat`
and add `wat` to your oh-my-zsh `plugins=(...)`. Install the engine separately:
`brew install apfel`.
</details>

## Requirements

- zsh, Homebrew
- For `??`: Apple Silicon Mac with Apple Intelligence enabled (macOS 15.1+)
- For `?`: the `claude` CLI, logged in

## Usage

| Command | What it does |
|---|---|
| `?? <intent>` | Suggests one zsh command via apfel, pushed onto your prompt line |
| `? <intent>` | Same, via Claude |
| `?! <feedback>` | Regenerates the last suggestion with your correction, on the same engine |
| `?e [command]` | Explains a command (no argument: explains the last suggestion) |

If apfel returns garbage, wat retries up to 3 times (you'll see
`retrying (N/3)…`) before giving up.

Claude runs with every tool, MCP server, setting, hook, plugin and skill turned
off and no saved session, so it can only reply with text; it cannot run anything
itself. Pick the model and effort with `WAT_CLAUDE_MODEL` (default `haiku`) and
`WAT_CLAUDE_EFFORT` (default `low`), set before the plugin is sourced.

## Honest limitations

- The on-device model is small (~3B). It gets things wrong more often than Claude — **always read
  the command before pressing Enter.** That's why nothing auto-executes.
- Quote sentences containing `'` or `!` (the shell parses them first):
  `?? "don't delete anything"`.
- `?` sends your request and current directory path to Anthropic.
- English prompts work best.

## License

MIT © Max Levitskiy
