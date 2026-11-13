#!/usr/bin/env bash
#
# Offline test suite for gh-batch. No network and no GitHub account are
# needed: bare repositories in a sandbox play the servers, their clones play
# two machines, and a stub gh answers with canned lists.
#
# Author: Dr. Denys Dutykh (Mathematics Department, Khalifa University of
#         Science and Technology, Abu Dhabi, UAE).
#
# Usage: tests/run-tests.sh [name-filter]

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GB="$ROOT/gh-batch"
FILTER="${1:-}"
PASS=0; FAIL=0; SKIP=0
FAILED_NAMES=""
TAB=$(printf '\t')

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/gh-batch-tests.XXXXXX")
SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT

# Settings of the person running the tests must not leak in.
for var in $(env | sed -n 's/^\(GH_BATCH_[A-Z_]*\)=.*/\1/p'); do
    unset "$var"
done
for var in $(git rev-parse --local-env-vars 2>/dev/null); do
    unset "$var"
done
unset GIT_SSH_COMMAND GIT_SSH SSH_ASKPASS GIT_ASKPASS NO_COLOR 2>/dev/null || true
export HOME="$SANDBOX/home"
export XDG_CONFIG_HOME="$SANDBOX/home/.config"
export XDG_STATE_HOME="$SANDBOX/home/.local/state"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Test Author"
export GIT_AUTHOR_EMAIL="author@example.org"
export GIT_COMMITTER_NAME="Test Author"
export GIT_COMMITTER_EMAIL="author@example.org"
export GIT_TERMINAL_PROMPT=0
export LC_ALL=C
export TZ=UTC
# The stub gh answers in place of the GitHub CLI.
export PATH="$ROOT/tests/stub:$PATH"
mkdir -p "$HOME"

N=0
WORLD=""; SRV=""; A=""; B=""
OUTPUT=""
RC=0
BG_PID=""

# ---------------------------------------------------------------------------
# The sandbox: servers, machines, commits
# ---------------------------------------------------------------------------

base_config() {
    rm -f "$HOME/.gitconfig"
    git config --global user.name "Test Author"
    git config --global user.email "author@example.org"
    git config --global init.defaultBranch main
    git config --global advice.detachedHead false
    git config --global protocol.file.allow always
}

world() {
    # A fresh world for one case: servers in $SRV, the workspace of machine
    # A in $A, the one of machine B in $B.
    N=$((N + 1))
    WORLD="$SANDBOX/w$N"
    SRV="$WORLD/srv"; A="$WORLD/a"; B="$WORLD/b"
    mkdir -p "$SRV" "$A" "$B"
    export GH_BATCH_STATE_DIR="$WORLD/state"
    export GH_STUB_DIR="$WORLD/gh"
    mkdir -p "$GH_STUB_DIR"
    unset GIT_SSH_COMMAND GH_BATCH_ROOT GH_BATCH_ISOLATE GH_BATCH_HIDE GIT_TEST_ASSUME_DIFFERENT_OWNER 2>/dev/null || true
    base_config
}

server() {
    # server NAME: a bare repository with one commit on main.
    local name="$1" seed="$WORLD/seed"
    git init -q --bare "$SRV/$name.git"
    git -C "$SRV/$name.git" symbolic-ref HEAD refs/heads/main
    rm -rf "$seed"
    git init -q "$seed"
    printf 'first line\n' > "$seed/readme.txt"
    git -C "$seed" add readme.txt
    git -C "$seed" commit -q -m "Start $name"
    git -C "$seed" push -q "$SRV/$name.git" HEAD:refs/heads/main
    rm -rf "$seed"
}

clone_to() {
    # clone_to MACHINE NAME [FOLDER]
    git clone -q "$SRV/$2.git" "$1/${3:-$2}"
}

repo() {
    # repo NAME: a server and its clone on each machine.
    server "$1"
    clone_to "$A" "$1"
    clone_to "$B" "$1"
}

commit() {
    # commit DIR FILE TEXT [MESSAGE]
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" > "$1/$2"
    git -C "$1" add -- "$2"
    git -C "$1" commit -q -m "${4:-Change $2}"
}

publish() {
    git -C "$1" push -q origin HEAD
}

head_of() { git -C "$1" rev-parse HEAD; }

state_of() {
    # Everything that must stay identical when a repository is said to be
    # untouched: commit, branch, staging area, references, stashes, files.
    (
        cd "$1" || exit 1
        git rev-parse HEAD 2>/dev/null
        git symbolic-ref -q HEAD
        git status --porcelain=v1 --untracked-files=all
        git ls-files -s
        git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags
        git stash list
        find . -path ./.git -prune -o -type f -print | sort | while IFS= read -r f; do
            cksum "$f"
        done
    )
}

operation_in_progress() {
    [ -d "$1/.git/rebase-merge" ] || [ -d "$1/.git/rebase-apply" ] || [ -f "$1/.git/MERGE_HEAD" ]
}

# ---------------------------------------------------------------------------
# Running the tool and reading its answer
# ---------------------------------------------------------------------------

gb() {
    OUTPUT=$("$GB" "$@" 2>&1)
    RC=$?
    return 0
}

st() {
    # st NAME -> the state reported for $A/NAME in a --porcelain output
    local line
    while IFS= read -r line; do
        case "$line" in
            *"$TAB$A/$1$TAB"*) printf '%s' "${line%%"$TAB"*}"; return 0 ;;
        esac
    done <<EOF
$OUTPUT
EOF
    return 0
}

msg() {
    # msg NAME -> the message reported for $A/NAME in a --porcelain output
    local line
    while IFS= read -r line; do
        case "$line" in
            *"$TAB$A/$1$TAB"*) printf '%s' "${line##*"$TAB"}"; return 0 ;;
        esac
    done <<EOF
$OUTPUT
EOF
    return 0
}

start_bg() {
    # start_bg ARGS...: the tool in a process group of its own, as a
    # terminal would run it, so that a signal can be sent to the group.
    set -m
    "$GB" "$@" > "$WORLD/bg.out" 2>&1 &
    BG_PID=$!
    set +m
}

wait_bg() {
    # wait_bg SECONDS -> 0 when the tool ended in time (RC and OUTPUT set)
    local limit="$1" n=0
    while kill -0 "$BG_PID" 2>/dev/null; do
        n=$((n + 1))
        if [ "$n" -gt $((limit * 10)) ]; then
            kill -KILL -- "-$BG_PID" 2>/dev/null
            wait "$BG_PID" 2>/dev/null
            RC=999
            OUTPUT=$(cat "$WORLD/bg.out" 2>/dev/null)
            return 1
        fi
        sleep 0.1
    done
    wait "$BG_PID" 2>/dev/null
    RC=$?
    OUTPUT=$(cat "$WORLD/bg.out" 2>/dev/null)
    return 0
}

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES
  - $1"; printf '  FAIL %s\n     %s\n' "$1" "$2"; }

check() {
    # check NAME EXPLANATION STATUS
    if [ "$3" -eq 0 ]; then ok "$1"; else bad "$1" "$2"; fi
}

# A pattern, not 'printf | grep -q': grep stops reading at the first match,
# and under pipefail the cut pipe would turn a match into a failure.
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

describe() {
    case "$FILTER" in
        "") return 0 ;;
        *) case "$1" in *"$FILTER"*) return 0 ;; *) SKIP=$((SKIP+1)); return 1 ;; esac ;;
    esac
}

# ---------------------------------------------------------------------------

printf 'gh-batch test suite\n\n'

# --- command line ----------------------------------------------------------
if describe "cli: version, help and usage errors"; then
    world
    gb --version
    check "cli: --version prints the name and a number" "got: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && contains "$OUTPUT" "gh-batch 1." && echo 0 || echo 1 )"
    gb help
    check "cli: help lists the commands" "got rc=$RC" \
        "$( [ "$RC" -eq 0 ] && contains "$OUTPUT" "COMMANDS" && contains "$OUTPUT" "pull" && echo 0 || echo 1 )"
    gb help pull
    check "cli: help of one command" "got rc=$RC" \
        "$( [ "$RC" -eq 0 ] && contains "$OUTPUT" "fast-forward" && echo 0 || echo 1 )"
    gb nosuchcommand
    check "cli: an unknown command is a usage error" "got rc=$RC" "$( [ "$RC" -eq 2 ] && echo 0 || echo 1 )"
    gb pull --nosuchoption
    check "cli: an unknown option is a usage error" "got rc=$RC" "$( [ "$RC" -eq 2 ] && echo 0 || echo 1 )"
    gb pull --jobs zero "$A"
    check "cli: a bad number of jobs is a usage error" "got rc=$RC" "$( [ "$RC" -eq 2 ] && echo 0 || echo 1 )"
    gb pull "$WORLD/missing"
    check "cli: a missing folder is a usage error" "got rc=$RC: $OUTPUT" "$( [ "$RC" -eq 2 ] && echo 0 || echo 1 )"
    gb pull "$A"
    check "cli: an empty folder is no error" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && contains "$OUTPUT" "no git repository" && echo 0 || echo 1 )"
