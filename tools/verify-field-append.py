"""Independent raw MSH receiving for the explicit two-input field append.
The small reader supports only the fixture's line/triangle geometry and the
existing2.2/4.1 ASCII/binary layouts; no product dump/evaluator is the oracle.
"""
import argparse,copy,hashlib,io,json,shutil,struct,subprocess
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--evidence',required=True);p.add_argument('--outputs',required=True);p.add_argument('--public-receipt',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(a.outputs).resolve();evidence=Path(a.evidence).resolve();public=Path(a.public_receipt).resolve();assert not out.exists() and not evidence.exists(),'Choose new paths';out.mkdir();node=shutil.which('node');assert node
commands=[];checks=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def check(v,label):checks.append(label);assert v,label

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
            arity={1:2,2:3}
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

def write22(m):
    s='$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$PhysicalNames\n'+str(len(m['physical_names']))+'\n'+''.join(f'{v["dim"]} {v["tag"]} '+json.dumps(v['name'],ensure_ascii=False)+'\n' for v in m['physical_names'])
    s+='$EndPhysicalNames\n$Nodes\n'+str(len(m['nodes']))+'\n'+''.join(str(v['tag'])+' '+' '.join(map(str,v['xyz']))+'\n' for v in m['nodes'])+'$EndNodes\n$Elements\n'+str(len(m['elements']))+'\n'
    for v in m['elements']:
        tags=[v['physical'][0] if v['physical'] else 0,v['entity'],*v['extra']];s+=f'{v["tag"]} {v["kind"]} {len(tags)} '+' '.join(map(str,[*tags,*v['nodes']]))+'\n'
    s+='$EndElements\n'
    for f in m['fields']:
        s+='$'+f['location']+'\n'
        for values,conv in [(f['strings'],lambda v:json.dumps(v,ensure_ascii=False)),(f['reals'],str),(f['integers'],str)]:s+=str(len(values))+'\n'+''.join(conv(v)+'\n' for v in values)
        s+=''.join(str(v['tag'])+' '+' '.join(map(str,v['values']))+'\n' for v in f['entries'])+'$End'+f['location']+'\n'
    for v in m['unknown_sections']:s+='$'+v['name']+'\n'+v['body']+'$End'+v['name']+'\n'
    return s.encode('utf-8')

target=out/'原 接收网格.msh';donor=out/'字段 来源.msh';target.write_bytes((root/'examples/append_fields/recipient.msh').read_bytes());donor.write_bytes((root/'examples/append_fields/donor.msh').read_bytes());original_a=parse(target.read_bytes());original_b=parse(donor.read_bytes())
check([v['tag'] for v in original_a['nodes']]==[50,90,10,2147483647] and [v['tag'] for v in original_b['nodes']]==[2147483647,10,50,90],'independent hand storage/domain witness')
check(original_a['fields'][0]['integers']==[2,1,4,17,91] and original_b['fields'][2]['entries'][0]['values']==[9,8,7,6,5,4,3,2,1],'independent literal recipient/raw donor sections')
expected_fields=[original_a['fields'][0],original_b['fields'][2],original_b['fields'][0],original_b['fields'][1],original_b['fields'][3]]
def receiving(m,version='2.2'):
    check(m['source_version']==version,'output retains requested recipient encoding version')
    check({n['tag']:n['xyz'] for n in m['nodes']}=={n['tag']:n['xyz'] for n in original_a['nodes']},'all recipient nodes and isolated coordinate by original tag')
    expected=copy.deepcopy(original_a['elements'])
    if version=='4.1':
        for e in expected:e['extra']=[]
    check({e['tag']:e for e in m['elements']}=={e['tag']:e for e in expected},'recipient kinds ordered roles labels/context retained with explicit old format loss')
    check(m['physical_names']==original_a['physical_names'],'recipient physical names retained instead of donor names')
    check(m['fields']==expected_fields,'complete ordered raw existing plus requested donor sections')
    check(not m['unknown_sections'],'no opaque context implicitly inherited')
    if version=='2.2':check(m['nodes']==original_a['nodes'] and m['elements']==original_a['elements'],'default recipient geometry/order/context exact')
public_data=json.loads(public.read_text(encoding='utf-8'));check(public_data['evidence']=='self-authored public-package receiver' and public_data['source_unchanged'] and not public_data['physical_equivalence_certified'],'actual self-authored public receiving boundary');receiving(public_data['received'])

def call(name,options=None,recipient=target,source=donor,expected=0):
    opts=out/(name+'-选项.json');opts.write_text(json.dumps({'field_indices':[2,0,1,3]} if options is None else options,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n');dest=out/(name+'-received.msh');before={v:sha(v.read_bytes()) for v in [recipient,source,opts]};argv=[node,str(root/'tools/gmsh.mjs'),'append-fields',str(recipient),str(source),str(opts),str(dest)]
    r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');check(r.returncode==expected,'expected append file exit '+str(expected));check(all(sha(v.read_bytes())==digest for v,digest in before.items()),'both originals and options unchanged');commands.append({'name':name,'argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'inputs':{str(k):v for k,v in before.items()},'output':str(dest),'outputSha256':sha(dest.read_bytes()) if dest.exists() else None})
    if expected:check(not dest.exists() and not r.stdout,'failure creates no partial output');return None
    check(dest.is_file() and not r.stdout,'actual standalone MSH output received');return parse(dest.read_bytes())
