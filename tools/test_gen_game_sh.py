#!/usr/bin/env python3
"""Self-test of tools/gen-game-sh.py and game.sh.in: every FEATURES block renders, the result
parses, and the behaviours that games rely on (suite args, raised limits, content links,
optional addons, UI checks, visual/perf commands) work against a fake godot.

    python3 -I tools/test_gen_game_sh.py
"""
import os, subprocess, sys, tempfile, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "gen-game-sh.py")
fails = 0


def check(name, ok, detail=""):
    global fails
    print("%s %s" % ("ok  " if ok else "FAIL", name) + ("" if ok else "\n      " + detail))
    fails += 0 if ok else 1


def sh(cmd, cwd, env=None):
    p = subprocess.run(cmd, cwd=cwd, env=dict(os.environ, **(env or {})), capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def script(path, body):
    with open(path, "w") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(path, 0o755)


def make(root, conf, gitignore="/addons/dot_core\n", tools=()):
    os.makedirs(os.path.join(root, "examples"), exist_ok=True)
    os.makedirs(os.path.join(root, "tools"), exist_ok=True)
    os.makedirs(os.path.join(root, "addons", "dot_core"), exist_ok=True)
    open(os.path.join(root, "game.conf"), "w").write(conf)
    open(os.path.join(root, ".gitignore"), "w").write(gitignore)
    for s in ("alpha", "headless_imported"):
        open(os.path.join(root, "examples", s + ".tscn"), "w").write("")
    for t in tools:
        script(os.path.join(root, "tools", t), 'echo "RAN %s $*"\n' % t)
    return sh([sys.executable, "-I", GEN, root], root)


BASE = 'GAME_NAME="T"\nPACK=""\nSUITES="alpha headless_imported"\n'
ALL = BASE + ('FEATURES="soak weapon_art suite_timeouts netchaos tool_checks min_timeouts ui_checks suite_args '
              'content_links gitignore_optional visual perf coldstart"\nSUITE_TIMEOUTS="alpha=5"\n'
              'MIN_TIMEOUTS="headless_imported=3000"\nUI_CHECKS="one two"\n')

with tempfile.TemporaryDirectory() as tmp:
    gd = os.path.join(tmp, "godot")
    env = {"FAKE_LOG": os.path.join(tmp, "log"), "GODOT": gd}
    # A fake godot: logs its arguments and prints a passing summary.
    script(gd, 'echo "ARGS $*" >> "$FAKE_LOG"\necho "1 passed, 0 failed"\n')

    # 1. the plain conf renders none of the optional blocks
    d = os.path.join(tmp, "plain")
    rc, out = make(d, BASE)
    txt = open(os.path.join(d, "game.sh")).read()
    check("plain conf renders", rc == 0, out)
    check("plain conf has no optional blocks", not any(w in txt for w in (
        "MIN_TIMEOUTS", "UI_CHECKS", "SUITE_ARGS", "bootstrap-link", "bootstrap-optional", "visual_check", "perf_budget")))
    check("plain game.sh parses", sh(["bash", "-n", "game.sh"], d)[0] == 0)
    check("--check passes on fresh output", sh([sys.executable, "-I", GEN, "--check", d], d)[0] == 0)
    open(os.path.join(d, "game.sh"), "a").write("# drift\n")
    check("--check fails on drift", sh([sys.executable, "-I", GEN, "--check", d], d)[0] != 0)

    # 2. every feature together renders and parses
    d = os.path.join(tmp, "all")
    rc, out = make(d, ALL, tools=("visual_check.sh", "perf_budget.sh", "verify_ui.sh"))
    check("all features render", rc == 0, out)
    check("all-features game.sh parses", sh(["bash", "-n", "game.sh"], d)[0] == 0)

    # 3. a feature without its setting is refused
    rc, out = make(os.path.join(tmp, "bad"), BASE + 'FEATURES="min_timeouts"\n')
    check("min_timeouts without MIN_TIMEOUTS is refused", rc != 0 and "MIN_TIMEOUTS" in out, out)
    rc, out = make(os.path.join(tmp, "bad2"), BASE + 'FEATURES="nonsense"\n')
    check("unknown feature is refused", rc != 0, out)

    # 4. behaviour against the fake godot
    def run(args, cwd=d, e=env):
        open(env["FAKE_LOG"], "w").close()
        rc, out = sh(["./game.sh", "--no-parse"] + args, cwd, e)
        return rc, out, open(env["FAKE_LOG"]).read()

    rc, out, log = run(["test", "alpha", "--", "--map=X"])
    check("suite args reach the suite", rc == 0 and "alpha.tscn -- --map=X" in log, out + log)
    rc, out = sh(["./game.sh", "suites"], d, env)
    check("suites lists them", out.split() == ["alpha", "headless_imported"], out)
    rc, out = sh(["./game.sh", "visual", "--update"], d, env)
    check("visual runs tools/visual_check.sh", "RAN visual_check.sh --update" in out, out)
    rc, out = sh(["./game.sh", "perf", "--post"], d, env)
    check("perf runs tools/perf_budget.sh", "RAN perf_budget.sh --post" in out, out)

    rc, out = sh(["./game.sh", "coldstart"], d, env)
    check("coldstart without tools/cold_start.tscn is refused", rc == 2 and "cold_start.tscn" in out, out)
    open(os.path.join(d, "tools", "cold_start.tscn"), "w").write("")
    rc, out = sh(["./game.sh", "coldstart", "m1"], d, env)
    check("coldstart passes the map to the scene", "cold_start.tscn -- --map m1" in open(env["FAKE_LOG"]).read(), out)

    # the limit: a fake godot that never ends, run through a fake `timeout` that echoes its limit
    tbin = os.path.join(tmp, "tbin")
    os.makedirs(tbin)
    script(os.path.join(tbin, "timeout"), 'echo "LIMIT $1" >> "$FAKE_LOG"\nshift\nexec "$@"\n')
    env_t = dict(env, PATH=tbin + ":" + os.environ["PATH"])
    rc, out, log = run(["test", "headless_imported"], e=env_t)
    check("min_timeouts raises a short default to the suite's limit", "LIMIT 3000" in log, log)
    rc, out, log = run(["--timeout", "5000", "test", "headless_imported"], e=env_t)
    check("a larger --timeout wins over min_timeouts", "LIMIT 5000" in log and "LIMIT 3000" not in log, log)
    rc, out, log = run(["test", "alpha"], e=env_t)
    check("suite_timeouts sets a suite's own limit", "LIMIT 5" in log.split("\n"), log)

    # 5. content links and optional addons
    d2 = os.path.join(tmp, "links")
    make(d2, ALL, gitignore="/addons/dot_core\n# bootstrap-optional: not needed\n/addons/dot_extra\n"
         "# bootstrap-link: ../maps\n/maps/imported\n", tools=("verify_ui.sh",))
    rc, out, log = run(["test", "alpha"], cwd=d2)
    check("missing content link is refused", rc == 2 and "Content not linked: maps/imported" in out, out)
    os.makedirs(os.path.join(d2, "maps", "imported"))
    rc, out, log = run(["test", "alpha"], cwd=d2)
    check("optional addon is not required, linked content passes", rc == 0, out)
    d3 = os.path.join(tmp, "nooptional")
    make(d3, BASE, gitignore="/addons/dot_core\n# bootstrap-optional: x\n/addons/dot_extra\n")
    rc, out, log = run(["test", "alpha"], cwd=d3)
    check("without gitignore_optional every addon is required", rc == 2 and "dot_extra" in out, out)

    # 6. UI checks run only on a full test, and only with xvfb-run
    ui_log = os.path.join(tmp, "ui")
    script(os.path.join(d2, "tools", "verify_ui.sh"), 'echo "$1" >> %s\necho "VERIFY 3 passed, 0 failed"\n' % ui_log)
    xbin = os.path.join(tmp, "xbin")
    os.makedirs(xbin)
    script(os.path.join(xbin, "xvfb-run"), "exit 0\n")
    env_x = dict(env, PATH=xbin + ":" + os.environ["PATH"])
    run(["test", "alpha"], cwd=d2, e=env_x)
    check("UI checks skipped when suites are named", not os.path.exists(ui_log))
    rc, out, log = run(["test"], cwd=d2, e=env_x)
    ran = open(ui_log).read().split() if os.path.exists(ui_log) else []
    check("UI checks run on a full test", ran == ["one", "two"] and rc == 0, out + str(ran))

print("%d failed" % fails if fails else "all passed")
sys.exit(1 if fails else 0)