fi

# --- discovery -------------------------------------------------------------
if describe "discovery: depth, nesting, hidden folders, duplicates"; then
    world
    server one
    clone_to "$A" one
    mkdir -p "$A/group" "$A/deep/er" "$A/too/deep/for" "$A/.hidden/inside"
    clone_to "$A" one "group/two"
    clone_to "$A" one "deep/er/three"
    clone_to "$A" one "too/deep/for/four"
    clone_to "$A" one ".dot"
    clone_to "$A" one ".hidden/inside/five"
    clone_to "$A" one "one/nested"
    mkdir -p "$A/node_modules"
    clone_to "$A" one "node_modules/six"
    mkdir -p "$A/plain"
    : > "$A/plain/.git"
    ln -s "$A/one" "$A/zlink"
    gb list "$A"
    expected="deep/er/three
group/two
one
.dot"
    check "discovery: three levels, no nesting, hidden repository kept, link dropped" "got: $OUTPUT" \
        "$( [ "$(printf '%s\n' "$OUTPUT" | sort)" = "$(printf '%s\n' "$expected" plain | sort)" ] && echo 0 || echo 1 )"
    gb status --porcelain -v "$A"
    check "discovery: a stray .git file is not a repository" "got: $OUTPUT" \
        "$( [ -z "$(st plain)" ] && [ -n "$(st one)" ] && [ "$(st .dot)" = "clean" ] && echo 0 || echo 1 )"
    gb list --depth 4 "$A"
    check "discovery: --depth reaches deeper" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "too/deep/for/four" && echo 0 || echo 1 )"
    gb list --only 'gr*' "$A"
    check "discovery: --only keeps the matching names" "got: $OUTPUT" \
        "$( [ "$OUTPUT" = "group/two" ] && echo 0 || echo 1 )"
    gb list --except 'one' --except '.dot' --except plain "$A"
    check "discovery: --except leaves names out" "got: $OUTPUT" \
        "$( [ "$(printf '%s\n' "$OUTPUT" | sort | tr '\n' ' ')" = "deep/er/three group/two " ] && echo 0 || echo 1 )"
    gb list "$A/one"
    check "discovery: a folder that is a repository is taken alone" "got: $OUTPUT" \
        "$( [ "$OUTPUT" = "one" ] && echo 0 || echo 1 )"
    gb list --absolute --only one "$A"
    check "discovery: --absolute prints full paths" "got: $OUTPUT" \
        "$( [ "$OUTPUT" = "$A/one" ] && echo 0 || echo 1 )"
fi

if describe "discovery: settings choose the folder"; then
    world
    repo alpha
    git config --global gh-batch.root "$A"
    OUTPUT=$(cd "$WORLD" && "$GB" list 2>&1)
    check "discovery: gh-batch.root is the default folder" "got: $OUTPUT" \
        "$( [ "$OUTPUT" = "alpha" ] && echo 0 || echo 1 )"
    git config --global gh-batch.exclude 'al*'
    OUTPUT=$(cd "$WORLD" && "$GB" list 2>&1)
    check "discovery: gh-batch.exclude leaves names out" "got: $OUTPUT" \
        "$( [ -z "$OUTPUT" ] && echo 0 || echo 1 )"
    git config --global --unset gh-batch.exclude
    OUTPUT=$(cd "$WORLD" && GH_BATCH_ROOT="$B" "$GB" list --absolute 2>&1)
    check "discovery: GH_BATCH_ROOT wins over the setting" "got: $OUTPUT" \
        "$( [ "$OUTPUT" = "$B/alpha" ] && echo 0 || echo 1 )"
    git -C "$A/alpha" config gh-batch.skip true
    gb pull --porcelain "$A"
    check "discovery: gh-batch.skip sets a repository aside" "got: $OUTPUT" \
        "$( [ "$(st alpha)" = "skipped" ] && [ "$RC" -eq 0 ] && echo 0 || echo 1 )"
fi

if describe "discovery: odd names and an inherited GIT_DIR"; then
    world
    server odd
    clone_to "$A" odd "with space"
    clone_to "$A" odd "-dash"
    clone_to "$A" odd "plain"
    commit "$B" x y z 2>/dev/null || true
    clone_to "$B" odd
    commit "$B/odd" new.txt "new" "Add new"
    publish "$B/odd"
    OUTPUT=$(GIT_DIR="$A/plain/.git" "$GB" pull --porcelain "$A" 2>&1); RC=$?
    check "discovery: names with a space or a leading dash are updated, GIT_DIR is ignored" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && [ "$(st "with space")" = "updated" ] && [ "$(st "-dash")" = "updated" ] && [ "$(st plain)" = "updated" ] && echo 0 || echo 1 )"
fi

# --- status ----------------------------------------------------------------
if describe "status: what is pending"; then
    world
    repo clean
    repo edited
    repo ahead
    repo stashed
    repo midmerge
    printf 'changed\n' >> "$A/edited/readme.txt"
    printf 'new\n' > "$A/edited/extra file.txt"
    commit "$A/ahead" a.txt "a" "Local work"
    printf 'wip\n' >> "$A/stashed/readme.txt"
    git -C "$A/stashed" stash -q
    commit "$A/midmerge" readme.txt "mine" "Mine"
    git -C "$A/midmerge" checkout -q -b side HEAD~1
    commit "$A/midmerge" readme.txt "theirs" "Theirs"
    git -C "$A/midmerge" checkout -q main
    git -C "$A/midmerge" merge -q side >/dev/null 2>&1
    git init -q "$A/lonely"
    commit "$A/lonely" f.txt "f" "Alone"
    before=$(state_of "$A/edited")
    gb status --porcelain "$A"
    check "status: clean, pending, ahead, stash, local only" "got: $OUTPUT" \
        "$( [ "$(st clean)" = "clean" ] && [ "$(st edited)" = "pending" ] && [ "$(st ahead)" = "ahead" ] && [ "$(st lonely)" = "localonly" ] && [ "$(st stashed)" = "stash" ] && contains "$(msg stashed)" "1 stash" && echo 0 || echo 1 )"
    check "status: the counts of pending files" "got: $(msg edited)" \
        "$( contains "$(msg edited)" "1 changed, 1 new" && echo 0 || echo 1 )"
    check "status: an unfinished merge needs the user" "got rc=$RC, $(st midmerge)" \
        "$( [ "$(st midmerge)" = "unfinished" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1 )"
    check "status: nothing is changed by looking" "the repository changed" \
        "$( [ "$(state_of "$A/edited")" = "$before" ] && echo 0 || echo 1 )"
    gb status "$A"
    check "status: the report hides clean repositories and counts them" "got: $OUTPUT" \
        "$( ! contains "$OUTPUT" "  clean  " && contains "$OUTPUT" "1 clean" && contains "$OUTPUT" "Needs you: midmerge" && echo 0 || echo 1 )"
    gb status --long --only edited "$A"
    check "status: --long lists the files, spaces kept" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "?? extra file.txt" && contains "$OUTPUT" ".M readme.txt" && echo 0 || echo 1 )"
    gb status --verbose --only clean "$A"
    check "status: --verbose shows a clean repository" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "clean" && [ "$RC" -eq 0 ] && echo 0 || echo 1 )"
fi

