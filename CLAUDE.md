# dot-game-template

The repository a third-party developer copies to start a game on the platform. It is a small, complete, playable networked game — Coin Grab — and its README is the guide.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, then dot-game's, dot-net's and dot-server-deploy's own `CLAUDE.md`. This file is what is specific to here.

## What this repository is for, and the budget that follows from it

**Every line in it is a line a stranger will read before they write their first one.** The other games in the family are the reference for what the platform can do; this is the reference for what a game has to do, and nothing else. So the budget is small on purpose — about 1,090 lines of game and 440 of suites — and anything a newcomer does not need to see on day one (chat, voice, moderation, identity, stats, maps, bots, art, sound) is left out and named in the README as the next thing to add, rather than shipped half-explained.

It is the organisation's (`modcommunity/dot-game-template`), not a game author's, because it is part of the platform's front door rather than a game anybody plays for its own sake.

## The shape, and why each piece is the one it is

- **`TplGame` is the whole game, and the same class runs everywhere.** Authoritative on a dedicated server and offline; a mirror on a connected client that only moves its own player. A second single-player copy of the rules would be a second game to keep in step.
- **`TplGame.step` is static and pure, because it is what prediction runs.** The server and the owning client call it with the same input for the same delta and agree. Nothing that differs between machines may reach it.
- **The module is sixty lines over `DotGameModule`.** The netcode's four load-bearing settings, the seal, the roster, the tick and the reverse teardown are dot-game's; the template must not show a newcomer a second copy of them. The tick rate is `Engine.physics_ticks_per_second`, which the server has set from `sv_tickrate`, because the module's tick IS the physics frame.
- **The bridge is the only file that names the game and dot-net.** Four things cross the wire, all through one `@rpc` node (`TplLink`) under the node named `Server` on each end: snapshots, inputs, events and requests.
- **A player is `SHARED` authority and `always_relevant`.** SHARED so the owner predicts and the server corrects; SERVER would leave a player a round trip behind their own keys. Always relevant because the arena is one screen; a bigger world wants interest management there, and the comment says so.
- **The score is a replicated net var; the coins are events.** That is deliberate teaching: state about an entity replicates (and recovers from loss for free), while a change to the world that is not an entity is an event. Both are in the game so both are in front of the reader.
- **READY before anything is sent.** The server seats a player on `client_spawn`, but for a game built into a client that happens before the client scene exists, and anything sent then lands on nothing. The client sends READY once `is_playing()`; the server sends the hello, the coins and the roster on it, and handles READY arriving first. A delivered game builds its scene before spawn and would get away without it; the template has to work both ways, and the suites run it both ways.
- **The client predicts with the DECODED input.** Eight bits per axis on the wire; a client that predicted with the raw float would disagree with the server a little every tick. `client_tick` writes the command, reads it back, and simulates that.
- **The client adopts the server's tick and snapshot rates from the hello**, and the engine's physics rate with them, for the reason g2gfast found: interpolation draws at a fraction through a physics frame, which is a fraction through a tick only while the two rates match.
- **`net.service_scope = &"client"`**, so a server and a client in one process (every suite) do not replace each other's registry entry.
- **Keys are read with `Input.is_physical_key_pressed`, not actions.** `project.godot` does not travel in a pack, so an input map defined there does not exist in the shell that mounts the game.
- **The RPCs are `_rpc_*`, and that is not style.** The first version called one `_input`, which is Node's virtual: *"The function signature doesn't match the parent"*, and every script that preloaded the link failed to compile behind it.

## The pack rules, and the three places they are enforced

No `class_name`; every `res://` string naming the game's own files goes through `TplPaths.rebase()` where it is defined; `extends`/`preload` relative; `client_scene`, `scene` and `module` relative. dot-server-deploy's CLAUDE.md is the history of why.

1. **`examples/headless_pack.tscn`, in this repository and in CI.** Scans every script for a `class_name` and every shipped script for a bare `"res://<a folder the game ships>/…"` outside a `…Paths.rebase("…")` call and outside comments. Both scanners run against a planted violation first, because a scanner that has gone blind reports a clean tree. It also asserts `rebase_onto` against a mount prefix — idempotent, `user://` untouched — which is the only way those properties can fail in a build, where `root()` is `res://` and they are tautologies.
2. **`tools/check.sh` runs it**, with the other suites and the rename test. It is a GDScript suite rather than a grep in the shell script so that CI, which runs `examples/headless_*`, enforces it too — a third-party developer's release is built by CI, not on the machine that has `check.sh` open.
3. **dot-server-deploy's `examples/template_client.tscn`** packages this repository's git HEAD with dot-ci's `package.sh --pack --name dot-game-template` exactly as the release does, publishes the zip the way the site does (signed under `someone/dot-game-template`, key made for the run), stamps `game.yml` with the installer's `stamp_identity`, boots a real host, joins a real client and collects a coin. It is the only place this game runs mounted. **It packages HEAD: commit before believing it.** Armed with a clone whose bridge was reached by `class_name`: *"Identifier "TplBridge" not declared"* in the mount, and the counters fail the run.

