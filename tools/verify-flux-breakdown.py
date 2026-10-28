"""Independent per-face Gmsh quadrature for the bounded flux breakdown API.
All coordinates/fields are self-authored; Gmsh is a development reference only.
"""
from pathlib import Path
import argparse, base64, hashlib, json, math, shutil, subprocess
import gmsh
import numpy as np

arg = argparse.ArgumentParser()
arg.add_argument('--evidence', required=True)
args = arg.parse_args()
evidence = Path(args.evidence).resolve()
assert not evidence.exists(), 'Choose a new evidence path'
root = Path(__file__).resolve().parents[1]
# Resolve before Gmsh initialization, which can affect Windows DLL/executable lookup.
host = subprocess.Popen([shutil.which('node') or 'node', str(root / 'tools/oracle-host.mjs')],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding='utf-8')
checks, records = [], []

def check(ok, label):
    checks.append(label)
    if not ok:
        raise AssertionError(label)

def close(actual, expected, label):
    check(math.isclose(actual, expected, rel_tol=8e-12, abs_tol=2e-12), label)

def api(q):
    host.stdin.write(json.dumps(q) + '\n')
    host.stdin.flush()
    v = json.loads(host.stdout.readline())
    check(v['ok'], 'public request succeeds')
    return v['result']

def change(data, command, **options):
    return api({'action': 'transform', 'data': data,
                'options': {'command': command, **options}})['bytes']

orders = {2: [0, 2, 1], 3: [0, 3, 2, 1], 9: [0, 2, 1, 5, 4, 3],
          16: [0, 3, 2, 1, 7, 6, 5, 4], 10: [0, 3, 2, 1, 7, 6, 5, 4, 8]}