# --- pull: the plain cases -------------------------------------------------
if describe "pull: up to date, fast-forward, ahead"; then
    world
    repo same
    repo behind
    repo ahead
    commit "$B/behind" news.txt "news" "Add the news"
    commit "$B/behind" more.txt "more" "Add more"
    publish "$B/behind"
    commit "$A/ahead" mine.txt "mine" "Local work"
    gb pull --porcelain "$A"
    check "pull: states of the three plain cases" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && [ "$(st same)" = "uptodate" ] && [ "$(st behind)" = "updated" ] && [ "$(st ahead)" = "ahead" ] && echo 0 || echo 1 )"
    check "pull: the branch is now where the server is" "heads differ" \
        "$( [ "$(head_of "$A/behind")" = "$(head_of "$B/behind")" ] && [ -f "$A/behind/more.txt" ] && echo 0 || echo 1 )"
    check "pull: the move is written in the journal" "journal: $(cat "$GH_BATCH_STATE_DIR/journal.tsv" 2>/dev/null)" \
        "$( contains "$(cat "$GH_BATCH_STATE_DIR/journal.tsv" 2>/dev/null)" "fast-forward" && echo 0 || echo 1 )"
    commit "$B/behind" third.txt "third" "Add a third file"
    publish "$B/behind"
    gb pull "$A"
    check "pull: the report names what arrived and sums up" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "Add a third file" && contains "$OUTPUT" "1 updated" && contains "$OUTPUT" "1 up to date" && ! contains "$OUTPUT" "Needs you" && echo 0 || echo 1 )"
fi

if describe "pull: pending changes are kept or protect the repository"; then
    world
    repo apart
    repo overlap
    repo untracked
    repo ignored
    commit "$B/apart" other.txt "other" "Touch another file"
    publish "$B/apart"
    printf 'my edit\n' >> "$A/apart/readme.txt"
    commit "$B/overlap" readme.txt "server version" "Rewrite the readme"
    publish "$B/overlap"
    printf 'my edit\n' >> "$A/overlap/readme.txt"
    commit "$B/untracked" data.txt "server data" "Add data"
    publish "$B/untracked"
    printf 'my data\n' > "$A/untracked/data.txt"
    commit "$B/ignored" secret.cfg "server" "Add a file ignored elsewhere"
    publish "$B/ignored"
    printf 'secret.cfg\n' > "$A/ignored/.git/info/exclude"
    printf 'my secret\n' > "$A/ignored/secret.cfg"
    s_overlap=$(state_of "$A/overlap")
    s_untracked=$(state_of "$A/untracked")
    s_ignored=$(state_of "$A/ignored")
    gb pull --porcelain "$A"
    check "pull: an edit in another file is kept through the update" "got: $(st apart), $(tail -n 1 "$A/apart/readme.txt")" \
        "$( [ "$(st apart)" = "updated" ] && [ "$(tail -n 1 "$A/apart/readme.txt")" = "my edit" ] && [ -f "$A/apart/other.txt" ] && echo 0 || echo 1 )"
    check "pull: an edit in the same file blocks, nothing changes" "got: $(st overlap) $(msg overlap)" \
        "$( [ "$(st overlap)" = "blocked" ] && [ "$(state_of "$A/overlap")" = "$s_overlap" ] && contains "$(msg overlap)" "readme.txt" && echo 0 || echo 1 )"
    check "pull: an untracked file in the way blocks, nothing changes" "got: $(st untracked)" \
        "$( [ "$(st untracked)" = "blocked" ] && [ "$(state_of "$A/untracked")" = "$s_untracked" ] && echo 0 || echo 1 )"
    check "pull: an ignored file in the way is not overwritten" "got: $(st ignored), file: $(cat "$A/ignored/secret.cfg")" \
        "$( [ "$(st ignored)" = "blocked" ] && [ "$(cat "$A/ignored/secret.cfg")" = "my secret" ] && echo 0 || echo 1 )"
    check "pull: a blocked repository makes the exit status 1" "got rc=$RC" "$( [ "$RC" -eq 1 ] && echo 0 || echo 1 )"
fi

# --- pull: both sides moved ------------------------------------------------
diverge() {
    # diverge NAME: a commit on the server and another one here, in
    # different files.
    repo "$1"
    commit "$B/$1" server.txt "server" "Server work"
    publish "$B/$1"
    commit "$A/$1" local.txt "local" "Local work"
}

clash() {
    # clash NAME: the same line changed on both sides.
    repo "$1"
    commit "$B/$1" readme.txt "server line" "Server rewrites the readme"
    publish "$B/$1"
    commit "$A/$1" readme.txt "local line" "Local rewrites the readme"
}

if describe "pull: diverged histories are reported by default"; then
    world
    diverge split
    before=$(state_of "$A/split")
    gb pull --porcelain "$A"
    check "pull: report is the default, nothing changes" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st split)" = "diverged" ] && [ "$RC" -eq 1 ] && [ "$(state_of "$A/split")" = "$before" ] && echo 0 || echo 1 )"
fi

if describe "pull: rebase replays the local commits"; then
    world
    diverge split
    local_subject="Local work"
    gb pull --porcelain --diverged rebase "$A"
    check "pull: a clean replay" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st split)" = "rebased" ] && [ "$RC" -eq 0 ] && echo 0 || echo 1 )"
    check "pull: the history is linear, the local commit on top" "log: $(git -C "$A/split" log --format=%s | tr '\n' '|')" \
        "$( [ "$(git -C "$A/split" log -1 --format=%s)" = "$local_subject" ] && [ "$(git -C "$A/split" rev-parse HEAD~1)" = "$(head_of "$B/split")" ] && [ "$(git -C "$A/split" rev-list --merges --count HEAD)" = 0 ] && echo 0 || echo 1 )"
    check "pull: the branch is attached and no operation is left" "state is odd" \
        "$( [ "$(git -C "$A/split" symbolic-ref --short HEAD)" = "main" ] && ! operation_in_progress "$A/split" && echo 0 || echo 1 )"
fi

if describe "pull: a conflict in a rebase is undone"; then
    world
    clash fight
    printf 'untracked stays\n' > "$A/fight/notes.txt"
    before=$(state_of "$A/fight")
    gb pull --porcelain --diverged rebase "$A"
    check "pull: the conflict is reported with its file" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st fight)" = "conflict" ] && [ "$RC" -eq 1 ] && contains "$(msg fight)" "readme.txt" && echo 0 || echo 1 )"
    check "pull: the repository is exactly as before" "the repository changed" \
        "$( [ "$(state_of "$A/fight")" = "$before" ] && ! operation_in_progress "$A/fight" && echo 0 || echo 1 )"
    git config --global gh-batch.diverged rebase
    gb pull --porcelain "$A"
    check "pull: the setting gh-batch.diverged is read" "got: $(st fight)" \
        "$( [ "$(st fight)" = "conflict" ] && echo 0 || echo 1 )"
fi

if describe "pull: the conditions of a safe rebase"; then
    world
    diverge dirty
    printf 'pending\n' >> "$A/dirty/readme.txt"
    diverge merged
    git -C "$A/merged" checkout -q -b side
    commit "$A/merged" side.txt "side" "Side work"
    git -C "$A/merged" checkout -q main
    git -C "$A/merged" merge -q --no-ff -m "Merge side" side
    diverge elsewhere
    git -C "$A/elsewhere" push -q origin HEAD:refs/heads/backup
    git -C "$A/elsewhere" fetch -q origin
    repo rewritten
    commit "$B/rewritten" a.txt "a" "Server commit that will vanish"
    publish "$B/rewritten"
    git -C "$A/rewritten" pull -q --ff-only
    commit "$A/rewritten" mine.txt "mine" "Local work"
    git -C "$B/rewritten" reset -q --hard HEAD~1
    commit "$B/rewritten" b.txt "b" "Server commit after the rewrite"
    git -C "$B/rewritten" push -q --force origin HEAD
    diverge inway
    commit "$B/inway" cache.dat "server cache" "Add a cache file"
    publish "$B/inway"
    printf 'cache.dat\n' > "$A/inway/.git/info/exclude"
    printf 'my cache\n' > "$A/inway/cache.dat"
    s_dirty=$(state_of "$A/dirty"); s_merged=$(state_of "$A/merged"); s_else=$(state_of "$A/elsewhere")
    s_rewritten=$(state_of "$A/rewritten"); s_inway=$(state_of "$A/inway")
    gb pull --porcelain --diverged rebase "$A"
    check "pull: no rebase over uncommitted changes" "got: $(st dirty) $(msg dirty)" \
        "$( [ "$(st dirty)" = "diverged" ] && contains "$(msg dirty)" "uncommitted" && [ "$(state_of "$A/dirty")" = "$s_dirty" ] && echo 0 || echo 1 )"
    check "pull: no rebase of merge commits" "got: $(st merged) $(msg merged)" \
        "$( [ "$(st merged)" = "diverged" ] && contains "$(msg merged)" "merge commits" && [ "$(state_of "$A/merged")" = "$s_merged" ] && echo 0 || echo 1 )"
    check "pull: no rebase of commits already on a server" "got: $(st elsewhere) $(msg elsewhere)" \
        "$( [ "$(st elsewhere)" = "diverged" ] && contains "$(msg elsewhere)" "already on a server" && [ "$(state_of "$A/elsewhere")" = "$s_else" ] && echo 0 || echo 1 )"
    check "pull: no rebase on a rewritten history" "got: $(st rewritten) $(msg rewritten)" \
        "$( [ "$(st rewritten)" = "diverged" ] && contains "$(msg rewritten)" "rewritten" && [ "$(state_of "$A/rewritten")" = "$s_rewritten" ] && echo 0 || echo 1 )"
    check "pull: no rebase over an ignored file that the server added" "got: $(st inway) $(msg inway)" \
        "$( [ "$(st inway)" = "diverged" ] && contains "$(msg inway)" "cache.dat" && [ "$(state_of "$A/inway")" = "$s_inway" ] && [ "$(cat "$A/inway/cache.dat")" = "my cache" ] && echo 0 || echo 1 )"
