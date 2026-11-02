import Foundation

/// Luksfer's zsh startup files. Luksfer points `ZDOTDIR` at a folder holding them, and passes the
/// user's own folder in `LUKSFER_USER_ZDOTDIR` (their `ZDOTDIR`, or `$HOME`).
///
/// Each file loads the user's file of the same name first, so the user's config, prompt and
/// PATH stay as they are. `.zshrc` then adds hooks that report to Luksfer with private OSC 6973
/// and the session key (`ShellReport`):
/// - `folder` and the folder as a percent-encoded file URL, before every prompt (`precmd`);
/// - `prompt` when the line editor starts on an empty line with nothing typed ahead,
///   `prompt-typed` when it starts with text, `exec` when a command starts.
///
/// The session key is random and new for each shell. `.zshenv` moves it from the environment to a
/// plain shell variable, so child programs never see it. Text a program prints (`cat` of a hostile
/// file, a remote host) cannot know it, so it cannot pass as a report.
///
/// The `prompt` mark comes from the line editor's `line-init` hook (zsh 5.3+), not `precmd`:
/// `precmd` runs before the prompt is drawn, so text Luksfer types then is echoed twice.
///
/// Follow moves the shell with a line editor widget, not a typed `cd` line: Luksfer sends
/// `followKeys(to:)`, the widget reads the folder, changes to it, runs the user's `chpwd` and
/// `precmd` hooks and redraws the prompt in place. Nothing shows on screen or in the history.
/// At the end `.zshrc` hands `ZDOTDIR` back, so `.zlogin`, `.zlogout` and child shells use the
/// user's own files.
public enum ZshIntegration {
    /// The private OSC code of the shell's reports.
    public static let markCode = 6973

    /// The environment variable that hands the session key to the shell.
    public static let sessionKeyVariable = "LUKSFER_SESSION_KEY"

