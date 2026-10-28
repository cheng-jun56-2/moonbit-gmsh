"""Independent actual-file check of one selected MSH frame in existing VTK.
Expected arrays come from authored tagged tuples, not the exported report.
meshio is a development consumer only. No legacy family/numerical matrix replay.
"""
from pathlib import Path
import argparse,copy,hashlib,json,shutil,subprocess
import numpy as np,meshio

parser=argparse.ArgumentParser()
parser.add_argument('--evidence',required=True)
parser.add_argument('--outputs',required=True)
parser.add_argument('--baseline-vtk')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
evidence,output=Path(args.evidence).resolve(),Path(args.outputs).resolve()
assert not evidence.exists() and not output.exists(),'Choose new evidence/output paths'
output.mkdir();node=shutil.which('node');assert node,'Node required'
checks,calls,consumers=[],[],[]
def sha(data):return hashlib.sha256(data).hexdigest()
def check(ok,label):
 checks.append(label)
 assert ok,label
def run(kind,argv,expected=0):
 c=subprocess.run([node,*map(str,argv)],cwd=root,capture_output=True,text=True,encoding='utf-8')
 calls.append(dict(kind=kind,argv=[node,*map(str,argv)],exitCode=c.returncode,stdout=c.stdout,stderr=c.stderr))
 (output/'commands.json').write_text(json.dumps(calls,indent=2)+'\n',encoding='utf-8')
 check(c.returncode==expected,kind+': expected exit '+str(expected));return c
def cli(command,source,options=None,destination=None,expected=0):
 argv=[root/'tools/gmsh.mjs',command,source]
 if options is not None:
  file=output/f'options-{len(calls)}.json';file.write_text(json.dumps(options),encoding='utf-8');argv.append(file)
 if destination is not None:argv.append(destination)
 return run('cli',argv,expected)
def create(model,name):
 file=output/(name+'.json');file.write_text(json.dumps(model,ensure_ascii=False),encoding='utf-8')
 msh=output/(name+'.msh');cli('create',file,destination=msh);return msh
def frame(f,index):
 data=dict(field_index=index,name=f['strings'][0],location=f['location'],components=f['integers'][1],time_step=f['integers'][0],entries=len(f['entries']))
 if f['reals']:data['time']=f['reals'][0]
 if len(f['strings'])>1 and f['strings'][1]:data['interpolation_scheme']=f['strings'][1]
 if len(f['integers'])>3:data['partition']=f['integers'][3]
 return data

