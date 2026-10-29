"""Reproduce the source extraction; never edits the source game."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess

FILES = [
    'core/dotnet_random.gd', 'core/world/endless_generator.gd',
    'core/world/endless_furnishing.gd', 'core/world/endless_floor_data.gd',
    'core/world/endless_node.gd',
    *[f'data/balance/{name}.{suffix}' for name in
      ['endless_scheme', 'endless_furnishing_stats', 'endless_sanity_stats']
      for suffix in ['gd', 'tres']],
    *[f'data/levels/{name}.gd' for name in ['level_def', 'room_def', 'door_def',
      'level_collider_def', 'wall_segment', 'door_opening', 'fog_placement',
      'light_placement_def', 'shadow_stroke_def', 'attic_anchor_def']],
    'data/props/trash_catalog.gd', 'data/props/trash_def.gd',
]

def extract(source, target):
    # Refresh upstream into a separate directory, keeping local edits intact.
    if target.exists() and any(target.iterdir()):
        raise SystemExit('Output directory must be empty; extract to a fresh snapshot directory.')
    (target / 'docs').mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    manifest = {'source_repository': 'https://github.com/samarsky-gamedev/The-way-to-Chekushka',
                'revision': revision, 'text_normalization':'UTF-8 without BOM, LF, single final newline', 'files': [], 'adaptations': [
                    'Remove the theme-dependent runtime trash catalogue load (no game art).',
                    'Keep the unchanged item-ID enum and plant predicate; remove gameplay inventory/assets.'
                ]}
    for name in FILES:
        raw = (source / name).read_bytes()
        text = raw.decode('utf-8-sig').replace('\r\n', '\n').rstrip('\n')+'\n'
        if name.endswith('endless_generator.gd'):
            text, count = re.subn(r'\tif theme in \[2, 3\]:\n\t\tlevel\.trash_catalog = load\([^\n]+\n',
                '\t# Standalone extraction: no runtime trash catalogue / game artwork.\n', text)
            assert count == 1, 'Upstream changed: review the extraction cut.'
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8', newline='\n')
        manifest['files'].append({'path': name, 'source_sha256': hashlib.sha256(raw).hexdigest(),
                                 'extracted_sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    loot = (source / 'core/loot/loot.gd').read_text(encoding='utf-8-sig')
    enum = re.search(r'enum Type \{.*?\n\}', loot, re.S).group(0)
    path = target / 'core/loot/loot.gd'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('class_name Loot\nextends RefCounted\n\n# Plant metadata adapter; identifiers retained from the source game.\n'
                    + enum + '\n\nstatic func is_plant(type: int) -> bool:\n\treturn type in [Type.PLANT_FERN, Type.PLANT_FICUS, Type.PLANT_CACTUS, Type.PLANT_ALOE, Type.PLANT_IVY]\n', encoding='utf-8', newline='\n')
    manifest['files'].append({'path':'core/loot/loot.gd', 'source_sha256': hashlib.sha256((source/'core/loot/loot.gd').read_bytes()).hexdigest(),
                             'extracted_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    (target / 'docs/source_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(f'Extracted {len(manifest["files"])} files from {revision[:12]}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path, help='New/empty directory for the upstream snapshot')
    args = parser.parse_args()
    extract(args.source.resolve(), args.output.resolve())
