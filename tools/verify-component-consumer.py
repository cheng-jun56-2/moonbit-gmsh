"""One existing components/subset/compact -> actual MSH consumer chain.
Small authored-graph pairwise BFS and binary struct reader are independent
oracles, not a general mesh parser, coordinate weld or production dependency.
"""
from pathlib import Path
import argparse, copy, hashlib, json, shutil, struct, subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--evidence',required=True)
parser.add_argument('--outputs',required=True)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
evidence,output=Path(args.evidence).resolve(),Path(args.outputs).resolve()
assert not evidence.exists() and not output.exists(),'Choose new output paths'
output.mkdir()
node=shutil.which('node')
assert node,'Node is required'
import gmsh

checks,calls,actual,parsed_records,bulk_query_notes=[],[],[],[],[]
def sha(data):return hashlib.sha256(data).hexdigest()
def check(ok,label):
 checks.append(label)
 assert ok,label
def run(kind,argv,expected=0):
 result=subprocess.run([node,*map(str,argv)],cwd=root,capture_output=True,text=True,encoding='utf-8')
 calls.append(dict(kind=kind,argv=[node,*map(str,argv)],exitCode=result.returncode,stdout=result.stdout,stderr=result.stderr))
 (output/'commands.json').write_text(json.dumps(calls,indent=2)+'\n',encoding='utf-8')
 check(result.returncode==expected,kind+': expected exit '+str(expected))
 return result
def cli(command,source,options=None,destination=None):
 argv=[root/'tools/gmsh.mjs',command,source]
 if options is not None:
  opts=output/f'options-{len(calls)}.json';opts.write_text(json.dumps(options),encoding='utf-8');argv.append(opts)
 if destination is not None:argv.append(destination)
 return run('cli',argv)

def graph_components(elements):
 # Deliberately small O(n²) pairwise set BFS, unlike production union-find.
 remaining=set(range(len(elements)));result=[]
 for start in range(len(elements)):
  if start not in remaining:continue
  queue=[start];remaining.remove(start);visited={start}
  for i in queue:
   adjacent=[j for j in sorted(remaining) if set(elements[i]['nodes'])&set(elements[j]['nodes'])]
   for j in adjacent:remaining.remove(j);visited.add(j);queue.append(j)
  result.append([e['tag'] for i,e in enumerate(elements) if i in visited])
 return result

def parse41(file):
 raw=file.read_bytes()
 check(raw.startswith(b'$MeshFormat\n4.1 1 8\n\x01\x00\x00\x00\n'),'actual little-endian4.1 binary header')
 pos=raw.index(b'$Nodes\n')+len(b'$Nodes\n')
 def take(fmt):
  nonlocal pos
  row=struct.unpack_from('<'+fmt,raw,pos);pos+=struct.calcsize('<'+fmt);return row
 blocks,count,_,_=take('QQQQ');nodes=[]
 for _ in range(blocks):
  dim,entity,param,n=take('iiiQ');tags=take(str(n)+'Q')
  for tag in tags:
   xyz=list(take('ddd'));parameters=list(take(str(dim)+'d')) if param else []
   nodes.append(dict(tag=tag,xyz=xyz,dim=dim,entity=entity,parameters=parameters))
 check(len(nodes)==count and raw[pos:pos+len(b'\n$EndNodes\n')]==b'\n$EndNodes\n','all binary nodes and footer consumed')
 pos=raw.index(b'$Elements\n')+len(b'$Elements\n')
 blocks,count,_,_=take('QQQQ');elements=[];widths={9:6,2:3,8:3,15:1}
 for _ in range(blocks):
  dim,entity,kind,n=take('iiiQ')
  check(kind in widths,'authored binary element family')
  for _ in range(n):
   row=take(str(widths[kind]+1)+'Q');elements.append(dict(tag=row[0],kind=kind,nodes=list(row[1:]),entity=entity,dim=dim))
 check(len(elements)==count and raw[pos:pos+len(b'\n$EndElements\n')]==b'\n$EndElements\n','all binary elements and footer consumed')
 pos+=len(b'\n$EndElements\n');fields=[]
 def line():
  nonlocal pos
  end=raw.index(b'\n',pos);value=raw[pos:end].decode('utf-8');pos=end+1;return value
 while pos<len(raw):
  location=line()[1:]
  check(location in ['NodeData','ElementData'],'actual field location')
  strings=[json.loads(line()) for _ in range(int(line()))]
  reals=[float(line()) for _ in range(int(line()))]
  integers=[int(line()) for _ in range(int(line()))];entries=[]
  for _ in range(integers[2]):
   row=take('i'+'d'*integers[1]);entries.append(dict(tag=row[0],values=list(row[1:])))
  if entries:
   check(raw[pos:pos+1]==b'\n','binary field payload terminator');pos+=1
  check(line()=='$End'+location,'binary field section end')
  fields.append(dict(location=location,strings=strings,reals=reals,integers=integers,entries=entries))
 start=raw.index(b'$PhysicalNames\n')+len(b'$PhysicalNames\n');end=raw.index(b'$EndPhysicalNames\n',start)
 rows=raw[start:end].decode('utf-8').splitlines();names=[]
 for row in rows[1:]:
  dim,tag,name=row.split(' ',2);names.append(dict(dim=int(dim),tag=int(tag),name=json.loads(name)))
 check(len(names)==int(rows[0]),'all physical names consumed')
 return dict(nodes=nodes,elements=elements,fields=fields,names=names)