fi

if describe "pull: merge joins the histories or is undone"; then
    world
    diverge split
    clash fight
    before=$(state_of "$A/fight")
    gb pull --porcelain --diverged merge "$A"
    check "pull: a clean merge has two parents" "got: $(st split)" \
        "$( [ "$(st split)" = "merged" ] && [ "$(git -C "$A/split" rev-list --merges --count HEAD)" = 1 ] && [ -f "$A/split/server.txt" ] && [ -f "$A/split/local.txt" ] && echo 0 || echo 1 )"
    check "pull: a conflicting merge is undone" "got: $(st fight)" \
        "$( [ "$(st fight)" = "conflict" ] && [ "$(state_of "$A/fight")" = "$before" ] && ! operation_in_progress "$A/fight" && echo 0 || echo 1 )"
fi

# --- pull: states that are reported and left alone ---------------------------
if describe "pull: repositories that are left alone"; then
    world
    repo detached
    repo nobranch
    repo midmerge
    repo vanished
    repo locked
    git -C "$A/detached" checkout -q --detach
    git -C "$A/nobranch" checkout -q -b topic
    commit "$A/midmerge" readme.txt "mine" "Mine"
    git -C "$A/midmerge" checkout -q -b side HEAD~1
    commit "$A/midmerge" readme.txt "theirs" "Theirs"
    git -C "$A/midmerge" checkout -q main
    git -C "$A/midmerge" merge -q side >/dev/null 2>&1
    git -C "$B/vanished" checkout -q -b work
    commit "$B/vanished" w.txt "w" "Work"
    git -C "$B/vanished" push -q -u origin work
    git -C "$A/vanished" fetch -q
    git -C "$A/vanished" checkout -q work
    git -C "$B/vanished" push -q origin --delete work
    : > "$A/locked/.git/index.lock"
    git init -q "$A/lonely"
    commit "$A/lonely" f.txt "f" "Alone"
    for r in detached nobranch midmerge vanished locked lonely; do
        eval "s_$r=\$(state_of \"\$A/$r\")"
    done
    gb pull --porcelain "$A"
    check "pull: the six states" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st detached)" = "detached" ] && [ "$(st nobranch)" = "noupstream" ] && [ "$(st midmerge)" = "unfinished" ] && [ "$(st vanished)" = "gone" ] && [ "$(st locked)" = "busy" ] && [ "$(st lonely)" = "localonly" ] && echo 0 || echo 1 )"
    rm -f "$A/locked/.git/index.lock"
    unchanged=0
    for r in detached nobranch midmerge vanished locked lonely; do
        eval "was=\$s_$r"
        [ "$(state_of "$A/$r")" = "$was" ] || unchanged=1
    done
    check "pull: none of them was touched" "a repository changed" "$unchanged"
fi

if describe "pull: a linked worktree and a shallow clone"; then
    world
    repo main
    git -C "$A/main" worktree add -q "$A/linked" -b second >/dev/null 2>&1
    server thin
    commit "$B" ignore me not 2>/dev/null || true
    clone_to "$B" thin
    commit "$B/thin" two.txt "2" "Second"
    commit "$B/thin" three.txt "3" "Third"
    publish "$B/thin"
    git clone -q --depth 1 "file://$SRV/thin.git" "$A/thin"
    commit "$B/thin" four.txt "4" "Fourth"
    publish "$B/thin"
    gb pull --porcelain "$A"
    check "pull: a linked worktree is skipped, a shallow clone moves forward" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st linked)" = "skipped" ] && [ "$(st thin)" = "updated" ] && [ -f "$A/thin/four.txt" ] && echo 0 || echo 1 )"
    commit "$B/thin" five.txt "5" "Fifth"
    publish "$B/thin"
    commit "$A/thin" mine.txt "mine" "Local work"
    gb pull --porcelain --diverged rebase "$A"
    check "pull: no rebase in a shallow clone" "got: $(st thin) $(msg thin)" \
        "$( [ "$(st thin)" = "diverged" ] && contains "$(msg thin)" "shallow" && echo 0 || echo 1 )"
fi

if describe "pull: hostile git settings change nothing"; then
    world
    repo behind
    repo overlap
    diverge split
    commit "$B/behind" n.txt "n" "News"
    publish "$B/behind"
    commit "$B/overlap" readme.txt "server" "Server"
    publish "$B/overlap"
    printf 'mine\n' >> "$A/overlap/readme.txt"
    git config --global pull.rebase true
    git config --global rebase.autoStash true
    git config --global merge.autoStash true
    git config --global merge.ff false
    git config --global branch.main.mergeOptions "--squash"
    git -C "$A/behind" config branch.main.mergeOptions "--squash --no-ff"
    before=$(state_of "$A/overlap")
    gb pull --porcelain "$A"
    check "pull: fast-forward, blocked and diverged as without the settings" "got: $OUTPUT" \
        "$( [ "$(st behind)" = "updated" ] && [ "$(head_of "$A/behind")" = "$(head_of "$B/behind")" ] && [ "$(st overlap)" = "blocked" ] && [ "$(state_of "$A/overlap")" = "$before" ] && [ "$(st split)" = "diverged" ] && echo 0 || echo 1 )"
    check "pull: no stash was made behind the user's back" "a stash exists" \
        "$( [ -z "$(git -C "$A/overlap" stash list)" ] && echo 0 || echo 1 )"
fi

if describe "pull: a repository that git refuses to read is reported"; then
    world
    repo owned
    OUTPUT=$(GIT_TEST_ASSUME_DIFFERENT_OWNER=1 "$GB" pull --porcelain "$A" 2>&1); RC=$?
    check "pull: dubious ownership is unreadable, not silently dropped" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st owned)" = "unreadable" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1 )"
fi

# --- fetch and --dry-run -----------------------------------------------------
if describe "fetch: look without touching"; then
    world
    repo behind
    diverge split
    commit "$B/behind" n.txt "n" "News from the server"
    publish "$B/behind"
    s_behind=$(state_of "$A/behind"); s_split=$(state_of "$A/split")
    gb fetch --porcelain "$A"
    check "fetch: behind and diverged are announced" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st behind)" = "behind" ] && [ "$(st split)" = "diverged" ] && echo 0 || echo 1 )"
    check "fetch: no branch and no file moved" "a repository changed" \
        "$( [ "$(state_of "$A/behind")" = "$s_behind" ] && [ "$(state_of "$A/split")" = "$s_split" ] && echo 0 || echo 1 )"
    gb pull --dry-run "$A"
    check "pull --dry-run: the same, with the commits that wait" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "News from the server" && [ "$(state_of "$A/behind")" = "$s_behind" ] && echo 0 || echo 1 )"
    gb status --porcelain "$A"
    check "status: behind is known after a fetch" "got: $(st behind)" \
        "$( [ "$(st behind)" = "behind" ] && echo 0 || echo 1 )"
fi

# --- failures of the network ---------------------------------------------------
if describe "pull: an unreachable server fails alone"; then
    world
    repo fine
    repo broken
    commit "$B/fine" n.txt "n" "News"
    publish "$B/fine"
    git -C "$A/broken" remote set-url origin "$SRV/nowhere.git"
    gb pull --porcelain "$A"
    check "pull: one failure, the others go on" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st broken)" = "failed" ] && [ "$(st fine)" = "updated" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1 )"
    git -C "$A/broken" remote set-url origin "https://user:hunter2secret@localhost:1/x.git"
    gb pull "$A"
    check "pull: a password in an address never reaches the report" "got: $OUTPUT" \
        "$( ! contains "$OUTPUT" "hunter2secret" && echo 0 || echo 1 )"
fi

