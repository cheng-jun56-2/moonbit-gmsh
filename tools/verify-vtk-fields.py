"""One same-Mesh multiple-array consumer gate, with authored independent values.
No old single-frame/edge/numerical matrix replay; meshio is development only.
"""
from pathlib import Path
import argparse,copy,hashlib,json,shutil,subprocess
import numpy as np,meshio
parser=argparse.ArgumentParser();parser.add_argument('--evidence',required=True);parser.add_argument('--outputs',required=True)
args=parser.parse_args();root=Path(__file__).resolve().parents[1]
evidence,output=Path(args.evidence).resolve(),Path(args.outputs).resolve()
assert not evidence.exists() and not output.exists(),'Choose new paths'
output.mkdir();node=shutil.which('node');assert node,'Node required'
checks,calls,readbacks=[],[],[]
def sha(data):return hashlib.sha256(data).hexdigest()
def check(ok,label):checks.append(label);assert ok,label
def run(kind,argv,expected=0):
 c=subprocess.run([node,*map(str,argv)],cwd=root,capture_output=True,text=True,encoding='utf-8')
 calls.append(dict(kind=kind,argv=[node,*map(str,argv)],exitCode=c.returncode,stdout=c.stdout,stderr=c.stderr))
 (output/'commands.json').write_text(json.dumps(calls,indent=2)+'\n',encoding='utf-8')
 check(c.returncode==expected,kind+': expected exit '+str(expected));return c
def cli(command,source,options=None,destination=None,expected=0):
 argv=[root/'tools/gmsh.mjs',command,source]
 if options is not None:
  opts=output/f'options-{len(calls)}.json';opts.write_text(json.dumps(options));argv.append(opts)
 if destination is not None:argv.append(destination)
 return run('cli',argv,expected)
def create(model,name):
 file=output/(name+'.json');file.write_text(json.dumps(model),encoding='utf-8');dest=output/(name+'.msh')
 cli('create',file,destination=dest);return dest
def frame(field,index):
 out=dict(field_index=index,name=field['strings'][0],location=field['location'],components=field['integers'][1],time_step=field['integers'][0],entries=len(field['entries']))
 if field['reals']:out['time']=field['reals'][0]
 if len(field['strings'])>1 and field['strings'][1]:out['interpolation_scheme']=field['strings'][1]
 if len(field['integers'])>3:out['partition']=field['integers'][3]
 return out
def attribute_groups(text):
 tokens=text.split();groups={}
 positions=[tokens.index(key) for key in ['POINT_DATA','CELL_DATA'] if key in tokens]
 i=min(positions)
 while i<len(tokens):
  association=tokens[i];count=int(tokens[i+1]);check(association in ['POINT_DATA','CELL_DATA'],'known grouped association')
  check(tokens[i+2:i+4]==['FIELD','FieldData'],'generic FIELD group, no vector/tensor inference')
  arrays_count=int(tokens[i+4]);i+=5;arrays=[]
  for _ in range(arrays_count):
   name,components,tuples,kind=tokens[i:i+4];components,tuples=int(components),int(tuples);i+=4
   values=[int(v) if kind=='int' else float(v) for v in tokens[i:i+components*tuples]];i+=components*tuples
   arrays.append(dict(name=name,components=components,tuples=tuples,kind=kind,values=values))
  check(association not in groups,'one block per association');groups[association]=(count,arrays)
 return groups