def subset_fields(fields,node_tags,element_tags,node_map=None,element_map=None):
 result=[]
 for original in fields:
  field=copy.deepcopy(original)
  tags=node_tags if field['location']=='NodeData' else element_tags
  mapping=node_map if field['location']=='NodeData' else element_map
  field['entries']=[d for d in field['entries'] if d['tag'] in tags]
  if mapping is not None:
   for datum in field['entries']:datum['tag']=mapping[datum['tag']]
  field['integers'][2]=len(field['entries']);result.append(field)
 return result

model_file=root/'examples/split_components/source.json'
model=json.loads(model_file.read_text(encoding='utf-8'))
source=output/'source.msh';cli('create',model_file,destination=source);source_sha=sha(source.read_bytes())
expected=graph_components(model['elements'])
check(expected==[[900,701,702],[200],[802]],'authored full-role/all-dimension graph has exactly three expected components')
reported=json.loads(cli('components',source).stdout)
check(reported==expected,'actual CLI components match independent graph and original first-element order')
bundle=output/'parts'
run('example',[root/'examples/split_components/run.mjs',source,bundle])
manifest=json.loads((bundle/'manifest.json').read_text(encoding='utf-8'))
check(json.loads((bundle/'components.json').read_text(encoding='utf-8'))==expected,'example graph report agrees')
check(manifest['inputSha256']==source_sha and len(manifest['parts'])==3,'example source identity and component count')
check(set(manifest['outputs'])=={'components.json',*[f'component-{i}{suffix}.msh' for i in range(3) for suffix in ['', '-compact']]},'exact seven payload set')
for name,digest in manifest['outputs'].items():check(sha((bundle/name).read_bytes())==digest,'payload SHA readback '+name)
check({f.name for f in bundle.iterdir()}==set(manifest['outputs'])|{'manifest.json'},'no unlisted bundle members')
source_nodes={n['tag']:n['xyz'] for n in model['nodes']}
consumer_cases=[]
for record,tags in zip(manifest['parts'],expected):
 check(record['source_element_tags']==tags,'manifest original element identity')
 original_file=bundle/record['original_file'];dense_file=bundle/record['dense_file']
 original=parse41(original_file);dense=parse41(dense_file)
 selected=[e for e in model['elements'] if e['tag'] in tags]
 used={tag for e in selected for tag in e['nodes']}
 check({n['tag']:n['xyz'] for n in original['nodes']}=={t:source_nodes[t] for t in used},'subset retains only actual full used nodes, not coincident others/unused999')
 check([e['tag'] for e in original['elements']]==tags,'binary subset stores original component element order')
 check([(e['kind'],e['nodes'],e['entity']) for e in original['elements']]==[(e['kind'],e['nodes'],e['entity']) for e in selected],'binary subset complete connectivity and entity identity')
 check(original['names']==model['names'] and dense['names']==model['names'],'all dimension-scoped physical names retained')
 node_map={n['tag']:i+1 for i,n in enumerate(original['nodes'])}
 element_map={e['tag']:i+1 for i,e in enumerate(original['elements'])}
 check(record['before_compact_node_tags']==list(node_map) and record['before_compact_element_tags']==list(element_map),'manifest uses actual encoded stored tag order')
 check(record['dense_node_tags']==[n['tag'] for n in dense['nodes']] and record['dense_element_tags']==[e['tag'] for e in dense['elements']],'manifest reports actual dense file IDs')
 check({n['tag']:n['xyz'] for n in dense['nodes']}=={node_map[t]:source_nodes[t] for t in used},'dense IDs follow serialized node order and preserve geometry')
 check([(e['tag'],e['kind'],e['nodes'],e['entity']) for e in dense['elements']]==[(element_map[e['tag']],e['kind'],[node_map[t] for t in e['nodes']],e['entity']) for e in selected],'dense elements and full connectivity use correct maps')
 original_fields=subset_fields(model['fields'],used,set(tags))
 dense_fields=subset_fields(model['fields'],used,set(tags),node_map,element_map)
 check(original['fields']==original_fields,'subset raw field heads/counts/all surviving data exact')
 check(dense['fields']==dense_fields,'dense raw field heads/counts/all tag-associated values exact')
 check(all(999 not in [d['tag'] for d in f['entries']] for f in original['fields']),'unused-node datum excluded')
 if tags==[802]:check(original_fields[1]['entries']==[] and original_fields[1]['integers']==[7,1,0],'sparse frame remains present empty on point component')
 parsed_records.append(dict(sourceTags=tags,nodeMap=node_map,elementMap=element_map,
   originalPath=str(original_file),densePath=str(dense_file),fieldEntries=[len(f['entries']) for f in original_fields]))
 consumer_cases.extend([(original_file,original,original_fields),(dense_file,dense,dense_fields)])
