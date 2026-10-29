"""Independent complete prescribed tag map MSH and actual downstream receiving."""
import argparse,copy,hashlib,io,json,shutil,struct,subprocess
from pathlib import Path

class Reader:
    def __init__(self,b):self.f=io.BytesIO(b);self.endian='<';self.width=8;self.binary=False
    def line(self):return self.f.readline().decode('utf-8').strip()
    def unpack(self,fmt):return struct.unpack(self.endian+fmt,self.f.read(struct.calcsize(self.endian+fmt)))
    def size(self,n=1):return self.unpack(('Q' if self.width==8 else 'I')*n)
def parse(b):
    c=Reader(b);assert c.line()=='$MeshFormat';version,binary,width=c.line().split();c.binary=binary=='1';c.width=int(width)
    if c.binary:
        magic=c.f.read(4);c.endian='<' if magic==b'\x01\x00\x00\x00' else '>';assert struct.unpack(c.endian+'i',magic)[0]==1
    result={'source_version':version,'nodes':[],'elements':[],'fields':[],'physical_names':[],'entities':[],'unknown_sections':[]};entity={}
    while c.f.tell()<len(b):
        marker=c.line()
        if marker=='$PhysicalNames':
            for _ in range(int(c.line())):
                dim,tag,text=c.line().split(maxsplit=2);result['physical_names'].append({'dim':int(dim),'tag':int(tag),'name':json.loads(text)})
        elif marker=='$Entities':
            counts=c.size(4) if c.binary else list(map(int,c.line().split()))
            for dim,count in enumerate(counts):
                for _ in range(count):
                    if c.binary:
                        tag=c.unpack('i')[0];bounds=list(c.unpack('d'*(3 if dim==0 else 6)));np=c.size()[0];physical=list(c.unpack('i'*np));nb=0 if dim==0 else c.size()[0];boundary=list(c.unpack('i'*nb))
                    else:
                        row=c.line().split();tag=int(row[0]);n=3 if dim==0 else 6;bounds=list(map(float,row[1:1+n]));i=n+1;np=int(row[i]);i+=1;physical=list(map(int,row[i:i+np]));i+=np;nb=0 if dim==0 else int(row[i]);boundary=[] if dim==0 else list(map(int,row[i+1:i+1+nb]))
                    item={'dim':dim,'tag':tag,'bounds':bounds,'physical':physical,'boundary':boundary};result['entities'].append(item);entity[dim,tag]=physical
        elif marker=='$Nodes':
            if version=='2.2':
                for _ in range(int(c.line())):
                    row=c.unpack('i3d') if c.binary else c.line().split();result['nodes'].append({'tag':int(row[0]),'xyz':list(map(float,row[1:])),'dim':-1,'entity':0,'parameters':[]})
            else:
                blocks,count,lo,hi=c.size(4) if c.binary else map(int,c.line().split())
                for _ in range(blocks):
                    dim,tag,param,n=(*c.unpack('iii'),c.size()[0]) if c.binary else map(int,c.line().split())
                    ids=list(c.size(n)) if c.binary else []
                    while not c.binary and len(ids)<n:ids.extend(map(int,c.line().split()))
                    coords=[]
                    if c.binary:coords=list(c.unpack('d'*(n*(3+dim*param))))
                    while not c.binary and len(coords)<n*(3+dim*param):coords.extend(map(float,c.line().split()))
                    for j,t in enumerate(ids):
                        row=coords[j*(3+dim*param):(j+1)*(3+dim*param)];result['nodes'].append({'tag':t,'xyz':row[:3],'dim':dim,'entity':tag,'parameters':row[3:]})
        elif marker=='$Elements':
            arity={1:2,2:3,8:3,9:6,15:1}
            if version=='2.2':
                remaining=int(c.line())
                while remaining:
                    if c.binary:
                        kind,n,nt=c.unpack('iii');rows=[c.unpack('i'*(1+nt+arity[kind])) for _ in range(n)]
                    else:
                        raw=list(map(int,c.line().split()));tag,kind,nt=raw[:3];n=1;rows=[(tag,*raw[3:])]
                    for row in rows:
                        tags=list(row[1:1+nt]);result['elements'].append({'tag':row[0],'kind':kind,'nodes':list(row[1+nt:]),'physical':[tags[0]] if nt and tags[0] else [],'entity':tags[1] if nt>1 else 0,'extra':tags[2:]})
                    remaining-=n
            else:
                blocks,count,lo,hi=c.size(4) if c.binary else map(int,c.line().split())
                for _ in range(blocks):
                    dim,tag,kind,n=(*c.unpack('iii'),c.size()[0]) if c.binary else map(int,c.line().split())
                    for _ in range(n):
                        row=c.size(1+arity[kind]) if c.binary else list(map(int,c.line().split()));result['elements'].append({'tag':row[0],'kind':kind,'nodes':list(row[1:]),'physical':entity.get((dim,tag),[]),'entity':tag,'extra':[]})
        elif marker in ['$NodeData','$ElementData']:
            groups=[]
            for convert in [json.loads,float,int]:groups.append([convert(c.line()) for _ in range(int(c.line()))])
            entries=[];components=groups[2][1]
            for _ in range(groups[2][2]):
                row=c.unpack('i'+'d'*components) if c.binary else c.line().split();entries.append({'tag':int(row[0]),'values':list(map(float,row[1:]))})
            result['fields'].append({'location':marker[1:],'strings':groups[0],'reals':groups[1],'integers':groups[2],'entries':entries})
        elif marker and marker.startswith('$') and not marker.startswith('$End'):
            name=marker[1:];lines=[]
            while (line:=c.line())!='$End'+name:lines.append(line)
            result['unknown_sections'].append({'name':name,'body':'\n'.join(lines)+'\n'})
    return result

