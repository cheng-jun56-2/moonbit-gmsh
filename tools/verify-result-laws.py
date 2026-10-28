"""Finite result-law review, not a new solver/transform/remeshing capability.
Authored rational polynomials give exact flux/area-vector expectations. Gmsh
independently reads each actual MSH and evaluates its own basis/Jacobians.
All numerical reports use the real public file CLI exactly once per case.
"""
from pathlib import Path
from fractions import Fraction as F
import argparse, base64, hashlib, json, math, shutil, subprocess, tempfile
import gmsh
import numpy as np

arg = argparse.ArgumentParser()
arg.add_argument('--evidence', required=True)
arg.add_argument('--outputs', help='optional new directory for all review inputs/receipts')
args = arg.parse_args()
evidence = Path(args.evidence).resolve()
assert not evidence.exists(), 'Choose a new evidence file'
evidence.parent.mkdir(parents=True, exist_ok=True)
output = Path(args.outputs).resolve() if args.outputs else None
if output:
    assert not output.exists(), 'Choose a new outputs directory'
    output.mkdir()
temporary = None if output else tempfile.TemporaryDirectory(prefix='gmsh-result-laws-', dir=evidence.parent)
folder = output or Path(temporary.name).resolve()
assert output or folder.is_relative_to(evidence.parent)
root = Path(__file__).resolve().parents[1]
node = shutil.which('node') or 'node'  # resolve before Gmsh initializes Windows DLL search
host = subprocess.Popen([node, str(root/'tools/oracle-host.mjs')], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, text=True, encoding='utf-8')
checks, records, commands, preflight, files = [], [], [], [], []

def check(ok, label):
    checks.append(label)
    if not ok:
        (folder/'failure-progress.json').write_text(json.dumps({'checks': checks, 'commands': commands, 'records': records}, indent=2)+'\n')
        raise AssertionError(label)

def close(a, b, label):
    check(math.isclose(a, b, rel_tol=5e-12, abs_tol=2e-12), label)

def create(model, name):
    host.stdin.write(json.dumps({'action': 'create', 'options': model})+'\n')
    host.stdin.flush()
    v = json.loads(host.stdout.readline())
    check(v['ok'], 'public mesh creation succeeds '+name)
    file = folder/(name+'.msh')
    file.write_bytes(base64.b64decode(v['result']['bytes']))
    files.append(file)
    return file

for i in [0, 1]:
    (folder/f'frame{i}.json').write_text(json.dumps({'field_index': i})+'\n')

def cli(command, file, frame=None):
    argv = [node, str(root/'tools/gmsh.mjs'), command, str(file)]
    if frame is not None:
        argv.append(str(folder/f'frame{frame}.json'))
    done = subprocess.run(argv, cwd=root, capture_output=True, text=True, encoding='utf-8')
    commands.append({'argv': argv, 'exitCode': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr})
    check(done.returncode == 0, 'actual CLI succeeds '+command)
    return json.loads(done.stdout)

# Small exact two-variable polynomial algebra, unrelated to MoonBit's Jets.
def poly(**terms):
    return {tuple(map(int, k.split('_'))): F(v) for k, v in terms.items()}

def add(a, b):
    result = dict(a)
    for key, value in b.items():
        result[key] = result.get(key, F(0))+value
    return {key: value for key, value in result.items() if value}

def scale(a, value):
    return {key: v*value for key, v in a.items() if v*value}

def multiply(a, b):
    result = {}
    for (i, j), x in a.items():
        for (k, l), y in b.items():
            key = (i+k, j+l)
            result[key] = result.get(key, F(0))+x*y
    return result

def derivative(a, axis):
    result = {}
    for key, value in a.items():
        if key[axis]:
            target = list(key)
            target[axis] -= 1
            result[tuple(target)] = value*key[axis]
    return result

def cross(a, b):
    return [add(multiply(a[(i+1)%3], b[(i+2)%3]), scale(multiply(a[(i+2)%3], b[(i+1)%3]), -1)) for i in range(3)]

def matvec(matrix, values):
    return [sum((matrix[i][j]*values[j] for j in range(3)), F(0)) for i in range(3)]

def matpoly(matrix, values):
    result = []
    for row in matrix:
        total = {}
        for coefficient, value in zip(row, values):
            total = add(total, scale(value, coefficient))
        result.append(total)
    return result

