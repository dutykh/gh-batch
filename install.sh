#!/usr/bin/env bash
#
# Installer for gh-batch.
#
# Author: Dr. Denys Dutykh (Mathematics Department, Khalifa University of
#         Science and Technology, Abu Dhabi, UAE).
#
# Usage:
#   ./install.sh                     copy the program into ~/.local/bin
#   ./install.sh --link              link it from this checkout instead
#   ./install.sh --prefix /usr/local install into /usr/local/bin (needs sudo)
#   ./install.sh --uninstall         remove the command and its completions
#   curl -fsSL https://raw.githubusercontent.com/dutykh/gh-batch/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/dutykh/gh-batch/main"
PREFIX="${PREFIX:-$HOME/.local}"
UNINSTALL=0
NO_COMPLETION=0
LINK=0

say()  { printf '%s\n' "$*"; }
warn() { printf 'install.sh: %s\n' "$*" >&2; }
die()  { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOS'
Installer for gh-batch.

  ./install.sh                     copy the program into ~/.local/bin
  ./install.sh --link              link it from this checkout instead, so that
                                   a "git pull" of the checkout updates it
  ./install.sh --prefix /usr/local install into /usr/local/bin (needs sudo)
  ./install.sh --uninstall         remove the command and its completions
  ./install.sh --no-completion     skip the bash and zsh completions
  curl -fsSL https://raw.githubusercontent.com/dutykh/gh-batch/main/install.sh | bash
EOS
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || die "--prefix needs a folder, for example: --prefix /usr/local"
            PREFIX="$2"; shift 2 ;;
        --link)           LINK=1; shift ;;
        --uninstall)      UNINSTALL=1; shift ;;
        --no-completion)  NO_COMPLETION=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

BIN_DIR="$PREFIX/bin"
COMP_DIR="$PREFIX/share/bash-completion/completions"
ZSH_DIR="$PREFIX/share/zsh/site-functions"
TARGET="$BIN_DIR/gh-batch"

# A checkout is used only when this script runs from a file inside it. Piped
# into bash, the script has no file, and the current folder must not be
# mistaken for a checkout: the program is downloaded instead.
SOURCE_DIR=""
script="${BASH_SOURCE[0]:-}"
if [ -n "$script" ] && [ -f "$script" ]; then
    SOURCE_DIR=$(cd "$(dirname "$script")" && pwd)
fi

if [ "$UNINSTALL" -eq 1 ]; then
    removed=0
    if [ -f "$TARGET" ] || [ -L "$TARGET" ]; then
        rm -f "$TARGET" && say "removed $TARGET" && removed=1
    fi
    for candidate in "$COMP_DIR/gh-batch" "$ZSH_DIR/_gh-batch"; do
        if [ -f "$candidate" ]; then rm -f "$candidate" && say "removed $candidate"; fi
    done
    # The completion in the user's own folder serves whichever gh-batch is on
    # the PATH: it goes only when none is left.
    user_comp="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/gh-batch"
    if [ "$removed" -eq 1 ] && [ -f "$user_comp" ] && ! command -v gh-batch >/dev/null 2>&1; then
        rm -f "$user_comp" && say "removed $user_comp"
    fi
    [ "$removed" -eq 1 ] || warn "no gh-batch found in $BIN_DIR"
    say ""
    say "The settings (git config --global --get-regexp '^gh-batch') and the record of"
    say "past runs in ${XDG_STATE_HOME:-$HOME/.local/state}/gh-batch were kept."
    exit 0
fi

command -v git >/dev/null 2>&1 || warn "git is not installed yet: gh-batch needs git 2.30 or newer"

mkdir -p "$BIN_DIR" || die "cannot create $BIN_DIR"

if [ "$LINK" -eq 1 ]; then
    [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/gh-batch" ] ||
        die "--link works from a checkout of the repository: git clone https://github.com/dutykh/gh-batch"
    ln -sfn "$SOURCE_DIR/gh-batch" "$TARGET"
    say "linked $TARGET to $SOURCE_DIR/gh-batch"
elif [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/gh-batch" ]; then
    # The new file takes the place of the old one in one step, so that a
    # gh-batch at work never reads a half-written program.
    tmp="$TARGET.tmp.$$"
    cp "$SOURCE_DIR/gh-batch" "$tmp"
    chmod 0755 "$tmp"
    mv -f "$tmp" "$TARGET"
    say "installed $TARGET from this checkout"
else
    say "downloading gh-batch from $REPO_RAW"
    tmp="$TARGET.tmp.$$"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_RAW/gh-batch" -o "$tmp" || { rm -f "$tmp"; die "download failed"; }
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$REPO_RAW/gh-batch" -O "$tmp" || { rm -f "$tmp"; die "download failed"; }
    else
        die "curl or wget is needed to download the program"
    fi
    if ! head -n1 "$tmp" | grep -q '^#!/usr/bin/env bash'; then
        rm -f "$tmp"
        die "the downloaded file does not look like gh-batch"
    fi
    chmod 0755 "$tmp"
    mv -f "$tmp" "$TARGET"
    say "installed $TARGET"
fi

if [ "$NO_COMPLETION" -eq 0 ]; then
    user_comp="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
    # Always mkdir the full completion path. "$PREFIX/share" being writable does
    # not mean bash-completion/completions already exists underneath it.
    if mkdir -p "$COMP_DIR" 2>/dev/null && [ -w "$COMP_DIR" ]; then
        "$TARGET" completion bash > "$COMP_DIR/gh-batch" 2>/dev/null &&
            say "bash completion installed in $COMP_DIR"
    elif mkdir -p "$user_comp" 2>/dev/null && [ -w "$user_comp" ]; then
        "$TARGET" completion bash > "$user_comp/gh-batch" 2>/dev/null &&
            say "bash completion installed in $user_comp"
    else
        warn "could not install the bash completion (no writable completions folder)"
    fi
    if mkdir -p "$ZSH_DIR" 2>/dev/null && [ -w "$ZSH_DIR" ]; then
        "$TARGET" completion zsh > "$ZSH_DIR/_gh-batch" 2>/dev/null &&
            say "zsh completion installed in $ZSH_DIR (add it to fpath if zsh does not see it)"
    fi
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        say ""
        warn "$BIN_DIR is not on your PATH."
        say "Add it with:"
        say "    echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.bashrc"
        say "    source ~/.bashrc"
        ;;
esac

say ""
say "Next steps:"
say "    git config --global gh-batch.root ~/workspace   the folder that holds your repositories"
say "    gh-batch status                                 what is pending in each of them"
say "    gh-batch pull                                   the morning command"
say "    gh-batch push                                   the evening command"
say "    gh-batch help                                   everything else"
