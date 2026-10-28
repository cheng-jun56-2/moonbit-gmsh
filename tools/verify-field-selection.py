"""Development oracle for exact section selection, not a general MSH parser.
Calls the real file CLI; independently compares section bytes and geometry,
then asks Gmsh for the original tags/data at their retained time-step indices.
"""
from pathlib import Path
import argparse, copy, hashlib, json, shutil, struct, subprocess
import gmsh

parser = argparse.ArgumentParser()
parser.add_argument('--evidence', required=True)
parser.add_argument('--outputs', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
evidence, output = Path(args.evidence).resolve(), Path(args.outputs).resolve()
assert not evidence.exists() and not output.exists(), 'Choose new output paths'
output.mkdir()
# Resolve before Gmsh changes Windows DLL search state.
node = shutil.which('node')
assert node, 'Node is required'
checks, commands, selections, consumers = [], [], [], []


def check(ok, label):
    checks.append(label)
    assert ok, label


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cli(command, source, options=None, destination=None):
    argv = [node, str(root/'tools/gmsh.mjs'), command, str(source)]
    if options is not None:
        opts = output/f'options-{len(commands)}.json'
        opts.write_text(json.dumps(options, ensure_ascii=False), encoding='utf-8')
        argv.append(str(opts))
    if destination is not None:
        argv.append(str(destination))
    result = subprocess.run(argv, cwd=root, capture_output=True, text=True, encoding='utf-8')
    commands.append({'argv': argv, 'exitCode': result.returncode,
                     'stdout': result.stdout, 'stderr': result.stderr})
    check(result.returncode == 0, 'real CLI succeeds: '+command)
    return result


def fields(raw, binary, little):
    # Authored files end their known geometry before these raw field sections.
    prefix_end = raw.index(b'$EndElements\n') + len(b'$EndElements\n')
    pos, result = prefix_end, []

    def line():
        nonlocal pos
        end = raw.index(b'\n', pos)
        text = raw[pos:end].decode('utf-8')
        pos = end + 1
        return text

    while pos < len(raw):
        start = pos
        location = line()[1:]
        check(location in ['NodeData', 'ElementData'], 'independent field marker')
        strings = [json.loads(line()) for _ in range(int(line()))]
        reals = [float(line()) for _ in range(int(line()))]
        integers = [int(line()) for _ in range(int(line()))]
        entries = []
        for _ in range(integers[2]):
            if binary:
                fmt = ('<' if little else '>') + 'i' + 'd' * integers[1]
                row = struct.unpack_from(fmt, raw, pos)
                pos += struct.calcsize(fmt)
            else:
                parts = line().split()
                row = [int(parts[0]), *map(float, parts[1:])]
            entries.append({'tag': row[0], 'values': list(row[1:])})
        if binary and entries:
            check(raw[pos:pos+1] == b'\n', 'binary record terminator')
            pos += 1
        check(line() == '$End'+location, 'independent field end')
        result.append(({'location': location, 'strings': strings, 'reals': reals,
                        'integers': integers, 'entries': entries}, raw[start:pos]))
    return raw[:prefix_end], result


def create(model, name):
    source = output/(name+'.json')
    source.write_text(json.dumps(model, ensure_ascii=False), encoding='utf-8')
    file = output/(name+'.msh')
    cli('create', source, destination=file)
    return file


model = json.loads((root/'examples/normal_field/source.json').read_text(encoding='utf-8'))
rich = copy.deepcopy(model)
for n in rich['nodes']:
    n.update(dim=2, entity=7, parameters=n['xyz'][:2])
rich['nodes'].append(dict(tag=999, xyz=[2, 2, 2], dim=0, entity=19, parameters=[]))
rich.update(version='4.1', entities=[
    dict(dim=0, tag=19, bounds=[2, 2, 2], physical=[], boundary=[]),
    dict(dim=2, tag=7, bounds=[0, 0, 0, 1, 1, 1], physical=[44], boundary=[])],
    names=[dict(dim=2, tag=44, name='wall'), dict(dim=1, tag=55, name='unused')])
rich['fields'] = [
    dict(location='NodeData', strings=['temperature'], reals=[], integers=[0, 1, 2],
         entries=[dict(tag=10, values=[300]), dict(tag=45, values=[1e-250])]),
    dict(location='NodeData', strings=['velocity', ''], reals=[.25, 5], integers=[3, 3, 7, 17, 99],
         entries=[dict(tag=n['tag'], values=[n['xyz'][0], -0.0, 2]) for n in rich['nodes']]),
    dict(location='ElementData', strings=['stress', 'custom_scheme'], reals=[.5],
         integers=[9, 9, 1, 0, -7], entries=[dict(tag=201, values=list(range(1, 10)))]),
    dict(location='NodeData', strings=['empty'], reals=[], integers=[0, 1, 0], entries=[])]
source = create(rich, 'rich-41-ascii')
big_model = dict(rich, binary=True, little=False)
big = create(big_model, 'rich-41-big')
small_model = dict(model, version='2.2', binary=True, little=True)
small = create(small_model, 'pressure-22-little')
cases = [
    ('nonzero-step', source, rich, False, True, [1]),
    ('reordered', source, rich, False, True, [2, 1, 0]),
    ('geometry-only', source, rich, False, True, []),
    ('retained-empty', source, rich, False, True, [3]),
    ('binary-reordered', big, rich, True, False, [2, 1, 0]),
    ('binary-pressure', small, model, True, True, [1])]
for name, src, expected_model, binary, little, indices in cases:
    dest = output/(name+'.msh')
    cli('select-fields', src, dict(field_indices=indices, binary=binary, little=little), dest)
    before_prefix, before = fields(src.read_bytes(), binary, little)
    after_prefix, after = fields(dest.read_bytes(), binary, little)
    check(before_prefix == after_prefix, name+': entire encoded geometry/metadata unchanged')
    check([f for f, _ in before] == expected_model['fields'], name+': independent source heads/data')
    check([f for f, _ in after] == [expected_model['fields'][i] for i in indices], name+': exact selected heads/data')
    check([raw for _, raw in after] == [before[i][1] for i in indices], name+': original section bytes preserved')
    selections.append(dict(name=name, source=str(src), output=str(dest), indices=indices,
                           sha256=sha(dest), sourceSha256=sha(src)))

gmsh.initialize()
try:
    gmsh.option.setNumber('General.Terminal', 0)
    # Empty sections and unsupported named schemes are byte-identity claims,
    # not assertions about Gmsh's view interpretation/defaults.
    for file, expected_model, indices in [(output/'nonzero-step.msh', rich, [1]),
                                          (output/'geometry-only.msh', rich, []),
                                          (output/'binary-pressure.msh', model, [1])]:
        for v in gmsh.view.getTags():
            gmsh.view.remove(int(v))
        gmsh.clear()
        gmsh.open(str(file))
        tags, xyz, _ = gmsh.model.mesh.getNodes()
        got = {int(t): list(map(float, xyz[3*i:3*i+3])) for i, t in enumerate(tags)}
        check(got == {n['tag']: n['xyz'] for n in expected_model['nodes']}, file.name+': Gmsh all nodes including isolated')
        kinds, etags, connectivity = gmsh.model.mesh.getElements(2)
        check(list(map(int, kinds)) == [9] and list(map(int, etags[0])) == [201]
              and list(map(int, connectivity[0])) == model['elements'][0]['nodes'], file.name+': Gmsh original element and winding')
        if expected_model is rich:
            ntags, _, parameters = gmsh.model.mesh.getNodes(2, 7, returnParametricCoord=True)
            param = {int(t): list(map(float, parameters[2*i:2*i+2])) for i, t in enumerate(ntags)}
            check(param == {n['tag']: n['xyz'][:2] for n in rich['nodes'] if n['tag'] != 999}, file.name+': Gmsh parametric classification')
            check(gmsh.model.getPhysicalName(2, 44) == 'wall', file.name+': Gmsh physical name')
        views = {gmsh.view.option.getString(int(v), 'Name'): int(v) for v in gmsh.view.getTags()}
        check(len(views) == len(indices), file.name+': Gmsh selected view count')
        for i in indices:
            f = expected_model['fields'][i]
            dtype, tags, values, time, components = gmsh.view.getModelData(views[f['strings'][0]], f['integers'][0])
            check(dtype == f['location'] and components == f['integers'][1] and time == f['reals'][0], file.name+': Gmsh original step/time/components')
            check({int(t): list(map(float, row)) for t, row in zip(tags, values)}
                  == {d['tag']: d['values'] for d in f['entries']}, file.name+': Gmsh original data tags and values')
        consumers.append(dict(path=str(file), sha256=sha(file), sourceIndices=indices))
finally:
    gmsh.finalize()
result = dict(status='PASS', cliCalls=len(commands), checks=len(checks), selections=selections,
              commands=commands, checkLabels=checks, gmshFiles=consumers, gmshVersion=gmsh.__version__,
              bridgeSha256=sha(root/'_build/js/release/build/cmd/bridge/bridge.js'),
              scope='six exact-section exports; standalone retained nonzero steps; no old numerical matrix replay')
with evidence.open('x', encoding='utf-8') as stream:
    stream.write(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(dict(status='PASS', cliCalls=len(commands), checks=len(checks), gmshFiles=len(consumers))))