gmsh.initialize(readConfigFiles=False)
gmsh.option.setNumber('General.Terminal', 0)
try:
    for reverse in [False, True]:
        nodes, elements, nodal_entries, cell_entries, reference = [], [], [], [], {}
        gmsh.clear()
        gmsh.model.add('independent-flux-breakdown')
        for i, kind in enumerate([2, 3, 9, 10, 16]):
            _, dim, _, n, local, _ = gmsh.model.mesh.getElementProperties(kind)
            refs = local.reshape(-1, dim)
            xyz = np.array([[3*i+u+.04*u*v, v+.03*u*u, .13*(u*u+v*v)+.07*u*v]
                            for u, v in refs])
            tags = [10+100*i+7*j for j in range(n)]
            values = np.array([[1+u*u, 2+v, -.5+u*v] for u, v in refs])
            constant = np.array([.25+i*.1, -.5, 1+i*.2])
            tag, entity = 201+11*i, 7 if i % 2 == 0 else 9
            order = orders[kind] if reverse else list(range(n))
            conn = [tags[j] for j in order]
            nodes.extend({'tag': t, 'xyz': v.tolist()} for t, v in zip(tags, xyz))
            elements.append({'tag': tag, 'kind': kind, 'nodes': conn, 'entity': entity, 'physical': [44]})
            if i == 0:
                elements.append({'tag': 900, 'kind': 15, 'nodes': [tags[0]], 'entity': 1})
            nodal_entries.extend({'tag': t, 'values': v.tolist()} for t, v in zip(tags, values))
            cell_entries.append({'tag': tag, 'values': constant.tolist()})
            # Independent model assembled directly from authored coordinates/connectivity.
            gmsh.model.addDiscreteEntity(2, i+100)
            gmsh.model.mesh.addNodes(2, i+100, tags, xyz.ravel())
            gmsh.model.mesh.addElementsByType(i+100, kind, [tag], conn)
            rule = 'Gauss4' if kind in [2, 9] else 'CompositeGauss4'
            loc, w = gmsh.model.mesh.getIntegrationPoints(kind, rule)
            jac, _, _ = gmsh.model.mesh.getJacobian(tag, loc)
            columns = jac.reshape(-1, 3, 3)
            cross = np.cross(columns[:, 0, :], columns[:, 1, :])
            area = float(np.sum(w*np.linalg.norm(cross, axis=1)))
            area_vector = np.sum(w[:, None]*cross, axis=0)
            _, basis, _ = gmsh.model.mesh.getBasisFunctions(kind, loc, 'Lagrange')
            sample = basis.reshape(-1, n) @ values[order]
            flux = float(np.sum(w*np.sum(sample*cross, axis=1)))
            reference[tag] = {'kind': kind, 'entity': entity, 'samples': len(w),
                              'surface_measure': area, 'area_vector': area_vector.tolist(),
                              'fluxes': [flux, 2*flux, float(constant @ area_vector)]}
        fields = [
            {'location': 'NodeData', 'strings': ['velocity'], 'reals': [.25],
             'integers': [0, 3, len(nodes)], 'entries': nodal_entries},
            {'location': 'NodeData', 'strings': ['velocity'], 'reals': [.5],
             'integers': [3, 3, len(nodes)],
             'entries': [{'tag': e['tag'], 'values': [2*x for x in e['values']]} for e in nodal_entries]},
            {'location': 'ElementData', 'strings': ['velocity'], 'reals': [.5],
             'integers': [3, 3, 5], 'entries': cell_entries},
        ]
        model = {'nodes': nodes, 'elements': elements, 'fields': fields}
        source = api({'action': 'create', 'options': model})['bytes']
        requested = [245, 900, 201, 234, 223, 212]
        subset = change(source, 'subset', tags=requested, version='4.1', binary=True, little=False)
        compact = change(subset, 'compact')
        binary = change(compact, 'convert', version='4.1', binary=True)
        stages = [('source', source, [e['tag'] for e in elements], False),
                  ('requested4.1BigEndian', subset, requested, False),
                  ('compact', compact, requested, True),
                  ('compactBinary4.1', binary, requested, True)]
        for stage, data, old_tags, dense in stages:
            for frame in [0, 1, 2]:
                q = {'data': data, 'options': {'command': 'surface-flux-breakdown',
                     'field_index': frame, 'max_elements': 5, 'max_samples': 39}}
                got = api(q)
                old = api({'data': data, 'options': {'command': 'integrate-surface-flux', 'field_index': frame}})
                check(got['total'] == old, 'old aggregate schema and values unchanged')
                check(len(got['contributions']) == 5, 'five surface rows; point skipped')
                check(got['total']['skipped_lower_dimension'] == 1, 'lower dimension counted')
                check(got['total']['time_step'] == (0 if frame == 0 else 3), 'exact step identity')
                check(got['total']['time'] == (.25 if frame == 0 else .5), 'exact time identity')
                check(got['total']['location'] == ('ElementData' if frame == 2 else 'NodeData'), 'field location identity')
                check(got['total']['normal_convention'] == 'stored_node_winding' and not got['total']['certified_error_bound'], 'winding and no false certificate')
                expected_rows = []
                for input_index, old_tag in enumerate(old_tags):
                    if old_tag == 900:
                        continue
                    ref = reference[old_tag]
                    expected_rows.append({'element': input_index+1 if dense else old_tag,
                        'input_index': input_index, 'kind': ref['kind'], 'entity': ref['entity'],
                        'samples': ref['samples'], 'surface_measure': ref['surface_measure'],
                        'area_vector': ref['area_vector'], 'flux': ref['fluxes'][frame], 'zero_measure_samples': 0})
                for row, expected in zip(got['contributions'], expected_rows):
                    for key in ['element', 'input_index', 'kind', 'entity', 'samples', 'zero_measure_samples']:
                        check(row[key] == expected[key], 'current row metadata '+key)
                    close(row['surface_measure'], expected['surface_measure'], 'independent per-face area')
                    close(row['flux'], expected['flux'], 'independent per-face signed flux')
                    for k in range(3):
                        close(row['area_vector'][k], expected['area_vector'][k], 'independent per-face area vector')
                close(got['total']['flux'], math.fsum(x['flux'] for x in expected_rows), 'independent total flux')
                close(got['total']['surface_measure'], math.fsum(x['surface_measure'] for x in expected_rows), 'independent total area')
                for k in range(3):
                    close(got['total']['area_vector'][k], math.fsum(x['area_vector'][k] for x in expected_rows), 'independent total area vector')
                records.append({'reverse': reverse, 'stage': stage, 'field_index': frame, 'request': q,
                                'actual': got, 'gmshExpectedRows': expected_rows,
                                'inputSha256': hashlib.sha256(base64.b64decode(data)).hexdigest()})
finally:
    gmsh.finalize()
    host.stdin.close()
    host.wait(timeout=10)
out = {'status': 'PASS', 'gmsh': gmsh.__version__, 'requests': len(records), 'checks': len(checks),
       'assertions': checks, 'records': records,
       'bridgeSha256': hashlib.sha256((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()).hexdigest(),
       'scope': 'Five mixed curved families, lower point, forward/reversed full-node winding, two same-name nodal frames plus cell vector, requested order and compact binary; independent Gmsh basis/Jacobians, not a global certificate.'}
evidence.parent.mkdir(parents=True, exist_ok=True)
with evidence.open('x', encoding='utf-8') as f:
    f.write(json.dumps(out, indent=2)+'\n')
print(json.dumps({'status': 'PASS', 'requests': len(records), 'checks': len(checks)}))
