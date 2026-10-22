# dot-game-template

Start a multiplayer game for the TMC platform from here. This repository is a small, complete, networked game — **Coin Grab** — written the way the platform wants a game written, so that the day you push a tag, anybody running a server can install it and anybody with the client can play it without downloading anything but your game.

It needs Godot 4.7 and a Linux or macOS shell for the tools (the game itself runs anywhere Godot does).

## 1. What you get

A 2D arena. Each player is a coloured disc that moves with WASD, the arrow keys or a finger; coins lie around the arena and reappear somewhere else when somebody takes one; the scores are in the corner. **Esc** opens the settings menu and **Tab**, held, shows the scoreboard: everybody's coins, how long they have been on the server and their ping. **M** lists the arenas (the game's maps) and changes to the one you pick; on a server, staff change it and everybody else starts a vote. **Y** opens chat, which also shows what the server says (a vote, somebody joining, an admin). The key under Esc opens the console, where every setting is a command of its own name — `net_stat 2` draws what the connection is doing. `sm` in the console, or `!sm` in chat, is your own mute list: `sm` lists who is here, `sm 2` mutes the second of them for you alone, and nobody is told.

Small as it is, it is the whole shape of a platform game:

- **Server-authoritative.** The server runs the rules and decides every score. Clients send only what they are pressing.
- **Predicted.** Your own disc moves the instant you press a key; the server's answer arrives a round trip later and corrects it if they disagree. Your disc is drawn between its ticks, so it glides on a fast screen, and everybody else is drawn smoothly between the server's updates.
- **Delivered.** It is packaged as a signed *pack* that a server and every player's client download and mount at runtime. Nobody rebuilds a client to play it.
- **Offline too.** Run the project on its own and the same scene plays a single-player game.

| File | What it is |
| --- | --- |
| `game/tpl_game.gd` | The rules and the state. Read this first. |
| `game/tpl_arenas.gd` | The arenas, the game's maps, as data: size, coins, colour. |
| `game/tpl_workshop.gd`, `provides.json` | Subscribed map packs in solo play: what the game accepts and the wiring. |
| `game/tpl_client.gd` | What a player runs: input, drawing, the netcode on a client, the menu and scoreboard, and chat. |
| `game/tpl_view.gd` | Draws the arena, the coins and the players. |
| `game/tpl_server.gd` | The scene a dedicated server loads. |
| `game/tpl_module.gd` | This game as a server module, over dot-game's `DotGameModule`. |
| `game/tpl_paths.gd` | Where the game's own files are, wherever it is mounted. |
| `game/net/tpl_bridge.gd` | Everything that crosses the wire starts or ends here. |
| `game/net/tpl_player_net.gd` | What replicates about a player, and who may simulate them. |
| `game/net/tpl_command.gd` | One tick of a player's input. |
| `game/net/tpl_event.gd`, `tpl_request.gd` | Server-to-client events, client-to-server requests. |
| `game/net/tpl_link.gd` | The four remote calls. |
| `game.yml` | What a server runs when it installs your game. |
| `examples/` | Three suites: the rules, a server and client over a real socket, and the pack rules. |
| `export_presets.example.cfg` | A Web export preset. Copy it to `export_presets.cfg` (the editor rewrites that file, so it is gitignored) before exporting. Keep `cfg/*` in `include_filter`: Godot drops `.yml` from an export, and the addons' defaults in `cfg/addons/` go with it. dot-ci fails a repository without it. |
| `tools/check.sh`, `tools/rename.sh` | The check to run before every push, and the rename. |

## 2. Make it yours

On GitHub, press **Use this template** on this repository and create yours. Or by hand:

```bash
git clone --depth 1 https://github.com/modcommunity/dot-game-template crate-rush
cd crate-rush && rm -rf .git && git init -b main
```

Then give it your own prefix and your repository's name, once:

```bash
tools/rename.sh cr crate-rush
```