    /// A new session key: 128 random bits in hex.
    public static func newSessionKey() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<2).map { _ in String(format: "%016llx", generator.next() as UInt64) }.joined()
    }

    /// The key sequence bound to the Follow widget. No keyboard sends it.
    public static let followKey = "\u{1B}[6973~"

    /// What Luksfer sends to move the shell to `path`: the Follow key, the path's UTF-8 bytes in
    /// lowercase hex, and ";". Hex keeps every byte of any path away from key bindings and quoting.
    public static func followKeys(to path: String) -> String {
        followKey + path.utf8.map { String(format: "%02x", $0) }.joined() + ";"
    }

    /// File name → contents.
    public static func files() -> [String: String] {
        [".zshenv": header + keepSessionKey + loadUserFile(".zshenv"),
         ".zprofile": header + loadUserFile(".zprofile"),
         ".zshrc": header + zshrc]
    }

    private static let header = """
    # Luksfer shell integration. Luksfer writes this file; edits are lost.
    # It loads your own file of the same name first.

    """

    /// First thing in the first file, so the user's startup files and their programs never see it.
    private static let keepSessionKey = """
    __luksfer_key="${\(sessionKeyVariable)-}"
    typeset +x __luksfer_key
    unset \(sessionKeyVariable)

    """

    /// Sources the user's file with ZDOTDIR set to their folder, keeps any change their file makes
    /// to ZDOTDIR (a .zshenv may move it), then points ZDOTDIR back here for zsh's next file.
    private static func loadUserFile(_ name: String) -> String {
        """
        if [[ -z "${__luksfer_zdotdir-}" ]]; then __luksfer_zdotdir="$ZDOTDIR"; fi
        ZDOTDIR="${LUKSFER_USER_ZDOTDIR:-$HOME}"
        if [[ -r "$ZDOTDIR/\(name)" ]]; then builtin source "$ZDOTDIR/\(name)"; fi
        LUKSFER_USER_ZDOTDIR="${ZDOTDIR:-$HOME}"
        ZDOTDIR="$__luksfer_zdotdir"

        """
    }

    private static let zshrc = #"""
    ZDOTDIR="${LUKSFER_USER_ZDOTDIR:-$HOME}"
    # /etc/zshrc put HISTFILE in Luksfer's folder; point it back at the user's.
    if [[ "${HISTFILE-}" == "${__luksfer_zdotdir-}/.zsh_history" ]]; then HISTFILE="$ZDOTDIR/.zsh_history"; fi
    if [[ -r "$ZDOTDIR/.zshrc" ]]; then builtin source "$ZDOTDIR/.zshrc"; fi

    # Writes straight to the terminal, past any redirect of stdout.
    __luksfer_emit() { builtin printf '%s' "$1" >|"${TTY:-/dev/tty}" 2>/dev/null }

    # A report to Luksfer: OSC 6973, the session key, the report.
    __luksfer_report() { __luksfer_emit $'\e]6973;'"${__luksfer_key-};$1"$'\a' }

    # The folder as a file URL, each byte outside [A-Za-z0-9/._~-] percent-encoded.
    __luksfer_report_folder() {
      emulate -L zsh -o extended_glob
      local LC_ALL=C
      __luksfer_report "folder;file://$HOST${PWD//(#m)[^A-Za-z0-9\/._~-]/%${(l:2::0:)$(( [##16] #MATCH ))}}"
    }

    # Line editor start: "prompt" on an empty main prompt with nothing typed ahead.
    __luksfer_line_init() {
      emulate -L zsh
      if [[ "$CONTEXT" == start && -z "$BUFFER" ]] && (( PENDING == 0 )); then
        __luksfer_report prompt
      else
        __luksfer_report prompt-typed
      fi
    }

    __luksfer_precmd() { __luksfer_report_folder }
    __luksfer_preexec() { __luksfer_report exec }
    __luksfer_prompt_fallback() { __luksfer_report prompt }
    # Keep typed " builtin cd -- '<folder>'" lines (the self-test types one) out of history.
    __luksfer_addhistory() { [[ "$1" != ' builtin cd -- '* ]] }

    # Follow: Luksfer sends ESC [6973~, the folder as hex bytes, then ";". REPLY = the folder.
    __luksfer_follow_read() {
      emulate -L zsh -o extended_glob
      local hex c
      while builtin read -rk 1 c && [[ "$c" != ';' ]] && (( ${#hex} < 8192 )); do hex+="$c"; done
      [[ "$hex" == ([0-9a-f][0-9a-f])## ]] || return 1
      builtin printf -v REPLY "${hex//(#b)(??)/\\x$match[1]}"
    }
    # The widget changes folder without a command line. It runs the hooks a cd at the prompt would
    # run, in the user's own options (so no emulate here), then redraws the prompt in place.
    __luksfer_follow() {
      local REPLY __luksfer_f
      if __luksfer_follow_read && builtin cd -q -- "$REPLY" 2>/dev/null; then
        for __luksfer_f in chpwd "${chpwd_functions[@]-}" precmd "${precmd_functions[@]-}"; do
          [[ -n "$__luksfer_f" ]] && (( ${+functions[$__luksfer_f]} )) && "$__luksfer_f" &>/dev/null
        done
        zle reset-prompt
      fi
      __luksfer_report prompt
    }

    __luksfer_install() {
      emulate -L zsh
      autoload -Uz add-zsh-hook is-at-least
      add-zsh-hook precmd __luksfer_precmd
      add-zsh-hook preexec __luksfer_preexec
      add-zsh-hook zshaddhistory __luksfer_addhistory
      zle -N __luksfer_follow
      local keymap
      for keymap in emacs viins vicmd; do bindkey -M "$keymap" $'\e[6973~' __luksfer_follow; done
      if is-at-least 5.3; then
        autoload -Uz add-zle-hook-widget
        add-zle-hook-widget line-init __luksfer_line_init
      else
        add-zsh-hook precmd __luksfer_prompt_fallback
      fi
    }
    __luksfer_install
    unfunction __luksfer_install

    # Hand ZDOTDIR back so .zlogin, .zlogout and child shells use the user's own files.
    if [[ "$ZDOTDIR" == "$HOME" ]]; then
      unset ZDOTDIR
    elif [[ -z "${LUKSFER_ZDOTDIR_EXPORTED-}" ]]; then
      typeset +x ZDOTDIR
    fi
    unset LUKSFER_USER_ZDOTDIR LUKSFER_ZDOTDIR_EXPORTED __luksfer_zdotdir

    """#
}