def consume(file,result,indices,model,label):
 check([f['field']['field_index'] for f in result['fields']]==indices,label+': requested report order')
 check([f['value_array'] for f in result['fields']]==['gmsh_value_'+str(i) for i in indices],label+': aliases use source index, not request position')
 for info,index in zip(result['fields'],indices):
  original=model['fields'][index]
  check(info['field']==frame(original,index),label+': original frame identity/time')
  check(all(info[k]==original[k] for k in ['strings','reals','integers']),label+': complete raw header copies')
 check(result['omitted_field_indices']==[i for i in range(len(model['fields'])) if i not in indices],label+': actual omitted source indices')
 wanted=['msh_field_headers_not_in_vtk'];locations={model['fields'][i]['location'] for i in indices}
 if len(locations)==1:wanted.append('other_association_tags_not_in_vtk')
 if len(indices)!=len(model['fields']):wanted.append('other_field_sections_omitted')
 wanted.append('mesh_metadata_omitted')
 check(result['losses']==wanted,label+': actual scope-aware losses')
 groups=attribute_groups(result['text']);mesh=meshio.read(file)
 for location,key,ids in [('NodeData','POINT_DATA',[n['tag'] for n in model['nodes']]),('ElementData','CELL_DATA',[e['tag'] for e in model['elements']])]:
  selected=[i for i in indices if model['fields'][i]['location']==location]
  actual_arrays=mesh.point_data if location=='NodeData' else mesh.cell_data
  if not selected:
   check(key not in groups and actual_arrays=={},label+': unselected association not invented');continue
  count,arrays=groups[key]
  names=['gmsh_value_'+str(i) for i in selected]+['gmsh_tag']
  check(count==len(ids) and [a['name'] for a in arrays]==names,label+': filtered request order and exactly one tag array')
  check(set(actual_arrays)==set(names),label+': actual consumer selected array names')
  tag_array=arrays[-1]
  check(tag_array['kind']=='int' and tag_array['components']==1 and tag_array['values']==ids,label+': token-level complete original ID map')
  actual_tags=np.asarray(actual_arrays['gmsh_tag']).reshape(-1) if location=='NodeData' else np.concatenate([np.asarray(v).reshape(-1) for v in actual_arrays['gmsh_tag']])
  check(actual_tags.dtype.kind in 'iu' and actual_tags.tolist()==ids,label+': actual consumer original point/cell IDs')
  for array,index in zip(arrays[:-1],selected):
   field=model['fields'][index];components=field['integers'][1];values={d['tag']:d['values'] for d in field['entries']}
   expected=np.asarray([values[tag] for tag in ids])
   check(array['components']==components and array['tuples']==len(ids) and array['kind']=='double',label+': exact component/count/double declaration')
   check(np.array_equal(np.asarray(array['values']).reshape(len(ids),components),expected),label+': independently tagged token values')
   data=np.asarray(actual_arrays[array['name']]).reshape(len(ids),components) if location=='NodeData' else np.concatenate([np.asarray(v).reshape(len(block.data),components) for block,v in zip(mesh.cells,actual_arrays[array['name']])])
   check(data.dtype.itemsize==8 and np.array_equal(data,expected),label+': actual simultaneous1/3/9 tuple association exact')
 if label=='mixed':
  check(mesh.points.tolist()==[n['xyz'] for n in model['nodes']],'all geometry points kept including isolated node')
  tags=[n['tag'] for n in model['nodes']]
  check([(c.type,[[tags[int(i)] for i in row] for row in c.data]) for c in mesh.cells]==[('quad9',[[10,20,30,40,50,60,70,80,90]]),('triangle',[[20,10,110]])],'Quad9 center role and full mixed connectivity retained')
 readbacks.append(dict(label=label,path=str(file),sha256=sha(file.read_bytes()),indices=indices,pointArrays=list(mesh.point_data),cellArrays=list(mesh.cell_data)))

model=json.loads((root/'examples/vtk_fields/source.json').read_text(encoding='utf-8'))
source=create(model,'source');source_sha=sha(source.read_bytes());results={}
for label,indices in [('mixed',[2,0,1]),('same-name-steps',[3,0]),('all-reordered',[3,2,1,0]),('cell-only',[2])]:
 file=output/(label+'.json');cli('vtk-fields',source,dict(field_indices=indices,allow_loss=True),file)
 result=json.loads(file.read_text());results[label]=result;vtk=output/(label+'.vtk');vtk.write_text(result['text'])
 consume(vtk,result,indices,model,label)