model=json.loads((root/'examples/vtk_field/source.json').read_text(encoding='utf-8'))
source=create(model,'source');source_sha=sha(source.read_bytes())
geometry=output/'geometry-only.vtk';cli('vtk',source,dict(allow_loss=True),geometry)
old=geometry.read_bytes()
if args.baseline_vtk:check(old==Path(args.baseline_vtk).read_bytes(),'old geometry-only endpoint exactly equals pre-implementation frozen file')
prefix=old.decode('utf-8').replace('MoonGmsh geometry-only export','MoonGmsh selected-field export')
tags=[n['tag'] for n in model['nodes']];element_tags=[e['tag'] for e in model['elements']]
reports=[]
for index,f in enumerate(model['fields']):
 report_file=output/f'frame-{index}.json'
 cli('vtk-field',source,dict(field_index=index,allow_loss=True),report_file)
 result=json.loads(report_file.read_text(encoding='utf-8'));reports.append(result)
 check(result['text'].startswith(prefix),'selected data reuses exact old geometry except title')
 check(result['field']==frame(f,index),'exact original frame/time/name/scheme/partition metadata')
 check(result['strings']==f['strings'] and result['reals']==f['reals'] and result['integers']==f['integers'],'all original raw field headers preserved in sidecar')
 check(result['source_version']=='2.2' and result['omitted_field_indices']==[i for i in range(len(model['fields'])) if i!=index],'source version and actual omitted frame indices')
 check(result['losses']==['msh_field_headers_not_in_vtk','other_association_tags_not_in_vtk','other_field_sections_omitted','mesh_metadata_omitted'],'explicit actual omissions travel with selected values')
 vtk=output/f'frame-{index}.vtk';vtk.write_text(result['text'],encoding='utf-8');mesh=meshio.read(vtk)
 nodal=f['location']=='NodeData';components=f['integers'][1]
 if index==0:
  check(mesh.points.tolist()==[n['xyz'] for n in model['nodes']],'actual consumer all points including isolated maxInt tag position')
  # Tet10 canonical edges are independently identified from reference geometry.
  corners=model['elements'][0]['nodes'][:4];bytag={n['tag']:n['xyz'] for n in model['nodes']}
  edge_tags=[]
  for a,b in [(0,1),(1,2),(2,0),(0,3),(1,3),(2,3)]:
   midpoint=[(x+y)/2 for x,y in zip(bytag[corners[a]],bytag[corners[b]])]
   edge_tags.append(next(n['tag'] for n in model['nodes'] if n['xyz']==midpoint))
  wanted=[('tetra10',corners+edge_tags),('triangle',model['elements'][1]['nodes']),('vertex',[999])]
  check([(block.type,[[tags[int(i)] for i in row] for row in block.data]) for block in mesh.cells]==[(kind,[conn]) for kind,conn in wanted],'actual consumer complete Tet10 edge roles and mixed-cell order')
 expected={d['tag']:d['values'] for d in f['entries']}
 if nodal:
  check(set(mesh.point_data)=={'gmsh_value','gmsh_tag'} and mesh.cell_data=={},'only selected point association arrays')
  actual_tags=np.asarray(mesh.point_data['gmsh_tag']).reshape(-1)
  actual_values=np.asarray(mesh.point_data['gmsh_value']).reshape(len(tags),components)
  check(actual_tags.dtype.kind in 'iu' and actual_tags.tolist()==tags,'original full point IDs preserved exactly as integers')
 else:
  check(mesh.point_data=={} and set(mesh.cell_data)=={'gmsh_value','gmsh_tag'},'only selected cell association arrays')
  actual_tags=np.concatenate([np.asarray(v).reshape(-1) for v in mesh.cell_data['gmsh_tag']])
  actual_values=np.concatenate([np.asarray(v).reshape(len(block.data),components) for block,v in zip(mesh.cells,mesh.cell_data['gmsh_value'])])
  check(actual_tags.dtype.kind in 'iu' and actual_tags.tolist()==element_tags,'original cell IDs preserved in actual output cell order')
 check(actual_values.dtype.itemsize==8 and np.array_equal(actual_values,np.asarray([expected[int(t)] for t in actual_tags])),'all selected1/3/9 double components attach to correct original IDs, not entry order')
 consumers.append(dict(fieldIndex=index,path=str(vtk),sha256=sha(vtk.read_bytes()),association=f['location'],components=components,tuples=len(actual_tags)))
check(reports[0]['field']['name']==reports[1]['field']['name'] and reports[0]['field']['time_step']==0 and reports[1]['field']['time_step']==3,'same names remain distinct exact original steps')
check('time' not in reports[2]['field'] and reports[2]['reals']==[],'absent time stays absent in sidecar')

errors=[('missing',dict(allow_loss=True)),('fraction',dict(field_index=.5,allow_loss=True)),
 ('negative',dict(field_index=-1,allow_loss=True)),('range',dict(field_index=7,allow_loss=True)),
 ('loss',dict(field_index=2))]
for name,opts in errors:
 file=output/('error-'+name+'.json');c=cli('vtk-field',source,opts,file,expected=2)
 check(not file.exists(),'no partial report on '+name)
 if name=='loss':check('allow_loss' in c.stderr,'loss acceptance required even though selected values are retained')
