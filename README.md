<!-- Author: Dr. Denys Dutykh (Mathematics Department, Khalifa University of Science and Technology, Abu Dhabi, UAE). -->

# gh-batch

Whoever keeps their work in many git repositories, on more than one machine, repeats the same gestures every day: in the morning each project must be brought up to date, in the evening each one must be pushed, and a project created on one machine must be cloned on the others. The tool `gh-batch` does this for a whole folder of repositories with one command. It goes over the folders, finds the git repositories, handles several of them at a time, and prints one line for each repository that changed or that needs you. A few repositories can also be named, from any folder, and several commands can share one line: `gh-batch pull commit push thesis notes` brings those two up to date, commits what is pending in them and pushes.

It is careful by construction. A conflict is never left inside a repository: the attempt is undone, the repository is exactly as it was, and you are told which files conflict; or, if you choose so, the version of the server wins the lines that both sides changed, and yours is kept beside it. A file of yours is never lost: one that stands where the server puts a file is moved aside, whole, and named in the report. A push is never forced. Nothing is committed unless you asked for it, and before the evening run commits or pushes anything it shows the full list and waits for one confirmation.

The tool is one bash file. It needs bash 3.2 or newer and git 2.30 or newer, and it runs on Linux and macOS. The GitHub CLI `gh` is optional: it is used to clone a whole account with its organisations, to mark the public repositories, and for one part of the health check.

The repository is at

https://github.com/dutykh/gh-batch

## A day with gh-batch

**In the morning** one command fetches every repository and brings it forward. What arrived is listed, and the two repositories that could not be updated safely are named with the reason. Here the setting `gh-batch.diverged` is `rebase`, so that the commits made on this machine are replayed after the new ones of the server; by default they are only reported. In `teaching/exam-2026` the other machine had started to track a file that this one kept for itself, ignored by git: that copy made way for the version of the server and was kept, and the report says where.

```text
$ gh-batch pull
gh-batch pull: 7 repositories under ~/workspace

  updated       lecture-notes       main     3 new commits
        c801050 Add the fourth exercise sheet
        2bd2d46 Add the lecture on the group velocity
        01ca9d9 Add the lecture on the dispersion relation
  blocked       paper-solitons      main     1 new commit on the server and your uncommitted changes touch the same lines, in notes.txt: nothing was changed
  updated       teaching/exam-2026  main     1 new commit; CLAUDE.md, which git did not track here, made way for the version of the server: this machine's copy is kept in .git/gh-batch/kept/20261117-081502
        fdbfc87 Add the third question
        to compare: git -C ~/workspace/teaching/exam-2026 diff --no-index -- .git/gh-batch/kept/20261117-081502/CLAUDE.md CLAUDE.md
        to take it back: cp -Rp ~/workspace/teaching/exam-2026/.git/gh-batch/kept/20261117-081502/. ~/workspace/teaching/exam-2026
  rebased       thesis              main     your 1 commit replayed on top of 2 new ones
        fb867f8 Add two references
        62de4fc Write the existence proof of chapter 2
  ahead         wave-solver         main     1 commit to push
  conflict      website             main     1 commit here and 1 on the server, and they conflict in notes.txt: nothing was changed, the rebase is yours (git pull --rebase)

7 repositories: 2 updated, 1 rebased, 1 up to date, 1 with commits to push, 1 in conflict, 1 blocked.
Kept aside: teaching/exam-2026 (CLAUDE.md).
Needs you: paper-solitons (blocked), website (conflict).
```

With the setting `gh-batch.conflicts` set to `server`, the two that need you would have been brought forward too: the version of the server taken in the lines of `notes.txt` that both sides changed, and the version of this machine kept beside it.

**In the evening** one command shows what it is about to do, waits for Enter, then commits what is pending and pushes. Here the automatic commit was asked for with `--commit`; it can also be made the rule with a setting.

```text
$ gh-batch push --commit
gh-batch push: 7 repositories under ~/workspace

Plan:
  not committed lecture-notes       main     1 changed, 1 new: the new file .env looks like a secret: commit it by hand, or add it to .gitignore
  to do         teaching/exam-2026  main     commit 1 file, then push 1 commit
        new      solutions.md
  to do         thesis              main     commit 3 files, then push 1 commit
        changed  notes.txt
        new      abstract.tex
        new      figures/energy.pdf
  to do         wave-solver         main     push 2 commits  [PUBLIC]

To do: a commit in 2 repositories, then a push from 3 repositories, 1 of them PUBLIC.
Proceed? [Y/n]

Done:
  not committed lecture-notes       main     1 changed, 1 new: the new file .env looks like a secret: commit it by hand, or add it to .gitignore
  local only    scratch             main     it has no remote: it exists on this machine only
  pushed        teaching/exam-2026  main     committed 1 file, pushed 1 commit after taking 1 commit from the server
  pushed        thesis              main     committed 3 files, pushed 1 commit
  pushed        wave-solver         main     pushed 2 commits  [PUBLIC]

7 repositories: 3 pushed, 2 with nothing to push, 1 without remote, 1 not committed.
Needs you: lecture-notes (not committed).
```

**During the day**, when the pending changes should become a commit before anything is sent, one command shows the list and asks for the message. Enter takes the sentence below. Another line replaces it, and a minus sign alone does nothing. The form `gh-batch commit push` then goes on to the push and asks for it separately, so a refusal there leaves the commits on this machine.

```text
$ gh-batch commit
gh-batch commit: 7 repositories under ~/workspace

Plan:
  to do         teaching/exam-2026  main     commit 1 file
        new      solutions.md
  to do         thesis              main     commit 3 files
        changed  notes.txt
        new      abstract.tex
        new      figures/energy.pdf
To do: a commit in 2 repositories.
Commit message [A Regular Commit to Synchronise], or - to do nothing:

Done:
  committed     teaching/exam-2026  main     committed 1 file: A Regular Commit to Synchronise
  committed     thesis              main     committed 3 files: A Regular Commit to Synchronise

7 repositories: 2 committed, 5 clean.
```

**For one project, or a few**, the repositories are named after the command, from whatever folder the terminal is in, and several commands can share the line, each with its own report and its own question. Here the thesis is brought up to date, its pending changes are committed under the message asked for, and the commit is pushed; no other repository is touched:

