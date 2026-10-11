# Design

## The shape, and why each piece is the one it is

- **`TplGame` is the whole game, and the same class runs everywhere**: authoritative on a dedicated server and offline, a mirror on a connected client that only moves its own player. A second single-player copy of the rules would be a second game to keep in step.
- **`TplGame.step` is static and pure, because it is what prediction runs.** The server and the owning client call it with the same input for the same delta and agree. Nothing that differs between machines may reach it.
- **The module is a thin `DotGameModule`.** The netcode's four load-bearing settings, the seal, the roster, the tick and the reverse teardown are dot-game's; the template must not show a newcomer a second copy. The tick rate is `Engine.physics_ticks_per_second`, which the server set from `sv_tickrate`, because the module's tick IS the physics frame.
- **The bridge is the only file that names the game and dot-net.** Four things cross the wire, all through one `@rpc` node (`TplLink`) under the node named `Server` on each end: snapshots, inputs, events and requests.
- **A player is `SHARED` authority and `always_relevant`.** SHARED so the owner predicts and the server corrects (SERVER would leave a player a round trip behind their own keys). Always relevant because the arena is one screen; a bigger world wants interest management, and the comment says so.
- **The score is a replicated net var; the coins are events.** Deliberate teaching: state about an entity replicates and recovers from loss for free; a change to the world that is not an entity is an event.
- **READY before anything is sent.** The server seats a player on `client_spawn`, but for a game built into a client that happens before the client scene exists. The client sends READY once `is_playing()`; the server sends the hello, the coins and the roster on it, and handles READY arriving first. A delivered game builds its scene before spawn, but the template has to work both ways, and the suites run it both ways.
- **The client predicts with the DECODED input.** Eight bits per axis on the wire; predicting with the raw float would disagree with the server a little every tick. `client_tick` writes the command, reads it back, and simulates that.
- **Every input packet carries the last five commands** (`INPUT_COPIES`, `DotNetInput.write_batch`/`read_batch`). Inputs go unreliable, and with one command a packet every lost packet was a tick the server ran on the previous command and a correction on the client's screen. The copies come from dot-net's replay history, kept as decoded and not sanitised so a copy re-encodes to the same bits (`TplGame.step` bounds the length itself); the server skips copies of ticks it has already simulated, which would otherwise each count as a late input. `headless_net` drops a packet between a socketless bridge pair to prove it.
- **The client adopts the server's tick and snapshot rates from the hello**, and the engine's physics rate with them: interpolation draws at a fraction through a physics frame, which is a fraction through a tick only while the two rates match.
- **`net.service_scope = &"client"`**, so a server and a client in one process (every suite) do not replace each other's registry entry.
- **Keys are read with `Input.is_physical_key_pressed`, not actions.** `project.godot` does not travel in a pack, so an input map defined there does not exist in the shell that mounts the game.
- **The RPCs are `_rpc_*`, and that is not style.** The first version called one `_input`, which is Node's virtual: "The function signature doesn't match the parent", and every script preloading the link failed to compile.
- **Settings and the console are dot-menu's `DotMenuSettings` and dot-console's `DotConsoleKit`**, the same as every game, so a developer starts with the Escape menu, the Tab board and `net_stat` the players already know.

## The pack rules, enforced in three places

No `class_name`; every `res://` string naming the game's own files goes through `TplPaths.rebase()` where it is defined; `extends`/`preload` relative; `client_scene`, `scene` and `module` relative. The reasoning is dot-server-deploy's [delivery-constraint.md](../../dot-server-deploy/docs/delivery-constraint.md).

1. **`examples/headless_pack.tscn`**, here and in CI, scans every script for a `class_name` and every shipped script for a bare `"res://<a folder the game ships>/…"` outside a `…Paths.rebase("…")` call and outside comments. Both scanners run against a planted violation first, because a scanner gone blind reports a clean tree. It also asserts `rebase_onto` against a mount prefix (idempotent, `user://` untouched), the only way those properties can fail in a build, where `root()` is `res://`.
2. **`tools/check.sh` runs it** with the other suites and the rename test. It is a GDScript suite rather than a shell grep so that CI, which runs `examples/headless_*`, enforces it: a third-party developer's release is built by CI.
3. **dot-server-deploy's `examples/template_client.tscn`** packages this repository's git HEAD with dot-ci's `package.sh --pack --name dot-game-template` exactly as the release does, publishes the zip the way the site does (signed under `someone/dot-game-template`, a run key), stamps `game.yml` with the installer's `stamp_identity`, boots a real host, joins a real client and collects a coin. It is the only place this game runs mounted. **It packages HEAD: commit before believing it.**

## The rename

`tools/rename.sh <prefix> <repo>` rewrites `\btpl` → prefix, `\bTpl` → Prefix and `dot-game-template` → repo in every tracked or new file except Markdown, renames every `tpl_*` file, and deletes `.godot/`.

- **A prefix at all** because a game here has no `class_name`, so its file names are what keep it apart from every other game installed beside it.
- **Markdown is left alone** because the README and this repository's docs describe the template; renaming the guide's own clone URL would make it lie.
- **It refuses a repository name the site's `IsPackSegment` would refuse** (lowercase `a-z0-9-_`, no leading, trailing or doubled `_`), because that name becomes the second half of the pack's id.
- **`tools/check.sh` tests it every run**: copies the tree, links the addons, renames to `cr`/`crate-rush`, fails if any trace of the old names survives outside Markdown, then imports and runs all three suites on the copy. With the `Tpl` substitution dropped the renamed copy still PASSED every suite (the constants are local aliases); only the survivor check caught it.

## Running it locally against a server

A locally published pack is not enough for a local client: the client fetches content from the server's `content_urls` (the platform's origin by default) and mounts only packs signed by a key in `client/content.json`. So the README's step 5 serves `dist/` with `python3 -m http.server`, passes `--content-url`, and adds this machine's key to the shell's trust. It uses plain `./setup.sh` in dot-server-deploy, which links every addon; **`--only-games` derives the addon list from the named games and is the wrong flag for this** ([dot-server-deploy's setup.md](../../dot-server-deploy/docs/setup.md#--only-games-and---skip-games)).
