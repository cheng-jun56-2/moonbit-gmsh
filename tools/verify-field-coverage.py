"""Independent authored-tag, field-section and Gmsh checks for frame coverage.
The small parser below reads only the self-authored fixture's field sections;
it is a development oracle, not a general MSH parser or production dependency.
"""
from pathlib import Path
import argparse, base64, copy, hashlib, json, shutil, struct, subprocess, tempfile
import gmsh

arg = argparse.ArgumentParser()
arg.add_argument('--evidence', required=True)
args = arg.parse_args()
evidence = Path(args.evidence).resolve()
assert not evidence.exists(), 'Choose a new evidence path'
root = Path(__file__).resolve().parents[1]
host = subprocess.Popen([shutil.which('node') or 'node', str(root/'tools/oracle-host.mjs')],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding='utf-8')
checks, records, gmsh_records = [], [], []

def check(ok, label):
    checks.append(label)
    if not ok:
        raise AssertionError(label)

def api(q):
    host.stdin.write(json.dumps(q, ensure_ascii=False)+'\n')
    host.stdin.flush()
    v = json.loads(host.stdout.readline())
    check(v['ok'], 'public request succeeds')
    return v['result']

def change(data, command, **options):
    return api({'action': 'transform', 'data': data, 'options': {'command': command, **options}})['bytes']

def parse_fields(raw, binary, little):
    pos = raw.index(b'$EndElements\n') + len(b'$EndElements\n')
    frames = []
    def line():
        nonlocal pos
        end = raw.index(b'\n', pos)
        text = raw[pos:end].decode('utf-8')
        pos = end+1
        return text
    while pos < len(raw):
        location = line()[1:]
        check(location in ['NodeData', 'ElementData'], 'independent field marker')
        strings = [json.loads(line()) for _ in range(int(line()))]
        reals = [float(line()) for _ in range(int(line()))]
        integers = [int(line()) for _ in range(int(line()))]
        entries = []
        for _ in range(integers[2]):
            if binary:
                fmt = ('<' if little else '>')+'i'+'d'*integers[1]
                row = struct.unpack_from(fmt, raw, pos)
                pos += struct.calcsize(fmt)
            else:
                parts = line().split()
                row = [int(parts[0]), *map(float, parts[1:])]
            entries.append({'tag': row[0], 'values': list(row[1:])})
        if binary and entries:
            check(raw[pos:pos+1] == b'\n', 'independent binary payload end')
            pos += 1
        check(line() == '$End'+location, 'independent field end marker')
        frames.append({'location': location, 'strings': strings, 'reals': reals,
                       'integers': integers, 'entries': entries})
    return frames

def info(f, index):
    result = {'field_index': index, 'name': f['strings'][0], 'location': f['location'],
            'components': f['integers'][1], 'time_step': f['integers'][0],
            'time': f['reals'][0] if f['reals'] else None, 'entries': len(f['entries']),
            'interpolation_scheme': None, 'partition': f['integers'][3] if len(f['integers']) > 3 else None}
    # MoonBit derived struct JSON omits None option fields; explicit0 remains.
    return {key: value for key, value in result.items() if value is not None}

def binary41_node_order(raw):
    # Compact follows the decoded file's stored nodes, not their pre-encode
    # positions: MSH4.1 groups nodes by entity. Read that order independently.
    pos = raw.index(b'$Nodes\n') + len(b'$Nodes\n')
    def take(fmt):
        nonlocal pos
        row = struct.unpack_from('<'+fmt, raw, pos)
        pos += struct.calcsize('<'+fmt)
        return row
    blocks, total, low, high = take('QQQQ')
    tags = []
    for _ in range(blocks):
        dim, _, parametric = take('iii')
        count = take('Q')[0]
        tags.extend(take('Q'*count))
        pos += 8*count*(3 + (dim if parametric else 0))
    check(len(tags) == total and min(tags) == low and max(tags) == high,
          'independent subset stored-node range/order')
    return tags

