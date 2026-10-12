# dot-game-template

The repository a third-party developer copies to start a game on the platform: a small, complete, playable networked game (Coin Grab), and its README is the guide. It is the organisation's (`modcommunity/dot-game-template`), not a game author's, because it is part of the platform's front door.

Read the family [CLAUDE.md](../../CLAUDE.md) first, then dot-game's, dot-net's and dot-server-deploy's own. The reasoning is in [docs/design.md](docs/design.md).

**Every line here is a line a stranger reads before they write their first one.** The other games show what the platform can do; this shows what a game has to do, and nothing else. The budget is small on purpose: anything a newcomer does not need on day one (chat, voice, moderation, identity, stats, maps, bots, art, sound) is left out and named in the README as the next thing to add, rather than shipped half-explained.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing any game file, the pack rules, `tools/rename.sh`, or the README's local-server steps |
| [docs/history.md](docs/history.md) | what building it found outside this repository |

## Layout

| Path | What |
| --- | --- |
| `game/tpl_game.gd` | the whole game; `step` is static and pure (what prediction runs) |
| `game/tpl_module.gd`, `tpl_server.gd` | the thin `DotGameModule` and the server scene |
| `game/tpl_client.gd`, `tpl_view.gd` | the client (settings through `DotMenuSettings`, console through `DotConsoleKit`) and drawing |
| `game/tpl_paths.gd` | `rebase()` / `rebase_onto()` for delivery |
| `game/net/` | `tpl_bridge.gd` (the only file naming the game and dot-net), `tpl_link.gd` (the one `@rpc` node), `tpl_command.gd`, `tpl_event.gd`, `tpl_request.gd`, `tpl_player_net.gd` |
| `examples/` | `headless_rules`, `headless_net`, `headless_pack`, and `suite.gd` (sections and a CHECKS total) |
| `tools/check.sh`, `tools/rename.sh` | everything, including the rename test; the rename a developer runs first |
| `.gitignore` | the dependency manifest: every `/addons/<name>` line is an addon dot-bootstrap and dot-ci link |

## Running and testing

```bash
tools/check.sh                                                 # every suite, the pack rules, the rename test
godot --headless --path . res://examples/headless_rules.tscn   # the rules
godot --headless --path . res://examples/headless_net.tscn     # server + client over a socket
godot --headless --path . res://examples/headless_pack.tscn    # the pack rules
../../tools/screenshot.sh dot-game-template out.png --wait 6   # look at it
```

Every suite shares `examples/suite.gd`: sections entered against sections completed, and a CHECKS total, because a script error aborts a section silently. dot-server-deploy's `template_client` is the only place it runs mounted, and it packages this repository's HEAD.

## Rules that bite

- Keep it small: a feature a newcomer does not need on day one goes in the README as a next step, not in the code.
- No `class_name`; every `res://` string naming the game's own files through `TplPaths.rebase()`; `extends`/`preload`/scene paths relative. [design](docs/design.md#the-pack-rules-enforced-in-three-places)
- `TplGame.step` is pure; nothing that differs between machines may reach it, and the client predicts with the decoded input. [design](docs/design.md#the-shape-and-why-each-piece-is-the-one-it-is)
- Every input packet carries the last `INPUT_COPIES` commands; the server skips copies at or below `last_consumed_tick`. [design](docs/design.md#the-shape-and-why-each-piece-is-the-one-it-is)
- Nothing is sent to a client before its READY. [design](docs/design.md#the-shape-and-why-each-piece-is-the-one-it-is)
- Read keys with `Input.is_physical_key_pressed`: `project.godot`'s input map does not travel in a pack. [design](docs/design.md#the-shape-and-why-each-piece-is-the-one-it-is)
- RPC methods are named `_rpc_*`, never a Node virtual. [design](docs/design.md#the-shape-and-why-each-piece-is-the-one-it-is)
- The HUD is a full-rect root Control the menu themes and scales (`settings.menu.follow_hud(root, accent)`, by name); put everything the HUD draws under it, and give your accent as a Theme rather than colouring Labels by hand.
- Commit before trusting dot-server-deploy's `template_client`: it packages HEAD. [design](docs/design.md#the-pack-rules-enforced-in-three-places)
- `tools/rename.sh` leaves Markdown alone and refuses a repository name the site cannot use as a pack id; `tools/check.sh` must keep the survivor check. [design](docs/design.md#the-rename)
- Add an addon only by adding its `/addons/<name>` line to `.gitignore` and using it; a pack is checked against the addons it names.
- `project.godot` carries no comments: the editor drops them, and any key left at its default, the first time it saves the file, so the reasons live here. The renderer is `gl_compatibility` because the client shell a published game is mounted into is, a browser being one of its targets. Nothing in that file travels in a pack (not the renderer, the input map or the gravity), so anything the game depends on at runtime is set from code. `[importer_defaults]` keeps new textures at `detect_3d/compress_to=0`, so the editor never re-imports one VRAM-compressed on a first open and leaves the checkout dirty.

## Not here yet

- **Chat, voice and moderation.** `DotGameServices` is the way (mg-buses-from-hell's `bfh_services.gd` is the short example), with `send_chat`/`send_voice` on the bridge. Left out to keep the netcode the only new idea in the first file a developer reads.
- **An exit probe.** The family's `dedicated` suites re-run themselves in a second process to catch "leaked at exit"; add it when the game grows.
- **The site half of the README is described, not run here.** Sections 8 and 9 follow website-city's `publish_release.ts` and `pack-id.ts`, and a server installing `someone/dot-game-template` from a site-shaped local origin was run end to end; a release published through the real site has not been verified from this repository.