if describe "engine: a server that never answers meets the deadline"; then
    world
    repo fine
    repo hang
    git -C "$A/hang" remote set-url origin "ssh://nowhere.invalid/hang.git"
    export GIT_SSH_COMMAND="$ROOT/tests/stub/hanging-ssh"
    started=$SECONDS
    gb pull --porcelain --timeout 2 "$A"
    took=$((SECONDS - started))
    unset GIT_SSH_COMMAND
    check "engine: the deadline ends the fetch and says so" "got rc=$RC after $took s: $OUTPUT" \
        "$( [ "$(st hang)" = "failed" ] && contains "$(msg hang)" "no answer" && [ "$(st fine)" = "uptodate" ] && [ "$took" -lt 15 ] && echo 0 || echo 1 )"
    sleep 0.3
    check "engine: no child of the fetch survives" "a stub ssh is still running" \
        "$( ! pgrep -f "$ROOT/tests/stub/hanging-ssh" >/dev/null 2>&1 && echo 0 || echo 1 )"
fi

if describe "engine: a signal stops the network steps at once"; then
    for sig in INT TERM; do
        world
        repo hang
        git -C "$A/hang" remote set-url origin "ssh://nowhere.invalid/hang.git"
        export GIT_SSH_COMMAND="$ROOT/tests/stub/hanging-ssh"
        start_bg pull --porcelain "$A"
        sleep 1.5
        if [ "$sig" = "INT" ]; then
            kill -INT -- "-$BG_PID" 2>/dev/null
        else
            kill -TERM "$BG_PID" 2>/dev/null
        fi
        ended=1
        wait_bg 10 && ended=0
        unset GIT_SSH_COMMAND
        check "engine: SIG$sig ends the run with status 130" "ended=$ended rc=$RC: $OUTPUT" \
            "$( [ "$ended" -eq 0 ] && [ "$RC" -eq 130 ] && [ "$(st hang)" = "interrupted" ] && echo 0 || echo 1 )"
        sleep 0.3
        check "engine: after SIG$sig no child survives and the scratch folder is gone" "leftovers found" \
            "$( ! pgrep -f "$ROOT/tests/stub/hanging-ssh" >/dev/null 2>&1 && [ -z "$(ls -d "${TMPDIR:-/tmp}"/gh-batch.* 2>/dev/null)" ] && echo 0 || echo 1 )"
    done
fi

if describe "engine: an interrupt lets a local step finish"; then
    world
    repo slow
    # A checkout filter that takes its time: the fast-forward is then a long
    # local step, in the middle of which the interrupt arrives.
    git config --global filter.slow.smudge 'sh -c "sleep 2; cat"'
    git config --global filter.slow.clean cat
    printf '*.slow filter=slow\n' > "$B/slow/.gitattributes"
    printf 'payload\n' > "$B/slow/big.slow"
    git -C "$B/slow" add .gitattributes big.slow
    git -C "$B/slow" commit -q -m "Add a file that is slow to check out"
    publish "$B/slow"
    start_bg pull --porcelain "$A"
    sleep 1.2
    kill -INT -- "-$BG_PID" 2>/dev/null
    ended=1
    wait_bg 20 && ended=0
    check "engine: the update is complete, not cut in the middle" "ended=$ended rc=$RC: $OUTPUT; status: $(git -C "$A/slow" status --porcelain)" \
        "$( [ "$ended" -eq 0 ] && [ "$(head_of "$A/slow")" = "$(head_of "$B/slow")" ] && [ "$(cat "$A/slow/big.slow" 2>/dev/null)" = "payload" ] && [ -z "$(git -C "$A/slow" status --porcelain)" ] && [ ! -f "$A/slow/.git/index.lock" ] && echo 0 || echo 1 )"
    check "engine: the run still reports the stop" "got rc=$RC" "$( [ "$RC" -eq 130 ] && echo 0 || echo 1 )"
fi

if describe "engine: the tool does not hold the pipe of its caller"; then
    world
    repo hooked
    commit "$B/hooked" n.txt "n" "News"
    publish "$B/hooked"
    printf '#!/bin/sh\nsleep 30 &\n' > "$A/hooked/.git/hooks/post-merge"
    chmod +x "$A/hooked/.git/hooks/post-merge"
    started=$SECONDS
    OUTPUT=$("$GB" pull --porcelain "$A" 2>&1); RC=$?
    took=$((SECONDS - started))
    check "engine: a command substitution returns although a hook left a process" "took $took s: $OUTPUT" \
        "$( [ "$took" -lt 10 ] && [ "$(st hooked)" = "updated" ] && echo 0 || echo 1 )"
fi

if describe "engine: one job or eight give the same report"; then
    world
    for r in r1 r2 r3 r4 r5 r6 r7 r8 r9; do repo "$r"; done
    for r in r2 r5 r8; do commit "$B/$r" n.txt "n" "News"; publish "$B/$r"; done
    for r in r3 r6; do commit "$A/$r" m.txt "m" "Mine"; done
    gb fetch --jobs 1 "$A"
    one=$OUTPUT
    gb fetch --jobs 8 "$A"
    check "engine: the order and the text do not depend on the number of jobs" "one job:
$one
eight jobs:
$OUTPUT" "$( [ "$one" = "$OUTPUT" ] && contains "$OUTPUT" "9 repositories" && echo 0 || echo 1 )"
fi

if describe "engine: one run at a time"; then
    world
    repo alpha
    mkdir -p "$GH_BATCH_STATE_DIR"
    sleep 60 &
    holder=$!
    printf '%s' "$holder" > "$GH_BATCH_STATE_DIR/lock"
    gb pull "$A"
    check "engine: a second run is refused while the first is alive" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 3 ] && contains "$OUTPUT" "another gh-batch" && echo 0 || echo 1 )"
    gb status "$A"
    check "engine: looking is always allowed" "got rc=$RC" "$( [ "$RC" -eq 0 ] && echo 0 || echo 1 )"
    kill "$holder" 2>/dev/null
    wait "$holder" 2>/dev/null
    gb pull "$A"
    check "engine: the lock of a dead run is taken over and released" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && [ ! -e "$GH_BATCH_STATE_DIR/lock" ] && echo 0 || echo 1 )"
fi

if describe "engine: without process groups the tool still works"; then
    world
    repo behind
    commit "$B/behind" n.txt "n" "News"
    publish "$B/behind"
    OUTPUT=$(GH_BATCH_ISOLATE=none "$GB" pull --porcelain "$A" 2>&1); RC=$?
    check "engine: the fallback updates as well" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st behind)" = "updated" ] && [ "$RC" -eq 0 ] && echo 0 || echo 1 )"
fi

# --- push: what is already committed -------------------------------------------
if describe "push: commits are pushed after one confirmation"; then
    world
    repo quiet
    repo ahead
    commit "$A/ahead" mine.txt "mine" "Local work"
    gb push --porcelain "$A"
    check "push: without a terminal the run asks for --yes and does nothing" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 2 ] && contains "$OUTPUT" "--yes" && [ "$(git -C "$SRV/ahead.git" rev-parse main)" != "$(head_of "$A/ahead")" ] && echo 0 || echo 1 )"
    gb push --dry-run "$A"
    check "push --dry-run: the list, and nothing sent" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && contains "$OUTPUT" "push 1 commit" && contains "$OUTPUT" "dry run" && [ "$(git -C "$SRV/ahead.git" rev-parse main)" != "$(head_of "$A/ahead")" ] && echo 0 || echo 1 )"
    gb push --yes "$A"
    check "push: the commit reaches the server" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && [ "$(git -C "$SRV/ahead.git" rev-parse main)" = "$(head_of "$A/ahead")" ] && contains "$OUTPUT" "pushed 1 commit" && contains "$OUTPUT" "1 pushed" && contains "$OUTPUT" "1 with nothing to push" && echo 0 || echo 1 )"
    check "push: the list comes before the report" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "Plan:" && contains "$OUTPUT" "To do: a push from 1 repository." && contains "$OUTPUT" "Done:" && echo 0 || echo 1 )"
    gb push --porcelain "$A"
    check "push: nothing to push needs no confirmation" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && [ "$(st ahead)" = "nothing" ] && echo 0 || echo 1 )"
    commit "$A/ahead" more.txt "more" "More local work"
    git config --global gh-batch.confirm false
    gb push --porcelain "$A"
    check "push: gh-batch.confirm false never asks" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && [ "$(st ahead)" = "pushed" ] && echo 0 || echo 1 )"
fi