for index,missing in [(2,2147483647),(4,201)]:
 sparse=copy.deepcopy(model);f=sparse['fields'][index]
 f['entries']=[d for d in f['entries'] if d['tag']!=missing];f['integers'][2]=len(f['entries'])
 file=create(sparse,'sparse-'+str(index));dest=output/f'error-sparse-{index}.json'
 c=cli('vtk-field',file,dict(field_index=index,allow_loss=True),dest,expected=2)
 check(not dest.exists() and str(missing) in c.stderr,'missing exact node/cell fails without zero filling or partial report')
 if index==2:
  legacy=output/'sparse-still-valid-old-vtk.vtk';cli('vtk',file,dict(allow_loss=True),legacy)
  check(legacy.read_bytes()==old,'old valid sparse MSH/geometry export acceptance is unchanged')
unsupported=dict(nodes=[dict(tag=i+1,xyz=[0,0,0]) for i in range(18)],
 elements=[dict(tag=201,kind=13,nodes=list(range(1,19)))],
 fields=[dict(location='NodeData',strings=['data'],reals=[],integers=[0,1,18],entries=[dict(tag=i+1,values=[1]) for i in range(18)])])
file=create(unsupported,'unsupported');dest=output/'error-unsupported.json'
c=cli('vtk-field',file,dict(field_index=0,allow_loss=True),dest,expected=2)
check(not dest.exists() and 'unsupported element family' in c.stderr,'existing VTK family boundary fails explicitly without partial report')
occupied=output/'occupied.json';occupied.write_bytes(b'keep-existing')
cli('vtk-field',source,dict(field_index=2,allow_loss=True),occupied,expected=2)
check(occupied.read_bytes()==b'keep-existing','actual new CLI endpoint refuses overwrite')

options=output/'example-options.json';options.write_text('{"field_index":1,"allow_loss":true}',encoding='utf-8')
bundle=output/'file-example';run('example',[root/'examples/vtk_field/run.mjs',source,options,bundle])
manifest=json.loads((bundle/'manifest.json').read_text(encoding='utf-8'))
check(manifest['inputSha256']==source_sha and manifest['optionsSha256']==sha(options.read_bytes()),'IO example exact input/options identity')
check(set(manifest['outputs'])=={'field.vtk','audit.json'},'VTK and sidecar are paired in manifest')
for name,digest in manifest['outputs'].items():check(sha((bundle/name).read_bytes())==digest,'IO payload SHA readback '+name)
check((bundle/'field.vtk').read_text(encoding='utf-8')==reports[1]['text'],'IO example exact native VTK text')
check(json.loads((bundle/'audit.json').read_text(encoding='utf-8'))=={k:v for k,v in reports[1].items() if k!='text'},'IO sidecar contains every raw header and loss unchanged')
saved={f.name:sha(f.read_bytes()) for f in bundle.iterdir()}
run('example',[root/'examples/vtk_field/run.mjs',source,options,bundle],expected=2)
check({f.name:sha(f.read_bytes()) for f in bundle.iterdir()}==saved,'existing example bundle refuses without changing a member')
check(sha(source.read_bytes())==source_sha,'source mesh bytes unchanged by all consumers')
result=dict(status='PASS',checks=len(checks),cliCalls=sum(c['kind']=='cli' for c in calls),exampleInvocations=sum(c['kind']=='example' for c in calls),
 commands=calls,checkLabels=checks,meshioFiles=consumers,payloadReadbacks=len(manifest['outputs']),
 sourceSha256=source_sha,geometryOnlySha256=sha(old),meshioVersion=meshio.__version__,
 bridgeSha256=sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),
 scope='one selected stored frame in existing VTK: both associations1/3/9 and exact same-name steps; raw/loss sidecar and old geometry compatibility; no old matrix replay')
with evidence.open('x',encoding='utf-8') as stream:stream.write(json.dumps(result,indent=2)+'\n')
print(json.dumps(dict(status='PASS',checks=len(checks),cliCalls=result['cliCalls'],exampleInvocations=result['exampleInvocations'],meshioFiles=len(consumers),payloadReadbacks=result['payloadReadbacks'])))