check([f['field']['time_step'] for f in results['same-name-steps']['fields']]==[5,4] and len({f['field']['name'] for f in results['same-name-steps']['fields']})==1,'same name explicit different steps retained without time alignment')
for name,opts in [('missing',dict(allow_loss=True)),('empty',dict(field_indices=[],allow_loss=True)),('duplicate',dict(field_indices=[0,0],allow_loss=True)),
 ('fraction',dict(field_indices=[0,.5],allow_loss=True)),('negative',dict(field_indices=[-1],allow_loss=True)),('range',dict(field_indices=[4],allow_loss=True)),
 ('cap',dict(field_indices=[0]*1025,allow_loss=True)),('loss',dict(field_indices=[0,1]))]:
 dest=output/('error-'+name+'.json');cli('vtk-fields',source,opts,dest,expected=2);check(not dest.exists(),name+': no partial report')
for index,missing in [(0,999),(2,901)]:
 sparse=copy.deepcopy(model);field=sparse['fields'][index];field['entries']=[d for d in field['entries'] if d['tag']!=missing];field['integers'][2]=len(field['entries'])
 file=create(sparse,'sparse-'+str(index));dest=output/f'error-sparse-{index}.json'
 c=cli('vtk-fields',file,dict(field_indices=[2,0,1],allow_loss=True),dest,expected=2)
 check(not dest.exists() and str(missing) in c.stderr,'whole selection fails on missing selected node/cell without partial output')
 if index==0:
  good=output/'omitted-sparse.json';cli('vtk-fields',file,dict(field_indices=[2,1],allow_loss=True),good)
  result=json.loads(good.read_text());vtk=output/'omitted-sparse.vtk';vtk.write_text(result['text']);consume(vtk,result,[2,1],sparse,'omitted-sparse')
occupied=output/'occupied.json';occupied.write_bytes(b'keep-existing')
cli('vtk-fields',source,dict(field_indices=[2,0,1],allow_loss=True),occupied,expected=2)
check(occupied.read_bytes()==b'keep-existing','new report endpoint refuses overwrite')
opts=output/'example-options.json';opts.write_text('{"field_indices":[2,0,1],"allow_loss":true}')
bundle=output/'file-example';run('example',[root/'examples/vtk_fields/run.mjs',source,opts,bundle])
manifest=json.loads((bundle/'manifest.json').read_text());check(manifest['inputSha256']==source_sha and manifest['optionsSha256']==sha(opts.read_bytes()),'IO example actual input/options identity')
check(set(manifest['outputs'])=={'fields.vtk','audit.json'},'IO paired value/report payloads')
for name,digest in manifest['outputs'].items():check(sha((bundle/name).read_bytes())==digest,'IO payload SHA readback '+name)
check((bundle/'fields.vtk').read_text()==results['mixed']['text'],'IO text equals exact native combined result')
check(json.loads((bundle/'audit.json').read_text())=={k:v for k,v in results['mixed'].items() if k!='text'},'IO sidecar retains ordered aliases/raw heads/losses exactly')
saved={f.name:sha(f.read_bytes()) for f in bundle.iterdir()};run('example',[root/'examples/vtk_fields/run.mjs',source,opts,bundle],expected=2)
check({f.name:sha(f.read_bytes()) for f in bundle.iterdir()}==saved,'existing example directory untouched')
check(sha(source.read_bytes())==source_sha,'original source unchanged')
out=dict(status='PASS',checks=len(checks),cliCalls=sum(c['kind']=='cli' for c in calls),exampleInvocations=sum(c['kind']=='example' for c in calls),
 meshioFiles=readbacks,payloadReadbacks=len(manifest['outputs']),commands=calls,checkLabels=checks,sourceSha256=source_sha,
 bridgeSha256=sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),meshioVersion=meshio.__version__,
 scope='four combined-field requests plus unselected-sparse positive path; source-index aliases and both original-ID maps; no old single/edge matrix replay')
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(out,indent=2)+'\n')
print(json.dumps(dict(status='PASS',checks=len(checks),cliCalls=out['cliCalls'],exampleInvocations=out['exampleInvocations'],meshioFiles=len(readbacks),payloadReadbacks=out['payloadReadbacks'])))
