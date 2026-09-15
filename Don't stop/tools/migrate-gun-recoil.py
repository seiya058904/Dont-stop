"""Migrate the remaining guns from the drifting recoil to BaseGun.play_shot_feedback().

Two mechanical edits, applied to game/guns/*.gd (excluding BaseGun.gd, already
done, and BabyZapZap.gd, done by hand):

1. The three-line tween block that animated towards the *current* position
   becomes a single call to the anchored, mutually-exclusive recoil helper.
2. The `_shootAnim` guard now tolerates a null player, matching BaseGun.
"""
import re
import pathlib
import sys

GUNS = pathlib.Path(__file__).resolve().parents[1] / "game" / "guns"

TWEEN_BLOCK = re.compile(
    r'\tvar tween = get_tree\(\)\.create_tween\(\)\.set_parallel\(true\)\n'
    r'\ttween\.tween_property\(self, "position", position, (?P<pos>[^\n]+?)\)\.from\(position \+ Vector2\(-1, -1\)\)\n'
    r'\ttween\.tween_property\(\$Sprite2D, "scale", Vector2\(1,1\), (?P<scl>[^\n]+?)\)\.from\(Vector2\(0\.5, 1\.1\)\)\n'
)

GUARD_OLD = "if not is_use or player.is_dead or get_tree().paused: return"
GUARD_NEW = "if not is_use or not is_instance_valid(player) or player.is_dead or get_tree().paused: return"

SKIP = {"BaseGun.gd", "BabyZapZap.gd"}

def main() -> int:
    problems = []
    changed = []
    for path in sorted(GUNS.glob("*.gd")):
        if path.name in SKIP:
            continue
        text = path.read_text(encoding="utf-8")
        original = text

        for match in TWEEN_BLOCK.finditer(text):
            if match.group("pos") != match.group("scl"):
                problems.append("%s: recoil durations differ (%r vs %r)"
                                % (path.name, match.group("pos"), match.group("scl")))

        text = TWEEN_BLOCK.sub(lambda m: "\tplay_shot_feedback(%s)\n" % m.group("pos"), text)
        text = text.replace(GUARD_OLD, GUARD_NEW)

        if text != original:
            path.write_text(text, encoding="utf-8")
            changed.append(path.name)

    print("changed: %s" % ", ".join(changed) if changed else "changed: none")
    if problems:
        print("PROBLEMS:")
        for line in problems:
            print("  " + line)
        return 1
    return 0

sys.exit(main())
