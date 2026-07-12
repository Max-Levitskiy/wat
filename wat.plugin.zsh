# wat — natural language → shell command, on-device via Apple Intelligence (apfel).
# https://github.com/Max-Levitskiy/wat  ·  MIT
#   ?? <intent>    suggest a command, push onto the prompt line (never auto-runs)
#   ?! <feedback>  regenerate the last suggestion with a correction
#   ?e [command]   explain a command (default: the last suggestion)
command -v apfel >/dev/null 2>&1 || return 0

typeset -g _APFEL_LAST_Q='' _APFEL_LAST_A=''
typeset -g _APFEL_SUGGEST_SYS='You translate natural language into a single zsh command for macOS. Output ONLY the command, no explanation, no markdown, no backticks.'
typeset -g _APFEL_EXPLAIN_SYS='You explain shell commands for macOS zsh in 1-2 short plain sentences. No markdown.'

# _apfel_run <system-prompt> <user-prompt> [line|text]
# Calls apfel with retries (3 attempts; retries at temperature 0.7).
# line mode (default): print first non-empty cleaned line. text mode: all cleaned lines.
_apfel_run() {
  local sys="$1" prompt="$2" mode="${3:-line}"
  local attempt rc raw result temp
  for attempt in 1 2 3; do
    temp=0; (( attempt > 1 )) && temp=0.7
    raw="$(apfel -q --no-color --temperature $temp --max-tokens 120 -s "$sys" -- "$prompt" 2>/dev/null)"
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
    (( attempt < 3 )) && print -u2 "apfel: bad result, retrying ($((attempt + 1))/3)…"
  done
  print -u2 "apfel: no usable result after 3 attempts"
  return 1
}

_apfel_suggest() {
  (( $# )) || { print -u2 'usage: ?? <what you want to do>'; return 1 }
  local q="$*" cmd
  cmd="$(_apfel_run "$_APFEL_SUGGEST_SYS" "$q")" || return 1
  _APFEL_LAST_Q="$q"
  _APFEL_LAST_A="$cmd"
  print -z -- "$cmd"
}

_apfel_retry() {
  (( $# )) || { print -u2 'usage: ?! <feedback about the last suggestion>'; return 1 }
  [[ -n "$_APFEL_LAST_A" ]] || { print -u2 '?!: nothing to retry — run ?? first'; return 1 }
  local cmd
  cmd="$(_apfel_run "$_APFEL_SUGGEST_SYS" "For the task \"$_APFEL_LAST_Q\" you suggested: $_APFEL_LAST_A
Feedback: $*
Reply with the corrected command only.")" || return 1
  _APFEL_LAST_A="$cmd"
  print -z -- "$cmd"
}

_apfel_explain() {
  local target="$*"
  [[ -n "$target" ]] || target="$_APFEL_LAST_A"
  [[ -n "$target" ]] || { print -u2 'usage: ?e <command>   (or run ?? first)'; return 1 }
  _apfel_run "$_APFEL_EXPLAIN_SYS" "Explain this command: $target" text
}

alias -- '??'='noglob _apfel_suggest'
alias -- '?!'='noglob _apfel_retry'
alias -- '?e'='noglob _apfel_explain'