if describe "push: pending changes stay unless a commit is asked for"; then
    world
    repo edited
    printf 'changed\n' >> "$A/edited/readme.txt"
    printf 'new\n' > "$A/edited/new file.txt"
    before=$(state_of "$A/edited")
    gb push --porcelain --yes "$A"
    check "push: by default nothing is committed" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && [ "$(st edited)" = "pending" ] && contains "$(msg edited)" "stay on this machine" && [ "$(state_of "$A/edited")" = "$before" ] && echo 0 || echo 1 )"
fi

# --- push: the automatic commit ---------------------------------------------------
if describe "push: --commit commits everything and pushes"; then
    world
    repo work
    printf 'changed\n' >> "$A/work/readme.txt"
    printf 'new\n' > "$A/work/new file.txt"
    mkdir -p "$A/work/sub"
    printf 'deep\n' > "$A/work/sub/deep.txt"
    commit "$A/work" gone.txt "gone" "Add a file to delete"
    rm "$A/work/gone.txt"
    printf 'ignored.log\n' > "$A/work/.gitignore"
    printf 'noise\n' > "$A/work/ignored.log"
    git config --global gh-batch.machine "test-machine"
    gb push --commit --dry-run "$A"
    check "push --commit --dry-run: the files are listed, nothing is committed" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "commit 5 files, then push 2 commits" && contains "$OUTPUT" "new file.txt" && [ -n "$(git -C "$A/work" status --porcelain)" ] && echo 0 || echo 1 )"
    gb push --commit --yes "$A"
    check "push --commit: one commit, pushed, the tree is clean" "got rc=$RC: $OUTPUT; status: $(git -C "$A/work" status --porcelain)" \
        "$( [ "$RC" -eq 0 ] && [ -z "$(git -C "$A/work" status --porcelain)" ] && [ "$(git -C "$SRV/work.git" rev-parse main)" = "$(head_of "$A/work")" ] && contains "$OUTPUT" "committed 5 files, pushed 2 commits" && echo 0 || echo 1 )"
    subject=$(git -C "$A/work" log -1 --format=%s)
    body=$(git -C "$A/work" log -1 --format=%b)
    check "push --commit: the message has the date, the machine and the files" "subject: $subject; body: $body" \
        "$( [ "$subject" = "Work in progress, $(date '+%Y-%m-%d') (test-machine)" ] && contains "$body" "?? new file.txt" && contains "$body" ".D gone.txt" && contains "$body" "sub/deep.txt" && echo 0 || echo 1 )"
    check "push --commit: an ignored file stays out" "it was committed" \
        "$( [ -z "$(git -C "$A/work" ls-files ignored.log)" ] && [ -f "$A/work/ignored.log" ] && echo 0 || echo 1 )"
    check "push --commit: the journal records the commit and the push" "journal: $(cat "$GH_BATCH_STATE_DIR/journal.tsv")" \
        "$( contains "$(cat "$GH_BATCH_STATE_DIR/journal.tsv")" "${TAB}commit${TAB}" && contains "$(cat "$GH_BATCH_STATE_DIR/journal.tsv")" "${TAB}push${TAB}" && echo 0 || echo 1 )"
    printf 'again\n' >> "$A/work/readme.txt"
    gb push --commit --yes -m "End of day %d, %n file(s) from %h, 100%%" "$A"
    check "push -m: the text of the message is chosen" "subject: $(git -C "$A/work" log -1 --format=%s)" \
        "$( [ "$(git -C "$A/work" log -1 --format=%s)" = "End of day $(date '+%Y-%m-%d'), 1 file(s) from test-machine, 100%" ] && echo 0 || echo 1 )"
fi

if describe "push: the setting, and a repository that opts out"; then
    world
    repo joins
    repo optsout
    repo readonly
    printf 'a\n' >> "$A/joins/readme.txt"
    printf 'b\n' >> "$A/optsout/readme.txt"
    printf 'c\n' >> "$A/readonly/readme.txt"
    git config --global gh-batch.commit true
    git -C "$A/optsout" config gh-batch.commit false
    git -C "$A/readonly" config gh-batch.pullOnly true
    s_out=$(state_of "$A/optsout"); s_ro=$(state_of "$A/readonly")
    gb push --porcelain --yes "$A"
    check "push: gh-batch.commit true commits without the option" "got: $OUTPUT" \
        "$( [ "$(st joins)" = "pushed" ] && [ -z "$(git -C "$A/joins" status --porcelain)" ] && echo 0 || echo 1 )"
    check "push: a repository with gh-batch.commit false is left alone" "got: $(st optsout)" \
        "$( [ "$(st optsout)" = "pending" ] && [ "$(state_of "$A/optsout")" = "$s_out" ] && echo 0 || echo 1 )"
    check "push: gh-batch.pullOnly keeps a repository out" "got: $(st readonly)" \
        "$( [ "$(st readonly)" = "skipped" ] && [ "$(state_of "$A/readonly")" = "$s_ro" ] && echo 0 || echo 1 )"
    gb push --porcelain --yes --commit "$A"
    check "push: --commit does not override the opt-out of a repository" "got: $(st optsout)" \
        "$( [ "$(st optsout)" = "pending" ] && [ "$(state_of "$A/optsout")" = "$s_out" ] && echo 0 || echo 1 )"
    printf 'd\n' >> "$A/joins/readme.txt"
    s_joins=$(state_of "$A/joins")
    gb push --porcelain --yes --no-commit "$A"
    check "push: --no-commit wins over the setting" "got: $(st joins)" \
        "$( [ "$(st joins)" = "pending" ] && [ "$(state_of "$A/joins")" = "$s_joins" ] && echo 0 || echo 1 )"
fi

if describe "push: the guards of the automatic commit"; then
    world
    repo secret
    repo heavy
    repo flood
    repo nested
    repo both
    printf 'TOKEN=abc\n' > "$A/secret/.env"
    printf 'x\n' >> "$A/secret/readme.txt"
    head -c 2200000 /dev/zero > "$A/heavy/big.bin"
    for k in 1 2 3 4 5; do printf '%s\n' "$k" > "$A/flood/f$k.txt"; done
    git init -q "$A/nested/inner"
    commit "$A/nested/inner" i.txt "i" "Inner"
    commit "$A/both" done.txt "done" "Finished work"
    printf 'KEY\n' > "$A/both/server.pem"
    git config --global gh-batch.maxFileSize 1
    git config --global gh-batch.maxNewFiles 4
    for r in secret heavy flood nested; do
        eval "s_$r=\$(state_of \"\$A/$r\")"
    done
    gb push --porcelain --yes --commit "$A"
    check "guard: a new file that looks like a secret" "got: $(st secret) $(msg secret)" \
        "$( [ "$(st secret)" = "notcommitted" ] && contains "$(msg secret)" ".env" && [ "$(state_of "$A/secret")" = "$s_secret" ] && echo 0 || echo 1 )"
    check "guard: a file above the size limit" "got: $(st heavy) $(msg heavy)" \
        "$( [ "$(st heavy)" = "notcommitted" ] && contains "$(msg heavy)" "big.bin" && [ "$(state_of "$A/heavy")" = "$s_heavy" ] && echo 0 || echo 1 )"
    check "guard: too many new files at once" "got: $(st flood) $(msg flood)" \
        "$( [ "$(st flood)" = "notcommitted" ] && contains "$(msg flood)" "5 new files" && [ "$(state_of "$A/flood")" = "$s_flood" ] && echo 0 || echo 1 )"
    check "guard: a git repository inside the repository" "got: $(st nested) $(msg nested)" \
        "$( [ "$(st nested)" = "notcommitted" ] && contains "$(msg nested)" "inner" && [ "$(state_of "$A/nested")" = "$s_nested" ] && echo 0 || echo 1 )"
    check "guard: the commits that exist are pushed, the guarded files stay and are named" "got rc=$RC: $(st both) $(msg both)" \
        "$( [ "$(st both)" = "pushed" ] && contains "$(msg both)" "NOT committed" && contains "$(msg both)" "server.pem" && [ "$(git -C "$SRV/both.git" rev-parse main)" = "$(head_of "$A/both")" ] && [ -f "$A/both/server.pem" ] && [ -z "$(git -C "$A/both" ls-files server.pem)" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1 )"
    printf 'PUBLIC\n' > "$A/secret/id_ed25519.pub"
    printf '.env\n' > "$A/secret/.gitignore"
    gb push --porcelain --yes --commit --only secret "$A"
    check "guard: an ignored secret and a public key do not stop the commit" "got: $(st secret) $(msg secret)" \
        "$( [ "$(st secret)" = "pushed" ] && [ -z "$(git -C "$A/secret" ls-files .env)" ] && echo 0 || echo 1 )"