```text
$ gh-batch pull commit push thesis
gh-batch pull: 1 repository under ~/workspace

  updated       thesis        main     1 new commit (your pending changes were kept)
        c2bb6d4 Add two references

1 repository: 1 updated.

gh-batch commit: 1 repository under ~/workspace

First, the commit:
Plan:
  to do         thesis        main     commit 2 files, then a push
        changed  readme.txt
        new      chapter2.tex

To do: a commit in 1 repository. A push is asked afterwards.
Commit message [A Regular Commit to Synchronise], or - to do nothing:

Done:
  committed     thesis        main     committed 2 files: A Regular Commit to Synchronise

1 repository: 1 committed.

Then, the push:
Plan:
  to do         thesis        main     push 1 commit

To do: a push from 1 repository.
Proceed? [Y/n]

Done:
  pushed        thesis        main     pushed 1 commit

1 repository: 1 pushed.
```

A name is the one that the report shows, or its last part, so `gh-batch push thesis exam-2026` finds `teaching/exam-2026` too. A misspelt name stops everything before anything is done, and a question answered no ends the line where it stands.

**In the middle of the day**, before leaving one machine for another, `gh-batch sync` does both in one run. **On a new machine**, or the day after a project was created elsewhere, `gh-batch clone` brings what is missing:

```text
$ gh-batch clone
gh-batch clone: 5 repositories of ada on GitHub; 2 already under ~/workspace, 3 to clone

Plan: clone 3 repositories into ~/workspace (about 55 MB)
  lecture-notes   private  51 MB
  paper-solitons  PUBLIC   3 MB
  website         private  under 1 MB
Proceed? [Y/n]

  cloned        lecture-notes   main     into ~/workspace/lecture-notes
  cloned        paper-solitons  main     into ~/workspace/paper-solitons
  cloned        website         main     into ~/workspace/website

3 repositories: 3 cloned.
```

The organisations that the account belongs to are read with it, and the repositories of each go to a folder of their own, which is asked for once.

## Installation

There are three ways, and they can coexist.

As an extension of the GitHub CLI, which then keeps it up to date with `gh extension upgrade batch`. The commands are typed `gh batch pull`, `gh batch push`, and so on; everywhere below, read `gh batch` for `gh-batch`.

```bash
gh extension install dutykh/gh-batch
```

With the installer, which copies the program into `~/.local/bin` and installs the completion for bash and zsh:

```bash
curl -fsSL https://raw.githubusercontent.com/dutykh/gh-batch/main/install.sh | bash
```

From a clone of the repository, linked instead of copied, so that a `git pull` of the clone (which `gh-batch pull` itself performs each morning, if the clone sits among your repositories) updates the command:

```bash
git clone https://github.com/dutykh/gh-batch
gh-batch/install.sh --link
```

The installer accepts `--prefix DIR` for another place than `~/.local`, `--no-completion`, and `--uninstall`. Since the tool is a single file, copying `gh-batch` anywhere on the `PATH` is an installation too.

Then tell it once where your repositories live, and look at them:

```bash
git config --global gh-batch.root ~/workspace
gh-batch status
```

Without that setting, every command works on the folders named on its command line, or on the current folder, where it also looks up the names of repositories.

## The commands

| Command | What it does |
|---|---|
| `pull` | Fetch every repository and bring it forward. |
| `push` | Push every repository that has new commits, after committing what is pending when asked to. |
| `commit` | Commit what is pending, asking for the message; `commit push` then pushes. |
| `sync` | Pull, then push. |
| `reset` | Set every branch to the one it follows on its server, safely: its commit is kept first, and commits that the server lacks are dropped only with `--discard-local`. |
| `clone` | Clone what is missing: a whole GitHub account with its organisations, or the entries of a layout file. |
| `status` | Show what is pending in every repository, without touching the network. |
| `fetch` | Look at the servers, change no file, say what `pull` would do. |
| `log` | List the commits of today, or of a period, across the repositories. |
| `exec` | Run a command in every repository. |
| `doctor` | Examine the repositories, their remotes and the folder around them. |
| `list` | Print the repositories found, or their layout. |
| `config` | Print the settings in force and where each comes from. |
| `completion` | Print the completion script for bash or zsh. |
| `help` | Print the help of one command: `gh-batch help push`. |

Every command takes folders as arguments. A folder is searched for repositories three levels deep (`--depth N` changes that); a folder that holds `.git` is a repository and is not searched further, so a repository nested inside another one is left to its parent. Hidden folders and `node_modules` are not entered.

A word that is not a folder where you stand is a name, looked up under the folders of `gh-batch.root`, so that it works from any folder. It takes the repository whose name in the report is that word (`teaching/exam-2026`), or whose last part is that word (`exam-2026`), or the repositories inside a folder of that name (`teaching`). A name may hold the wildcards of `--only`, quoted so that the shell leaves them alone (`'paper-*'`). A name that matches nothing stops the run before anything is done, and the message lists the names that contain the word; a part of a name is suggested, never taken. A folder of the same name in the current folder wins, and a path such as `./notes` or `~/papers` is always a folder.

```text
$ gh-batch status thesis exam-2026
gh-batch status: 2 repositories under ~/workspace

  pending       thesis              main     1 changed, 1 new (the oldest since 0 min)
  pending       teaching/exam-2026  main     1 new (the oldest since 0 min)

2 repositories: 2 with pending changes.

$ gh-batch push thesis exam-2026 notes
gh-batch: error: notes is neither a folder here nor the name of a repository under ~/workspace; the names that contain it: lecture-notes
```

The completion of bash and zsh offers these names. The options common to all commands are these.

| Option | Meaning |
|---|---|
| `-j N`, `--jobs N` | Repositories handled at the same time; 8 by default, and 1 means strictly one after the other. The report always follows the order of the folders. |
| `--depth N` | Levels searched below each folder (3). |
| `--only GLOB`, `--except GLOB` | Keep, or leave out, the repositories whose name matches; both can be repeated. |
| `-n`, `--dry-run` | Show what would be done and change nothing. |
| `-y`, `--yes` | Do not ask before committing, pushing, cloning or dropping commits. |
| `-v`, `--verbose` | Show every repository, not only those that changed. |
| `-q`, `--quiet` | Show only what needs you. |
| `--porcelain` | One line per repository, with fields separated by tabs. |
| `--timeout SEC` | Give up on a server that does not answer (300). |
| `--color WHEN`, `--no-color` | `auto`, `always` or `never`, and `--no-color` is `never`; `NO_COLOR` is honoured. |
| `-h`, `--help` | Print the help, or the help of the command that comes before it. |
| `--version` | Print the version, as `gh-batch version` does. |

