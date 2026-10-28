"""Finite actual-file audit of the existing STL exporter and IO handoff.
The authored mixed mesh is not printable; no repair/certification is attempted.
Independent rational crosses, Decimal normalization, grammar and meshio readback
check actual emitted facet normals and winding, not just triangle counts.
"""
from pathlib import Path
from decimal import Decimal, localcontext
from fractions import Fraction
import argparse, hashlib, json, math, shutil, subprocess
import meshio

parser = argparse.ArgumentParser()
parser.add_argument('--evidence', required=True)
parser.add_argument('--outputs', required=True)
args = parser.parse_args()
evidence, output = Path(args.evidence).resolve(), Path(args.outputs).resolve()
assert not evidence.exists() and not output.exists(), 'Choose new evidence/output paths'
output.mkdir()
root = Path(__file__).resolve().parents[1]
node = shutil.which('node')
assert node, 'Node is required'
checks, calls, consumers, payload_readbacks = [], [], [], []

def sha(data): return hashlib.sha256(data).hexdigest()
def check(ok, label):
    checks.append(label)
    assert ok, label

def run(kind, argv, expected=0):
    result = subprocess.run([node, *map(str, argv)], cwd=root, capture_output=True, text=True, encoding='utf-8')
    calls.append(dict(kind=kind, argv=[node, *map(str, argv)], exitCode=result.returncode,
                      stdout=result.stdout, stderr=result.stderr))
    (output/'commands.json').write_text(json.dumps(calls, indent=2)+'\n', encoding='utf-8')
    check(result.returncode == expected, kind+': expected exit '+str(expected))
    return result

def create(model_file, destination):
    run('cli', [root/'tools/gmsh.mjs', 'create', model_file, destination])

def example(source, destination, flag=None, expected=0):
    argv = [root/'examples/audited_stl/run.mjs', source, destination]
    if flag is not None: argv.append(flag)
    return run('example', argv, expected)

def parse_stl(file):
    lines = file.read_text(encoding='utf-8').splitlines()
    check(lines[0] == 'solid MoonGmsh' and lines[-1] == 'endsolid MoonGmsh', 'ASCII solid wrapper')
    index, facets = 1, []
    while index < len(lines)-1:
        header = lines[index].split()
        check(header[:2] == ['facet', 'normal'] and len(header) == 5, 'facet normal grammar')
        normal = list(map(float, header[2:]))
        check(lines[index+1] == 'outer loop', 'outer loop grammar')
        vertices = []
        for offset in [2, 3, 4]:
            row = lines[index+offset].split()
            check(row[0] == 'vertex' and len(row) == 4, 'exactly three coordinate vertex tokens')
            vertices.append(list(map(float, row[1:])))
        check(lines[index+5] == 'endloop' and lines[index+6] == 'endfacet', 'facet terminators')
        check(all(math.isfinite(x) for x in normal+[x for point in vertices for x in point]), 'all emitted numbers finite')
        facets.append(dict(normal=normal, vertices=vertices))
        index += 7
    check(index == len(lines)-1, 'all ASCII tokens consumed')
    return facets

def expected_normal(vertices):
    a, b, c = [[Fraction(x) for x in point] for point in vertices]
    u, v = [[y-x for x, y in zip(a, point)] for point in [b, c]]
    cross = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    square = sum(x*x for x in cross)
    if square == 0: return [0.0, 0.0, 0.0]
    with localcontext() as context:
        context.prec = 80
        length = (Decimal(square.numerator)/Decimal(square.denominator)).sqrt()
        return [float((Decimal(x.numerator)/Decimal(x.denominator))/length) for x in cross]

def close_vector(a, b):
    return len(a) == len(b) and all(math.isclose(x, y, rel_tol=1e-14, abs_tol=1e-14) for x, y in zip(a, b))

def consume_bundle(bundle, source, expected_vertices, expected_policy):
    manifest = json.loads((bundle/'manifest.json').read_text(encoding='utf-8'))
    check(manifest['inputSha256'] == sha(source.read_bytes()), 'manifest actual source identity')
    check(manifest['policy'] == expected_policy, 'manifest explicit policy')
    check(set(manifest['outputs']) == {'surface.stl', 'audit.json'}, 'manifest pairs STL and audit')
    check({f.name for f in bundle.iterdir()} == {'surface.stl', 'audit.json', 'manifest.json'}, 'bundle exact file set')
    for name, digest in manifest['outputs'].items():
        check(sha((bundle/name).read_bytes()) == digest, 'payload SHA readback '+name)
        payload_readbacks.append(dict(path=str(bundle/name), sha256=digest))
    facets = parse_stl(bundle/'surface.stl')
    check([f['vertices'] for f in facets] == expected_vertices, 'every emitted triangle retains expected vertices/order/winding')
    normals = []
    for i, facet in enumerate(facets):
        wanted = expected_normal(facet['vertices'])
        check(close_vector(facet['normal'], wanted), 'facet'+str(i)+' declared normal equals independent oriented cross')
        normals.append(wanted)
    mesh = meshio.read(bundle/'surface.stl')
    check(all(c.type == 'triangle' for c in mesh.cells), 'actual meshio triangular cells')
    triangles = mesh.points[mesh.get_cells_type('triangle')].tolist()
    check(triangles == expected_vertices, 'actual meshio all oriented vertex triples')
    declared = mesh.get_cell_data('facet_normals', 'triangle').tolist()
    check(len(declared) == len(normals) and all(close_vector(a, b) for a, b in zip(declared, normals)), 'actual meshio stored facet normals')
    check(mesh.point_data == {} and set(mesh.cell_data) == {'facet_normals'}, 'meshio receives geometry/normals without source field metadata')
    consumers.append(dict(path=str(bundle/'surface.stl'), sha256=sha((bundle/'surface.stl').read_bytes()),
                          triangles=len(facets), normals=declared))
    return json.loads((bundle/'audit.json').read_text(encoding='utf-8'))

