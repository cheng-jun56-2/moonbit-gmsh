"""Independent Gmsh check of the actual quadratic tutorial consumer outputs."""
import argparse,pathlib,json,gmsh,meshio,hashlib
from collections import Counter
p=argparse.ArgumentParser();p.add_argument('input');p.add_argument('output');p.add_argument('--evidence',required=True);a=p.parse_args();src=pathlib.Path(a.input);out=pathlib.Path(a.output);checks=0
def check(ok,msg):
 global checks
 checks+=1
 if not ok:raise AssertionError(msg)
gmsh.initialize();gmsh.option.setNumber('General.Terminal',0)
try:
 gmsh.open(str(src));types,els,conns=gmsh.model.mesh.getElements(1);expected=[]
 for k,es,cs in zip(types,els,conns):
  n=gmsh.model.mesh.getElementProperties(k)[3]
  for tag,row in zip(es,cs.reshape(-1,n)):
   dim,entity=gmsh.model.mesh.getElement(int(tag))[2:];phys=gmsh.model.getPhysicalGroupsForEntity(dim,entity).tolist();expected.append((int(tag),row.tolist(),phys))
 # Gmsh SaveAll=0 omits ten unlabelled explicit curve elements. Derive
 # the boundary independently from complete triangle edge-node incidence,
 # then check explicit labels/tags only where source elements really exist.
 edge_rows=gmsh.model.mesh.getElementEdgeNodes(9,primary=False).reshape(-1,3).tolist()
 counts=Counter(tuple(sorted(row[:2])) for row in edge_rows)
 boundary_rows=[row for row in edge_rows if counts[tuple(sorted(row[:2]))]==1]
 coverage=json.loads((out/'coverage.json').read_text());provenance=json.loads((out/'provenance.json').read_text());check(coverage['facets']==len(boundary_rows),'boundary count from independent Gmsh complete edge incidence')
 gmsh.clear();gmsh.open(str(out/'boundary.msh'));types,els,conns=gmsh.model.mesh.getElements();actual={}
 for k,es,cs in zip(types,els,conns):
  n=gmsh.model.mesh.getElementProperties(k)[3];check(int(k)==8,'retained quadratic edge family')
  for tag,row in zip(es,cs.reshape(-1,n)):
   dim,entity=gmsh.model.mesh.getElement(int(tag))[2:];actual[int(tag)]=(row.tolist(),gmsh.model.getPhysicalGroupsForEntity(dim,entity).tolist())
 check(sorted(sorted(v[0]) for v in actual.values())==sorted(sorted(row) for row in boundary_rows),'all actual complete boundary edges')
 for tag,ns,phys in expected:check(actual[tag]==(ns,phys),'explicit same tag/full nodes/physical group')
 explicit_tags={tag for tag,_,_ in expected}
 check(sum(tag not in explicit_tags for tag in actual)==10,'ten generated unlabelled facets')
 check(all(not phys for tag,(_,phys) in actual.items() if tag not in explicit_tags),'generated facets never inherit region physical group')
 check(len(provenance['nodes'])==len({n for row in boundary_rows for n in row}),'all boundary midpoints retained')
 check(len(coverage['unlabeled'])==10,'tutorial unlabeled ten retained')
 for ext in ['obj','stl']:
  loss=json.loads((out/(ext+'Loss.json')).read_text());m=meshio.read(out/('surface.'+ext));check(sum(len(c.data) for c in m.cells)==loss['output_elements'],'consumer geometry readback');check(not loss['certified_bound'] and len(loss['discarded_curved_node_tags'])>0,'actual loss audit')
 m=meshio.read(out/'mesh.vtk');check(any(c.type=='triangle6' for c in m.cells),'quadratic VTK preserved')
 receipt={'gmsh':gmsh.__version__,'meshio':meshio.__version__,'checks':checks,'boundary_facets':coverage['facets'],'source_explicit_edges':len(expected),'boundary_nodes':len(provenance['nodes']),'unlabeled':len(coverage['unlabeled']),'input_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'scope':'tutorial-generated second-order input; full boundary nodes/tags/physical groups and downstream readback; not NASA/engineering adoption'}
 pathlib.Path(a.evidence).write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt,indent=2))
finally:gmsh.finalize()
