# wat — natural language → shell command on your zsh prompt line.
# https://github.com/Max-Levitskiy/wat  ·  MIT
# Engines: apfel (on-device Apple Intelligence) and claude (Claude Code CLI).
#   ?? <intent>    suggest a command via apfel, push onto the prompt line (never auto-runs)
#   ?  <intent>    same, via Claude
#   ?! <feedback>  regenerate the last suggestion with a correction (same engine)
#   ?e [command]   explain a command (default: the last suggestion; same engine)
(( $+commands[apfel] || $+commands[claude] )) || return 0

typeset -g WAT_CLAUDE_MODEL="${WAT_CLAUDE_MODEL:-haiku}"
typeset -g WAT_CLAUDE_EFFORT="${WAT_CLAUDE_EFFORT:-low}"
typeset -g _WAT_LAST_Q='' _WAT_LAST_A='' _WAT_LAST_ENGINE=''
typeset -g _WAT_DEFAULT_ENGINE=claude
(( $+commands[apfel] )) && _WAT_DEFAULT_ENGINE=apfel
typeset -g _WAT_EXPLAIN_SYS='You explain shell commands for macOS zsh in 1-2 short plain sentences. No markdown.'

# _wat_suggest_sys <engine>
# The ~3B on-device model does best with a short prompt; Claude gets the machine and directory too.
_wat_suggest_sys() {
  if [[ "$1" == apfel ]]; then
    print -r -- 'You translate natural language into a single zsh command for macOS. Output ONLY the command, no explanation, no markdown, no backticks.'
    return
  fi
  print -r -- "Translate the request into one shell command for zsh on macOS ($(uname -m), BSD userland, Homebrew installed). Current directory: $PWD.
Output the command only, on one line: no explanation, no markdown, no code fences, no leading \$.
Chain with && or | when needed. Use the most common, safe tool for the job.
Put <placeholders> only for values the request does not give.
If no command fits, output a single line starting with # that says why."
}

# _wat_call <engine> <system-prompt> <user-prompt> <attempt>
_wat_call() {
  local engine="$1" sys="$2" prompt="$3" attempt="$4" temp=0
  case "$engine" in
    apfel)
      (( attempt > 1 )) && temp=0.7
      apfel -q --no-color --temperature $temp --max-tokens 120 -s "$sys" -- "$prompt" 2>/dev/null ;;
    claude)
      # No tools, MCP servers, settings/hooks/plugins, skills or saved session: text in, text out.
      # stderr stays visible so login and network errors reach the user.
      claude -p --model "$WAT_CLAUDE_MODEL" --effort "$WAT_CLAUDE_EFFORT" --system-prompt "$sys" \
        --tools "" --strict-mcp-config --setting-sources "" \
        --disable-slash-commands --no-session-persistence -- "$prompt" ;;
  esac
}

# _wat_run <engine> <system-prompt> <user-prompt> [line|text]
# apfel gets 3 attempts (retries at temperature 0.7); claude gets 1, its failures are not random.
# line mode (default): print first non-empty cleaned line. text mode: all cleaned lines.
_wat_run() {
  local engine="$1" sys="$2" prompt="$3" mode="${4:-line}"
  local attempt attempts=1 rc raw result
  [[ "$engine" == apfel ]] && attempts=3
  for (( attempt = 1; attempt <= attempts; attempt++ )); do
    raw="$(_wat_call "$engine" "$sys" "$prompt" $attempt)"
    rc=$?
    result=''
    if (( rc == 0 )) && [[ -n "$raw" ]]; then
      if [[ "$mode" == line ]]; then
        result="$(print -r -- "$raw" | grep -v '^ *```' | sed -e 's/`//g' \
          -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -m1 .)"
      else
        result="$(print -r -- "$raw" | grep -v '^ *```' | sed -e 's/^[[:space:]]*//' \
          -e 's/[[:space:]]*$//' | grep .)"
      fi
    fi
    if [[ -n "$result" ]]; then
      print -r -- "$result"
      return 0
    fi
    (( attempt < attempts )) && print -u2 "$engine: bad result, retrying ($((attempt + 1))/$attempts)…"
  done
  print -u2 "$engine: no usable result after $attempts attempt$( (( attempts > 1 )) && print s)"
  return 1
}

# _wat_suggest <engine> <intent...>
_wat_suggest() {
  local engine="$1"; shift
  local name='??'; [[ "$engine" == claude ]] && name='?'
  (( $# )) || { print -u2 "usage: $name <what you want to do>"; return 1 }
  local q="$*" cmd
  cmd="$(_wat_run "$engine" "$(_wat_suggest_sys "$engine")" "$q")" || return 1
  _WAT_LAST_Q="$q"
  _WAT_LAST_A="$cmd"
  _WAT_LAST_ENGINE="$engine"
  print -z -- "$cmd"
}

_wat_retry() {
  (( $# )) || { print -u2 'usage: ?! <feedback about the last suggestion>'; return 1 }
  [[ -n "$_WAT_LAST_A" ]] || { print -u2 '?!: nothing to retry — run ?? or ? first'; return 1 }
  local cmd
  cmd="$(_wat_run "$_WAT_LAST_ENGINE" "$(_wat_suggest_sys "$_WAT_LAST_ENGINE")" "For the task \"$_WAT_LAST_Q\" you suggested: $_WAT_LAST_A
Feedback: $*
Reply with the corrected command only.")" || return 1
  _WAT_LAST_A="$cmd"
  print -z -- "$cmd"
}

_wat_explain() {
  local target="$*"
  [[ -n "$target" ]] || target="$_WAT_LAST_A"
  [[ -n "$target" ]] || { print -u2 'usage: ?e <command>   (or run ?? or ? first)'; return 1 }
  _wat_run "${_WAT_LAST_ENGINE:-$_WAT_DEFAULT_ENGINE}" "$_WAT_EXPLAIN_SYS" "Explain this command: $target" text
}

(( $+commands[apfel] )) && alias -- '??'='noglob _wat_suggest apfel'
(( $+commands[claude] )) && alias -- '?'='noglob _wat_suggest claude'
alias -- '?!'='noglob _wat_retry'
alias -- '?e'='noglob _wat_explain'
