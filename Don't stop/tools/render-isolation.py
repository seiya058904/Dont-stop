"""Make an input-isolated render copy without changing production mouse behavior."""
import hashlib, os, pathlib, re, shutil

def prepare(source):
    support=pathlib.Path(__file__).resolve().parents[2]/'archive/workspace-support'
    name='current' if source.parent==support.parent.parent else source.parent.name
    target=support/'m8-r1-render'/name/source.name
    def copy_asset(src,dst):
        path=pathlib.Path(src)
        # Only immutable binary assets may be hardlinked; all code/config is copied.
        if path.suffix.lower() not in ['.png','.jpg','.ogg','.mp3','.wav','.ctex','.ttf','.woff','.otf']:
            return shutil.copy2(src,dst)
        try: os.link(src,dst)
        except OSError: shutil.copy2(src,dst)
        return dst
    if not target.exists():
        shutil.copytree(source,target,copy_function=copy_asset,ignore=shutil.ignore_patterns('evidence','docs','shader_cache','editor','__pycache__','*.log'))
    # Refresh all mutable runtime inputs from the measured version.
    for folder in ['autoload','game','ui','tests']:
        for path in (source/folder).rglob('*'):
            if path.is_file() and path.suffix not in ['.png','.jpg','.ogg','.mp3','.wav','.ctex','.ttf','.woff','.otf']:
                dest=target/path.relative_to(source); dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(path,dest)
    shutil.copy2(source/'project.godot',target/'project.godot')
    substitutions=[]
    for path in target.rglob('*'):
        if '.godot' in path.parts or path.suffix not in ['.gd','.tscn','.tres']: continue
        content=path.read_text(encoding='utf-8-sig')
        original=content
        content=re.sub(r'Input\.mouse_mode\s*=\s*Input\.MOUSE_MODE_(?:CONFINED_HIDDEN|CONFINED|CAPTURED|HIDDEN)', 'Input.mouse_mode = Input.MOUSE_MODE_VISIBLE',content)
        # Old unused test scenes are isolated too; never permit an OS cursor warp.
        content=re.sub(r'(?m)^(\s*)(?:get_viewport\(\)|Input)\.warp_mouse\([^\n]*\)',r'\1pass # OS cursor warp disabled in render-only copy',content)
        if content!=original:
            path.write_text(content,encoding='utf-8')
            substitutions.append(dict(path=path.relative_to(target).as_posix(),before=hashlib.sha256(original.encode()).hexdigest(),after=hashlib.sha256(content.encode()).hexdigest()))
        assert not re.search(r'Input\.mouse_mode\s*=\s*Input\.MOUSE_MODE_(?:CONFINED|CAPTURED|HIDDEN)',content),path
        assert not re.search(r'\.warp_mouse\(',content),path
    return target,substitutions
