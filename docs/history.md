# History

What building the template found outside this repository:

- **A delivered artifact is named after the checkout's directory unless `--name` is passed** to dot-ci's `package.sh`. The release workflow passes the repository's name; the first armed run of `template_client` (from a scratch clone called `armclone`) did not, and looked for a zip that was not there.
- **`./setup.sh --only-games <game>` on a fresh dot-server-deploy clone built a server that could not run this template**: the addon list was derived from another game's `.gitignore`, so `dot_game` was not linked, and `./server check` printed `selftest ok` under "Could not find base class DotGameModule". dot-server-deploy's `./server check` now fails on any script error (`TmcScriptWatch`).
- **Every suite total was armed** (off by one, run, exit 1); `headless_net` by not copying the replicated score into the client's player, `headless_rules` by removing the diagonal clamp.
- **The template passed against the addons as they were on GitHub**, not only the local checkouts: a fresh clone, `dot-ci/scripts/resolve-deps.sh`, `tools/check.sh --quick`. Re-check that way after an addon release, since local checkouts are usually ahead.