### pull

For each repository the branch that is checked out is compared with the branch it follows on the server, and one of the outcomes below follows.

```mermaid
flowchart TD
    fetch["Fetch the server"] --> new{"New commits<br/>on the server?"}
    new -- no --> same["Nothing moves:<br/>up to date"]
    new -- yes --> aside["A file of yours in the way<br/>is set aside and kept"]
    aside --> mine{"Commits here that<br/>the server lacks?"}
    mine -- no --> clash{"Do they clash with<br/>uncommitted changes?"}
    clash -- no --> ff["Fast-forward, your changes<br/>carried over: updated"]
    clash -- yes --> who1{"Setting<br/>gh-batch.conflicts"}
    who1 -- report --> blocked["Nothing moves:<br/>blocked"]
    who1 -- server --> stash["Fast-forward, your changes<br/>wait in the stash"]
    mine -- yes --> setting{"Setting<br/>gh-batch.diverged"}
    setting -- report --> diverged["Nothing moves:<br/>diverged"]
    setting -- rebase or merge --> safe{"Safe to try?"}
    safe -- no --> diverged
    safe -- yes --> conflict{"Conflict?"}
    conflict -- no --> done["Rebased or merged"]
    conflict -- yes --> who2{"Setting<br/>gh-batch.conflicts"}
    who2 -- report --> undone["Undone, as it was:<br/>conflict"]
    who2 -- server --> again["Made again, the server first<br/>where both changed a line"]
```

When only the server has new commits, the branch is moved forward. Files with uncommitted changes that the new commits do not touch stay as they are. When the new commits touch them, the changes travel over the update in a stash of the tool's own and are back in the files afterwards, provided git tells beforehand that they still apply, which needs git 2.40 or newer. When they touch the same lines as the new commits, nothing changes and the repository is reported as blocked with the names of the files; with `gh-batch.conflicts server` the update is made, the version of the server is in the files, and your changes wait in the stash with the command that brings them back (`git stash pop`), the repository being named among those that need you. A file deleted here without a commit is the one exception, because git does not count a missing file as a change it could overwrite: when the new commits change it, it comes back in its new version, and the report names it.

A file that git does not track here, untracked or ignored, and that stands where the new commits put a file, makes way for the version of the server. It is moved, whole, into the git folder of the repository, `.git/gh-batch/kept/DATE-TIME/`, where nothing can be committed, and the report names it with the command that compares the two versions and the one that takes yours back; a copy identical to the version of the server is simply dropped, and a folder or a link in the way is moved as it is. The typical case is a file such as the `CLAUDE.md` of an agent: another machine stops ignoring it and commits its own version, while this machine holds a different one. Git refuses such an update, and a `git pull` typed by hand would then replace the ignored file without asking; `gh-batch` keeps it. The end of the report lists what was kept aside.

When both sides have new commits, the setting `gh-batch.diverged` decides. With `report`, the default, nothing is tried. With `rebase`, your commits are replayed on top of those of the server; with `merge`, the two histories are joined by a merge commit. The option `--diverged report`, `--diverged rebase` or `--diverged merge` makes that choice for one run, whatever the setting says, and it holds wherever commits of the server are taken: in `fetch`, which says what `pull` would try, in `push` and `sync`, and in `clone --update`. At the first conflict the attempt is undone at once, the tool verifies that the commit, the branch and every pending change are what they were, and the conflicting files are named together with the command to run by hand.

The setting `gh-batch.conflicts` decides what follows a conflict. With `report`, the default, it stops there. With `server`, the commit of the branch is first kept under `refs/gh-batch/before-pull/BRANCH/DATE-TIME`, the version of this machine of each file that both sides changed is copied into `.git/gh-batch/kept/DATE-TIME/`, and the replay or the merge is made again with the version of the server in the lines that both sides changed. A file that git cannot merge line by line, such as a PDF rebuilt on both machines, takes the version of the server whole; a commit of yours that is left empty by it is dropped, and the report says so. The report names the files, says where your versions are, and prints the one command that restores the branch as it was. What even this cannot settle, a file deleted on one side and changed on the other, is undone as before. The option `--conflicts report` or `--conflicts server` decides for one run.

A replay is tried only when it is safe. It is refused, and the repository reported as diverged with the reason, when a merge commit is among your commits, when some of them are already on a server, when the history of the server was rewritten while commits of yours came after the old one, when the commits are signed (signing them again could ask for a passphrase), when the clone is shallow, or when uncommitted changes cannot travel in a stash (an older git, a submodule, a file added with `--intent-to-add`, a file that git no longer tracks but that stays on the disk). When the history of the server was rewritten and every commit here that it lacks was once on it, nothing of this machine is at stake: the branch takes the new history, its commit kept under `refs/gh-batch/before-pull/`, and the report lists the old commits.

The other local branches that follow the branch of the same name on the server and only lack its new commits are moved forward too, without a file being touched. A branch checked out in another worktree, or one that follows a branch of another name, as a bookmark made from `main` does, stays where it is. A detached HEAD, an operation left in progress, a branch that no longer exists on the server and a repository without remote are reported and left alone. The command `gh-batch pull --dry-run` fetches and only says what would be done; it is the same as `gh-batch fetch`.

### push

The push works in two passes. The first one, local and fast, works out for every repository the files to commit and the commits to push. Their list is shown, the public repositories are marked `PUBLIC` when `gh` is installed, and one confirmation is asked. The second pass commits and pushes. Without a terminal there is nobody to ask, so the run refuses to act unless `--yes` is given.

