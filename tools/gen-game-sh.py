#!/usr/bin/env python3
"""Generate a game's game.sh from tools/game.sh.in and the game's game.conf.

    gen-game-sh.py [--check] [GAME_DIR]      (default: the current directory)

Writes GAME_DIR/game.sh (mode 755). With --check it writes nothing and exits 1 when
game.sh differs from what the template and game.conf produce (CI runs this).

game.conf is KEY=VALUE lines, shell quoting, '#' comments:
  GAME_NAME, PACK, EXTRA_PACKS, SUITES      the settings every game has
  FEATURES="soak weapon_art ..."            blocks of the template to keep (see FEATURES)
  SOAK_ARG (default MAP), SOAK_FLAGS        soak: help-text word, extra godot flags ("--fixed-fps 60 ")
  TIMEOUT_DEFAULT (default 900), TIMEOUT_NOTE   default per-suite timeout and a help-text note
  SUITE_TIMEOUTS="suite=secs ..."           with the suite_timeouts feature
  SUITES_COMMENT                            comment lines above SUITES; use \\n for a newline
  MIN_TIMEOUTS="suite=secs ..."             with min_timeouts: a suite's limit is raised to at least secs
  UI_CHECKS="name ..."                      with ui_checks: tools/verify_ui.sh checks run under xvfb
Further FEATURES: suite_args (`test NAME -- ARGS`), content_links (the .gitignore
"# bootstrap-link:" paths must exist), gitignore_optional (addons under "# bootstrap-optional"
are not required), visual, perf (commands that run tools/visual_check.sh, tools/perf_budget.sh).
Template syntax: '#@if NAME' / '#@else' / '#@end' lines (no nesting) and @{VAR}.
"""
import os, re, shlex, stat, sys

FEATURES = {"soak", "weapon_art", "suite_timeouts", "netchaos", "tool_checks", "min_timeouts", "ui_checks",
            "suite_args", "content_links", "gitignore_optional", "visual", "perf"}
DEFAULTS = {"EXTRA_PACKS": "", "SOAK_ARG": "MAP", "SOAK_FLAGS": "", "TIMEOUT_DEFAULT": "900",
            "TIMEOUT_NOTE": "", "SUITE_TIMEOUTS": "", "MIN_TIMEOUTS": "", "UI_CHECKS": "", "SUITES_COMMENT": "", "FEATURES": ""}
REQUIRED = ("GAME_NAME", "PACK", "SUITES")

def die(msg):
    sys.exit("gen-game-sh: " + msg)

def load_conf(path):
    conf = dict(DEFAULTS)
    for n, line in enumerate(open(path), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"([A-Z_]+)=(.*)$", line)
        if not m:
            die("%s:%d: not KEY=VALUE: %s" % (path, n, line))
        parts = shlex.split(m.group(2))
        conf[m.group(1)] = parts[0] if parts else ""
        if len(parts) > 1:
            die("%s:%d: quote the value" % (path, n))
    for k in REQUIRED:
        if k not in conf:
            die("%s: %s is not set" % (path, k))
    return conf

def render(template, conf):
    feats = set(conf["FEATURES"].split())
    if feats - FEATURES:
        die("unknown FEATURES: %s" % " ".join(sorted(feats - FEATURES)))
    conf = dict(conf, LIMIT='"$limit"' if "min_timeouts" in feats else '"$TIMEOUT"',
                LIMIT_MSG="${limit}" if "min_timeouts" in feats else "${TIMEOUT}",
                SUITE_ARGS_SH=' ${SUITE_ARGS[@]+-- "${SUITE_ARGS[@]}"}' if "suite_args" in feats else "")
    for need, key in (("min_timeouts", "MIN_TIMEOUTS"), ("ui_checks", "UI_CHECKS"), ("suite_timeouts", "SUITE_TIMEOUTS")):
        if need in feats and not conf[key]:
            die("FEATURES has %s but %s is empty" % (need, key))
    conf = dict(conf, SOAK_USAGE=("[%s] [MIN]" % conf["SOAK_ARG"]).ljust(16))
    comment = conf["SUITES_COMMENT"].replace("\\n", "\n")
    conf = dict(conf, SUITES_COMMENT=comment + "\n" if comment else "")
    out, keep, state = [], True, None
    for line in template.split("\n"):
        m = re.match(r"#@(if|else|end)\b\s*(\S*)$", line)
        if m:
            kind, name = m.groups()
            if kind == "if":
                if name not in FEATURES:
                    die("template uses unknown feature " + name)
                keep, state = name in feats, True
            elif kind == "else":
                keep = not keep
            else:
                keep, state = True, None
            continue
        if keep:
            out.append(re.sub(r"@\{([A-Z_]+)\}", lambda mm: conf[mm.group(1)], line))
    return "\n".join(out)

def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv[1:]
    game = os.path.abspath(args[0] if args else ".")
    here = os.path.dirname(os.path.abspath(__file__))
    text = render(open(os.path.join(here, "game.sh.in")).read(), load_conf(os.path.join(game, "game.conf")))
    target = os.path.join(game, "game.sh")
    if check:
        if not os.path.exists(target) or open(target).read() != text:
            sys.exit("game.sh is out of date: run dot-game-template/tools/gen-game-sh.py .")
        return
    with open(target, "w") as f:
        f.write(text)
    os.chmod(target, os.stat(target).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

main()
