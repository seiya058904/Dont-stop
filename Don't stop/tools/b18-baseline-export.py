"""Export B17 gameplay with the current read-only B18 measurement harness.

Temporarily restores only this task's performance edits, then restores exact bytes
even if export fails. Never moves the checkout or touches user files.
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
mode = sys.argv[1]
assert mode in ['a3', 'b3']
paths = ['autoload/Demo.gd', 'game/monster/EnemyShot.gd',
         'game/monster/DemoEnemy.gd', 'game/monster/EnemyBarrage.gd', 'game/monster/TacticalEnemy.gd']
paths += ['game/config/M5Content.gd', 'game/monster/BaseMonster.gd', 'game/hero/Hero.gd']
saved = {p: (root / p).read_bytes() for p in paths}
try:
    for name in paths[1:]:
        original = subprocess.check_output(['git', 'show', '46d215f:Don\'t stop/' + name], cwd=root).decode('utf-8')
        if mode == 'b3':
            if name.endswith('EnemyShot.gd'):
                original = original.replace('extends CharacterBody2D', 'extends CharacterBody2D\nstatic var live_count := 0\nconst CAPACITY := 180\nvar registered := false')
                original = original.replace('func _ready():', 'func _enter_tree():\n\tif live_count >= CAPACITY:\n\t\tset_physics_process(false); queue_free(); return\n\tlive_count += 1\n\tregistered = true\n\nfunc _exit_tree():\n\tif registered:\n\t\tlive_count -= 1\n\t\tregistered = false\n\nfunc _ready():')
                original = original.replace('get_tree().get_nodes_in_group("enemy_projectiles").size() >= 180', 'not registered')
            elif name.endswith('DemoEnemy.gd'):
                original = original.replace('get_tree().get_nodes_in_group("enemy_projectiles").size() >= 180', 'preload("res://game/monster/EnemyShot.gd").live_count >= 180')
            elif name.endswith('EnemyBarrage.gd'):
                original = original.replace('get_tree().get_nodes_in_group("enemy_projectiles").size()', 'preload("res://game/monster/EnemyShot.gd").live_count')
        (root / name).write_text(original, encoding='utf-8', newline='')
    demo = saved[paths[0]].decode('utf-8')
    if mode == 'a3':
        demo = demo.replace('\t\tvar previous_stacks = kill_stacks\n', '')
        demo = demo.replace('\t\tif kill_stacks != previous_stacks: refresh()', '\t\trefresh()')
    (root / paths[0]).write_text(demo, encoding='utf-8', newline='')
    (root / f'build/b18-{mode}-web').mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(root / 'tools/b18-run.py'), 'export-'+mode, '--headless',
                    '--export-release', 'Web Release', f'build/b18-{mode}-web/index.html'], check=True)
finally:
    for name, data in saved.items():
        (root / name).write_bytes(data)
