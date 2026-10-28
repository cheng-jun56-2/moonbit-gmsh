"""Independent full-node scalar-normal integral using actual Gmsh file data.
Self-authored curved inputs. Gmsh is an oracle only; no runtime dependency or
third-party implementation is copied into the production MoonBit calculation.
"""
from pathlib import Path
import argparse, base64, hashlib, json, math, shutil, subprocess, tempfile
import gmsh
import numpy as np

arg = argparse.ArgumentParser()
arg.add_argument('--evidence', required=True)
args = arg.parse_args()
evidence = Path(args.evidence).resolve()
assert not evidence.exists(), 'Choose a new evidence file'
evidence.parent.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[1]
node = shutil.which('node') or 'node'
host = subprocess.Popen([node, str(root/'tools/oracle-host.mjs')], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, text=True, encoding='utf-8')
checks, records, commands = [], [], []

def check(ok, label):
    checks.append(label)
    if not ok:
        raise AssertionError(label)

def close(a, b, label):
    check(math.isclose(a, b, rel_tol=6e-12, abs_tol=2e-12), label)

def create(model):
    q = {'action': 'create', 'options': model}
    host.stdin.write(json.dumps(q)+'\n')
    host.stdin.flush()
    v = json.loads(host.stdout.readline())
    check(v['ok'], 'public mesh creation succeeds')
    return base64.b64decode(v['result']['bytes'])

orders = {2: [0, 2, 1], 3: [0, 3, 2, 1], 9: [0, 2, 1, 5, 4, 3],
          16: [0, 3, 2, 1, 7, 6, 5, 4], 10: [0, 3, 2, 1, 7, 6, 5, 4, 8]}