```mermaid
flowchart TD
    look["Look at every repository,<br/>without the network"] --> list["Show the list: files to commit,<br/>commits to push, PUBLIC marks"]
    list --> ask{"Proceed?"}
    ask -- no --> nothing["Nothing is done"]
    ask -- yes --> guard{"Do the pending changes<br/>pass the four guards?"}
    guard -- yes --> commit["Commit them"]
    guard -- no --> keep["Leave them,<br/>and say why"]
    commit --> push["Push the branch,<br/>never forced"]
    keep --> push
    push --> refused{"Refused because the server<br/>has newer commits?"}
    refused -- no --> pushed["Pushed"]
    refused -- yes --> take["Take them as pull does,<br/>then push once more"]
    take --> pushed
```

**The automatic commit** is off by default: pending changes are then only reported, as what stays on this machine. With `--commit`, or with `git config --global gh-batch.commit true`, every pending change of every repository is committed first: files modified, deleted or new, the ignored ones excepted. The option `--no-commit` turns the automatic commit off for one run, whatever the settings say. The message is `Work in progress, DATE (MACHINE)`, followed by the list of the files; `-m TEXT` or the setting `gh-batch.message` gives another first line, in which `%d` is the date, `%t` the time, `%h` the machine and `%n` the number of files.

Four guards leave a repository uncommitted and name it in the report: a new file whose name suggests a secret (`.env`, a private key, a credentials file, and the like), a file above `gh-batch.maxFileSize` (50 MB), more new files at once than `gh-batch.maxNewFiles` (200, the sign of a missing `.gitignore`), and a folder that is a git repository of its own and is not ignored. The commits that already exist are still pushed. When a commit is refused, by a hook for instance, the staging area is put back exactly as it was.

A repository opts out for good with `git config gh-batch.commit false`, typed inside it: neither the option nor the general setting overrides that. With `git config gh-batch.pullOnly true` a repository is neither committed nor pushed, which suits the clone of somebody else's project.

**The push itself** sends the branch where `git push` would send it and never forces. A branch that exists on this machine only is reported, and published only with `--set-upstream`. Only the branch that is checked out is pushed; another local branch with unpushed commits is named in the report. When GitHub answers that the account has no right to push, or that the repository is archived, nothing is tried.

**When the server has newer commits**, they are first taken exactly as `pull` would take them, under the same setting `gh-batch.diverged`, and the push is tried once more. A conflict on the way is undone and reported, and the commit just made stays on this machine. With the default setting `report`, a repository whose last fetch already showed such commits is neither committed nor pushed, since the push would be refused: the plan names it, and `gh-batch sync`, which pulls first, is the command for it.

### commit

The command `gh-batch commit` is the commit on its own, for the moment in the day when the work should be recorded and not yet sent. It commits every pending change of every repository (files modified, deleted or new, the ignored ones excepted) under one message, the same one for the whole run. The list of files is shown first. The first line is then asked for:

```text
Commit message [A Regular Commit to Synchronise], or - to do nothing:
```

Enter takes that sentence. A line that is typed replaces it. A minus sign alone, or the end of the input, does nothing. The list of the files follows the first line in the commit, as it does for the evening commit. The option `-m TEXT` gives the first line in advance, and the question is then the usual confirmation; `%d` is the date, `%t` the time, `%h` the machine and `%n` the number of files. When `gh-batch.message` has been set, that text replaces the sentence, in the question and in the commit. Without a terminal the run needs `--yes`. With `gh-batch.confirm false` nothing is asked.

The four guards of the evening commit apply here too, and a refusal by a hook puts the staging area back as it was. A repository that sets `gh-batch.commit` to false, or `gh-batch.pullOnly`, is left alone. A detached HEAD is left alone. A repository without a remote is committed, and the report says that the commit stays on this machine. The evening push is unchanged: it still commits only when asked, and then under its own line, `Work in progress, DATE (MACHINE)`, unless `-m` or `gh-batch.message` says otherwise.

The form `gh-batch commit push` runs the push once the commits are made. The push has its own list and its own confirmation, including the commits that were already waiting. Declining it leaves the new commits on this machine. The word `push` is that request. A folder or a repository that is itself named push is given as a path, for example `./push`, or after `--`.

### sync

The command `gh-batch sync` runs the pull, prints its summary, then runs the push with its list and its confirmation. It accepts the options of both, and the line `gh-batch pull push` is the same.

### Several commands on one line

Commands can follow one another on one line, on the same repositories, each with its own report and its own question. They run in the order typed, as in the line `gh-batch pull commit push thesis` of the day above. Each command is the one described in its own section, with its plan, its guards and its confirmation: a line only spares the typing, never a question.

```bash
gh-batch pull commit push thesis notes   # bring both forward, commit with the message asked for, push
gh-batch clone pull status               # clone what is missing, bring everything forward, show what remains
gh-batch fetch status thesis             # look at the server and at what is pending, change no file
gh-batch status log                      # what is pending, then what was done today
```

A commit followed by a push is the form `commit push` of the section on commit, and a pull followed by a push is `sync`. The command `fetch` changes no file: on a line it says what `pull` would do, and `pull` is the one that brings the repositories forward, while `push` itself takes the new commits of the server before it sends yours. When `clone` is on the line, it reads the whole account and its organisations, as it does without owners, and the folders or names of the line belong to the other commands: `gh-batch clone pull status` clones what is missing, then brings everything forward and shows what remains.

A question answered no ends the line there: what was done stays done, and nothing after it starts. An interrupt ends it too. A repository that needs you in one command does not stop the next ones, since each repository is handled on its own, and the exit status is then 1. A name that matches nothing stops the line before its first command, the clone included. Each command comes once. The option `-u`, which means `--update` to clone and `--set-upstream` to the others, is written in full on such a line, and `--manifest` belongs to clone or to list alone. Every word that names a command is a command, so a folder or a repository named like one, such as `status` or `log`, is given as a path or after `--`. When such a word is also a folder where the line is typed, the run stops before anything is done rather than guess which was meant.

### reset

The command `gh-batch reset` sets the branch of every repository to the branch it follows on its server. It does what `git fetch` followed by `git reset --hard @{u}` does by hand, without the losses that a hard reset can cause: it throws away uncommitted changes, overwrites the untracked files that stand in its way, and leaves the commits it drops in the reflog only, until git clears it. After the fetch, a repository that is level with its server is left as it is, and one whose server only has new commits is moved forward, as `pull` would move it. A branch that holds commits which the server lacks is not moved: the report gives their number and their first subjects, and the reset waits for the option `--discard-local`. With that option the plan is shown, one confirmation is asked (`--yes` skips it), and the branch and its files are then set to those of the server.