That renames every `tpl_` file and every `Tpl` name to your prefix (`game/cr_game.gd`, `CrGame`, the `cr_status` console command) and every `dot-game-template` to your repository's name, in the code and the config. It leaves the Markdown alone: this guide describes the template, and is yours to rewrite. The prefix matters because a game here has no `class_name` (see section 7), so file names are what keep your game's files apart from every other game a server has installed. Use your repository's exact name; the script refuses a name the site would refuse. Put your name in `LICENSE`, then commit.

## 3. Get the addons

The game is built on the dot-* addons (dot-core, dot-net, dot-server, dot-game, dot-menu with dot-ui and dot-settings for the menu and the scoreboard, dot-console for the console, dot-chat for the self-mute list behind dot-ui's chat box, dot-vote for the map menu and the vote on a server, and dot-map for subscribed map packs in solo). They are not copied into your repository: the `/addons/<name>` lines in `.gitignore` are the list, and one script reads it and links them:

```bash
git clone https://github.com/modcommunity/dot-ci ../dot-ci
../dot-ci/scripts/resolve-deps.sh .
```

That clones the addons into `.deps/` (ignored) and links them into `addons/`. It clones only what is missing, so to update them, delete `.deps/` and run it again. To use another addon, add its line to `.gitignore` and run it again; keep the list to what you use.

Working inside the whole family instead? [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap) clones every repository side by side and links every project's addons in one go (`./bootstrap.sh`), this one included.

## 4. Play it offline

```bash
godot --headless --path . --import     # once, and after adding a file
godot --path .
```

WASD or the arrow keys, or hold a finger or the mouse where you want to go.

## 5. A dedicated server and a client, on your machine

The server is [dot-server-deploy](https://github.com/modcommunity/dot-server-deploy), the same tool every server on the platform runs. Beside your game:

```bash
git clone https://github.com/modcommunity/dot-server-deploy ../dot-server-deploy
cd ../dot-server-deploy
./setup.sh
```

`setup.sh` fetches a verified Godot if you have none, links the addons, writes `./server`, and makes a content signing key for this machine (`keys/`). Then publish your game into it as a signed pack and start a server on it:

```bash
mkdir -p content/crate-rush && cp ../crate-rush/game.yml content/crate-rush/
echo '{"exclude_dirs": ["addons", "examples", "tools", ".deps", ".github"]}' > content/crate-rush/pack.json
./server pack crate-rush --source ../crate-rush
./server check --game crate-rush          # boots, mounts it, loads it, exits 0
```

A client downloads the pack from wherever the server says content lives, so serve `dist/` and point the server at it. The shell only mounts packs signed by a key it trusts, so trust this machine's key first (this edits a tracked file in your dot-server-deploy checkout, on purpose):

```bash
python3 -c 'import json; p="client/content.json"; d=json.load(open(p)); d["trusted_keys"]["local"]=open("keys/content.pub").read(); json.dump(d, open(p,"w"), indent=4)'

python3 -m http.server 8000 --bind 127.0.0.1 --directory dist     # one terminal
./server --game crate-rush --port 27015 --content-url http://127.0.0.1:8000   # another
godot --path . -- --connect 127.0.0.1:27015                        # a third: the client
```

Run the last line twice for two players. After changing your game, run `./server pack crate-rush --source ../crate-rush` again and restart the server.

## 6. Change something real

**Coins worth more, players faster.** The numbers are constants at the top of `game/tpl_game.gd`: `COIN_VALUE`, `PLAYER_SPEED`, `PLAYER_RADIUS`. They are used by the server and by the client's prediction alike, which is the point: the server and the client run the same function to move a player (`TplGame.step`), so change it in one place.

**Make the player wait for something.** The first thing `_ready` in `game/tpl_client.gd` does is add dot-game's `DotGameClient`, the platform layer every game client has: dot-core's loading cover (`platform.gate`, a `DotLoadGate`), then, from `platform.setup()`, the settings and Escape menu, the console, the HUD in the player's theme, Tab for the board, M for the map menu, and input held while the cover is up, a menu is open or chat is being typed (`platform.is_input_blocked()`). It needs dot-game API level 9 and dot-core API level 10, which `package.sh` writes into `requires.json` for you. The cover is closed until the player has joined and lifts by itself, so the player never sees an empty arena or steers before the server has placed them. Add your own holds on `platform.gate`: `gate.hold(&"map", "Loading the map")` when you start building something, `gate.release(&"map")` when it is built (hold again on each map change), `gate.require(&"reason", func() -> bool: return ready, "text")` for a condition asked every frame, and `gate.freeze(body)` to stop a body until the cover lifts. A 3D game leaves `platform.require_camera` at its default, so the cover also waits for the first camera, and leaves `platform.capture_pointer` on so the mouse turns the view; Coin Grab is 2D and turns both off. Every piece of `DotGameClient` can be switched off or replaced; dot-game's README lists them.

**Hazards: a player behind their loading cover can't be harmed.** The server knows which players are still behind their client's cover (a joining player, or everybody after a map change), because a player who can't see or steer must not lose anything to a hazard, and must not take anything either. Ask the question at the one place your game acts on a player: Coin Grab has no damage, so its choke point is `TplGame.collect`, which starts with `if not can_be_harmed(who.id): return -1`. `game/tpl_module.gd` hands the world dot-game's `can_be_harmed` (`world.harm_gate = can_be_harmed`), and the same line goes wherever you apply damage, eliminate a player, count a fall or let a round count the living. Use `can_peer_be_harmed(peer_id)` if what you hold is a peer id, or give your world object a `var peer_loading_fn: Callable` and dot-game fills it in. Bots and a listen server's own player are never loading, and the state ends by itself after `load_timeout_sec`. `examples/headless_net.gd`'s "a player behind their loading cover collects nothing" section shows it over a real socket, and `tools/render_cover.sh` renders the cover and the first frames after it.

**A new arena.** Add a row to `LIST` in `game/tpl_arenas.gd`: an id, a name, a size no bigger than `TplGame.ARENA`, a coin count and a floor colour. It is in the M menu and on the server's vote with nothing else to change. An arena with walls or obstacles in it is where `TplGame.step` grows them, and stays pure: give it the arena, never anything one machine knows and another does not.

**Accepting Workshop content.** A player can subscribe to map packs on the site, and the next solo launch downloads and lists them. A game takes none until it says so: `provides.json` at the repository root has `accepts` (`"kinds": ["map"]` and the `map_kinds` you play, here `coin_arena`). `game/tpl_workshop.gd` is the whole wiring, about 80 lines: it follows dot-core's shared `DotContentIndex` through dot-map's `DotMapCatalogue.follow_content`, reads each accepted pack map and adds it to `TplArenas.workshop`, so M lists it as "Name [Pack]" and `change_arena` plays it like any arena. Because an arena here is a row of numbers, a pack's map entry points `scene` at a small JSON document (`{"id", "name", "size": [w, h], "coins", "floor": [r, g, b]}`, checked and refused with a reason in the log if it does not fit `TplGame.ARENA`); a game whose maps are scenes loads `map.scene_path` instead. Your own ids win over a pack's. **Solo only, on purpose**: the client follows the index only offline, and a server never does, so online lists none, and the vote keeps naming `TplArenas.LIST` (an arena id is the wire, and a player's subscription is not on the server). `examples/headless_workshop.tscn` checks the lot, and `tools/shot_workshop.tscn` renders a pack map. Rename `coin_arena` and the document format for your game; the rest copies as it is.

**Something new the server tells players** — say, a line when somebody takes a coin:

1. In `game/net/tpl_event.gd`, add `PICKUP` to the **end** of `enum Kind`.
2. In `game/net/tpl_bridge.gd`, send it from `_on_coin_moved` with `_tell(peer, TplEvent.Kind.PICKUP, body)`, writing what it carries into `body` with a `DotNetWriter`.
3. In the same file's `_on_event`, add a `TplEvent.Kind.PICKUP:` branch that reads the same fields, in the same order, with a `DotNetReader`.

The rule for anything on the wire is **append only**: add kinds at the end of the enum, add fields at the end of a body, and read a field you added later only `if reader.has_more()`. Never reorder, retype or remove one — the number of a kind and the position of a field ARE the wire, and a reordered enum makes an older reader see a COIN as a SPAWN. Something that cannot be an append is a new message type with a new name. A server and its players always mount the same version of your pack, so this mostly protects you from yourself; it is also what lets two builds of the platform underneath you meet on one socket. And never add an `@rpc` to `tpl_link.gd`: both ends must declare exactly the same set, or every call between them fails.

**A column on the scoreboard** (deaths, a team, a level): return it from `_game_board_fields(session)` in `game/tpl_module.gd`, which already adds `coins`, and add a column with the same key in `_dress_board` in `game/tpl_client.gd` (and in `board_snapshot`, for solo play). The server sends every player's name, ping and time on the server by itself; your module adds what only your game knows. Teams, a header line, or a board that looks nothing like this one are all options on dot-menu's `DotMenuScoreboard`.

**A setting** (a colour-blind palette, a camera zoom): add it to the schema in `_build_menu` with `DotSettingsDef`, apply it from `settings.applier.on(&"your_key", func(value, _why): ...)`, and add a row for it to a page (`settings.menu.page(&"general").section("Display").add(DotMenuRow.toggle(&"your_key", "Your words"))`). The menu writes the setting and the applier applies it, at start and whenever it changes. It is a console command too, with nothing to add: the console binds every setting in the schema by name.

**Chat with channels of your own** (team chat, a radius): the chat box sends through the server's own chat (`link.send_chat` in `_build_chat`, `game/tpl_client.gd`), which every player hears. For channels, route chat through your game instead with dot-game's `DotGameServices`; the family's bus game (`mg-buses-from-hell`, `bfh_services.gd`) is the short example. A line starting with `!` or `/` is a server command, so `!rtv` already works.

**Something new about each player** (a colour choice, a health bar): declare it in `_register_net_vars` in `game/net/tpl_player_net.gd` and copy it in the three methods below it. dot-net sends only what changed.

Then run the checks (section 7) and play it (sections 4 and 5).

## 7. The pack rules, and what the check catches

A delivered game is mounted inside somebody else's client at `res://dot_cloud/<owner>/<repo>/<version>/`, not at `res://`. Two things that work perfectly in your project break there, silently:

- **No `class_name`, anywhere.** A mounted pack's class names are never registered, so every script that names another by its class fails to compile in the client. Reference your own scripts by relative path: `const CrGame := preload("cr_game.gd")`, `extends "cr_event.gd"`.
- **No bare `"res://<your folder>/..."` in a script.** It resolves against the host, where your file is not. Wrap it where it is defined: `static var CRATE := CrPaths.rebase("res://props/crate.tscn")`. Paths inside `.tscn` and `.tres` files are fine: the publisher rewrites those.

And two more that follow from the same fact: nothing in `project.godot` travels (read keys directly, set physics from code), and `client_scene`, `scene` and `module` in `game.yml` stay relative.

```bash
tools/check.sh           # import, parse every script, run every suite, test the rename
tools/check.sh --quick   # without the rename test
```

`examples/headless_pack.tscn` is the suite that refuses a `class_name` or a bare path, and it plants one of each first to prove it can still see them. `headless_rules` runs the rules with no window; `headless_net` boots a real dedicated server, loads the module by path the way a deployed server does, connects a real client over a real socket, steers it, checks that the move and a collected coin's score reach the client, that a chat line makes the round trip and `!sm` never leaves the client, that M changes the arena solo, and on a server by vote or for staff directly, and that an input packet lost on the way is made up by the copies in the next one. CI runs the parse pass and every `examples/headless_*` suite on each push (`.github/workflows/ci.yml`).

## 8. Publish it

Push a tag:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The release workflow runs the checks, then attaches three files to the GitHub Release: `crate-rush-0.1.0.tar.gz` (the source), `crate-rush-0.1.0-pack.zip` (the game as a pack: imported, without addons, examples or tools, with a `requires.json` — section 10) and `SHA256SUMS`. It signs nothing; the site does.

Then, on the TMC website:

1. **Add your game to the TMC Gaming Platform.** Open the Godot page (`/godot`), press **Add Game!**, pick the Dot collection and game or minigame, and create it. You own its page: its settings, its own categories, which site-wide categories mods and servers under it may use, and who else may manage it (**Permissions**). It comes with a **content asset**, the asset whose releases are your game's packs; its **Repository name** field is the name your pack is published under, so make it your repository's name. It locks once a pack has been published under it. (Already published your game as an asset? Link that asset on the game's **Content** tab instead, and your pack keeps its name.)
2. On the content asset (the game page's **Releases & packs**), open **Releases from a repository**, paste `https://github.com/<you>/crate-rush`, and **Save**.
3. Press **Verify ownership**. Release files are only fetched from a repository you have proven is yours (GitHub only).
4. Switch on **Also fetch the release files** and **Publish as a content pack**, then press **Pull now** (or tick **Check every night**).

The site takes the `-pack.zip` (and only it) from each release and publishes it as a signed pack called **`<your site username>/<repository name>`**, at the tag's version without the `v` — `alice/crate-rush@0.1.0`. Publishing the same tag again makes `0.1.0+r2`; a version is never overwritten. Both halves of the name must be lowercase `a-z`, `0-9`, `-` and `_`, at most 64 characters, with no leading, trailing or doubled `_`; `tmc` and `modcommunity` are reserved. Pack publishing has to be switched on for the site.

## 9. Run it on a server

On any dot-server-deploy server:

```bash
TMC_GAMES=alice/crate-rush ./server              # the newest version
./server --games alice/crate-rush@0.1.0          # or a particular one
```

The server fetches the pack from its content origin (`content_urls` in `cfg/server.yml`, the platform's by default), checks its signature, writes your `game.yml` to `content/crate-rush/game.yml` with the right id and version stamped in, and starts it. Edit that file to change the player count or add cvars; it is never overwritten unless you pass `--refresh`. Who may change the arena from the M menu is the `sv_map_menu_flag` cvar: `generic` (moderators and up) by default, `changemap` for admins only, or empty for everybody; anybody without it gets a vote. At the console the game is `crate-rush` (`changelevel crate-rush`), and your module's commands are there (`cr_status`). Players join it like any other server — from the server browser if it is listed, or by address — and their client downloads your pack as they connect.

## 10. Versions: what "this game needs dot-net API level 2" means

Your pack contains your game and none of the addons: those are in the client and the server that mount it. So a pack built against a newer dot-net than a player's client has would fail to compile there, halfway through loading. To say that in a sentence instead, every addon declares an **API level** (`LEVEL` and `OLDEST` in `addons/<addon>/<addon>_api.gd`), and `package.sh` writes `requires.json` into your pack naming the level of each addon your game uses, as built:

```json
{"format": 1, "addons": {"dot_core": 1, "dot_game": 1, "dot_net": 1, "dot_server": 1}}
```

Before mounting, a client or server compares that against its own addons. If yours needs more than it has, it refuses with "This game needs dot-net API level 2 or newer; this server has level 1" — the server's operator or the player updates, and nothing half-loads. An addon raises `LEVEL` when it adds something a game could use, and raises `OLDEST` when it removes or changes something; a pack built before that is refused by the newer host rather than breaking in it. So: build against the addons your players have (running `resolve-deps.sh` gets the newest), and when a newer addon breaks your game, release again.

To pin it yourself, commit your own `requires.json` at the root; the release then checks that it covers everything the game uses instead of writing one.

## Licence

MIT. See `LICENSE`.
