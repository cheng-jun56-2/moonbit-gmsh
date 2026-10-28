"""Actual Gmsh and meshio readers; independent triangle edge incidence oracle."""
import argparse
from collections import Counter
import contextlib
import hashlib
import io
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import gmsh
import meshio
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / 'examples/public'
NODE = shutil.which('node')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', default='evidence/public-t1.json')
    args = parser.parse_args()
    manifest = json.loads((PUBLIC / 'SOURCE.json').read_text(encoding='utf-8'))
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((PUBLIC / name).read_bytes()).hexdigest() == digest, name
    cases = []
    gmsh.initialize()
    gmsh.option.setNumber('General.Terminal', 0)
    try:
        with tempfile.TemporaryDirectory(prefix='gmsh-public-') as temporary:
            tmp = Path(temporary)
            def run(command, source, options=None, output=None, code=0):
                argv = [NODE, str(ROOT/'tools/gmsh.mjs'), command, str(source)]
                if options is not None:
                    option_file = tmp/'options.json'
                    option_file.write_text(json.dumps(options), encoding='utf-8')
                    argv.append(str(option_file))
                if output: argv.append(str(output))
                result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
                assert result.returncode == code, (argv, result.returncode, result.stderr)
                return json.loads(result.stdout) if result.stdout else None

            for source in sorted(PUBLIC.glob('*.msh')):
                gmsh.clear()
                gmsh.open(str(source))
                tags, xyz, _ = gmsh.model.mesh.getNodes()
                coords = dict(zip(map(int, tags), np.array(xyz).reshape(-1, 3)))
                cells = {}
                all_elements = []
                for kind, ids, connected in zip(*gmsh.model.mesh.getElements()):
                    count = gmsh.model.mesh.getElementProperties(int(kind))[3]
                    for tag, ns in zip(ids, np.array(connected).reshape(-1, count)):
                        entry = (int(tag), int(kind), tuple(map(int, ns)))
                        all_elements.append(entry)
                        if int(kind) == 2: cells[int(tag)] = tuple(map(int, ns))
                incidence = Counter()
                owners = {}
                for tag, nodes in cells.items():
                    for edge in ((nodes[0],nodes[1]), (nodes[1],nodes[2]), (nodes[2],nodes[0])):
                        key = tuple(sorted(edge)); incidence[key] += 1; owners[key] = tag
                edges = {edge for edge, count in incidence.items() if count == 1}
                labels = {}
                for dim, physical in gmsh.model.getPhysicalGroups(1):
                    for entity in gmsh.model.getEntitiesForPhysicalGroup(dim, physical):
                        for kind, ids, connected in zip(*gmsh.model.mesh.getElements(dim, int(entity))):
                            assert kind == 1
                            for ns in np.array(connected).reshape(-1, 2):
                                labels.setdefault(tuple(sorted(map(int, ns))), set()).add(int(physical))
                with contextlib.redirect_stdout(io.StringIO()): independent = meshio.read(source)
                assert sum(len(c.data) for c in independent.cells if c.type == 'triangle') == len(cells)
                dump = run('dump', source)
                assert {e['tag']:(e['kind'],tuple(e['nodes'])) for e in dump['elements']} == {tag:(kind,ns) for tag,kind,ns in all_elements}
                assert len(dump['nodes']) == len(coords)
                for node in dump['nodes']:
                    np.testing.assert_allclose(node['xyz'], coords[node['tag']], rtol=0, atol=1e-15)
                report = run('boundary', source)
                coverage = run('coverage', source, {'required_groups':[5,6], 'strict':True}, code=3)
                assert coverage['facets'] == len(edges)
                expected_unlabeled = {edge for edge in edges if not labels.get(edge)}
                assert len(coverage['unlabeled']) == len(expected_unlabeled)
                assert coverage['multiple'] == [] and coverage['missing_groups'] == [6]
                counts = Counter(tag for edge in edges for tag in labels.get(edge, ()))
                assert coverage['groups'] == [{'tag':tag,'facets':count} for tag,count in sorted(counts.items())]
                output = tmp/(source.stem+'-boundary.msh')
                run('boundary-msh', source, {}, output, code=2)
                assert not output.exists(), 'rejected export must not write a partial file'
                run('boundary-msh', source, {'allow_loss':True}, output)
                boundary = run('dump', output)
                extracted = {e['tag']:e for e in boundary['elements']}
                assert {tuple(sorted(e['nodes'])) for e in extracted.values()} == edges
                for item in report['facets']:
                    element = extracted[item['element']]; edge = tuple(sorted(element['nodes']))
                    assert item['owner'] == owners[edge]
                    assert set(element['physical']) == labels.get(edge, set())
                    assert (item['explicit_element'] == 0) == (edge in expected_unlabeled)
                assert {tuple(sorted(extracted[f['element']]['nodes'])) for f in coverage['unlabeled']} == expected_unlabeled
                with contextlib.redirect_stdout(io.StringIO()): exported = meshio.read(output)
                assert sum(len(c.data) for c in exported.cells if c.type == 'line') == len(edges)
                run('coverage', source, {'max_facets':len(edges)-1}, code=2)
                run('coverage', source, {'required_groups':[5.5]}, code=2)
                run('coverage', source, {'required_groups':[5,5]}, code=2)
                cases.append(dict(file=source.name,nodes=len(coords),triangles=len(cells),boundary=len(edges),
                                  labeled=len(edges)-len(expected_unlabeled),unlabeled=len(expected_unlabeled),
                                  groups=coverage['groups'],missing_groups=coverage['missing_groups'],losses=report['losses']))
    finally: gmsh.finalize()
    result = dict(gmsh=gmsh.__version__,meshio=meshio.__version__,numpy=np.__version__,files=cases,
                  scope='actual upstream-generated tutorial; complete connectivity/coordinates/labels, independent edge incidence and owner map, meshio export readback; strict policy and refusal checks',
                  limits=['not engineering/production/adoption evidence','coverage is not boundary-condition correctness','Gmsh API and meshio are verification only'])
    evidence=Path(args.evidence); evidence.parent.mkdir(parents=True,exist_ok=True)
    evidence.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))


if __name__ == '__main__': main()