Before any branch moves, its commit is kept under a reference of its own, `refs/gh-batch/before-reset/BRANCH/DATE-TIME`, and the report prints the one command that puts the branch and its files back. A repository with uncommitted changes to tracked files is left alone, and so are a detached HEAD, an operation in progress, a branch that follows nothing and a repository without remote. Untracked and ignored files are never deleted or overwritten: one that stands where the server has a file is moved, whole, into `.git/gh-batch/kept/DATE-TIME/`, as `pull` does, and the report names it. Nothing is pushed, and `--dry-run` fetches and only says what would be done.

The command was made for a history rewritten on the server. Here a folder of data was removed from every commit of a paper with `git filter-repo`, on another machine, and the result was pushed by force. This clone still holds the three old commits, which the server no longer has, so `pull` reports it as diverged, and with `gh-batch.diverged rebase` it would try to replay them. The command `reset` recognises the rewrite and leaves the clone alone:

```text
$ gh-batch reset
gh-batch reset: 3 repositories under ~/workspace

  diverged      paper-solitons  main     the history of the server was rewritten; 3 commits here that the server lacks, and 2 new ones there: left to you (--discard-local drops those here)
        0673a4d Add the figures of section 4
        e6e7a01 Write the introduction
        86a09ec Add the data of the experiments

3 repositories: 2 level with the server, 1 diverged.
Needs you: paper-solitons (diverged).
```

With `--discard-local` the clone takes the new history:

```text
$ gh-batch reset --discard-local --only paper-solitons
gh-batch reset: 1 repository under ~/workspace

Plan:
  to do         paper-solitons  main     the history of the server was rewritten; drop 3 commits that the server lacks, and take 2 new ones
        0673a4d Add the figures of section 4
        e6e7a01 Write the introduction
        86a09ec Add the data of the experiments

To do: a reset in 1 repository, dropping commits that the server lacks.
Proceed? [Y/n]

Done:
  reset         paper-solitons  main     the history of the server was rewritten; dropped 3 commits that the server lacks, took 2 new ones; the commit before is kept as refs/gh-batch/before-reset/main/20261114-201514
        to restore: git -C ~/workspace/paper-solitons checkout --no-track --no-overwrite-ignore -B main refs/gh-batch/before-reset/main/20261114-201514

1 repository: 1 reset.
```

The files that only the old commits held, the removed folder among them, leave the working tree, and the backup keeps them. One of them comes back on its own, as an untracked file, with `git restore --source=REF -- PATH`, where `REF` is the name of the backup. The backups of a repository are listed by `git for-each-ref refs/gh-batch`, and `gh-batch tidy` removes those older than a month.

When `gh-batch.diverged` is `rebase` or `merge`, `pull` does the same by itself in the one case where nothing of this machine is at stake: the history of the server was rewritten, and every commit here that the server lacks was once on it. Commits made here after the old history still wait for `reset --discard-local`.

### tidy

The backups that `reset` and `pull` keep, and the folders of files that made way for the version of the server, stay until they are removed. `gh-batch doctor` lists them, as a note while they are recent and as a warning once the oldest is older than a week (`--days N`). The command `gh-batch tidy` removes those older than a month: the list is shown first, one confirmation is asked (`--yes` skips it), and a backup goes only if it still names the commit it was made for. `--days N` sets another age, `--days 0` removes everything that the tool kept, and `--dry-run` only shows the list. Stashes are never touched.

```text
$ gh-batch tidy
gh-batch tidy: 7 repositories under ~/workspace

Plan:
  to do         thesis        main     remove 2 backups and 1 folder of kept files, the oldest from 14 October 2026
        before-pull/main/20261014-081502
        before-reset/main/20261015-201514
        .git/gh-batch/kept/20261014-081502

To do: remove what gh-batch kept in 1 repository, up to 17 October 2026.
Proceed? [Y/n]

Done:
  tidied        thesis        main     removed 2 backups and 1 folder of kept files

7 repositories: 1 tidied, 6 clean.
```

### clone

In its first form the list comes from GitHub, through `gh`: every repository of the account that `gh` is logged in to and of the organisations it belongs to, or of the owners named on the command line (accounts or organisations).

```bash
gh-batch clone                      # what is missing of your account and of its organisations
gh-batch clone --no-orgs            # of your account alone
gh-batch clone my-organisation      # of one owner alone, account or organisation
gh-batch clone --since 2026-01-01   # only what was pushed this year
gh-batch clone --update             # and pull what is present already
```

A repository counts as present when one of the clones under the destination has it as a remote, whatever the name and the depth of its folder, and also when it was renamed or transferred on GitHub since. The missing ones go to `DEST/name` for the account itself and to `DEST/folder/name` for any other owner; `--flat` puts every owner at the top, and `--by-owner` gives the account a folder too. The destination is `--into DIR`, else the folder of `gh-batch.root`; a mass clone never falls back on the current folder. The filters are `--only GLOB`, `--except GLOB`, `--since DATE`, `--no-forks` and `--no-archived`.

**The folder of an organisation** is asked for once. The first time an organisation of the account has something to clone, the tool proposes a folder, the one where clones of that organisation already are, else its name on GitHub, and waits: Enter takes it, another name replaces it, and a minus sign leaves the organisation out. The answer is kept in git's configuration, so the question does not return.

```text
$ gh-batch clone
3 repositories of the organisation Hydrodynamics Laboratory (hydro-lab) are missing here.
Folder for the organisation under ~/workspace [hydro-lab], or - to leave it out: lab
(kept: git config --global gh-batch.hydro-lab.folder lab)

gh-batch clone: 8 repositories of ada and hydro-lab on GitHub; 5 already under ~/workspace, 3 to clone

Plan: clone 3 repositories into ~/workspace (about 14 MB)
  lab/flume-data      private  12 MB
  lab/group-meetings  private  under 1 MB
  lab/wave-tank       PUBLIC   2 MB
Proceed? [Y/n]
```