def cofactor(matrix):
    out = []
    for i in range(3):
        row = []
        for j in range(3):
            a = [[matrix[r][c] for c in range(3) if c != j] for r in range(3) if r != i]
            row.append((a[0][0]*a[1][1]-a[0][1]*a[1][0])*(-1)**(i+j))
        out.append(row)
    return out

def evaluate(a, u, v):
    return sum((x*u**i*v**j for (i, j), x in a.items()), F(0))

def integrate(a, triangle):
    if triangle:
        return sum((x*F(math.factorial(i)*math.factorial(j), math.factorial(i+j+2)) for (i, j), x in a.items()), F(0))
    return sum((x*F(4, (i+1)*(j+1)) for (i, j), x in a.items() if i%2 == 0 and j%2 == 0), F(0))

def exact_flux(field, normal, triangle):
    total = {}
    for a, b in zip(field, normal):
        total = add(total, multiply(a, b))
    return integrate(total, triangle)

identity = [[F(int(i == j)) for j in range(3)] for i in range(3)]
rotation = [[F(0), F(-1), F(0)], [F(1), F(0), F(0)], [F(0), F(0), F(1)]]
anisotropic = [[F(2), F(0), F(0)], [F(0), F(3), F(0)], [F(0), F(0), F(1, 2)]]
mirror = [[F(-1), F(0), F(0)], [F(0), F(1), F(0)], [F(0), F(0), F(1)]]
millimetres = [[1000*x for x in row] for row in identity]
cases = [('base', identity, identity, [F(0)]*3),
         ('rigid', rotation, rotation, [F(7), F(-4), F(2)]),
         ('anisotropic', anisotropic, anisotropic, [F(7), F(-4), F(2)]),
         ('mirror', mirror, mirror, [F(0)]*3),
         ('coordinates-mm', millimetres, identity, [F(0)]*3),
         ('coordinates-and-velocity-mm', millimetres, millimetres, [F(0)]*3)]

def open_reference(file, model):
    for view in gmsh.view.getTags():
        gmsh.view.remove(int(view))
    gmsh.clear()
    gmsh.open(str(file))
    views = {gmsh.view.option.getString(int(v), 'Name'): int(v) for v in gmsh.view.getTags()}
    reference = []
    for field in model['fields']:
        dtype, tags, data, time, nc = gmsh.view.getModelData(views[field['strings'][0]], 0)
        check(dtype == field['location'] and time == .25 and nc == 3, 'Gmsh actual dataset identity')
        actual_data = dict(zip(map(int, tags), map(np.array, data)))
        check({t: v.tolist() for t, v in actual_data.items()} == {d['tag']: d['values'] for d in field['entries']}, 'Gmsh actual input field values')
        rows = []
        for element in model['elements']:
            tag, kind = element['tag'], element['kind']
            _, conn, _, _ = gmsh.model.mesh.getElement(tag)
            rule = 'Gauss4' if kind in [2, 9] else 'CompositeGauss4'
            loc, weights = gmsh.model.mesh.getIntegrationPoints(kind, rule)
            jac, _, _ = gmsh.model.mesh.getJacobian(tag, loc)
            columns = jac.reshape(-1, 3, 3)
            normal = np.cross(columns[:, 0, :], columns[:, 1, :])
            measure = np.linalg.norm(normal, axis=1)
            if field['location'] == 'NodeData':
                _, basis, _ = gmsh.model.mesh.getBasisFunctions(kind, loc, 'Lagrange')
                values = basis.reshape(-1, len(conn)) @ np.array([actual_data[int(t)] for t in conn])
            else:
                values = np.tile(actual_data[tag], (len(weights), 1))
            rows.append({'element': tag, 'area': float(weights @ measure),
                         'area_vector': np.sum(weights[:, None]*normal, axis=0).tolist(),
                         'flux': float(np.sum(weights*np.sum(values*normal, axis=1))),
                         'components': np.sum((weights*measure)[:, None]*values, axis=0).tolist()})
        reference.append(rows)
    return reference