gmsh.initialize(readConfigFiles=False)
gmsh.option.setNumber('General.Terminal', 0)
try:
    with tempfile.TemporaryDirectory(prefix='gmsh-scalar-normal-', dir=evidence.parent) as temp:
        folder = Path(temp).resolve()
        assert folder.is_relative_to(evidence.parent)
        for kind in [2, 3, 9, 10, 16]:
            _, dim, _, n, local, _ = gmsh.model.mesh.getElementProperties(kind)
            refs = local.reshape(-1, dim)
            xyz = [[float(u+.04*u*v), float(v+.03*u*u), float(.13*(u*u+v*v)+.07*u*v+(.03*u*u*v*v if kind == 10 else 0))] for u, v in refs]
            scalar = [float(1+u*u+.5*v+(.1*u*u*v*v if kind == 10 else 0)) for u, v in refs]
            tags = [10+7*i for i in range(n)]
            fields = [
                {'location': 'NodeData', 'strings': ['pressure'], 'reals': [.25], 'integers': [0, 1, n], 'entries': [{'tag': t, 'values': [v]} for t, v in zip(tags, scalar)]},
                {'location': 'NodeData', 'strings': ['pressure'], 'reals': [.75], 'integers': [3, 1, n], 'entries': [{'tag': t, 'values': [2*v]} for t, v in zip(tags, scalar)]},
                {'location': 'ElementData', 'strings': ['signed_constant'], 'reals': [.25], 'integers': [0, 1, 1], 'entries': [{'tag': 201, 'values': [-.75]}]},
            ]
            for reverse in [False, True]:
                order = orders[kind] if reverse else list(range(n))
                elements = [{'tag': 201, 'kind': kind, 'nodes': [tags[i] for i in order], 'entity': 7, 'physical': [44]}]
                if kind == 9:
                    elements.append({'tag': 900, 'kind': 15, 'nodes': [tags[0]], 'entity': 1})
                model = {'nodes': [{'tag': t, 'xyz': x} for t, x in zip(tags, xyz)], 'elements': elements, 'fields': fields}
                raw = create(model)
                file = folder/f'normal-{kind}-{reverse}.msh'
                file.write_bytes(raw)
                for view in gmsh.view.getTags():
                    gmsh.view.remove(int(view))
                gmsh.clear()
                gmsh.open(str(file))
                views = {gmsh.view.option.getString(int(v), 'Name'): int(v) for v in gmsh.view.getTags()}
                actual_kind, conn, _, _ = gmsh.model.mesh.getElement(201)
                check(int(actual_kind) == kind and list(map(int, conn)) == elements[0]['nodes'], 'Gmsh full connectivity identity')
                rule = 'Gauss4' if kind in [2, 9] else 'CompositeGauss4'
                loc, w = gmsh.model.mesh.getIntegrationPoints(kind, rule)
                jac, _, _ = gmsh.model.mesh.getJacobian(201, loc)
                columns = jac.reshape(-1, 3, 3)
                cross = np.cross(columns[:, 0, :], columns[:, 1, :])
                area = float(np.sum(w*np.linalg.norm(cross, axis=1)))
                area_vector = np.sum(w[:, None]*cross, axis=0)
                _, basis, _ = gmsh.model.mesh.getBasisFunctions(kind, loc, 'Lagrange')
                for frame, field in enumerate(fields):
                    dtype, ftags, values, time, components = gmsh.view.getModelData(views[field['strings'][0]], field['integers'][0])
                    check(dtype == field['location'] and time == field['reals'][0] and components == 1, 'Gmsh actual scalar frame metadata')
                    data = {int(t): float(v[0]) for t, v in zip(ftags, values)}
                    check(data == {e['tag']: e['values'][0] for e in field['entries']}, 'Gmsh actual scalar tag association')
                    sample = basis.reshape(-1, n) @ np.array([data[int(t)] for t in conn]) if dtype == 'NodeData' else np.full(len(w), data[201])
                    expected = np.sum((w*sample)[:, None]*cross, axis=0)
                    options = folder/f'options-{frame}.json'
                    options.write_text(json.dumps({'field_index': frame, 'max_samples': len(w)})+'\n')
                    argv = [node, str(root/'tools/gmsh.mjs'), 'integrate-surface-normal-field', str(file), str(options)]
                    done = subprocess.run(argv, cwd=root, capture_output=True, text=True, encoding='utf-8')
                    commands.append({'argv': argv, 'exitCode': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr})
                    check(done.returncode == 0, 'actual scalar-normal CLI succeeds')
                    got = json.loads(done.stdout)
                    for k in range(3):
                        close(got['normal_integral'][k], float(expected[k]), 'independent scalar-normal component '+str(k))
                        close(got['area_vector'][k], float(area_vector[k]), 'independent oriented area component '+str(k))
                    close(got['surface_measure'], area, 'independent area estimate')
                    check(got['field_index'] == frame and got['name'] == field['strings'][0] and got['location'] == dtype and got['time_step'] == field['integers'][0] and got['time'] == time, 'exact source frame identity')
                    check(got['samples'] == len(w) and got['elements'] == 1 and got['skipped_lower_dimension'] == (1 if kind == 9 else 0), 'rules and lower-dimensional skip')
                    check(got['normal_convention'] == 'stored_node_winding' and not got['certified_error_bound'] and got['zero_measure_samples'] == 0, 'explicit convention and numeric limits')
                    records.append({'kind': kind, 'reverse': reverse, 'field_index': frame, 'actual': got,
                        'gmshExpected': {'normal_integral': expected.tolist(), 'area_vector': area_vector.tolist(), 'surface_measure': area, 'rule': rule},
                        'inputBytesBase64': base64.b64encode(raw).decode(), 'inputSha256': hashlib.sha256(raw).hexdigest()})
finally:
    gmsh.finalize()
    host.stdin.close()
    host.wait(timeout=10)
out = {'status': 'PASS', 'gmsh': gmsh.__version__, 'requests': len(records), 'checks': len(checks),
       'assertions': checks, 'records': records, 'cliCalls': commands, 'actualGmshFiles': 10,
       'bridgeSha256': hashlib.sha256((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()).hexdigest(),
       'scope': 'New scalar-normal vector quantity on five curved/full-node families, NodeData exact frames and signed ElementData, forward/reversed stored winding and point skip; actual file CLI/Gmsh basis/derivative products. No round12 transformation/interpolation-law matrix replay or certified error claim.'}
with evidence.open('x', encoding='utf-8') as f:
    f.write(json.dumps(out, indent=2)+'\n')
print(json.dumps({'status': 'PASS', 'requests': len(records), 'checks': len(checks), 'gmshFiles': 10}))