The same choices can be typed by hand: `gh-batch.OWNER.folder NAME` names the folder of an owner, and holds also when that owner is named on the command line; `gh-batch.OWNER.skip true` leaves an organisation out until it is named. A folder is a path below the destination, no deeper than the other commands search (`a/b` at most with the default depth of three), and a dot stands for the destination itself. With `--yes`, with `--dry-run` or without a terminal nothing is asked and the folder proposed is taken. The setting `gh-batch.orgs false` keeps `clone` to the account alone, as `--no-orgs` does for one run; `--orgs` reads the organisations for one run all the same. An organisation that GitHub refuses to list is named in the report and does not stop the others.

Four repositories are cloned at a time. Each clone is made under a temporary name beside its place and renamed when it is complete, so an interrupted run leaves nothing half-made, and the leftover of a run that died is removed by the next one. A folder that exists and is not the repository is never touched: it is named in the report. Large files kept with git-lfs are downloaded in a second step, so that a failed download cannot lose the clone.

In its second form the list is a layout file. On one machine, `gh-batch list --manifest` writes one line per repository with its folder, its address and its branch; on another, `gh-batch clone --manifest FILE` clones the missing ones into the same folders, on the same branches. This form needs no `gh` and works with any git server.

```text
$ gh-batch list --manifest
# Layout of ~/workspace, written by gh-batch list --manifest.
# One repository per line: folder, address, branch, separated by tabs.
# "gh-batch clone --manifest FILE" clones the missing ones into the same folders.
lecture-notes	https://github.com/ada/lecture-notes	main
paper-solitons	https://github.com/ada/paper-solitons	main
thesis	https://github.com/ada/thesis	main
wave-solver	https://github.com/ada/wave-solver	main
website	https://github.com/ada/website	main
```

### status and fetch

The command `status` uses no network. It shows what is pending and since when: files changed or new, commits to push, commits behind the last fetch, stashes, an operation left in progress. With `--long` the pending files are listed.

```text
$ gh-batch status
gh-batch status: 7 repositories under ~/workspace

  pending       lecture-notes       main     1 changed, 1 new (the oldest since 0 min)
  local only    scratch             main     no remote: it exists on this machine only
  pending       teaching/exam-2026  main     1 new (the oldest since 0 min)
  pending       thesis              main     1 changed, 2 new (the oldest since 0 min)
  ahead         wave-solver         main     2 commits to push (the oldest since 0 min)

7 repositories: 2 clean, 3 with pending changes, 1 with commits to push, 1 without remote.
```

The command `fetch` asks the servers and says what `pull` would do, without touching a branch or a file: how many commits wait, which files would be set aside, which branches would move, which repositories have diverged.

A fork is compared with the repository it was forked from. When `gh` is installed, `fetch` asks GitHub for the forks of each owner met among the remotes, then compares the branch of each fork with the default branch of its original, and a section at the end names the commits of the original that the fork lacks and those of the fork that the original lacks, with the command that would offer them to it. Nothing is synced, opened or pushed, and `--offline` leaves the question out. `doctor` makes the same comparison, and `status`, which uses no network, shows the last one with its date.

```text
Forks:
  lanyon: the original poole/lanyon has 70 commits that this fork lacks
  NEOLAB: this fork has 2 commits that its original FlorianGallois/NEOLAB lacks; to offer them: gh pr create --repo FlorianGallois/NEOLAB --head dutykh:main
```

### log

The command `log` answers the question of the evening, or of the weekly report: what did I do? Without an option it lists your commits of today on every local branch, each repository with its commits in the order they were made.

```text
$ gh-batch log
  commits       scratch             main     1 commit
        13:42  d27d145  First try
  commits       teaching/exam-2026  main     2 commits
        13:42  b87e3c1  Add the third question
        13:42  3f0bd89  Work in progress, 2026-11-13 (office)
  commits       thesis              main     1 commit
        13:42  c255063  Work in progress, 2026-11-13 (office)
  commits       wave-solver         main     2 commits
        13:42  386a3db  Add the time stepper
        13:42  4ff7be0  Test the time stepper

6 commits in 4 repositories today (7 searched under ~/workspace).
```

The period is set with `--since` and `--until`, in any form git reads (`yesterday`, `monday`, `"2 weeks ago"`, `2026-11-01`). "Yours" means the address that git uses in each repository (`user.email`); `--author TEXT` selects another author and `--all-authors` everybody. A long first line is cut at 100 characters and a repository shows at most 50 commits, unless `--long` is given. With `--porcelain` each commit is one line: the time in seconds, the path, the short hash, the author and the subject.

### exec

The command `exec` runs anything in every repository, several at a time, and prints what it wrote under the name of each repository. The command starts at `--`, or at the first word that is not an option, and keeps the rest of the line. It runs in the top folder of the repository, without a terminal, with `GH_BATCH_REPO` (the path) and `GH_BATCH_NAME` (the name) in its environment.

```bash
gh-batch exec git gc --quiet
gh-batch exec --dirty -- git status --short
gh-batch exec --in ~/papers -- sh -c 'ls *.tex 2>/dev/null | wc -l'
```

The options `--dirty`, `--clean`, `--ahead` and `--behind` keep only the repositories in that state. Because the command starts at the first plain word, a folder, or the name of a repository, is given here with `--in`. A repository where the command succeeded and wrote nothing is only counted, and the exit status is 1 when it failed somewhere.

### doctor

The command `doctor` changes nothing and names what is wrong, or will be.

```text
$ gh-batch doctor
gh-batch doctor: 4 repositories under ~/workspace

  warning       old-course    main     1 warning
        warning: the remote origin moved on GitHub to teaching/course-2024: git remote set-url origin https://github.com/teaching/course-2024
  warning       scratch       main     1 warning
        warning: no remote: the repository exists on this machine only
  warning       thesis        main     1 warning
        warning: 1 stash: what is stashed stays on this machine
  warning       wave-solver   main     1 warning
        warning: ada/wave-solver is archived on GitHub: it takes no push

Around the repositories:
  warning: the folder ~/workspace/drafts holds no git repository within 3 levels: git saves nothing of it

4 repositories: 4 with warnings.
```

