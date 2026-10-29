"""Independent node-domain MSH and actual downstream VTK file receiving."""
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
            arity={1:2,2:3,15:1}
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
root=Path(__file__).resolve().parents[1];out=Path(a.outputs).resolve();evidence=Path(a.evidence).resolve();public=Path(a.public_receipt).resolve()
assert not out.exists() and not evidence.exists(),'Choose new paths';out.mkdir();node=shutil.which('node');assert node
hand_path=root/'examples/node_cloud/expected.json';hand=json.loads(hand_path.read_text(encoding='utf-8'));commands=[];checks=[];copies=[];clouds=[]

def sha(b):return hashlib.sha256(b).hexdigest()
def identity(p):
    p=Path(p);b=p.read_bytes();return {'path':str(p),'sha256':sha(b),'bytes':len(b)}
def check(value,label):checks.append(label);assert value,label
def save_json(p,value):p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

source=out/'原 监测网格.msh';original=root/'examples/node_cloud/source.msh';source.write_bytes(original.read_bytes());copies.append({'original':identity(original),'copy':identity(source)})
check(parse(source.read_bytes())==hand['source'],'entire independent literal source matches frozen nodes/cells/fields/context')
pub=json.loads(public.read_text(encoding='utf-8'))
for key in ['selected','single','empty','all']:check(pub[key]==hand['expected'][key],'complete public Mesh receiver '+key)
check(pub['source_unchanged'] is True and pub['ownership_isolated'] is True,'public source/request/getter ownership witness')

def binary_input(mesh,version,width,endian):
    # This writer consumes only the frozen hand model, never a product dump.
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
        groups=[]
        for n in mesh['nodes']:
            key=(n['dim'],n['entity'],int(bool(n['parameters'])))
            if not groups or groups[-1][0]!=key:groups.append((key,[]))
            groups[-1][1].append(n)
        size(len(groups),len(mesh['nodes']),min(n['tag'] for n in mesh['nodes']),max(n['tag'] for n in mesh['nodes']))
        for (dim,entity,param),ns in groups:
            pack('iii',dim,entity,param);size(len(ns));size(*(n['tag'] for n in ns))
            for n in ns:pack('d'*(3+len(n['parameters'])),*n['xyz'],*n['parameters'])
    else:
        line(str(len(mesh['nodes'])))
        for n in mesh['nodes']:pack('i3d',n['tag'],*n['xyz'])
    line('');line('$EndNodes');line('$Elements')
    if version=='4.1':size(len(mesh['elements']),len(mesh['elements']),min(e['tag'] for e in mesh['elements']),max(e['tag'] for e in mesh['elements']))
    else:line(str(len(mesh['elements'])))
    for e in mesh['elements']:
        if version=='4.1':
            pack('iii',0 if e['kind']==15 else 2,e['entity'],e['kind']);size(1);size(e['tag'],*e['nodes'])
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

binary41=out/'hand41-be4.msh';binary41.write_bytes(binary_input(hand['source'],'4.1',4,'>'));check(parse(binary41.read_bytes())==hand['source'],'entire independent4.1 big-endian size4 source')
m22=copy.deepcopy(hand['source']);m22.update(source_version='2.2',entities=[])
for n in m22['nodes']:n.update(dim=-1,entity=0,parameters=[])
binary22=out/'hand22-be8.msh';binary22.write_bytes(binary_input(m22,'2.2',8,'>'));check(parse(binary22.read_bytes())==m22,'entire independent2.2 big-endian source')

def expected22(key):
    mesh=copy.deepcopy(hand['expected'][key]);mesh.update(source_version='2.2',entities=[])
    for n in mesh['nodes']:n.update(dim=-1,entity=0,parameters=[])
    return mesh

def call(name,options,src=source,command='node-cloud',expected=0,raw_options=None,destination=None,no_output=False):
    req=out/(name+'-请求.json');req.write_bytes(raw_options if raw_options is not None else (json.dumps(options,ensure_ascii=False)+'\n').encode('utf-8'))
    dest=out/(name+('.msh' if command=='node-cloud' else '.json')) if destination is None else destination
    before=(identity(src),identity(req));argv=[node,str(root/'tools/gmsh.mjs'),command,str(src),str(req)]
    if not no_output:argv.append(str(dest))
    r=subprocess.run(argv,cwd=root,capture_output=True)
    stdout_path=out/(name+'.stdout');stderr_path=out/(name+'.stderr');stdout_path.write_bytes(r.stdout);stderr_path.write_bytes(r.stderr)
    commands.append({'name':name,'argv':argv,'exitCode':r.returncode,'stdout':r.stdout.decode('utf-8'),'stderr':r.stderr.decode('utf-8'),'stdoutFile':str(stdout_path),'stderrFile':str(stderr_path)})
    save_json(out/'file-calls-so-far.json',commands)
    check(r.returncode==expected,name+' actual expected exit');check((identity(src),identity(req))==before,name+' original and request bytes unchanged')
    check(not r.stdout,name+' file command has no partial stdout')
    if expected:check(destination is not None or not dest.exists(),name+' rejected without partial output')
    else:check(dest.is_file() and not r.stderr,name+' actual complete file output')
    return dest,r

