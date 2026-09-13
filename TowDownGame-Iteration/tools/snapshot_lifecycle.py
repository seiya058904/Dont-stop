"""Bounded, workspace-local test copies; durable evidence lives outside the copy."""
import atexit
import io
import pathlib
import shutil
import subprocess
import tarfile
import tempfile


def remove_owned_tree(target, owner):
    target = pathlib.Path(target)
    if target.is_symlink() or (hasattr(target, 'is_junction') and target.is_junction()):
        raise ValueError(f'Linked cleanup target: {target}')
    target, owner = pathlib.Path(target).resolve(), pathlib.Path(owner).resolve()
    if target == owner or not target.is_relative_to(owner):
        raise ValueError(f'Unsafe cleanup target: {target}')
    if not target.exists():
        return
    # Refuse junctions/symlinks before mutating anything.
    paths = list(target.rglob('*'))
    if any(p.is_symlink() or (hasattr(p, 'is_junction') and p.is_junction()) for p in [target, *paths]):
        raise ValueError(f'Linked directory in cleanup target: {target}')
    for path in sorted(paths, key=lambda p: len(p.parts), reverse=True):
        if path.is_dir():
            path.rmdir()
        else:
            path.unlink()
    target.rmdir()


def allocate(support, milestone, label):
    owner = support / 'test-temp'
    owner.mkdir(parents=True, exist_ok=True)
    target = pathlib.Path(tempfile.mkdtemp(prefix=f'{milestone}-{label}-', dir=owner))
    atexit.register(remove_owned_tree, target, owner)
    return target


def git_baseline(root, destination, revision):
    """Rebuild a pinned baseline, never depend on an old run directory."""
    subprocess.run(['git', 'rev-parse', '--verify', revision+'^{commit}'], cwd=root, check=True, capture_output=True)
    archive = subprocess.run(['git', 'archive', revision, root.name], cwd=root.parent,
                             check=True, capture_output=True).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        members = [m for m in bundle.getmembers()
                   if '/docs/' not in m.name and '/evidence/' not in m.name]
        bundle.extractall(destination, members=members, filter='data')
    baseline = destination / root.name
    # Reuse imported binary assets; all baseline source comes from the pinned Git tree.
    if (root / '.godot').exists():
        shutil.copytree(root / '.godot', baseline / '.godot',
                        ignore=shutil.ignore_patterns('shader_cache', 'editor'))
    return baseline