A problem makes the exit status 1: an operation left in progress, unresolved conflicts, a branch whose upstream is gone, a password or a token written in the address of a remote (it is never printed), a repository that GitHub does not know, a folder that git refuses to read. A warning does not: no remote, a detached HEAD, a branch that follows nothing, pending changes or unpushed commits older than a week (`--days N`), stashes, a remote renamed or transferred on GitHub (with the command that corrects its address), an archived repository, git-lfs needed and missing, backups and kept files of the tool older than a week (a note while they are recent, shown with `--verbose`). Around the repositories it names the folders that hold no repository, the loose files and the leftovers of an interrupted clone, and the forks are compared with their originals as `fetch` does. GitHub is asked through `gh`, one question per repository; `--offline` leaves those questions out.

### list, config, completion

The command `list` prints the names of the repositories found, their full paths with `--absolute`, or their layout with `--manifest`. The command `config` prints every setting with its value and its source. The command `completion bash` or `completion zsh` prints the completion script, which the installer puts in place.

## What gh-batch never does

It never forces a push, never deletes a branch, never cleans a working tree, never drops a stash of yours and never skips a hook; the only stash it applies is its own, the one that carried your changes over an update. It never deletes or overwrites a file that git does not track: one that stands where the server puts a file is moved, whole, into `.git/gh-batch/kept/`, and named. It never sets a branch back from commits that its server lacks, except in `reset --discard-local`, after one confirmation, and in `pull` when the server rewrote its history and every such commit was once on the server; both keep the commit under a reference of its own first and print the command that restores it. It never leaves a conflict, a half-finished rebase or a half-finished merge behind. It never commits unless the commit command, the option or the setting says so, and then never a repository that opted out. It never pushes a branch onto a branch of another name unless git itself was configured to do so. It never asks a question in the middle of a run: git is run so that a missing password is an error, not a prompt, and its own questions, the folder of an organisation met for the first time and the one confirmation, come before anything is changed. A test of the suite reads the source and fails if a forced push, a hard reset or a cleaning command ever appears in it; `reset` itself moves a branch with a checkout, which refuses to overwrite what git does not track. It never guesses which repository is meant: a name that matches nothing stops the run before anything is done, a part of a name is suggested and never taken, and a word that names a command and also a folder where you stand is refused. A line of several commands never goes past a question answered no, an interrupt, or a command that could not start.

## Settings

The settings live in git's own configuration, so there is no new file to learn. A setting is changed with `git config --global gh-batch.NAME VALUE`, and `gh-batch config` shows them all.

| Setting | Default | Meaning |
|---|---|---|
| `gh-batch.root` | the current folder | The folder searched when none is named, and where the names of repositories are looked up; it may be given several times. |
| `gh-batch.depth` | 3 | Levels searched below each folder. |
| `gh-batch.jobs` | 8 | Repositories handled at the same time. |
| `gh-batch.timeout` | 300 | Seconds after which a silent server is given up. |
| `gh-batch.diverged` | `report` | What `pull` does when both sides have commits: `report`, `rebase` or `merge`. |
| `gh-batch.conflicts` | `report` | What follows a conflict: `report` undoes it; `server` makes the attempt again with the version of the server in the lines that both sides changed, yours kept beside it. |
| `gh-batch.commit` | `false` | Commit pending changes before the push. |
| `gh-batch.confirm` | `true` | Ask once before committing, pushing, cloning or dropping commits. |
| `gh-batch.message` | `Work in progress, %d (%h)` | First line of the commits made by `push --commit`. The command `commit` uses it too, when it has been set; otherwise its sentence is "A Regular Commit to Synchronise". |
| `gh-batch.machine` | the name of the host | The machine named in those commits. |
| `gh-batch.maxFileSize` | 50 | Megabytes above which a file stops the automatic commit; 0 for no limit. |
| `gh-batch.maxNewFiles` | 200 | New files at once above which the automatic commit stops; 0 for no limit. |
| `gh-batch.exclude` | none | A pattern of names to leave out of every command; it may be given several times. |
| `gh-batch.notify` | none | A command that receives the report on its standard input. |
| `gh-batch.notifyOn` | `never` | When to send it: `never`, `attention` or `always`. |
| `gh-batch.orgs` | `true` | Whether `clone` reads the organisations of the account too. |

Two settings concern one owner on GitHub, an account or an organisation, whose name stands in the middle of the key; `clone` writes them when it has asked, and they can be typed by hand.

| Setting | Meaning |
|---|---|
| `gh-batch.OWNER.folder NAME` | The folder below the destination where `clone` puts the repositories of that owner; a dot for the destination itself. |
| `gh-batch.OWNER.skip true` | `clone` leaves that organisation out, unless it is named on the command line. |

Three settings belong inside a repository, where they are typed without `--global`.

| Setting | Meaning |
|---|---|
| `gh-batch.skip true` | No command touches the repository. |
| `gh-batch.pullOnly true` | It is updated, never committed or pushed. |
| `gh-batch.commit false` | It is never committed automatically, whatever the option or the general setting. |

The command line wins over the environment, which wins over the configuration. The environment variables are `GH_BATCH_ROOT`, `GH_BATCH_JOBS`, `GH_BATCH_DEPTH`, `GH_BATCH_TIMEOUT`, `GH_BATCH_DIVERGED`, `GH_BATCH_CONFLICTS`, `GH_BATCH_COMMIT`, `GH_BATCH_CONFIRM`, `GH_BATCH_ORGS`, `GH_BATCH_MESSAGE`, `GH_BATCH_MACHINE`, `GH_BATCH_MAX_FILE_SIZE`, `GH_BATCH_MAX_NEW_FILES`, `GH_BATCH_NOTIFY` and `GH_BATCH_NOTIFY_ON`.

## Reading the report

A report has one line per repository that changed or needs you, in the order of the folders, then one summary line, then the line "Kept aside" with what made way for the version of the server, then the list of those that need you. The repositories where nothing happened are only counted; `--verbose` shows them, and `--quiet` shows nothing but what needs you.