def cloud(name,options,wanted,src=source,unordered_nodes=False):
    dest,_=call(name,options,src=src);actual=parse(dest.read_bytes())
    if unordered_nodes:
        actual['nodes'].sort(key=lambda n:n['tag']);wanted=copy.deepcopy(wanted);wanted['nodes'].sort(key=lambda n:n['tag'])
    check(actual==wanted,name+' entire independent Mesh/headers/rows/classification receiving');check(not actual['elements'],name+' no induced or invented vertex cells')
    clouds.append(identity(dest));return dest

selected={'tags':[2147483647,7,50]}
dest=cloud('selected',selected,hand['expected']['selected'])
cloud('single',{'tags':[7]},hand['expected']['single']);cloud('empty',{'tags':[]},hand['expected']['empty'])
all_dest=cloud('all',{'tags':[90,2147483647,7,50]},hand['expected']['all'])
cloud('binary41-be4',{**selected,'binary':True,'little':False,'size_width':4},hand['expected']['selected'],src=binary41)
cloud('binary22-be8',{**selected,'binary':True,'little':False},expected22('selected'),src=binary22)
call('conversion-loss-not-authorized',{**selected,'version':'2.2'},expected=2)
cloud('conversion-loss-authorized',{**selected,'version':'2.2','allow_loss':True},expected22('selected'))
mixed=copy.deepcopy(hand['expected']['all']);mixed['nodes']=[n for tag in [7,90,2147483647] for n in hand['source']['nodes'] if n['tag']==tag]
for field in mixed['fields']:
    field['entries']=[d for d in field['entries'] if d['tag']!=50];field['integers'][2]=len(field['entries'])
cloud('mixed-classification',{'tags':[7,90,2147483647]},mixed,unordered_nodes=True)

for name,opts in [('missing-tags',{}),('wrong-tags-type',{'tags':'7'}),('duplicate-tags',{'tags':[7,7]}),('unknown-late',{'tags':[7,50,999]}),('cell-only-tag',{'tags':[700]}),('zero-tag',{'tags':[0]}),('negative-tag',{'tags':[-1]}),('fractional-tag',{'tags':[7.5]}),('oversize-tag',{'tags':[2147483648]})]:call(name,opts,expected=2)
call('missing-output',selected,expected=2,no_output=True)
opaque=out/'原 未知上下文.msh';opaque.write_bytes(source.read_bytes()+b'$Opaque\nreferences7\n$EndOpaque\n')
call('opaque-default',selected,src=opaque,expected=2);call('opaque-allow-loss',{**selected,'allow_loss':True},src=opaque,expected=2)
cloud('opaque-explicit-drop',{**selected,'drop_unknown':True},hand['expected']['selected'],src=opaque)
_,r=call('invalid-utf8',selected,raw_options=b'{"tags":[7],"note":"\xff"}',expected=2);check(b'valid UTF-8' in r.stderr,'old strictUTF8 options gate retained')
cloud('legal-replacement',{**selected,'note':'\ufffd'},hand['expected']['selected'])
saved=identity(dest);call('no-overwrite',selected,destination=dest,expected=2);check(identity(dest)==saved,'complete existing cloud bytes stay unchanged')

# Consume the actual new MSH through the old VTK field entry point. Expected
# numbers and raw heads come from frozen hand input, not any product verifier.
vtk_path,_=call('downstream-vtk',{'field_indices':[0,2,4],'allow_loss':True},src=dest,command='vtk-fields')
audit=json.loads(vtk_path.read_text(encoding='utf-8'));vtk_file=out/'actual-downstream.vtk';vtk_file.write_text(audit['text'],encoding='utf-8',newline='\n')
check(set(audit)=={'text','fields','source_version','omitted_field_indices','losses'},'complete VTK audit keys')
expected_fields=[]
for index in [0,2,4]:
    f=hand['expected']['selected']['fields'][index]
    frame={'field_index':index,'name':f['strings'][0],'location':f['location'],'components':f['integers'][1],'time_step':f['integers'][0],'entries':len(f['entries'])}
    if f['reals']:frame['time']=f['reals'][0]
    if len(f['strings'])>1 and f['strings'][1]:frame['interpolation_scheme']=f['strings'][1]
    if len(f['integers'])>3:frame['partition']=f['integers'][3]
    expected_fields.append({'field':frame,'value_array':'gmsh_value_'+str(index),'strings':f['strings'],'reals':f['reals'],'integers':f['integers']})
