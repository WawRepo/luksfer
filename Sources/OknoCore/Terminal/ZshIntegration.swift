import Foundation

/// Okno's zsh startup files. Okno points `ZDOTDIR` at a folder holding them, and passes the
/// user's own folder in `OKNO_USER_ZDOTDIR` (their `ZDOTDIR`, or `$HOME`).
///
/// Each file loads the user's file of the same name first, so the user's config, prompt and
/// PATH stay as they are. `.zshrc` then adds hooks that report to Okno:
/// - OSC 7 with the percent-encoded folder, before every prompt (`precmd`);
/// - private OSC 6973 `prompt` when the line editor starts on an empty line with nothing typed
///   ahead, `prompt-typed` when it starts with text, `exec` when a command starts.
///
/// The `prompt` mark comes from the line editor's `line-init` hook (zsh 5.3+), not `precmd`:
/// `precmd` runs before the prompt is drawn, so text Okno types then is echoed twice.
/// At the end `.zshrc` hands `ZDOTDIR` back, so `.zlogin`, `.zlogout` and child shells use the
/// user's own files.
public enum ZshIntegration {
    /// The private OSC code of Okno's prompt marks.
    public static let markCode = 6973

    /// File name → contents.
    public static func files() -> [String: String] {
        [".zshenv": header + loadUserFile(".zshenv"),
         ".zprofile": header + loadUserFile(".zprofile"),
         ".zshrc": header + zshrc]
    }

    private static let header = """
    # Okno shell integration. Okno writes this file; edits are lost.
    # It loads your own file of the same name first.

    """

    /// Sources the user's file with ZDOTDIR set to their folder, keeps any change their file makes
    /// to ZDOTDIR (a .zshenv may move it), then points ZDOTDIR back here for zsh's next file.
    private static func loadUserFile(_ name: String) -> String {
        """
        if [[ -z "${__okno_zdotdir-}" ]]; then __okno_zdotdir="$ZDOTDIR"; fi
        ZDOTDIR="${OKNO_USER_ZDOTDIR:-$HOME}"
        if [[ -r "$ZDOTDIR/\(name)" ]]; then builtin source "$ZDOTDIR/\(name)"; fi
        OKNO_USER_ZDOTDIR="${ZDOTDIR:-$HOME}"
        ZDOTDIR="$__okno_zdotdir"

        """
    }

    private static let zshrc = #"""
    ZDOTDIR="${OKNO_USER_ZDOTDIR:-$HOME}"
    # /etc/zshrc put HISTFILE in Okno's folder; point it back at the user's.
    if [[ "${HISTFILE-}" == "${__okno_zdotdir-}/.zsh_history" ]]; then HISTFILE="$ZDOTDIR/.zsh_history"; fi
    if [[ -r "$ZDOTDIR/.zshrc" ]]; then builtin source "$ZDOTDIR/.zshrc"; fi

    # Writes straight to the terminal, past any redirect of stdout.
    __okno_emit() { builtin printf '%s' "$1" >|"${TTY:-/dev/tty}" 2>/dev/null }

    # OSC 7: the folder as a file URL, each byte outside [A-Za-z0-9/._~-] percent-encoded.
    __okno_osc7() {
      emulate -L zsh -o extended_glob
      local LC_ALL=C
      __okno_emit $'\e]7;file://'"$HOST${PWD//(#m)[^A-Za-z0-9\/._~-]/%${(l:2::0:)$(( [##16] #MATCH ))}}"$'\a'
    }

    # Line editor start: "prompt" on an empty main prompt with nothing typed ahead.
    __okno_line_init() {
      emulate -L zsh
      if [[ "$CONTEXT" == start && -z "$BUFFER" ]] && (( PENDING == 0 )); then
        __okno_emit $'\e]6973;prompt\a'
      else
        __okno_emit $'\e]6973;prompt-typed\a'
      fi
    }

    __okno_precmd() { __okno_osc7 }
    __okno_preexec() { __okno_emit $'\e]6973;exec\a' }
    __okno_prompt_fallback() { __okno_emit $'\e]6973;prompt\a' }
    # Okno types " builtin cd -- '<folder>'" to follow the active pane; keep it out of history.
    __okno_addhistory() { [[ "$1" != ' builtin cd -- '* ]] }

    __okno_install() {
      emulate -L zsh
      autoload -Uz add-zsh-hook is-at-least
      add-zsh-hook precmd __okno_precmd
      add-zsh-hook preexec __okno_preexec
      add-zsh-hook zshaddhistory __okno_addhistory
      if is-at-least 5.3; then
        autoload -Uz add-zle-hook-widget
        add-zle-hook-widget line-init __okno_line_init
      else
        add-zsh-hook precmd __okno_prompt_fallback
      fi
    }
    __okno_install
    unfunction __okno_install

    # Hand ZDOTDIR back so .zlogin, .zlogout and child shells use the user's own files.
    if [[ "$ZDOTDIR" == "$HOME" ]]; then
      unset ZDOTDIR
    elif [[ -z "${OKNO_ZDOTDIR_EXPORTED-}" ]]; then
      typeset +x ZDOTDIR
    fi
    unset OKNO_USER_ZDOTDIR OKNO_ZDOTDIR_EXPORTED __okno_zdotdir

    """#
}