model_file = root/'examples/audited_stl/source.json'
model = json.loads(model_file.read_text(encoding='utf-8'))
source = output/'mixed.msh'
create(model_file, source)
source_hash = sha(source.read_bytes())
rejected = output/'strict-mixed'
error = example(source, rejected, expected=2)
check('strict planar export refuses loss' in error.stderr and not rejected.exists(), 'default Strict refuses before creating destination')
bundle = output/'permissive-mixed'
example(source, bundle, '--permissive')
points = {n['tag']: n['xyz'] for n in model['nodes']}
expected = [[points[t] for t in row] for row in [[10,20,30], [10,30,40], [10,40,20], [50,60,70]]]
audit = consume_bundle(bundle, source, expected, 'PermissiveWithAudit')
losses = {'metadata_omitted', 'lower_dimension_elements_omitted', 'quad_triangulation_diagonal_0_2',
          'unreferenced_output_nodes_omitted', 'degenerate_output_triangles'}
check(set(audit['losses']) == losses, 'five actual mixed-output losses, no invented curved-line loss')
check(audit['source_dimension'] == 2 and audit['output_vertices'] == 7 and audit['output_elements'] == 4, 'audit actual dimension/vertex/facet counts')
check(audit['discarded_curved_node_tags'] == [] and audit['orientations'] == [], 'excluded Line3 is not surface linearization or outward certification')
check(audit['error_samples'] == 4 and math.isclose(audit['estimated_chord_error'], 1/6, rel_tol=1e-14), 'independent warped bilinear-to-planar sampled deviation1/6')
check(audit['certified_bound'] is False, 'sampled deviation remains uncertified')
stl_text = (bundle/'surface.stl').read_text(encoding='utf-8')
check('temperature' not in stl_text and 'wall' not in stl_text, 'source field/name omission agrees with audit')
opts = output/'permissive.json'
opts.write_text('{"permissive":true}', encoding='utf-8')
direct = output/'direct-cli.json'
run('cli', [root/'tools/gmsh.mjs', 'audited-stl', source, opts, direct])
cli_value = json.loads(direct.read_text(encoding='utf-8'))
check(cli_value['text'] == stl_text and cli_value['loss_report'] == audit, 'saved pair equals actual direct MoonBit file CLI result')
clean_model = dict(nodes=[n for n in model['nodes'] if n['tag'] in [10,20,40]],
                   elements=[dict(tag=301, kind=2, nodes=[10,20,40])])
clean_json, clean = output/'clean.json', output/'clean.msh'
clean_json.write_text(json.dumps(clean_model), encoding='utf-8')
create(clean_json, clean)
clean_bundle = output/'strict-clean'
example(clean, clean_bundle)
clean_audit = consume_bundle(clean_bundle, clean, [[points[t] for t in [10,20,40]]], 'Strict')
check(clean_audit['losses'] == [] and clean_audit['output_elements'] == 1 and clean_audit['output_vertices'] == 3, 'lossless Strict positive case')
check(clean_audit['error_samples'] == 0 and clean_audit['estimated_chord_error'] == 0, 'unchanged planar triangle has no approximation samples')
before = {f.name: sha(f.read_bytes()) for f in bundle.iterdir()}
example(source, bundle, '--permissive', expected=2)
check({f.name: sha(f.read_bytes()) for f in bundle.iterdir()} == before, 'existing bundle refuses without changing any member')
invalid = output/'invalid-policy'
example(source, invalid, '--permisive', expected=2)
check(not invalid.exists(), 'invalid policy flag does not silently accept losses')
check(sha(source.read_bytes()) == source_hash, 'all consumer invocations retain source bytes')
result = dict(status='PASS', cliCalls=sum(c['kind']=='cli' for c in calls),
              exampleInvocations=sum(c['kind']=='example' for c in calls), checks=len(checks),
              payloadReadbacks=payload_readbacks, consumers=consumers, commands=calls, checkLabels=checks,
              source=dict(path=str(source), sha256=source_hash), meshioVersion=meshio.__version__,
              bridgeSha256=sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),
              scope='one existing audited-STL handoff; mixed warped/reversed/degenerate surface plus strict lossless triangle; no new core feature or certification')
with evidence.open('x', encoding='utf-8') as stream:
    stream.write(json.dumps(result, indent=2)+'\n')
print(json.dumps(dict(status='PASS', cliCalls=result['cliCalls'], exampleInvocations=result['exampleInvocations'],
                      checks=len(checks), meshioFiles=len(consumers), payloadReadbacks=len(payload_readbacks))))