direct=output/'direct-subset.msh'
cli('subset',source,dict(tags=expected[0],version='4.1',binary=True),direct)
check(direct.read_bytes()==(bundle/'component-0.msh').read_bytes(),'direct file CLI subset equals example output')
direct_dense=output/'direct-compact.msh'
cli('compact',direct,dict(version='4.1',binary=True),direct_dense)
check(direct_dense.read_bytes()==(bundle/'component-0-compact.msh').read_bytes(),'direct file CLI compact equals example output')
saved={f.name:sha(f.read_bytes()) for f in bundle.iterdir()}
run('example',[root/'examples/split_components/run.mjs',source,bundle],expected=2)
check({f.name:sha(f.read_bytes()) for f in bundle.iterdir()}==saved,'existing destination refuses without altering any member')
check(sha(source.read_bytes())==source_sha,'all IO consumers retain original source bytes')

gmsh.initialize();frames=0
try:
 gmsh.option.setNumber('General.Terminal',0)
 for file,parsed,fields in consumer_cases:
  for view in gmsh.view.getTags():gmsh.view.remove(int(view))
  gmsh.clear();gmsh.open(str(file))
  ntags,xyz,_=gmsh.model.mesh.getNodes()
  check({int(t):list(map(float,xyz[3*i:3*i+3])) for i,t in enumerate(ntags)}=={n['tag']:n['xyz'] for n in parsed['nodes']},'Gmsh all actual node IDs/coordinates '+file.name)
  # Mixed linear/quadratic cells on one entity can be absent from this bulk
  # query even though getElement(tag) reads them. Exhaust the exact independently
  # parsed file tag list instead; preserve the bulk observation as a limit.
  _,bulk_tags,_=gmsh.model.mesh.getElements()
  reported_tags={int(t) for group in bulk_tags for t in group}
  file_tags={e['tag'] for e in parsed['elements']}
  if reported_tags!=file_tags:
   bulk_query_notes.append(dict(path=str(file),bulkReportedTags=sorted(reported_tags),
                                fileTags=sorted(file_tags),verifiedBy='getElement for every parsed file tag'))
  cells={}
  for e in parsed['elements']:
   kind,conn,dim,entity=gmsh.model.mesh.getElement(e['tag'])
   cells[e['tag']]=(int(kind),list(map(int,conn)))
   check(int(entity)==e['entity'] and list(map(int,gmsh.model.getPhysicalGroupsForEntity(int(dim),int(entity))))==[44],'Gmsh entity and dimension-scoped physical group')
  check(cells=={e['tag']:(e['kind'],e['nodes']) for e in parsed['elements']},'Gmsh every explicit file element and full role order '+file.name)
  views={gmsh.view.option.getString(int(v),'Name'):int(v) for v in gmsh.view.getTags()}
  for field in fields:
   if not field['entries']:continue # raw parser, not Gmsh defaults, proves empty/header identity
   dtype,tags,values,time,components=gmsh.view.getModelData(views[field['strings'][0]],field['integers'][0])
   check(dtype==field['location'] and components==field['integers'][1] and time==(field['reals'][0] if field['reals'] else 0),'Gmsh original step/time/components '+field['strings'][0])
   check({int(t):list(map(float,row)) for t,row in zip(tags,values)}=={d['tag']:d['values'] for d in field['entries']},'Gmsh actual field values stay attached to correct current IDs')
   frames+=1
  actual.append(dict(path=str(file),sha256=sha(file.read_bytes()),nodes=len(parsed['nodes']),elements=len(parsed['elements'])))
finally:gmsh.finalize()
check(len(actual)==6 and frames==16,'six actual binary consumers and16 nonempty original-step fields checked')
result=dict(status='PASS',checks=len(checks),cliCalls=sum(c['kind']=='cli' for c in calls),exampleInvocations=sum(c['kind']=='example' for c in calls),
 commands=calls,checkLabels=checks,components=expected,parsedOutputs=parsed_records,gmshFiles=actual,gmshFrames=frames,gmshVersion=gmsh.__version__,bulkQueryNotes=bulk_query_notes,
 payloadReadbacks=len(manifest['outputs']),sourceSha256=source_sha,
 bridgeSha256=sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),
 scope='one full-node all-dimension component/subset/serialized-order compact/field-to-MSH chain; no field selection, STL or numerical-matrix replay')
with evidence.open('x',encoding='utf-8') as stream:stream.write(json.dumps(result,indent=2)+'\n')
print(json.dumps(dict(status='PASS',checks=len(checks),cliCalls=result['cliCalls'],exampleInvocations=result['exampleInvocations'],gmshFiles=len(actual),gmshFrames=frames,payloadReadbacks=result['payloadReadbacks'])))