check(audit['fields']==expected_fields,'entire original raw VTK audit headers/index/time/partition/descriptor')
check(audit['source_version']=='4.1' and audit['omitted_field_indices']==hand['downstreamVTK']['omitted_indices'],'VTK original version and exact omitted field positions')
check(audit['losses']==hand['downstreamVTK']['losses'],'all actual VTK metadata losses exact')
lines=vtk_file.read_text(encoding='utf-8').splitlines();check(lines[:4]==['# vtk DataFile Version 3.0','MoonGmsh selected-fields export','ASCII','DATASET UNSTRUCTURED_GRID'],'entire actual legacy VTK header')
tokens=lines[4:];tokens=' '.join(tokens).split();i=0
check(tokens[i:i+3]==['POINTS','3','double'],'exact point count/type');i+=3
points=[list(map(float,tokens[j:j+3])) for j in range(i,i+9,3)];i+=9
check(points==hand['downstreamVTK']['points'],'all downstream point coordinates in node order')
check(tokens[i:i+3]==['CELLS','0','0'],'zero downstream cells and connectivity payload');i+=3
check(tokens[i:i+2]==['CELL_TYPES','0'],'zero downstream cell types');i+=2
check(tokens[i:i+5]==['POINT_DATA','3','FIELD','FieldData','4'],'one point-data group with exactly values and originaltag');i+=5
arrays=[]
for _ in range(4):
    name,components,count,kind=tokens[i:i+4];components,count=int(components),int(count);i+=4
    values=[int(v) if kind=='int' else float(v) for v in tokens[i:i+components*count]];i+=components*count
    arrays.append({'name':name,'components':components,'count':count,'kind':kind,'values':values})
check(i==len(tokens),'entire VTK consumed without extra cell data or trailing arrays')
check([a['name'] for a in arrays]==['gmsh_value_0','gmsh_value_2','gmsh_value_4','gmsh_tag'],'exact original source-index aliases and one tag array')
for array,index,components in zip(arrays[:3],[0,2,4],[1,3,9]):
    check((array['components'],array['count'],array['kind'])==(components,3,'double'),'VTK exact declaration field'+str(index))
    values=[array['values'][j:j+components] for j in range(0,len(array['values']),components)]
    check(values==hand['downstreamVTK']['arrays']['gmsh_value_'+str(index)],'all independently tagged1/3/9 component tuples field'+str(index))
check(arrays[-1]=={'name':'gmsh_tag','components':1,'count':3,'kind':'int','values':hand['downstreamVTK']['node_tags']},'complete original integer node tags including MAX,not row ordinal')
call('downstream-loss-gate',{'field_indices':[0,2,4]},src=dest,command='vtk-fields',expected=2)
_,r=call('downstream-sparse-missing',{'field_indices':[4],'allow_loss':True},src=all_dest,command='vtk-fields',expected=2)
check(b'missing tag 90' in r.stderr,'existing downstream full-coverage rejection,legal sparse cloud never filled')
check(parse(all_dest.read_bytes())==hand['expected']['all'],'sparse rejection leaves complete actual node cloud unchanged')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'fullCloudCases':len(clouds),'commands':commands,'checkLabels':checks,'actualTestInputCopies':copies,'publicReceipt':identity(public),'manualSource':identity(source),'handExpected':identity(hand_path),'coreSource':identity(root/'node_cloud.mbt'),'bridge':identity(root/'_build/js/release/build/cmd/bridge/bridge.js'),'consumerSource':identity(Path(__file__).resolve()),'cloudOutputs':clouds,'actualDownstream':{'source':identity(dest),'audit':identity(vtk_path),'vtk':identity(vtk_file),'points':3,'cells':0,'components':[1,3,9]},'independentOrigin':'Frozen literal original/complete hand expectations;independent ASCII/struct MSH reader and binary writers,independent full VTK token/audit receiving. Product dump/verifier/exporter is not the expected-value oracle.','receivingBoundary':'Actual self-authored public/file/downstream integration;zero cells,no automatic vertex rendering or external adoption/scientific/identity certification.'}
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'fullCloudCases':len(clouds),'downstreamPoints':3,'downstreamCells':0}))