for name,options in [('default',None),('binary22',{'field_indices':[2,0,1,3],'binary':True,'little':False}),('ascii41',{'field_indices':[2,0,1,3],'version':'4.1','allow_loss':True}),('binary41',{'field_indices':[2,0,1,3],'version':'4.1','binary':True,'little':False,'size_width':4,'allow_loss':True})]:
    m=call(name,options);receiving(m,'4.1' if name.endswith('41') else '2.2')
    if name=='default':check(m==public_data['received'],'public receiver and independent received-file full Mesh agree')
for name,options in [('missing-request',{}),('empty-request',{'field_indices':[]}),('duplicate-request',{'field_indices':[0,0]}),('negative-index',{'field_indices':[-1]}),('out-of-range',{'field_indices':[4]}),('fractional-index',{'field_indices':[0.5]}),('wrong-type',{'field_indices':'0'}),('encoding-loss',{'field_indices':[0],'version':'4.1'})]:call(name,options,expected=2)

def variant(name,m,change):
    m=copy.deepcopy(m);change(m);f=out/(name+'.msh');f.write_bytes(write22(m));return f
def wrong_node(m):
    for n in m['nodes']:
        if n['tag']==2147483647:n['tag']=999
    for f in m['fields']:
        for d in f['entries']:
            if d['tag']==2147483647:d['tag']=999
def wrong_cell(m):
    for e in m['elements']:
        if e['tag']==201:e['tag']=202
    for f in m['fields']:
        if f['location']=='ElementData':
            for d in f['entries']:
                if d['tag']==201:d['tag']=202
changes=[('wrong-node-tag',wrong_node),('wrong-cell-tag',wrong_cell),('coordinate-ulp',lambda m:m['nodes'][1].update(xyz=[2.0000000000000004,0,0])),('ordered-roles',lambda m:m['elements'][1].update(nodes=[10,90,50])),('kind',lambda m:m['elements'][1].update(kind=1,nodes=[90,10])),('extra-isolated',lambda m:m['nodes'].append({'tag':1234,'xyz':[0,0,0],'dim':-1,'entity':0,'parameters':[]}))]
for name,change in changes:call(name,source=variant(name,original_b,change),expected=2)
opaque_a=variant('opaque-recipient',original_a,lambda m:m['unknown_sections'].append({'name':'Opaque','body':'0\n'}));opaque_b=variant('opaque-donor',original_b,lambda m:m['unknown_sections'].append({'name':'Opaque','body':'1\n'}))
call('recipient-opaque',recipient=opaque_a,expected=2);call('donor-opaque',source=opaque_b,expected=2);call('loss-is-not-drop',{'field_indices':[0],'allow_loss':True},recipient=opaque_a,source=opaque_b,expected=2)
receiving(call('explicit-drop',{'field_indices':[2,0,1,3],'drop_unknown':True},recipient=opaque_a,source=opaque_b))
empty={'source_version':'2.2','nodes':[],'elements':[],'entities':[],'physical_names':[],'unknown_sections':[],'fields':[]};f={'location':'NodeData','strings':['empty'],'reals':[],'integers':[0,1,0],'entries':[]}
many=variant('many-empty',empty,lambda m:m.update(fields=[copy.deepcopy(f) for _ in range(1023)]));two=variant('two-empty',empty,lambda m:m.update(fields=[copy.deepcopy(f),copy.deepcopy(f)]))
call('combined-budget',{'field_indices':[0,1]},recipient=many,source=two,expected=2)
received=call('budget-boundary',{'field_indices':[1]},recipient=many,source=two);check(len(received['fields'])==1024 and all(v==f for v in received['fields']),'combined exact existing1024 budget boundary')
old_output=out/'default-received.msh';before=sha(old_output.read_bytes());argv=[node,str(root/'tools/gmsh.mjs'),'append-fields',str(target),str(donor),str(out/'default-选项.json'),str(old_output)];r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');commands.append({'name':'no-overwrite','argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr});check(r.returncode==2 and sha(old_output.read_bytes())==before,'old output remains byte-identical under no-overwrite')
bad=out/'bad-utf8.json';bad.write_bytes(b'{"field_indices":[0],"note":"\xff"}');dest=out/'bad-utf8.msh';argv=[node,str(root/'tools/gmsh.mjs'),'append-fields',str(target),str(donor),str(bad),str(dest)];r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');commands.append({'name':'bad-utf8','argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr});check(r.returncode==2 and not dest.exists() and not r.stdout,'existing strict external JSON UTF8 gate applies to new route')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'commands':commands,'checkLabels':checks,'publicReceipt':{'path':str(public),'sha256':sha(public.read_bytes())},'manualSources':{str(v):sha(v.read_bytes()) for v in [target,donor]},'appendSourceSha256':sha((root/'field_append.mbt').read_bytes()),'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),'independentOrigin':'Literal hand MSH inputs; independent struct/raw-header reader; explicit output section origins recipient0,donor2,donor0,donor1,donor3. No product dump or encoder as oracle.','receivingBoundary':'Actual self-authored public/file receiver; no third-party deployment/adoption.','limits':'Strict complete discrete identity and raw append only, not interpolation/physical equivalence or source authentication.'}
with evidence.open('x',encoding='utf-8') as stream:stream.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'encodingCases':4}))