gmsh.initialize(readConfigFiles=False)
gmsh.option.setNumber('General.Terminal', 0)
try:
    nodes, elements, omitted = [], [], []
    for i, kind in enumerate([2, 3, 9, 10, 16]):
        _, dim, _, n, coords, _ = gmsh.model.mesh.getElementProperties(kind)
        refs = coords.reshape(-1, dim)
        tags = [10+100*i+7*j for j in range(n)]
        omitted.append(tags[-1])
        nodes.extend({'tag': t, 'xyz': [3*i+float(v[0]), float(v[1]), .03*float(v[0]*v[1])]}
                     for t, v in zip(tags, refs))
        elements.append({'tag': 201+11*i, 'kind': kind, 'nodes': tags, 'entity': 7 if i % 2 == 0 else 9, 'physical': [44]})
        if i == 0:
            elements.append({'tag': 900, 'kind': 15, 'nodes': [999], 'entity': 1})
    nodes.extend([{'tag': 999, 'xyz': [20, 0, 0]}, {'tag': 1000, 'xyz': [21, 0, 0]}])
    fields = []
    for name, step, time, nc, entries, partition in [
        ('温度', 0, None, 1, [{'tag': n['tag'], 'values': [300.0]} for n in nodes], None),
        ('velocity', 0, .25, 3, [{'tag': n['tag'], 'values': [0.0, 0.0, -2.0]} for n in nodes if n['tag'] not in omitted], None),
        ('velocity', 3, .75, 3, [{'tag': n['tag'], 'values': [0.0, 0.0, -4.0]} for n in nodes], None),
        ('tensor', 0, .25, 9, [{'tag': t, 'values': [float(k) for k in range(9)]} for t in [201, 212, 223, 234, 900]], 17),
        ('empty', 0, None, 3, [], None),
    ]:
        integers = [step, nc, len(entries)] + ([] if partition is None else [partition])
        fields.append({'location': 'ElementData' if name in ['tensor', 'empty'] else 'NodeData',
                       'strings': [name], 'reals': [] if time is None else [time], 'integers': integers, 'entries': entries})
    model = {'nodes': nodes, 'elements': elements, 'fields': fields}
    source = api({'action': 'create', 'options': model})['bytes']
    requested = [245, 900, 201, 234, 223, 212]
    subset = change(source, 'subset', tags=requested, version='4.1', binary=True)
    compact = change(subset, 'compact')
    big = change(compact, 'convert', version='4.1', binary=True, little=False)
    narrow = change(compact, 'convert', version='4.1', binary=True, size_width=4)
    by_tag = {e['tag']: e for e in elements}
    selected_elements = [by_tag[t] for t in requested]
    used = {t for e in selected_elements for t in e['nodes']}
    stored_nodes = binary41_node_order(base64.b64decode(subset))
    check(set(stored_nodes) == used, 'independent subset node set')
    nm = {tag: i+1 for i, tag in enumerate(stored_nodes)}
    em = {t: i+1 for i, t in enumerate(requested)}
    stages = [('source22', source, elements, False, True, False, False),
              ('requested41', subset, selected_elements, True, True, False, False),
              ('compactBig64', big, selected_elements, True, False, True, False),
              ('compactLittle32', narrow, selected_elements, True, True, True, True)]
    with tempfile.TemporaryDirectory(prefix='gmsh-field-coverage-', dir=evidence.parent) as temp:
        for stage, data, ordered, binary, little, dense, size4 in stages:
            expected_fields = copy.deepcopy(fields)
            expected_elements = copy.deepcopy(ordered)
            for f in expected_fields:
                f['entries'] = [e for e in f['entries'] if stage == 'source22' or e['tag'] in (used if f['location'] == 'NodeData' else set(requested))]
                if dense:
                    for entry in f['entries']:
                        entry['tag'] = (nm if f['location'] == 'NodeData' else em)[entry['tag']]
                f['integers'][2] = len(f['entries'])
            if dense:
                for e in expected_elements:
                    e['tag'] = em[e['tag']]
                    e['nodes'] = [nm[t] for t in e['nodes']]
            raw = base64.b64decode(data)
            parsed = parse_fields(raw, binary, little)
            check(parsed == expected_fields, 'independent field bytes preserve authored records '+stage)
            catalog = api({'data': data, 'options': {'command': 'field-frames'}})
            check(catalog == [info(f, i) for i, f in enumerate(parsed)], 'catalog exact independent headers '+stage)
            for index, f in enumerate(expected_fields):
                # Mathematical set difference anchored in independently authored
                # full-node connectivity; point/isolated records cannot cover it.
                faces = [e for e in expected_elements if e['kind'] != 15]
                tags_in_order = [t for e in faces for t in (e['nodes'] if f['location'] == 'NodeData' else [e['tag']])]
                required = list(dict.fromkeys(tags_in_order))
                supplied = {e['tag'] for e in f['entries']}
                missing = [t for t in required if t not in supplied]
                for cap in [0, 2, 1000]:
                    q = {'data': data, 'options': {'command': 'surface-field-coverage', 'field_index': index, 'max_missing': cap}}
                    got = api(q)
                    expected = {'field': info(f, index), 'elements': 5, 'skipped_lower_dimension': 1,
                        'required_tags': len(required), 'present_tags': len(required)-len(missing),
                        'missing_count': len(missing), 'missing_tags': missing[:cap],
                        'missing_truncated': len(missing)>cap, 'all_required_tags_present': not missing}
                    check(got == expected, 'independent full-node/face coverage and capped IDs '+stage)
                    records.append({'stage': stage, 'request': q, 'actual': got, 'expected': expected,
                                    'inputSha256': hashlib.sha256(raw).hexdigest()})
            if not size4:
                file = Path(temp)/(stage+'.msh')
                file.write_bytes(raw)
                for v in gmsh.view.getTags():
                    gmsh.view.remove(int(v))
                gmsh.clear()
                gmsh.open(str(file))
                for e in expected_elements:
                    kind, conn, _, _ = gmsh.model.mesh.getElement(e['tag'])
                    check(int(kind) == e['kind'] and list(map(int, conn)) == e['nodes'], 'Gmsh actual full connectivity '+stage)
                views = {gmsh.view.option.getString(int(v), 'Name'): int(v) for v in gmsh.view.getTags()}
                read_frames = []
                for f in expected_fields:
                    if not f['entries']:
                        continue  # Empty frame identity is established by the raw section parser.
                    dtype, tags, values, time, components = gmsh.view.getModelData(views[f['strings'][0]], f['integers'][0])
                    check(dtype == f['location'] and components == f['integers'][1], 'Gmsh actual field kind/components '+stage)
                    check(dict(zip(map(int, tags), map(list, values))) == {e['tag']: e['values'] for e in f['entries']}, 'Gmsh actual sparse data association '+stage)
                    check(time == (f['reals'][0] if f['reals'] else 0.0), 'Gmsh exact/default time '+stage)
                    read_frames.append({'name': f['strings'][0], 'step': f['integers'][0], 'entries': len(tags), 'time': time})
                gmsh_records.append({'stage': stage, 'frames': read_frames, 'fullConnectivityVerified': True})
finally:
    gmsh.finalize()
    host.stdin.close()
    host.wait(timeout=10)
out = {'status': 'PASS', 'gmsh': gmsh.__version__, 'requests': len(records), 'checks': len(checks),
       'assertions': checks, 'records': records, 'actualGmshFiles': gmsh_records,
       'bridgeSha256': hashlib.sha256((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()).hexdigest(),
       'scope': 'Five full surface families, point/isolated extra data, exact 1/3/9-component records and sparse steps, requested/compact tags, caps0/2/1000. Struct verifies all20 field sections; Gmsh verifies actual data in3 supported files. Size_t4 and empty records are not counted as Gmsh frame acceptance; missing-time absence is raw-header evidence, Gmsh defaults it to0.'}
with evidence.open('x', encoding='utf-8') as f:
    f.write(json.dumps(out, ensure_ascii=False, indent=2)+'\n')
print(json.dumps({'status': 'PASS', 'requests': len(records), 'checks': len(checks), 'gmshFiles': len(gmsh_records)}))