fi

if describe "push: a commit refused by a hook restores the staging area"; then
    world
    repo hooked
    printf 'one\n' > "$A/hooked/staged.txt"
    printf 'two\n' > "$A/hooked/unstaged.txt"
    git -C "$A/hooked" add staged.txt
    printf '#!/bin/sh\necho "the hook says no" >&2\nexit 1\n' > "$A/hooked/.git/hooks/pre-commit"
    chmod +x "$A/hooked/.git/hooks/pre-commit"
    before=$(state_of "$A/hooked")
    gb push --porcelain --yes --commit "$A"
    check "push: the refusal is reported with the words of the hook" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st hooked)" = "notcommitted" ] && contains "$(msg hooked)" "the hook says no" && [ "$RC" -eq 1 ] && echo 0 || echo 1 )"
    check "push: what was staged is staged, what was not is not" "status: $(git -C "$A/hooked" status --porcelain | tr '\n' '|')" \
        "$( [ "$(state_of "$A/hooked")" = "$before" ] && echo 0 || echo 1 )"
fi

# --- push: when the server has moved ----------------------------------------------
if describe "push: the server has newer commits"; then
    world
    diverge split
    gb push --porcelain --yes "$A"
    check "push: with the default the refusal is reported, nothing changes here" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st split)" = "rejected" ] && [ "$RC" -eq 1 ] && contains "$(msg split)" "pull first" && [ "$(git -C "$A/split" log -1 --format=%s)" = "Local work" ] && [ ! -f "$A/split/server.txt" ] && echo 0 || echo 1 )"
    gb push --porcelain --yes --diverged rebase "$A"
    check "push: with rebase the commits of the server are taken, then all is pushed" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st split)" = "pushed" ] && [ "$RC" -eq 0 ] && [ "$(git -C "$SRV/split.git" rev-parse main)" = "$(head_of "$A/split")" ] && [ -f "$A/split/server.txt" ] && [ "$(git -C "$A/split" rev-list --merges --count HEAD)" = 0 ] && echo 0 || echo 1 )"
    clash fight
    before=$(state_of "$A/fight")
    gb push --porcelain --yes --diverged rebase --only fight "$A"
    check "push: a conflict on the way is undone and reported" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st fight)" = "conflict" ] && [ "$RC" -eq 1 ] && [ "$(state_of "$A/fight")" = "$before" ] && ! operation_in_progress "$A/fight" && echo 0 || echo 1 )"
    repo evening
    commit "$B/evening" theirs.txt "theirs" "Work of the other machine"
    publish "$B/evening"
    printf 'pending\n' > "$A/evening/pending.txt"
    gb push --porcelain --yes --commit --diverged rebase --only evening "$A"
    check "push --commit: commit, take the server's commits, push" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st evening)" = "pushed" ] && [ "$(git -C "$SRV/evening.git" rev-parse main)" = "$(head_of "$A/evening")" ] && [ -f "$A/evening/theirs.txt" ] && [ -z "$(git -C "$A/evening" status --porcelain)" ] && echo 0 || echo 1 )"
fi

if describe "push: a hook of the server side or of this side that refuses"; then
    world
    repo guarded
    commit "$A/guarded" mine.txt "mine" "Local work"
    printf '#!/bin/sh\necho "pushing is closed today" >&2\nexit 1\n' > "$A/guarded/.git/hooks/pre-push"
    chmod +x "$A/guarded/.git/hooks/pre-push"
    gb push --porcelain --yes "$A"
    check "push: a refusing pre-push hook is a failure with its words" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st guarded)" = "failed" ] && [ "$RC" -eq 1 ] && contains "$(msg guarded)" "closed today" && echo 0 || echo 1 )"
    rm "$A/guarded/.git/hooks/pre-push"
    printf '#!/bin/sh\necho "the server says no" >&2\nexit 1\n' > "$SRV/guarded.git/hooks/pre-receive"
    chmod +x "$SRV/guarded.git/hooks/pre-receive"
    gb push --porcelain --yes --diverged rebase "$A"
    check "push: a refusal by the server is not mistaken for newer commits" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st guarded)" = "failed" ] && [ "$RC" -eq 1 ] && [ "$(git -C "$A/guarded" log -1 --format=%s)" = "Local work" ] && echo 0 || echo 1 )"
fi

# --- push: where a branch goes --------------------------------------------------------
if describe "push: branches and their destinations"; then
    world
    repo fresh
    repo renamed
    repo two
    git -C "$A/fresh" checkout -q -b topic
    commit "$A/fresh" t.txt "t" "Topic work"
    git -C "$A/renamed" checkout -q -b feature origin/main
    commit "$A/renamed" f.txt "f" "Feature work"
    commit "$A/two" a.txt "a" "Work on main"
    git -C "$A/two" checkout -q -b other
    git -C "$A/two" push -q -u origin other
    commit "$A/two" o.txt "o" "Work on other"
    git -C "$A/two" checkout -q main
    git config --global push.default matching
    main_before=$(git -C "$SRV/renamed.git" rev-parse main)
    gb push --porcelain --yes "$A"
    check "push: a branch that exists here only is reported, not published" "got: $(st fresh) $(msg fresh)" \
        "$( [ "$(st fresh)" = "noupstream" ] && ! git -C "$SRV/fresh.git" rev-parse -q --verify topic >/dev/null && echo 0 || echo 1 )"
    check "push: a branch that follows main under another name is not pushed onto main" "got: $(st renamed) $(msg renamed)" \
        "$( [ "$(git -C "$SRV/renamed.git" rev-parse main)" = "$main_before" ] && [ "$(st renamed)" = "noupstream" ] && ! git -C "$SRV/renamed.git" rev-parse -q --verify feature >/dev/null && echo 0 || echo 1 )"
    check "push: only the current branch goes, even with push.default matching" "other on the server moved" \
        "$( [ "$(st two)" = "pushed" ] && [ "$(git -C "$SRV/two.git" rev-parse main)" = "$(git -C "$A/two" rev-parse main)" ] && [ "$(git -C "$SRV/two.git" rev-parse other)" != "$(git -C "$A/two" rev-parse other)" ] && echo 0 || echo 1 )"
    git config --global --unset push.default
    commit "$A/two" b.txt "b" "More work on main"
    gb push --yes --only two "$A"
    check "push: the other branch with unpushed commits is named" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "the branch other has commits that are not pushed" && echo 0 || echo 1 )"
    gb push --porcelain --yes --set-upstream --only fresh "$A"
    check "push --set-upstream: the branch is published and followed" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st fresh)" = "pushed" ] && [ "$(git -C "$SRV/fresh.git" rev-parse topic)" = "$(head_of "$A/fresh")" ] && [ "$(git -C "$A/fresh" rev-parse --abbrev-ref 'topic@{u}')" = "origin/topic" ] && echo 0 || echo 1 )"
fi

if describe "push: repositories where nothing can be pushed"; then
    world
    repo detached
    git -C "$A/detached" checkout -q --detach
    printf 'x\n' >> "$A/detached/readme.txt"
    git init -q "$A/lonely"
    commit "$A/lonely" f.txt "f" "Alone"
    printf 'y\n' >> "$A/lonely/f.txt"
    s_det=$(state_of "$A/detached"); s_lon=$(state_of "$A/lonely")
    gb push --porcelain --yes --commit "$A"
    check "push: a detached HEAD and a repository without remote are reported, untouched" "got rc=$RC: $OUTPUT" \
        "$( [ "$(st detached)" = "detached" ] && [ "$(st lonely)" = "localonly" ] && [ "$(state_of "$A/detached")" = "$s_det" ] && [ "$(state_of "$A/lonely")" = "$s_lon" ] && [ "$RC" -eq 0 ] && echo 0 || echo 1 )"
fi

# --- push: what GitHub says -----------------------------------------------------------
as_github() {
    # as_github NAME: the clone of machine A now names GitHub as its server;
    # a rewriting rule sends the traffic to the sandbox.
    git -C "$A/$1" remote set-url origin "https://github.com/owner/$1.git"
    git config --global "url.$SRV/.insteadOf" "https://github.com/owner/"
}

facts() {
    # facts NAME PRIVATE MAY_PUSH ARCHIVED: what the stub gh answers.
    mkdir -p "$GH_STUB_DIR/repos/owner"
    printf '%s\037%s\037%s\n' "$2" "$3" "$4" > "$GH_STUB_DIR/repos/owner/$1"
}

