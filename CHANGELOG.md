<!-- Author: Dr. Denys Dutykh (Mathematics Department, Khalifa University of Science and Technology, Abu Dhabi, UAE). -->

# Changelog

The versions follow semantic versioning: a change that breaks a command line, a setting or the format of `--porcelain` raises the first number.

## 1.2.0, 13 November 2026

The command `clone` reads the organisations of the account. Without an owner on its command line it lists the repositories of the account that `gh` is logged in to and of every organisation that this account belongs to. The account goes to the top of the destination, as before, and each organisation into a folder of its own: the one that the new setting `gh-batch.OWNER.folder` names, else the one where clones of the organisation already are, else its name on GitHub.

The first time an organisation has something to clone, its folder is asked for, before the list and the confirmation: Enter takes the folder proposed, another name replaces it, a minus sign leaves the organisation out, and the answer is kept in git's configuration (`gh-batch.OWNER.folder`, `gh-batch.OWNER.skip`), so the question does not return. A run with `--yes`, with `--dry-run` or without a terminal asks nothing and takes the folder proposed. The option `--no-orgs` and the setting `gh-batch.orgs false` keep `clone` to the account alone, and an owner named on the command line is read alone, as before.

An organisation that GitHub refuses to list is named in the report and does not stop the others. No clone is made below a folder that is itself a repository, at any level between the destination and the clone. The leftovers of a run that died are removed from every folder that is about to receive a clone, and `doctor` sees them one level deeper. While GitHub is asked for its lists, a line says which one is being read. An interrupt that comes while a question waits, the one about a folder or the confirmation, ends the run at once with nothing done, instead of waiting for the end of the line, and the time spent waiting for an answer no longer counts in the duration that a run reports.

## 1.1.0, 13 November 2026

The report is easier to read at a glance. Every repository carries a sign: a tick for what was done, a dot for nothing to do, arrows for commits to push or to pull, a cross for what needs you; the names are bold, the branches cyan, the commits in the yellow of git, the changed files named in words with the colour of their change, and the summary coloured the same way. A spinner shows the progress of a run, and a run of some length says how long it took. The colours are the sixteen of the terminal, so that they follow its theme; a pipe, a notification, `--color never` and `NO_COLOR` keep the plain text, and a terminal that is not UTF-8 gets letters in place of the signs.

## 1.0.0, 13 November 2026

First release.

The three commands of the daily routine are there. The command `pull` fetches every repository and moves its branch forward; when both sides have commits it reports, rebases or merges according to `gh-batch.diverged`, and it undoes a conflict so that the repository is left as it was. The command `push` shows what it will do and asks once, commits pending changes behind four guards when `--commit` or `gh-batch.commit` asks for it, pushes each branch to its own destination without ever forcing, and takes the newer commits of the server before a second try. The command `clone` brings what is missing from a GitHub account or from a layout file, each clone under a temporary name until it is complete.

Around them, `sync` chains the pull and the push, `status` shows what is pending without the network, `fetch` says what a pull would do, `log` lists the commits of a period across the repositories, `exec` runs a command in each of them, `doctor` names what is wrong in the repositories, in their remotes and around them, `list` prints the repositories or their layout, `config` prints the settings, and `completion` serves bash and zsh.

The repositories are handled several at a time and reported in the order of the folders. Every long step runs in a process group of its own, so that an interrupt ends the network steps at once and lets a step that moves files finish. The settings live in the configuration of git, the moves of every branch are recorded in a journal, and a report can be handed to a command for the runs that nobody watches.

The installer copies the program or links it from a clone, and the file at the root of the repository also makes it an extension of the GitHub CLI. The tests run without network on Linux, on macOS and under bash 3.2.
