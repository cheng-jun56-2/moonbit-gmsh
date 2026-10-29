"""Independent full record/file receiving for the exact-tag raw observation API.
The small struct/ASCII MSH reader and hand-selected original rows are separate
from the product query/encoder. No interpolation or scientific model is tested.
"""
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
root=Path(__file__).resolve().parents[1];out=Path(a.outputs).resolve();evidence=Path(a.evidence).resolve();public=Path(a.public_receipt).resolve();assert not out.exists() and not evidence.exists(),'Choose new paths';out.mkdir();node=shutil.which('node');assert node
hand=json.loads((root/'examples/field_records/expected.json').read_text(encoding='utf-8'));source=out/'原 观测网格.msh';source.write_bytes((root/'examples/field_records/source.msh').read_bytes());commands=[];checks=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def check(value,label):checks.append(label);assert value,label
check(parse(source.read_bytes())==hand['source'],'entire literal MSH matches frozen hand input including opaque context')
pub=json.loads(public.read_text(encoding='utf-8'))
for key in ['node','cell','collision']:check(pub[key]==hand['expected'][key],'public receiver full raw record/header/role witness '+key)
check(pub['source_unchanged'] is True and pub['ownership_isolated'] is True and pub['time_series_certified'] is False,'public source/ownership and non-certification evidence')

def binary_input(mesh,version,width,endian):
    f=io.BytesIO();line=lambda text:f.write((text+'\n').encode('utf-8'))
    def pack(fmt,*v):f.write(struct.pack(endian+fmt,*v))
    def size(*v):pack(('Q' if width==8 else 'I')*len(v),*v)
    line('$MeshFormat');line(version+' 1 '+str(width));pack('i',1);line('');line('$EndMeshFormat')
    line('$PhysicalNames');line(str(len(mesh['physical_names'])))
    for n in mesh['physical_names']:line(f'{n["dim"]} {n["tag"]} '+json.dumps(n['name'],ensure_ascii=False))
    line('$EndPhysicalNames')
    if version=='4.1':
        line('$Entities');size(1,1,1,0)
        for e in mesh['entities']:
            pack('i',e['tag']);pack('d'*len(e['bounds']),*e['bounds']);size(len(e['physical']));pack('i'*len(e['physical']),*e['physical'])
            if e['dim']:size(0)
        line('');line('$EndEntities')
    line('$Nodes')
    if version=='4.1':
        size(1,4,7,2147483647);pack('iii',2,7,1);size(4);size(*(n['tag'] for n in mesh['nodes']))
        for n in mesh['nodes']:pack('5d',*n['xyz'],*n['parameters'])
    else:
        line('4')
        for n in mesh['nodes']:pack('i3d',n['tag'],*n['xyz'])
    line('');line('$EndNodes');line('$Elements')
    if version=='4.1':size(3,3,3,700)
    else:line('3')
    for e in mesh['elements']:
        if version=='4.1':pack('iii',0 if e['kind']==15 else 1 if e['kind']==1 else 2,e['entity'],e['kind']);size(1);size(e['tag'],*e['nodes'])
        else:pack('iii',e['kind'],1,4);pack('i'*(5+len(e['nodes'])),e['tag'],e['physical'][0],e['entity'],*e['extra'],*e['nodes'])
    line('');line('$EndElements')
    for field in mesh['fields']:
        line('$'+field['location'])
        for values,convert in [(field['strings'],lambda x:json.dumps(x,ensure_ascii=False)),(field['reals'],str),(field['integers'],str)]:
            line(str(len(values)))
            for v in values:line(convert(v))
        for d in field['entries']:pack('i'+'d'*len(d['values']),d['tag'],*d['values'])
        line('');line('$End'+field['location'])
    for section in mesh['unknown_sections']:line('$'+section['name']);f.write(section['body'].encode('utf-8'));line('$End'+section['name'])
    return f.getvalue()

opaque_binary=out/'hand41-be4-opaque.msh';opaque_binary.write_bytes(binary_input(hand['source'],'4.1',4,'>'))
m41=copy.deepcopy(hand['source']);m41['unknown_sections']=[]
binary41=out/'hand41-be4.msh';binary41.write_bytes(binary_input(m41,'4.1',4,'>'));check(parse(binary41.read_bytes())==m41,'independent4.1 big-endian size4 entire legal input')
m22=copy.deepcopy(hand['source']);m22['source_version']='2.2';m22['entities']=[];m22['unknown_sections']=[]
for n in m22['nodes']:n.update(dim=-1,entity=0,parameters=[])
for e in m22['elements']:e['extra']=[1,17]
binary22=out/'hand22-be.msh';binary22.write_bytes(binary_input(m22,'2.2',8,'>'));check(parse(binary22.read_bytes())==m22,'independent2.2 big-endian entire input with extra element tags')

def expected22(key):
    d=copy.deepcopy(hand['expected'][key]);d['source_version']='2.2';d['unknown_section_names']=[]
    for n in d['nodes']:n.update(dim=-1,entity=0,parameters=[])
    if 'element' in d:d['element']['extra']=[1,17]
    return d