if describe "push: public repositories are marked, forbidden ones are not tried"; then
    world
    for r in open closed foreign frozen unknown; do
        repo "$r"
        as_github "$r"
        commit "$A/$r" mine.txt "mine" "Local work"
    done
    facts open false true false
    facts closed true true false
    facts foreign false false false
    facts frozen true true true
    gb push --yes "$A"
    plan=${OUTPUT%%Done:*}
    check "push: PUBLIC is written in the list, before the confirmation" "got: $OUTPUT" \
        "$( contains "$plan" "push 1 commit  [PUBLIC]" && contains "$plan" "1 of them PUBLIC" && echo 0 || echo 1 )"
    gb push --porcelain --yes "$A"
    commit "$A/open" more.txt "more" "More"
    commit "$A/closed" more.txt "more" "More"
    gb push --porcelain --yes "$A"
    check "push: the report marks the public one only" "got: $OUTPUT" \
        "$( contains "$(msg open)" "[PUBLIC]" && ! contains "$(msg closed)" "PUBLIC" && [ "$(st open)" = "pushed" ] && [ "$(st closed)" = "pushed" ] && echo 0 || echo 1 )"
    check "push: no push where GitHub gives no right, or to an archive" "got: $(st foreign) $(msg foreign) | $(st frozen) $(msg frozen)" \
        "$( [ "$(st foreign)" = "ahead" ] && contains "$(msg foreign)" "no right to push" && [ "$(st frozen)" = "ahead" ] && contains "$(msg frozen)" "archived" && echo 0 || echo 1 )"
    check "push: a repository unknown to GitHub is pushed without a mark" "got: $OUTPUT" \
        "$( [ "$(git -C "$SRV/unknown.git" rev-parse main)" = "$(head_of "$A/unknown")" ] && echo 0 || echo 1 )"
    commit "$A/open" third.txt "third" "Third"
    : > "$GH_STUB_DIR/calls"
    OUTPUT=$(GH_BATCH_HIDE=gh "$GB" push --porcelain --yes "$A" 2>&1); RC=$?
    check "push: without gh nothing is asked and nothing is marked" "got: $OUTPUT; calls: $(cat "$GH_STUB_DIR/calls")" \
        "$( [ "$(st open)" = "pushed" ] && ! contains "$(msg open)" "PUBLIC" && [ ! -s "$GH_STUB_DIR/calls" ] && echo 0 || echo 1 )"
fi

if describe "github: addresses are recognised in every form"; then
    world
    slug() { ( PROG=t; eval "$(sed -n '/^github_slug() {/,/^}/p' "$GB")"; github_slug "$1" ); }
    all=0
    for pair in \
        "https://github.com/Owner/Name.git=owner/name" \
        "https://github.com/owner/name=owner/name" \
        "https://github.com/owner/name/=owner/name" \
        "https://user:secret@github.com/owner/name.git=owner/name" \
        "git@github.com:owner/name.git=owner/name" \
        "ssh://git@github.com/owner/name.git=owner/name" \
        "ssh://git@github.com:22/owner/name=owner/name" \
        "git://github.com/owner/name.git=owner/name" \
        "https://gitlab.com/owner/name.git=" \
        "https://github.com/owner=" \
        "https://github.com/owner/name/extra=" \
        "/srv/git/name.git=" \
        "git@example.org:owner/name.git="; do
        url=${pair%%=*}; want=${pair##*=}
        got=$(slug "$url")
        [ "$got" = "$want" ] || { all=1; printf '     %s gave "%s", not "%s"\n' "$url" "$got" "$want"; }
    done
    check "github: thirteen addresses" "see above" "$all"
fi

# --- sync ---------------------------------------------------------------------------
if describe "sync: pull, then push"; then
    world
    repo behind
    repo ahead
    commit "$B/behind" n.txt "n" "News"
    publish "$B/behind"
    commit "$A/ahead" mine.txt "mine" "Local work"
    gb sync --yes "$A"
    check "sync: both steps, each with its summary" "got rc=$RC: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && contains "$OUTPUT" "First, the pull:" && contains "$OUTPUT" "1 updated" && contains "$OUTPUT" "Then, the push:" && contains "$OUTPUT" "1 pushed" && [ "$(head_of "$A/behind")" = "$(head_of "$B/behind")" ] && [ "$(git -C "$SRV/ahead.git" rev-parse main)" = "$(head_of "$A/ahead")" ] && echo 0 || echo 1 )"
    commit "$B/behind" n2.txt "n2" "More news"
    publish "$B/behind"
    commit "$A/ahead" m2.txt "m2" "More local work"
    s_b=$(state_of "$A/behind"); srv_a=$(git -C "$SRV/ahead.git" rev-parse main)
    gb sync --dry-run "$A"
    check "sync --dry-run: nothing moves on either side" "got: $OUTPUT" \
        "$( [ "$(state_of "$A/behind")" = "$s_b" ] && [ "$(git -C "$SRV/ahead.git" rev-parse main)" = "$srv_a" ] && contains "$OUTPUT" "dry run" && echo 0 || echo 1 )"
fi

# --- notification ---------------------------------------------------------------------
if describe "notify: the report is handed to a command"; then
    world
    repo behind
    clash fight
    commit "$B/behind" n.txt "n" "News"
    publish "$B/behind"
    git config --global gh-batch.notify "cat > '$WORLD/note.txt'; printf '%s %s' \"\$GH_BATCH_COMMAND\" \"\$GH_BATCH_STATUS\" > '$WORLD/note.env'"
    gb pull --only behind "$A"
    check "notify: silent by default" "a note was written" "$( [ ! -e "$WORLD/note.txt" ] && echo 0 || echo 1 )"
    gb pull --only behind --notify "$A"
    check "notify: --notify sends the report and says how the run went" "note: $(cat "$WORLD/note.txt" 2>/dev/null); env: $(cat "$WORLD/note.env" 2>/dev/null)" \
        "$( contains "$(cat "$WORLD/note.txt" 2>/dev/null)" "1 repository" && [ "$(cat "$WORLD/note.env" 2>/dev/null)" = "pull ok" ] && echo 0 || echo 1 )"
    rm -f "$WORLD/note.txt" "$WORLD/note.env"
    git config --global gh-batch.notifyOn attention
    gb pull --only behind "$A"
    check "notify: on attention only, a quiet run sends nothing" "a note was written" "$( [ ! -e "$WORLD/note.txt" ] && echo 0 || echo 1 )"
    gb pull --only fight "$A"
    check "notify: on attention only, a run that needs the user sends its report" "note: $(cat "$WORLD/note.txt" 2>/dev/null)" \
        "$( contains "$(cat "$WORLD/note.txt" 2>/dev/null)" "Needs you: fight" && [ "$(cat "$WORLD/note.env" 2>/dev/null)" = "pull attention" ] && echo 0 || echo 1 )"
fi

# --- output ------------------------------------------------------------------
if describe "output: quiet, verbose and colour"; then
    world
    repo same
    repo behind
    clash fight
    commit "$B/behind" n.txt "n" "News"
    publish "$B/behind"
    gb pull --quiet --dry-run "$A"
    check "output: --quiet prints nothing when nothing needs the user" "got: $OUTPUT" \
        "$( [ -z "$OUTPUT" ] || contains "$OUTPUT" "fight" && ! contains "$OUTPUT" "behind  " && echo 0 || echo 1 )"
    gb fetch --verbose "$A"
    check "output: --verbose shows the repositories that are up to date" "got: $OUTPUT" \
        "$( contains "$OUTPUT" "up to date" && contains "$OUTPUT" "same" && echo 0 || echo 1 )"
    gb fetch --color always "$A"
    esc=$(printf '\033')
    check "output: --color always colours, the default does not when piped" "no escape found" \
        "$( contains "$OUTPUT" "$esc[" && echo 0 || echo 1 )"
    gb fetch "$A"
    check "output: no colour in a pipe" "an escape was found" \
        "$( ! contains "$OUTPUT" "$esc[" && echo 0 || echo 1 )"
    gb config
    check "config: the settings and their source" "got: $OUTPUT" \
        "$( [ "$RC" -eq 0 ] && contains "$OUTPUT" "diverged" && contains "$OUTPUT" "default" && echo 0 || echo 1 )"
fi

# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed' "$PASS" "$FAIL"
[ "$SKIP" -gt 0 ] && printf ', %d groups skipped by the filter' "$SKIP"
printf '\n'
if [ "$FAIL" -gt 0 ]; then
    printf '\nFailed:%s\n' "$FAILED_NAMES"
    exit 1
fi
exit 0