gmsh.initialize(readConfigFiles=False)
gmsh.option.setNumber('General.Terminal', 0)
try:
    for kind in [9, 10]:
        triangle = kind == 9
        xyz = [poly(**{'1_0': 1, '1_1': F(1, 10)}),
               poly(**{'0_1': 1, '2_0': F(1, 20)}),
               poly(**{'2_0': F(1, 5), '1_1': F(1, 10), '0_2': F(3, 20)})]
        nodal = [poly(**{'0_0': 1, '2_0': 1}), poly(**{'0_0': F(1, 2), '0_1': 1}), poly(**{'0_0': 2, '1_1': 1})]
        if not triangle:
            xyz[2] = add(xyz[2], poly(**{'2_2': F(1, 20)}))
            nodal[2] = add(nodal[2], poly(**{'2_2': F(1, 10)}))
        fields = [nodal, [poly(**{'0_0': x}) for x in [F(1, 4), F(-1, 2), F(1)]]]
        normal = cross([derivative(a, 0) for a in xyz], [derivative(a, 1) for a in xyz])
        _, _, _, count, local, _ = gmsh.model.mesh.getElementProperties(kind)
        refs = [[F(float(x)) for x in row] for row in local.reshape(-1, 2)]
        base_results, base_components = {}, {}
        for name, a, b, shift in cases:
            transformed_normal = matpoly(cofactor(a), normal)
            points = [matvec(a, [evaluate(v, u, w) for v in xyz]) for u, w in refs]
            nodes = [{'tag': 10+7*i, 'xyz': [float(x+y) for x, y in zip(point, shift)]} for i, point in enumerate(points)]
            data_fields = []
            for index, vector in enumerate(fields):
                transformed_field = matpoly(b, vector)
                entries = [{'tag': node['tag'], 'values': [float(evaluate(v, *uv)) for v in transformed_field]} for node, uv in zip(nodes, refs)] if index == 0 else [{'tag': 201, 'values': [float(evaluate(v, F(0), F(0))) for v in transformed_field]}]
                data_fields.append({'location': 'NodeData' if index == 0 else 'ElementData', 'strings': ['nodal_velocity' if index == 0 else 'cell_velocity'], 'reals': [.25], 'integers': [0, 3, len(entries)], 'entries': entries})
            model = {'nodes': nodes, 'elements': [{'tag': 201, 'kind': kind, 'nodes': [n['tag'] for n in nodes], 'entity': 7, 'physical': [44]}], 'fields': data_fields}
            file = create(model, f'curved-{kind}-{name}')
            gmsh_expected = open_reference(file, model)
            if name == 'base':
                catalog = cli('field-frames', file)
                cov = [cli('surface-field-coverage', file, i) for i in [0, 1]]
                check(all(v['all_required_tags_present'] for v in cov), 'base query used as preflight only')
                preflight.append({'kind': kind, 'catalog': catalog, 'coverage': cov})
            for index, vector in enumerate(fields):
                transformed_field = matpoly(b, vector)
                expected = exact_flux(transformed_field, transformed_normal, triangle)
                expected_area_vector = [integrate(v, triangle) for v in transformed_normal]
                got = cli('integrate-surface-flux', file, index)
                close(got['flux'], float(expected), 'exact rational polynomial flux '+name)
                close(got['flux'], gmsh_expected[index][0]['flux'], 'independent Gmsh flux '+name)
                close(got['surface_measure'], gmsh_expected[index][0]['area'], 'independent fixed-rule area '+name)
                for x, y in zip(got['area_vector'], expected_area_vector):
                    close(x, float(y), 'exact transformed area vector '+name)
                check(got['normal_convention'] == 'stored_node_winding' and not got['certified_error_bound'], 'stored convention and no false certificate')
                if name == 'base':
                    base_results[index] = got
                elif name in ['rigid', 'mirror']:
                    close(got['surface_measure'], base_results[index]['surface_measure'], 'orthogonal area invariance '+name)
                if name in ['rigid', 'anisotropic', 'mirror', 'coordinates-and-velocity-mm']:
                    determinant = sum((a[0][j]*cofactor(a)[0][j] for j in range(3)), F(0))
                    close(got['flux'], float(determinant)*base_results[index]['flux'], 'co-transformed determinant law '+name)
                if name == 'coordinates-mm':
                    close(got['flux'], 1e6*base_results[index]['flux'], 'coordinate-only unit scaling')
                records.append({'case': name, 'kind': kind, 'field_index': index, 'command': 'integrate-surface-flux', 'input': file.name, 'actual': got, 'exactFlux': str(expected), 'exactAreaVector': list(map(str, expected_area_vector)), 'gmsh': gmsh_expected[index][0]})
                if name in ['base', 'rigid']:
                    component = cli('integrate-surface-field', file, index)
                    for x, y in zip(component['integral'], gmsh_expected[index][0]['components']):
                        close(x, y, 'Gmsh component integral '+name)
                    if name == 'base':
                        base_components[index] = component['integral']
                    else:
                        target = matvec(rotation, base_components[index])
                        for x, y in zip(component['integral'], target):
                            close(x, float(y), 'proper rotated component integral')
                    records.append({'case': name, 'kind': kind, 'field_index': index, 'command': 'integrate-surface-field', 'input': file.name, 'actual': component, 'gmshComponents': gmsh_expected[index][0]['components']})

    corners = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
    grid = [[-1, -1], [0, -1], [1, -1], [-1, 0], [0, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]
    reconstructions = [('quad', corners, 3, [[1, 2, 3, 4]], [[8], [8]]),
                       ('triangles', corners, 2, [[1, 2, 3], [1, 3, 4]], [[F(8, 3), F(16, 3)], [F(10, 3), F(6)]]),
                       ('subquads', grid, 3, [[1, 2, 5, 4], [2, 3, 6, 5], [5, 6, 9, 8], [4, 5, 8, 7]], [[0, 1, 4, 3], [F(1, 4), F(3, 4), F(17, 4), F(11, 4)]])]
    reconstruction_totals = {}
    for name, points, kind, connections, expected_rows in reconstructions:
        nodes = [{'tag': i+1, 'xyz': [x, y, 0]} for i, (x, y) in enumerate(points)]
        fields = [{'location': 'NodeData', 'strings': ['affine' if index == 0 else 'bilinear'], 'reals': [.25], 'integers': [0, 3, len(nodes)], 'entries': [{'tag': n['tag'], 'values': [0, 0, 2+x+3*y+(x*y if index == 1 else 0)]} for n, (x, y) in zip(nodes, points)]} for index in [0, 1]]
        model = {'nodes': nodes, 'elements': [{'tag': 201+i, 'kind': kind, 'nodes': conn, 'entity': 7, 'physical': [44]} for i, conn in enumerate(connections)], 'fields': fields}
        file = create(model, 'reconstruction-'+name)
        gmsh_expected = open_reference(file, model)
        reconstruction_totals[name] = []
        for index in [0, 1]:
            got = cli('surface-flux-breakdown', file, index)
            check(len(got['contributions']) == len(expected_rows[index]), 'reconstruction complete face rows')
            for row, expected, independent in zip(got['contributions'], expected_rows[index], gmsh_expected[index]):
                close(row['flux'], float(expected), 'exact planar per-face flux '+name)
                close(row['flux'], independent['flux'], 'Gmsh planar per-face flux '+name)
            target = sum(expected_rows[index], F(0))
            close(got['total']['flux'], float(target), 'exact planar recomposition '+name)
            close(got['total']['surface_measure'], 4, 'same planar region area '+name)
            reconstruction_totals[name].append(got['total']['flux'])
            records.append({'case': 'reconstruction-'+name, 'field_index': index, 'command': 'surface-flux-breakdown', 'input': file.name, 'actual': got, 'exactFluxRows': list(map(str, expected_rows[index])), 'exactTotal': str(target), 'gmshRows': gmsh_expected[index]})
    check(not math.isclose(reconstruction_totals['quad'][1], reconstruction_totals['triangles'][1], rel_tol=1e-3), 'Q1 to P1 corner reconstruction is correctly a different field')
finally:
    gmsh.finalize()
    host.stdin.close()
    host.wait(timeout=10)

out = {'status': 'PASS', 'gmsh': gmsh.__version__, 'mathReports': len(records), 'cliCalls': len(commands), 'checks': len(checks), 'assertions': checks, 'records': records, 'preflight': preflight, 'commands': commands,
       'actualGmshFiles': len(files), 'bridgeSha256': hashlib.sha256((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()).hexdigest(),
       'scope': 'Finite laws on curved Tri6/Quad9 NodeData/ElementData plus three planar reconstructions. All math reports use actual file CLI; exact rational polynomial flux/area-vector plus Gmsh basis/Jacobians. No sparse/cap/compact matrix, new API, transform/resampling implementation, error certificate or physical unit inference.'}
with evidence.open('x', encoding='utf-8') as f:
    f.write(json.dumps(out, indent=2)+'\n')
if output:
    (folder/'review.json').write_text(json.dumps(out, indent=2)+'\n')
    payloads = [*files, folder/'frame0.json', folder/'frame1.json', folder/'review.json']
    (folder/'manifest.json').write_text(json.dumps({'outputs': {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in payloads}}, indent=2)+'\n')
else:
    temporary.cleanup()
print(json.dumps({'status': 'PASS', 'mathReports': len(records), 'cliCalls': len(commands), 'checks': len(checks), 'gmshFiles': len(files)}))