## The rename

`tools/rename.sh <prefix> <repo>` rewrites `\btpl` → prefix, `\bTpl` → Prefix and `dot-game-template` → repo in every tracked or new file except Markdown, renames every `tpl_*` file, and deletes `.godot/`. A prefix at all because a game here has no `class_name`, so its file names are what keep it apart from every other game installed beside it. Markdown is left alone because the README and this file describe the template — renaming the guide's own clone URL to the developer's repository would make it lie. It refuses a repository name the site's `IsPackSegment` would refuse (lowercase `a-z0-9-_`, no leading, trailing or doubled `_`), because that name becomes the second half of the pack's id.

`tools/check.sh` tests it every run: copies the tree, links the addons, renames to `cr`/`crate-rush`, fails if any trace of the old names survives outside Markdown, then imports and runs all three suites on the copy. Armed by dropping the `Tpl` substitution: the renamed copy still PASSED every suite (the constants are local aliases), and only the survivor check caught it — which is why that check exists.

## Validating

```bash
tools/check.sh                                              # everything, ~20 s
godot --headless --path . res://examples/headless_rules.tscn   # 17 checks, 4 sections: the rules
godot --headless --path . res://examples/headless_net.tscn     # 14 checks, 5 sections: server + client over a socket
godot --headless --path . res://examples/headless_pack.tscn    # 12 checks, 4 sections: the pack rules
../../tools/screenshot.sh dot-game-template out.png --wait 6   # look at it
```

Every suite shares `examples/suite.gd`: sections entered against sections completed, and a CHECKS total, because a script error aborts a section silently. Each total was armed (off by one, run, exit 1). `headless_net` was armed by not copying the replicated score into the client's player: *"and the client's copy shows the score (0)"*. `headless_rules` by removing the diagonal clamp: *"a diagonal is no faster than a straight line (45.25)"*.

It passes against the addons as they are on GitHub, not only against the local checkouts: a fresh clone, `dot-ci/scripts/resolve-deps.sh`, `tools/check.sh --quick`, all green (2026-09-26, with dot-core, dot-net, dot-server and dot-game each one or two commits behind this tree).

## What building it found, outside this repository

- **A delivered artifact is named after the checkout's directory unless `--name` is passed** to dot-ci's `package.sh`. The release workflow passes the repository's name; the first armed run of `template_client` (from a scratch clone called `armclone`) did not, and looked for a zip that was not there. The suite passes `--name` now.
- **`./setup.sh --only-games <game>` on a fresh dot-server-deploy clone builds a server that cannot run this template**: the addon list is derived from the named game's `.gitignore`, GitHub's copy of the lobby predates its move onto dot-game, so `dot_game` was not linked — and **`./server check` then printed `selftest ok`** with *"Could not find base class DotGameModule"* above it, because a script error inside a mount aborts the mount, not the run. dot-server-deploy's CLAUDE.md already calls `--only-games` a trap; the README's step 5 uses plain `./setup.sh`, which links all of them. `./server check` passing over an unparsed module is worth fixing there.
- **A locally published pack is not enough for a local client.** The client fetches content from the server's `content_urls` (the platform's origin by default) and only mounts packs signed by a key in `client/content.json`, so step 5 serves `dist/` with `python3 -m http.server`, passes `--content-url`, and adds this machine's key to the shell's trust. Verified on a fresh GitHub clone of dot-server-deploy: pack, `./server check`, a headless shell joining over the socket, and a rendered frame of the game inside the shell.

## Not here yet

- **Chat, voice and moderation.** `DotGameServices` is the way (see mg-buses-from-hell's sixty-line `bfh_services.gd`), with `send_chat`/`send_voice` on the bridge. Left out to keep the netcode the only new idea in the first file a developer reads.
- **An exit probe.** The family's `dedicated` suites re-run themselves in a second process to catch "leaked at exit", which no check can read. `headless_net` prints none today; add the probe when the game grows.
- **The site half is described, not run.** Sections 8 and 9 of the README follow website-city's `publish_release.ts` and `pack-id.ts`, and a server installing `someone/dot-game-template` from a site-shaped local origin was run end to end — but no release of this repository has been published through the real site yet, because the repository is not on GitHub yet.