def call(name,options,src=source,expected=0,expect_record=None,raw_options=None,stdout_only=False,destination=None):
    req=out/(name+'-请求.json');req.write_bytes(raw_options if raw_options is not None else (json.dumps(options,ensure_ascii=False)+'\n').encode('utf-8'));dest=out/(name+'-result.json') if destination is None else destination;before=(sha(src.read_bytes()),sha(req.read_bytes()));argv=[node,str(root/'tools/gmsh.mjs'),'field-records',str(src),str(req)]
    if not stdout_only:argv.append(str(dest))
    r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');commands.append({'name':name,'argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr});(out/'file-calls-so-far.json').write_text(json.dumps(commands,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    check(r.returncode==expected,name+' expected actual exit');check((sha(src.read_bytes()),sha(req.read_bytes()))==before,name+' original/options byte unchanged')
    if expected:check(not r.stdout and (destination is not None or not dest.exists()),name+' no partial record JSON/stdout')
    else:
        if stdout_only:data=r.stdout;check(not dest.exists(),name+' stdout path has no extra output file')
        else:data=dest.read_text(encoding='utf-8');check(not r.stdout,name+' file command has no report stdout')
        actual=json.loads(data);check(actual==expect_record,name+' complete independently expected record/header/tag/witness')
    return dest,r

node_options={'location':'NodeData','tag':7,'field_indices':[4,0,3,2]};cell_options={'location':'ElementData','tag':700,'field_indices':[5,1]};collision_options={'location':'ElementData','tag':7,'field_indices':[7,1]}
dest,_=call('node',node_options,expect_record=hand['expected']['node']);call('cell',cell_options,expect_record=hand['expected']['cell']);call('collision',collision_options,expect_record=hand['expected']['collision'])
binary_node=copy.deepcopy(hand['expected']['node']);binary_node['unknown_section_names']=[]
call('binary41-node',node_options,src=binary41,expect_record=binary_node);call('binary22-cell',cell_options,src=binary22,expect_record=expected22('cell'));call('stdout',node_options,stdout_only=True,expect_record=hand['expected']['node'])
_,opaque_error=call('binary41-opaque-rejected',node_options,src=opaque_binary,expected=2);check('cannot safely preserve unknown binary section' in opaque_error.stderr,'pre-existing decoder binary opaque rejection retained; ASCII opaque raw query still succeeds')
for name,options in [('missing-location',{'tag':7,'field_indices':[0]}),('bad-location',{'location':'node','tag':7,'field_indices':[0]}),('missing-tag',{'location':'NodeData','field_indices':[0]}),('unknown-node',{**node_options,'tag':999}),('unknown-cell',{**cell_options,'tag':999}),('zero-tag',{**node_options,'tag':0}),('fractional-tag',{**node_options,'tag':7.5}),('oversize-tag',{**node_options,'tag':2147483648}),('missing-indices',{'location':'NodeData','tag':7}),('empty-indices',{**node_options,'field_indices':[]}),('duplicate-indices',{**node_options,'field_indices':[0,0]}),('negative-index',{**node_options,'field_indices':[-1]}),('outside-index',{**node_options,'field_indices':[8]}),('fractional-index',{**node_options,'field_indices':[.5]}),('too-many-indices',{**node_options,'field_indices':[0]*1025}),('mixed-association',{**node_options,'field_indices':[4,1]}),('late-sparse-missing',{**node_options,'tag':90,'field_indices':[3,0]}),('late-empty-field',{**node_options,'field_indices':[0,6]})]:call(name,options,expected=2)
_,r=call('invalid-utf8',node_options,raw_options=b'{"location":"NodeData","tag":7,"field_indices":[0],"note":"\xff"}',expected=2);check('valid UTF-8' in r.stderr,'existing raw options strictUTF8 gate precedes parsing')
call('legal-replacement',{**node_options,'note':'\ufffd'},expect_record=hand['expected']['node'])
saved=sha(dest.read_bytes());call('no-overwrite',node_options,destination=dest,expected=2);check(sha(dest.read_bytes())==saved,'existing full report bytes remain unchanged')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'commands':commands,'checkLabels':checks,'publicReceipt':{'path':str(public),'sha256':sha(public.read_bytes())},'manualSourceSha256':sha(source.read_bytes()),'handExpectedSha256':sha((root/'examples/field_records/expected.json').read_bytes()),'coreSourceSha256':sha((root/'field_records.mbt').read_bytes()),'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),'independentOrigin':'Literal original4.1/headers/tag rows; independent big-endian4.1-size4/2.2 writers and raw struct/ASCII readers; complete exact record DTO compared to frozen hand originals. Product dump/query/encoder is not the expected-value oracle.','receivingBoundary':'Actual self-authored public/file integration; no time-series,numerical,source authenticity or external adoption certification.'}
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'independentInputEncodings':3,'fullRecordCases':7}))