| Word | Meaning |
|---|---|
| `updated`, `rebased`, `merged` | The branch was brought forward by `pull`, or by `reset` for `updated`. |
| `reset` | The branch was set to the one of its server by `reset --discard-local`, or by `pull` after a rewritten history, its commit kept. |
| `tidied` | Old backups and kept files were removed by `tidy`. |
| `up to date`, `level`, `clean`, `nothing` | Nothing to do. |
| `ahead`, `behind`, `pending`, `stash` | Commits to push, commits to pull, uncommitted changes, stashes. |
| `pushed`, `cloned`, `committed`, `to do` | Done by `push`, `clone` or `commit`, or about to be done. |
| `blocked` | New commits wait on the server, and they touch the same lines as uncommitted changes here. |
| `diverged` | Both sides have commits, and they were not reconciled. |
| `conflict` | A rebase or a merge was tried, conflicted, and was undone. |
| `rejected`, `failed` | The server refused the push; a fetch, a push or a clone failed. |
| `not committed` | A guard stopped the automatic commit. |
| `local only`, `no upstream`, `detached`, `gone` | No remote; a branch that follows nothing; no branch; a branch that left the server. |
| `unfinished`, `busy` | An operation is in progress; another git process holds the index. |
| `skipped`, `unreadable` | Set aside by a setting; git cannot read the folder. |

On a terminal every line carries a sign and a colour: a green tick for what was done, a faint dot for nothing to do, yellow arrows and dots for what waits (commits to push, commits to pull, pending changes), a red cross for what needs you; the names are in bold, the branches in cyan, the commits in the yellow of git, and a run of some length says how long it took. The colours are the sixteen of the terminal, so they follow its theme. A report written to a pipe or handed to a command stays plain, `--color never` and the variable `NO_COLOR` turn the colours off, and a terminal that is not UTF-8 gets letters in place of the signs.

The exit status is 0 when nothing needs you, 1 when at least one repository needs you, 2 for a bad invocation, 3 when git or `gh` is missing or another `gh-batch` is at work, and 130 when the run was stopped by a signal. With `--porcelain` each repository is one line of four fields separated by tabs: the state, the path, the branch and the message.

Every move of a branch is recorded with its date in `~/.local/state/gh-batch/journal.tsv`: the fast-forwards, the rebases, the resets, the commits and the pushes, with the commits before and after. The same folder keeps the date of the last pull and of the last push, which `status` shows.

## Runs that nobody watches

A run started by a timer has no terminal, so it tells its result through a command of your choice. That command receives the report on its standard input, and finds the name of the command in `GH_BATCH_COMMAND` and `ok` or `attention` in `GH_BATCH_STATUS`.

```bash
git config --global gh-batch.notify 'tg-ping --title "Repositories"'
git config --global gh-batch.notifyOn attention
```

Here the report goes to Telegram through [tg-ping](https://github.com/dutykh/tg-ping), and only when a repository needs you; `notify-send gh-batch "$(cat)"` would show it on the desktop, and `mail -s gh-batch you@example.org` would send it by mail. The option `--notify` sends the report of one run whatever the setting.

With systemd, two small files in `~/.config/systemd/user/` run the morning update on working days at half past seven. The exit status 1 means that a repository needs you, which is not a failure of the service.

```ini
# gh-batch-pull.service
[Unit]
Description=Morning update of the git repositories

[Service]
Type=oneshot
ExecStart=%h/.local/bin/gh-batch pull --notify
SuccessExitStatus=1
```

```ini
# gh-batch-pull.timer
[Unit]
Description=Morning update of the git repositories, on working days

[Timer]
OnCalendar=Mon..Fri 07:30
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user enable --now gh-batch-pull.timer
```

Such a run needs credentials that git finds without asking: a credential helper for HTTPS, or an ssh agent whose socket the service can see. An evening push by a timer needs `--yes`, and deserves a thought: it would commit and publish whatever is in the folders at that hour.

## How it works

The repositories found are shared among a few workers. Each worker claims the next free repository, handles it, and writes its result to a file; the main program prints the results in the order of the folders as they become available. One job or eight give the same report.

Every long step (a fetch, a push, a clone, a merge, a rebase, a commit) runs in a process group of its own. An interrupt from the keyboard therefore reaches the tool and not the step: the tool ends the network steps at once, since stopping them is harmless, and lets a step that is moving files finish, so that Ctrl-C never leaves a working tree half-updated. A second Ctrl-C stops everything at once. Each network step has a deadline, and a step that stops to wait for the terminal is ended and reported.

Before a repository is moved, the commit, the branch and the pending changes are recorded; after a refusal they are compared, which tells "refused, nothing changed" from "stopped half-way", and the second case is reported as such instead of being hidden. Decisions are taken on commit identifiers read once, not on names that another program could move in the meantime.

One run at a time may change repositories; a second one is refused while the first is alive. The lock, like the claims of the workers, is an exclusive file creation by the shell itself, because the `mkdir` of some systems (the Rust coreutils of recent Ubuntu releases among them) lets two callers create the same folder at the same instant.

## Limits

Submodules are not updated: the repository that holds them is, and git then shows them as changed. A linked worktree is skipped, since its main repository is the one to handle. Only the branch that is checked out is reset and pushed; `pull` also moves forward the other branches that only lack the new commits of the branch of the same name on the server. A repository cloned without its full history is brought forward, but never rebased. Names are looked up under the folders of `gh-batch.root`, as deep as the search goes, and a repository elsewhere is given by its path. The marks, the listing of an account and the remote part of the health check speak to GitHub only; everything else works with any git server. Windows was not tried.

## Tests

The tests need no network and no account. Bare repositories in a temporary folder play the servers, their clones play two machines, and a small program answers in place of `gh`.

```bash
tests/run-tests.sh            # everything
tests/run-tests.sh push       # the groups whose name holds "push"
```

They check each situation named above, and wherever a repository must stay untouched they compare its commit, its branch, its staging area, its files, its references and its stashes before and after. They also run the tool against a server that never answers, send it interrupts in the middle of a fetch, of a checkout and of a clone and in a line of several commands, type names and lines of commands from a folder outside the root, try it under git settings that would change the meaning of a pull, and read its source for commands that must never appear in it. The same suite runs on Ubuntu, on macOS and under the bash 3.2 of macOS at every change.

## Licence

The program is free software under the GNU Lesser General Public License, version 2.1 or later; see the file [LICENSE](LICENSE).

It was written by Dr. Denys Dutykh, Mathematics Department, Khalifa University of Science and Technology, Abu Dhabi, UAE.
