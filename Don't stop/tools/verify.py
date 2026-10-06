"""Timed, isolated local/CI verification; full acceptance never uses a frame limit.

python tools/verify.py verify-fast [--base origin/main]
python tools/verify.py verify-web|verify-native|verify-full|verify-release
CI consumers pass --imported --shard contracts-N|pressure-N after one shared import.
Evidence is retained; every case gets a separate user-data directory.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parent
MANIFEST = json.loads((PROJECT / 'tools/native-cases.json').read_text(encoding='utf-8'))
CASES = {c['id']: c for g in MANIFEST['groups'].values() for c in g['cases']}
SHARDS = {s['name']: s['cases'] for g in MANIFEST['groups'].values() for s in g['shards']}
BASE_FAST = ['B194Contracts', 'P0SaveSanity', 'BaselineRegression']
TARGETS = [
    (r'/(autoload/Demo|ui/SaveDialog|web/loader)', ['R1Persistence', 'R1RecoveryUI', 'B12Save', 'B17Saved']),
    (r'/(ui|fonts|shader)/', ['CampPresentation', 'DeepQuality', 'WeaponVisualPose']),
    (r'/(game/guns|game/bullets|game/config)/', ['M3Weapons', 'B12Catalog', 'B13Catalog']),
    (r'/(game/map|autoload/SceneManager|autoload/Camera)', ['CameraTransitions', 'WebPhysicsContracts', 'B11Stages']),
]

def revision():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def isolated_env(directory):
    directory.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(APPDATA=str(directory), XDG_DATA_HOME=str(directory), XDG_CONFIG_HOME=str(directory / 'config'))
    return env

def command(args, log, timeout, env=None):
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    with log.open('w', encoding='utf-8') as stream:
        try:
            result = subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, env=env)
            code = result.returncode
        except subprocess.TimeoutExpired:
            # subprocess.run waits for the killed child; no orphaned engine remains.
            code = 124
    return code, round(time.perf_counter() - started, 3)

def copy_candidate(destination, imported=False):
    destination.mkdir(parents=True, exist_ok=False)
    paths = subprocess.check_output(['git', 'ls-files', '-z', '--', PROJECT.name], cwd=ROOT).split(b'\0')
    for raw in paths:
        if not raw:
            continue
        source = ROOT / raw.decode('utf-8')
        target = destination / source.relative_to(PROJECT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    # Uncommitted verification tools are allowed locally, with exact source identity
    # recorded separately; tracked product files always come from this same checkout.
    for name in ['verify.py', 'native-cases.json']:
        shutil.copy2(PROJECT / 'tools' / name, destination / 'tools' / name)
    if imported:
        shutil.copytree(PROJECT / '.godot', destination / '.godot', ignore=shutil.ignore_patterns('editor'))
    return destination

def clone_candidate(project, destination):
    # Folding/layout files belong to the editor, not the imported runtime; some
    # exceed Windows MAX_PATH under an isolated checkout and need not travel.
    def ignore(directory, names):
        return ['editor'] if Path(directory).name == '.godot' and 'editor' in names else []
    shutil.copytree(project, destination, ignore=ignore)

def prepare(engine, out, imported):
    t = time.perf_counter()
    project = copy_candidate(out / 'candidate', imported)
    preparation = {'copy_seconds': round(time.perf_counter() - t, 3), 'commit': revision(),
                   'engine_version': subprocess.check_output([engine, '--version'], text=True, encoding='utf-8').strip(),
                   'source_sha256': {p.relative_to(project).as_posix(): digest(p) for p in project.rglob('*') if p.is_file() and '.godot' not in p.relative_to(project).parts}}
    if not preparation['engine_version'].startswith('4.7.2.stable.'):
        raise RuntimeError('Godot must be pinned to 4.7.2 stable')
    if imported:
        if (project / '.godot/candidate-sha').read_text().strip() != revision():
            raise RuntimeError('imported candidate commit differs from tested commit')
    else:
        code, seconds = command([engine, '--headless', '--path', str(project), '--editor', '--import', '--quit'], out / 'import.log', 600,
                                isolated_env(out / 'import-userdata'))
        preparation['import_seconds'] = seconds
        checker = subprocess.run([sys.executable, str(project / 'tools/b194_import_check.py'), str(project), str(out / 'import.log')])
        if code or checker.returncode:
            raise RuntimeError('import failed')
        (project / '.godot/candidate-sha').write_text(revision() + '\n')
    (out / 'preparation.json').write_text(json.dumps(preparation, indent=2))
    return project

def assess(case, code, content):
    checks = len(re.findall(r'^PASS ', content, re.M))
    issues = re.findall(r'^(?:FAIL |SCRIPT ERROR).*', content, re.M)
    marker = case.get('completion_marker')
    complete = not marker or bool(re.search(marker, content, re.M))
    # Stronger than the former PASS>0 gate: preserve the same-commit floor too.
    return dict(success=code == 0 and not issues and checks >= case['min_checks'] and complete,
                exit=code, checks=checks, minimum_checks=case['min_checks'], issues=issues, completed=complete)

def native_shard(project, engine, out, ids):
    out.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    results = []
    evidence_before = {p.relative_to(project).as_posix(): digest(p)
                       for rel in ['docs/iteration/evidence', 'evidence']
                       for p in (project / rel).rglob('*') if p.is_file()}
    try:
        # All processes within a shard share the immutable imported candidate;
        # each shard owns its writable source/evidence and each case owns its save.
        for index, identity in enumerate(ids):
            case = CASES[identity]
            log = out / f'{index:02d}-{case["scene"]}.log'
            args = [engine, '--headless', '--path', str(project), f'res://tests/{case["scene"]}.tscn', '--', *case['args']]
            code, seconds = command(args, log, case['timeout_seconds'], isolated_env(out / f'userdata-{index:02d}'))
            result = dict(id=identity, seconds=seconds, **assess(case, code, log.read_text(encoding='utf-8', errors='replace')))
            results.append(result)
            print(f'{"PASSED" if result["success"] else "FAILED"}: {identity} checks={result["checks"]} seconds={seconds}', flush=True)
            if not result['success']:
                print(log.read_text(encoding='utf-8', errors='replace')[-8000:], flush=True)
                break
    finally:
        # Preserve generated per-fixture evidence, without uploading the whole source/cache.
        for rel in ['docs/iteration/evidence', 'evidence']:
            source = project / rel
            if source.exists():
                for path in source.rglob('*'):
                    if path.is_file():
                        relative = path.relative_to(project)
                        if evidence_before.get(relative.as_posix()) != digest(path):
                            target = out / 'fixture-evidence' / relative
                            target.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copy2(path, target)
        report = dict(commit=revision(), requested=ids, cases=results, wall_seconds=round(time.perf_counter() - started, 3),
                      success=len(results) == len(ids) and all(r['success'] for r in results))
        (out / 'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report

def targeted(base):
    ids = list(BASE_FAST)
    if not base:
        return ids
    files = subprocess.check_output(['git', 'diff', '--name-only', base, '--', PROJECT.name], cwd=ROOT, text=True, encoding='utf-8').splitlines()
    matched = set()
    for file in files:
        if '/tests/' in file:
            scene = Path(file).stem
            ids.extend(c['id'] for c in CASES.values() if c['scene'] == scene and scene not in ['M6EncounterAudit', 'M8Encounters'])
        for pattern, cases in TARGETS:
            if re.search(pattern, file):
                ids.extend(cases)
                matched.add(file)
    # Unknown gameplay changes receive all short contracts, rather than silently
    # guessing coverage. Tests/tools/workflows get their policy checks below.
    if any(file.endswith(('.gd', '.tscn', '.tres', '.godot')) and '/tests/' not in file and file not in matched for file in files):
        ids.extend(SHARDS['contracts-3'])
    return list(dict.fromkeys(ids))

def windows(project, engine, out):
    build = project / 'build/windows'
    build.mkdir(parents=True, exist_ok=True)
    code, wall = command([engine, '--headless', '--path', str(project), '--export-release', 'Windows x64 Release', "build/windows/Don't stop.exe"], out / 'export.log', 600)
    content = (out / 'export.log').read_text(encoding='utf-8', errors='replace')
    files = {p.name: dict(bytes=p.stat().st_size, sha256=digest(p)) for p in build.iterdir() if p.is_file()}
    report = dict(commit=revision(), seconds=wall, files=files,
                  success=code == 0 and not re.search(r'^(ERROR:|SCRIPT ERROR:)', content, re.M)
                  and all(files.get(name, {}).get('bytes', 0) > 0 for name in ["Don't stop.exe", "Don't stop.pck"]))
    (out / 'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report

def web(project, engine, out, tiers, node):
    out.mkdir(parents=True, exist_ok=True)
    build = project / 'build/web'
    build.mkdir(parents=True)
    code, seconds = command([engine, '--headless', '--path', str(project), '--export-release', 'Web Release', 'build/web/index.html'], out / 'export.log', 600)
    content = (out / 'export.log').read_text(encoding='utf-8', errors='replace')
    if code or re.search(r'^(ERROR:|SCRIPT ERROR:)', content, re.M):
        raise RuntimeError('Web export failed')
    identity = out / 'build-identity.json'
    subprocess.run([sys.executable, str(project / 'tools/stamp-build-identity.py'), str(build), revision(), str(identity)], check=True)
    # A kernel-selected port avoids interfering with another developer's server.
    import http.server
    import functools
    import threading
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(build)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/index.html'
    before = {p.name: digest(p) for p in build.iterdir() if p.is_file()}
    specs = [('loader', 'web-loader-check.js', []), ('smoke', 'smoke-web.js', []), ('menu-return', 'web-menu-return-e2e.js', ['20' if tiers else '1'])]
    if tiers:
        specs += [('save-audit', 'save-audit-web.js', []), ('durable-save', 'web-save-durable.js', []), ('aim-core', 'web-aim-e2e.js', ['core']), ('aim-fault', 'web-aim-e2e.js', ['fault']), ('stages-fair', 'web-b11-stagerun.js', [])]
    env = os.environ.copy()
    env.update(E2E_SCREENSHOTS='none', E2E_HEADED='0', E2E_WATCHDOG_MS='1500000' if tiers else '420000')
    def gate(spec):
        name, script, args = spec
        dest = out / name
        code, wall = command([node, str(PROJECT / 'tools' / script), url, str(dest), *args], out / f'{name}.log', 1800, env)
        return dict(gate=name, exit=code, seconds=wall, success=code == 0)
    try:
        # Avoid starving the real-time native encounters/browser renderer locally.
        # CI runs each gate on a separate runner. On one developer machine,
        # multiple software renderers can invalidate the real-time save fixture.
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            results = list(pool.map(gate, specs))
        code, wall = command([node, str(PROJECT / 'tools/verify-pages-deployment.js'), url, revision(), str(identity), str(out / 'identity')], out / 'identity.log', 120, env)
        results.append(dict(gate='identity', exit=code, seconds=wall, success=code == 0))
        if before != {p.name: digest(p) for p in build.iterdir() if p.is_file()}:
            raise RuntimeError('tested Web bytes changed after stamping')
        report = dict(commit=revision(), export_seconds=seconds, gates=results, success=all(r['success'] for r in results))
        (out / 'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        return report
    finally:
        server.shutdown()
        server.server_close()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier', choices=['verify-fast', 'verify-web', 'verify-native', 'verify-full', 'verify-release'])
    parser.add_argument('--godot', default=os.environ.get('GODOT', str(ROOT / 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe')))
    parser.add_argument('--node', default='node')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--base')
    parser.add_argument('--shard', choices=sorted(SHARDS))
    parser.add_argument('--jobs', type=int, default=1)
    parser.add_argument('--imported', action='store_true')
    parser.add_argument('--candidate', type=Path, help='Reuse a previously prepared, same-source imported candidate')
    parser.add_argument('--list-fast', action='store_true', help='Print change-related case identities without running/importing')
    args = parser.parse_args()
    if args.shard and args.tier != 'verify-native':
        parser.error('--shard is only valid for verify-native; full/release must run every shard')
    if args.list_fast:
        print('\n'.join(targeted(args.base)))
        return 0
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    engine = str(Path(args.godot).resolve()) if Path(args.godot).exists() else args.godot
    started = time.perf_counter()
    out = (args.out or ROOT / 'output' / ('verify-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))).resolve()
    out.mkdir(parents=True, exist_ok=False)
    if args.candidate:
        imported_project = args.candidate.resolve()
        record = json.loads((imported_project.parent / 'preparation.json').read_text(encoding='utf-8'))
        if record['commit'] != revision():
            raise RuntimeError('reused candidate commit differs from checkout')
        # Runtime/source identity must still match; tools/docs may change without
        # invalidating imported product resources. Actual test scripts come from ROOT.
        for relative, expected in record['source_sha256'].items():
            if not relative.startswith(('tools/', 'docs/')) and digest(PROJECT / relative) != expected:
                raise RuntimeError('reused candidate source changed: ' + relative)
        project = out / 'candidate'
        clone_candidate(imported_project, project)
        shutil.copy2(PROJECT / 'tools/native-cases.json', project / 'tools/native-cases.json')
        (out / 'preparation.json').write_text(json.dumps(dict(record, reused_from=str(imported_project)), indent=2))
    else:
        project = prepare(engine, out, args.imported)
    reports = []
    if args.tier in ['verify-fast', 'verify-web']:
        reports.append(native_shard(project, engine, out / 'fast', targeted(args.base)))
    else:
        names = [args.shard] if args.shard else list(SHARDS)
        projects = [project]
        for index in range(1, len(names)):
            dest = out / f'candidate-{index}'
            clone_candidate(project, dest)
            projects.append(dest)
        web_project = None
        if args.tier in ['verify-full', 'verify-release']:
            web_project = out / 'web-candidate'
            clone_candidate(project, web_project)
        windows_project = None
        if args.tier == 'verify-release':
            windows_project = out / 'windows-candidate'
            clone_candidate(project, windows_project)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(native_shard, p, engine, out / name, SHARDS[name]) for p, name in zip(projects, names)]
            reports.extend(f.result() for f in futures)
        # Full native/Web workflows run concurrently on GitHub's separate hosts.
        # Locally retain real-time semantics by releasing native load first.
        if web_project:
            reports.append(web(web_project, engine, out / 'web', True, args.node))
        if windows_project:
            reports.append(windows(windows_project, engine, out / 'windows'))
    if args.tier == 'verify-web':
        reports.append(web(project, engine, out / 'web', False, args.node))
    result = dict(commit=revision(), tier=args.tier, wall_seconds=round(time.perf_counter() - started, 3),
                  reports=reports, success=all(r['success'] for r in reports))
    (out / 'results.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(dict(tier=args.tier, wall_seconds=result['wall_seconds'], success=result['success'], evidence=str(out))), flush=True)
    return 0 if result['success'] else 1

if __name__ == '__main__':
    sys.exit(main())