p=argparse.ArgumentParser();p.add_argument('--evidence',required=True);p.add_argument('--outputs',required=True);p.add_argument('--public-receipt',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(a.outputs).resolve();evidence=Path(a.evidence).resolve();public=Path(a.public_receipt).resolve();assert not out.exists() and not evidence.exists(),'Choose new paths';out.mkdir();node=shutil.which('node');assert node
hand_path=root/'examples/remap_tags/expected.json';hand=json.loads(hand_path.read_text(encoding='utf-8'));commands=[];checks=[];copies=[];meshes=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def identity(p):
    p=Path(p);b=p.read_bytes();return {'path':str(p),'sha256':sha(b),'bytes':len(b)}
def check(value,label):checks.append(label);assert value,label
def save_json(p,value):p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
source=out/'原 外部编号网格.msh';original=root/'examples/remap_tags/source.msh';source.write_bytes(original.read_bytes());copies.append({'original':identity(original),'copy':identity(source)})
check(parse(source.read_bytes())==hand['source'],'entire independent literal original including Line3/Tri6 roles and raw field context')
pub=json.loads(public.read_text(encoding='utf-8'))
for key in ['mapped','identity','recovered','empty']:check(pub[key]==hand['expected'][key],'entire public received Mesh '+key)
check(pub['source_unchanged'] is True and pub['ownership_isolated'] is True,'public source/map/all nested getter ownership')

def binary_input(mesh,version,width,endian):
    # Authored from the frozen source tables,never from a product output.
    f=io.BytesIO();line=lambda text:f.write((text+'\n').encode('utf-8'))
    def pack(fmt,*v):f.write(struct.pack(endian+fmt,*v))
    def size(*v):pack(('Q' if width==8 else 'I')*len(v),*v)
    line('$MeshFormat');line(version+' 1 '+str(width));pack('i',1);line('');line('$EndMeshFormat')
    line('$PhysicalNames');line(str(len(mesh['physical_names'])))
    for n in mesh['physical_names']:line(f'{n["dim"]} {n["tag"]} '+json.dumps(n['name'],ensure_ascii=False))
    line('$EndPhysicalNames')
    if version=='4.1':
        line('$Entities');size(*(sum(e['dim']==d for e in mesh['entities']) for d in range(4)))
        for e in mesh['entities']:
            pack('i',e['tag']);pack('d'*len(e['bounds']),*e['bounds']);size(len(e['physical']));pack('i'*len(e['physical']),*e['physical'])
            if e['dim']:size(len(e['boundary']));pack('i'*len(e['boundary']),*e['boundary'])
        line('');line('$EndEntities')
    line('$Nodes')
    if version=='4.1':
        size(1,len(mesh['nodes']),min(n['tag'] for n in mesh['nodes']),max(n['tag'] for n in mesh['nodes']));pack('iii',2,7,1);size(len(mesh['nodes']));size(*(n['tag'] for n in mesh['nodes']))
        for n in mesh['nodes']:pack('5d',*n['xyz'],*n['parameters'])
    else:
        line(str(len(mesh['nodes'])))
        for n in mesh['nodes']:pack('i3d',n['tag'],*n['xyz'])
    line('');line('$EndNodes');line('$Elements')
    if version=='4.1':size(len(mesh['elements']),len(mesh['elements']),7,700)
    else:line(str(len(mesh['elements'])))
    for e in mesh['elements']:
        if version=='4.1':pack('iii',{8:1,9:2}[e['kind']],e['entity'],e['kind']);size(1);size(e['tag'],*e['nodes'])
        else:
            tags=[e['physical'][0],e['entity'],*e['extra']];pack('iii',e['kind'],1,len(tags));pack('i'*(1+len(tags)+len(e['nodes'])),e['tag'],*tags,*e['nodes'])
    line('');line('$EndElements')
    for field in mesh['fields']:
        line('$'+field['location'])
        for values,convert in [(field['strings'],lambda x:json.dumps(x,ensure_ascii=False)),(field['reals'],str),(field['integers'],str)]:
            line(str(len(values)))
            for v in values:line(convert(v))
        for d in field['entries']:pack('i'+'d'*len(d['values']),d['tag'],*d['values'])
        line('');line('$End'+field['location'])
    return f.getvalue()

binary41=out/'hand41-be4.msh';binary41.write_bytes(binary_input(hand['source'],'4.1',4,'>'));check(parse(binary41.read_bytes())==hand['source'],'entire independent4.1BE-size4 original')
m22=copy.deepcopy(hand['source']);m22.update(source_version='2.2',entities=[])
for n in m22['nodes']:n.update(dim=-1,entity=0,parameters=[])
for e in m22['elements']:e['extra']=[1,17]
binary22=out/'hand22-be8.msh';binary22.write_bytes(binary_input(m22,'2.2',8,'>'));check(parse(binary22.read_bytes())==m22,'entire independent2.2BE original with uninterpreted extra tags')
empty_source=out/'hand-empty.msh';empty_source.write_bytes(b'$MeshFormat\n4.1 0 8\n$EndMeshFormat\n$Nodes\n0 0 0 0\n$EndNodes\n$Elements\n0 0 0 0\n$EndElements\n');check(parse(empty_source.read_bytes())==hand['expected']['empty'],'entire literal empty original')
def expected22(key,extra):
    mesh=copy.deepcopy(hand['expected'][key]);mesh.update(source_version='2.2',entities=[])
    for n in mesh['nodes']:n.update(dim=-1,entity=0,parameters=[])
    for e in mesh['elements']:e['extra']=extra.copy()
    return mesh
def call(name,options,src=source,command='remap-tags',expected=0,raw_options=None,destination=None,no_output=False):
    req=out/(name+'-请求.json');req.write_bytes(raw_options if raw_options is not None else (json.dumps(options,ensure_ascii=False)+'\n').encode('utf-8'));dest=out/(name+('.msh' if command=='remap-tags' else '.json')) if destination is None else destination;before=(identity(src),identity(req));argv=[node,str(root/'tools/gmsh.mjs'),command,str(src),str(req)]
    if not no_output:argv.append(str(dest))
    r=subprocess.run(argv,cwd=root,capture_output=True);stdout_path=out/(name+'.stdout');stderr_path=out/(name+'.stderr');stdout_path.write_bytes(r.stdout);stderr_path.write_bytes(r.stderr);commands.append({'name':name,'argv':argv,'exitCode':r.returncode,'stdout':r.stdout.decode('utf-8'),'stderr':r.stderr.decode('utf-8'),'stdoutFile':str(stdout_path),'stderrFile':str(stderr_path)});save_json(out/'file-calls-so-far.json',commands)
    check(r.returncode==expected,name+' expected actual exit');check((identity(src),identity(req))==before,name+' source and complete request bytes unchanged');check(not r.stdout,name+' no partial stdout')
    if expected:check(destination is not None or not dest.exists(),name+' no partial output')
    else:check(dest.is_file() and not r.stderr,name+' actual complete file')
    return dest,r
def receive(name,options,wanted,src=source):
    dest,_=call(name,options,src=src);actual=parse(dest.read_bytes());check(actual==wanted,name+' entire independently expected Mesh/roles/headers/metadata/rows');meshes.append(identity(dest));return dest
request=hand['request'];mapped=receive('mapped',request,hand['expected']['mapped'])
identity_options={'node_tags':[{'old_tag':n['tag'],'new_tag':n['tag']} for n in hand['source']['nodes']],'element_tags':[{'old_tag':e['tag'],'new_tag':e['tag']} for e in hand['source']['elements']]}
inverse={key:[{'old_tag':r['new_tag'],'new_tag':r['old_tag']} for r in request[key]] for key in ['node_tags','element_tags']}
receive('identity',identity_options,hand['expected']['identity']);receive('recovered',inverse,hand['expected']['recovered'],src=mapped);receive('empty',{'node_tags':[],'element_tags':[]},hand['expected']['empty'],src=empty_source)
receive('binary41-be4',{**request,'binary':True,'little':False,'size_width':4},hand['expected']['mapped'],src=binary41)
receive('binary22-be8',{**request,'binary':True,'little':False},expected22('mapped',[1,17]),src=binary22)
call('conversion-loss-not-authorized',{**request,'version':'2.2'},expected=2);receive('conversion-loss-authorized',{**request,'version':'2.2','allow_loss':True},expected22('mapped',[]))
for name,options in [('missing-node-map',{'element_tags':request['element_tags']}),('missing-cell-map',{'node_tags':request['node_tags']}),('wrong-map-type',{**request,'node_tags':'7'}),('incomplete-node-map',{**request,'node_tags':request['node_tags'][:-1]}),('incomplete-cell-map',{**request,'element_tags':[]}),('extra-node-row',{**request,'node_tags':request['node_tags']+[request['node_tags'][0]]})]:call(name,options,expected=2)
for name,key,index,field,value in [('duplicate-old-node','node_tags',1,'old_tag',7),('duplicate-new-node','node_tags',1,'new_tag',2147483647),('cell-only-as-node','node_tags',0,'old_tag',700),('zero-old-node','node_tags',0,'old_tag',0),('zero-new-node','node_tags',0,'new_tag',0),('negative-new-node','node_tags',0,'new_tag',-1),('fractional-old-node','node_tags',0,'old_tag',7.5),('fractional-new-node','node_tags',0,'new_tag',3.5),('oversize-new-node','node_tags',0,'new_tag',2147483648),('duplicate-old-cell','element_tags',1,'old_tag',700),('duplicate-new-cell','element_tags',1,'new_tag',7),('late-node-only-as-cell','element_tags',1,'old_tag',2147483647),('zero-new-cell','element_tags',1,'new_tag',0)]:
    options=copy.deepcopy(request);options[key][index][field]=value;call(name,options,expected=2)
for name,key,missing in [('missing-old-tag','node_tags','old_tag'),('missing-new-tag','element_tags','new_tag')]:
    options=copy.deepcopy(request);options[key][0].pop(missing);call(name,options,expected=2)
options=copy.deepcopy(request);options['node_tags'][0]=7;call('wrong-row-type',options,expected=2)
call('missing-output',request,expected=2,no_output=True)
opaque=out/'原 未知引用.msh';opaque.write_bytes(source.read_bytes()+b'$Opaque\nreferences7\n$EndOpaque\n');call('opaque-default',request,src=opaque,expected=2);call('opaque-allow-loss',{**request,'allow_loss':True},src=opaque,expected=2);receive('opaque-explicit-drop',{**request,'drop_unknown':True},hand['expected']['mapped'],src=opaque)
_,r=call('invalid-utf8',request,raw_options=b'{"node_tags":[],"element_tags":[],"note":"\xff"}',expected=2);check(b'valid UTF-8' in r.stderr,'raw malformed UTF8 options rejected before map parse')
receive('legal-replacement',{**request,'note':'\ufffd'},hand['expected']['mapped']);saved=identity(mapped);call('no-overwrite',request,destination=mapped,expected=2);check(identity(mapped)==saved,'existing complete output bytes not overwritten')

# Read actual saved remapped MSH through the existing exporter. Hand-authored
# target tuples/roles and original heads are the oracle,not that exporter.
audit_path,_=call('actual-downstream-vtk',{'field_indices':[0,2,1],'allow_loss':True},src=mapped,command='vtk-fields');audit=json.loads(audit_path.read_text(encoding='utf-8'));vtk_path=out/'actual-downstream.vtk';vtk_path.write_text(audit['text'],encoding='utf-8',newline='\n');target=hand['downstreamVTK']
check(set(audit)=={'text','fields','source_version','omitted_field_indices','losses'},'complete downstream audit keys');expected_fields=[]
for index in target['selected_indices']:
    f=hand['expected']['mapped']['fields'][index];frame={'field_index':index,'name':f['strings'][0],'location':f['location'],'components':f['integers'][1],'time_step':f['integers'][0],'entries':len(f['entries'])}
    if f['reals']:frame['time']=f['reals'][0]
    if len(f['strings'])>1 and f['strings'][1]:frame['interpolation_scheme']=f['strings'][1]
    if len(f['integers'])>3:frame['partition']=f['integers'][3]
    expected_fields.append({'field':frame,'value_array':'gmsh_value_'+str(index),'strings':f['strings'],'reals':f['reals'],'integers':f['integers']})
check(audit['fields']==expected_fields,'full downstream raw header/frame/order including semantic head integer90 unchanged');check(audit['source_version']=='4.1' and audit['omitted_field_indices']==target['omitted_indices'],'exact original version/omitted positions');check(audit['losses']==target['losses'],'exact real scope-aware downstream losses')
lines=vtk_path.read_text(encoding='utf-8').splitlines();check(lines[:4]==['# vtk DataFile Version 3.0','MoonGmsh selected-fields export','ASCII','DATASET UNSTRUCTURED_GRID'],'actual complete VTK header');tokens=' '.join(lines[4:]).split();i=0
check(tokens[i:i+3]==['POINTS','7','double'],'all original points including isolated retained');i+=3;points=[list(map(float,tokens[j:j+3])) for j in range(i,i+21,3)];i+=21;check(points==target['points'],'all point coordinates in stored order')
check(tokens[i:i+3]==['CELLS','2','11'],'complete downstream cell count/payload declaration');i+=3;connectivity=[]
for _ in range(2):
    count=int(tokens[i]);i+=1;connectivity.append(list(map(int,tokens[i:i+count])));i+=count
check(connectivity==target['connectivity'],'complete Line3/Tri6 ordered connectivity roles');check(tokens[i:i+2]==['CELL_TYPES','2'],'all cell types declaration');i+=2;cell_types=list(map(int,tokens[i:i+2]));i+=2;check(cell_types==target['cell_types'],'exact quadratic edge/triangle VTK types')
groups={}
for association,count,arrays_count in [('POINT_DATA',7,3),('CELL_DATA',2,2)]:
    check(tokens[i:i+5]==[association,str(count),'FIELD','FieldData',str(arrays_count)],association+' exact grouped association/count/arrays');i+=5;arrays=[]
    for _ in range(arrays_count):
        name,components,tuples,kind=tokens[i:i+4];components,tuples=int(components),int(tuples);i+=4;values=[int(v) if kind=='int' else float(v) for v in tokens[i:i+components*tuples]];i+=components*tuples;arrays.append({'name':name,'components':components,'tuples':tuples,'kind':kind,'values':values})
    groups[association]=arrays
check(i==len(tokens),'entire actual VTK consumed without missing/trailing data');check([x['name'] for x in groups['POINT_DATA']]==['gmsh_value_0','gmsh_value_2','gmsh_tag'] and [x['name'] for x in groups['CELL_DATA']]==['gmsh_value_1','gmsh_tag'],'exact original aliases and one tag per domain')
for association,index,components,count in [('POINT_DATA',0,1,7),('POINT_DATA',2,3,7),('CELL_DATA',1,9,2)]:
    array=next(x for x in groups[association] if x['name']=='gmsh_value_'+str(index));check((array['components'],array['tuples'],array['kind'])==(components,count,'double'),'exact1/3/9 array declaration'+str(index));values=[array['values'][j:j+components] for j in range(0,len(array['values']),components)];check(values==target['arrays'][array['name']],'all independent complete per-tag tuples'+str(index))
for association,key,count in [('POINT_DATA','point_tags',7),('CELL_DATA','cell_tags',2)]:check(groups[association][-1]=={'name':'gmsh_tag','components':1,'tuples':count,'kind':'int','values':target[key]},association+' complete new tag map,7 stays distinct bydomain')
call('downstream-loss-gate',{'field_indices':[0,2,1]},src=mapped,command='vtk-fields',expected=2);_,r=call('downstream-sparse-missing',{'field_indices':[4],'allow_loss':True},src=mapped,command='vtk-fields',expected=2);check(b'missing tag 3' in r.stderr,'old full-coverage gate reports the actual new missing node tag,no filling');check(parse(mapped.read_bytes())==hand['expected']['mapped'],'all downstream rejects leave actual complete remapped Mesh unchanged')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'fullMeshCases':len(meshes),'commands':commands,'checkLabels':checks,'actualTestInputCopies':copies,'publicReceipt':identity(public),'manualSource':identity(source),'handExpected':identity(hand_path),'coreSource':identity(root/'tag_remap.mbt'),'bridge':identity(root/'_build/js/release/build/cmd/bridge/bridge.js'),'consumerSource':identity(Path(__file__).resolve()),'remappedOutputs':meshes,'actualDownstream':{'source':identity(mapped),'audit':identity(audit_path),'vtk':identity(vtk_path),'points':7,'cells':2,'cellTypes':[21,22],'components':[1,3,9]},'independentOrigin':'Frozen literal original and explicit independent whole target tables;ASCII/struct MSH reader and hand-source binary writers;entire saved VTK geometry/connectivity/types/point+cell arrays/audit independently received. Product remapper/dump/verifier/exporter is not an expected-value oracle.','receivingBoundary':'Actual self-authored public/file/downstream integration;not external adoption,optimized numbering/assembly,geometry/physical/source certification or nativeVTK rendering.'}
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'fullMeshCases':len(meshes),'downstreamPoints':7,'downstreamCells':2}))

