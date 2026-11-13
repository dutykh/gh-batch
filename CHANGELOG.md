<!-- Author: Dr. Denys Dutykh (Mathematics Department, Khalifa University of Science and Technology, Abu Dhabi, UAE). -->

# Changelog

The versions follow semantic versioning: a change that breaks a command line, a setting or the format of `--porcelain` raises the first number.

## 1.0.0, 13 November 2026

First release.

The three commands of the daily routine are there. The command `pull` fetches every repository and moves its branch forward; when both sides have commits it reports, rebases or merges according to `gh-batch.diverged`, and it undoes a conflict so that the repository is left as it was. The command `push` shows what it will do and asks once, commits pending changes behind four guards when `--commit` or `gh-batch.commit` asks for it, pushes each branch to its own destination without ever forcing, and takes the newer commits of the server before a second try. The command `clone` brings what is missing from a GitHub account or from a layout file, each clone under a temporary name until it is complete.

Around them, `sync` chains the pull and the push, `status` shows what is pending without the network, `fetch` says what a pull would do, `log` lists the commits of a period across the repositories, `exec` runs a command in each of them, `doctor` names what is wrong in the repositories, in their remotes and around them, `list` prints the repositories or their layout, `config` prints the settings, and `completion` serves bash and zsh.

The repositories are handled several at a time and reported in the order of the folders. Every long step runs in a process group of its own, so that an interrupt ends the network steps at once and lets a step that moves files finish. The settings live in the configuration of git, the moves of every branch are recorded in a journal, and a report can be handed to a command for the runs that nobody watches.

The installer copies the program or links it from a clone, and the file at the root of the repository also makes it an extension of the GitHub CLI. The tests run without network on Linux, on macOS and under bash 3.2.
