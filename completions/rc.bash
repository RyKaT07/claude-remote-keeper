# bash completion for rc (claude-remote-keeper)
# Installed to ~/.local/share/bash-completion/completions/rc by install.sh.
_rc_complete() {
  local cur subcmds desired names IFS
  cur="${COMP_WORDS[COMP_CWORD]}"
  subcmds="up pick down ls attach sync reconcile help"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    down|attach|a)
      # complete with registered session names (spaces escaped)
      desired="${CLAUDE_RC_DESIRED:-$HOME/.config/claude-rc/desired}"
      names="$(awk -F'|' '$1!="" && $1 !~ /^#/ {print $1}' "$desired" 2>/dev/null)"
      IFS=$'\n'
      COMPREPLY=( $(compgen -W "$names" -- "$cur") )
      COMPREPLY=( "${COMPREPLY[@]// /\\ }" )
      ;;
    up)
      COMPREPLY=( $(compgen -W "--new" -- "$cur") )
      ;;
  esac
}
complete -F _rc_complete rc
