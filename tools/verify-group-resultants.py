"""Independent complete file receiving for the per-physical-group workflow.
Raw struct/MSH parsing and literal hand expectations are independent of the
MoonBit encoder/integrator; this does not rerun field-append or curved math suites.
"""
import argparse,copy,hashlib,io,json,math,shutil,struct,subprocess
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

p=argparse.ArgumentParser();p.add_argument('--evidence',required=True);p.add_argument('--outputs',required=True);p.add_argument('--public-receipt',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(a.outputs).resolve();evidence=Path(a.evidence).resolve();public=Path(a.public_receipt).resolve()
assert not out.exists() and not evidence.exists(),'Choose new paths';out.mkdir();node=shutil.which('node');assert node
hand=json.loads((root/'examples/group_resultants/expected.json').read_text(encoding='utf-8'));source=out/'原 场网格.msh';source.write_bytes((root/'examples/group_resultants/source.msh').read_bytes());source_sha=hashlib.sha256(source.read_bytes()).hexdigest()
commands=[];checks=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def check(v,label):
    checks.append(label)
    assert v,label
def close(actual,expected,label):
    check(len(actual)==len(expected) and all(math.isclose(x,y,rel_tol=3e-12,abs_tol=3e-12) for x,y in zip(actual,expected)),label)
check(parse(source.read_bytes())==hand['source'],'literal original MSH fully matches frozen hand source context')

def frame(f,index):
    values={'field_index':index,'name':f['strings'][0],'location':f['location'],'components':f['integers'][1],'time_step':f['integers'][0],
            'time':f['reals'][0] if f['reals'] else None,'entries':f['integers'][2],
            'interpolation_scheme':f['strings'][1] if len(f['strings'])>1 and f['strings'][1] else None,'partition':f['integers'][3] if len(f['integers'])>3 else None}
    # Existing derived ToJson omits absent optional struct fields.
    return {k:v for k,v in values.items() if v is not None}

def estimate(r,g,index):
    h=hand['groups'][str(g)];f=hand['source']['fields'][index]
    keys={'field_index','name','location','time_step','elements','skipped_lower_dimension','samples','rules','surface_measure','area_vector','normal_integral','zero_measure_samples','normal_convention','certified_error_bound'}
    if f['reals']:keys.add('time')
    check(set(r)==keys,'complete original normal integral DTO including absence of optional time')
    check((r['field_index'],r['name'],r['location'],r['time_step'],r.get('time'))==(index,f['strings'][0],f['location'],f['integers'][0],f['reals'][0] if f['reals'] else None),'selected original section identity/time')
    check(r['elements']==len(h['element_tags']) and r['samples']==h['samples'] and r['skipped_lower_dimension']==0 and r['rules']==['triangle:Gauss4'],'selected faces and existing fixed rule counts')
    close([r['surface_measure']],[h['surface_measure']],'independent planar group area')
    close(r['area_vector'],h['area_vector'],'independent oriented area vector')
    expected=h['normal_integral'] if index==1 else ([30,0,0] if index==2 else ([-3,0,4] if g==44 else [0,0,0]))
    close(r['normal_integral'],expected,'independent affine nodal/constant cell analytical resultant')
    check(r['zero_measure_samples']==0 and r['normal_convention']=='stored_node_winding' and r['certified_error_bound'] is False,'orientation/estimate limits retained')

pub=json.loads(public.read_text(encoding='utf-8'))
check(pub['field_index']==1 and pub['source_unchanged'] and pub['group_aggregate_provided'] is False,'public composition preserves source and no overlap aggregate')
check([r['physical_group'] for r in pub['groups']]==[55,44],'public group request order')
for row in pub['groups']:
    check(row['mesh']==hand['groups'][str(row['physical_group'])]['mesh'],'public receiver complete context/field/node-role witness')
    estimate(row['estimate'],row['physical_group'],1)

def call(name,options=None,src=source,expected=0,request_bytes=None,destination=None):
    options={'field_index':1,'groups':[55,44],'max_samples':12} if options is None else options
    req=out/(name+'-请求.json');req.write_bytes(request_bytes if request_bytes is not None else (json.dumps(options,ensure_ascii=False)+'\n').encode('utf-8'))
    dest=out/(name+'-bundle') if destination is None else destination
    before=(sha(src.read_bytes()),sha(req.read_bytes()))
    argv=[node,str(root/'examples/group_resultants/run.mjs'),str(src),str(req),str(dest)]
    r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8')
    commands.append({'name':name,'argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
    # Keep a failed attempt's real stdout/stderr even if a later assertion fails.
    (out/'file-calls-so-far.json').write_text(json.dumps(commands,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    check(r.returncode==expected,name+' expected exit')
    check((sha(src.read_bytes()),sha(req.read_bytes()))==before,name+' original input/request bytes unchanged')
    if expected:
        check(not r.stdout and (destination is not None or not dest.exists()),name+' no stdout/partial delivery')
    else:check(json.loads(r.stdout)['output']==str(dest.resolve()),name+' actual file destination')
    return dest,req,r

def receive(dest,req,groups,index,src=source,meshes=None):
    m=json.loads((dest/'manifest.json').read_text(encoding='utf-8'))
    check(m['schema']=='gmsh-group-resultants/v1' and m['field_index']==index and [g['physical_group'] for g in m['groups']]==groups,'manifest exact ordered request identity')
    check(m['source_file']=='original.msh' and m['request_file']=='request.json' and (dest/'original.msh').read_bytes()==src.read_bytes() and (dest/'request.json').read_bytes()==req.read_bytes(),'archived original/request exact raw bytes')
    check(set(m['outputs'])=={'original.msh','request.json',*[f'group-{i}{s}' for i in range(len(groups)) for s in ['.msh','-result.json']]} and {p.name for p in dest.iterdir()}==set(m['outputs'])|{'manifest.json'},'every output listed and physically consumed, no unlisted output')
    for filename,identity in m['outputs'].items():
        b=(dest/filename).read_bytes();check(identity=={'sha256':sha(b),'bytes':len(b)},'actual output byte length/SHA '+filename)
    for i,g in enumerate(groups):
        part=m['groups'][i];check(part=={'physical_group':g,'mesh_file':f'group-{i}.msh','result_file':f'group-{i}-result.json'},'manifest index-to-file mapping')
        expected_mesh=hand['groups'][str(g)]['mesh'] if meshes is None else meshes[str(g)]
        mesh_bytes=(dest/part['mesh_file']).read_bytes();check(mesh_bytes.startswith(('$MeshFormat\n'+expected_mesh['source_version']+' 1 8\n').encode()+b'\x01\0\0\0'),'actual requested source-version little-endian8 binary')
        mesh=parse(mesh_bytes);check(mesh==expected_mesh,'independent raw reader complete saved Mesh/context/headers/rows')
        row=json.loads((dest/part['result_file']).read_text(encoding='utf-8'))
        check(set(row)=={'physical_group','dimension','field_index','source_frame','mesh_frame','estimate'} and row['physical_group']==g and row['dimension']==2 and row['field_index']==index,'complete group result envelope')
        check(row['source_frame']==frame(hand['source']['fields'][index],index) and row['mesh_frame']==frame(mesh['fields'][index],index),'source/filtered frame catalogs exact metadata and entry counts')
        estimate(row['estimate'],g,index)
    check('aggregate' not in m and m['encoding']=={'version':'source_version','binary':True,'little':True,'size_width':8},'no invented cross-group sum; encoding disclosed')
    return m

dest,req,_=call('default');receive(dest,req,[55,44],1)
# A second same-name/time section is intentionally sparse. Its exact source index
# works on group66 but cannot be silently substituted on the other groups.
d,q,_=call('sparse-selected',{'field_index':2,'groups':[66]});receive(d,q,[66],2)
d,q,_=call('cell-no-time',{'field_index':3,'groups':[55,44]});receive(d,q,[55,44],3)
opaque=out/'opaque.msh';opaque.write_bytes(source.read_bytes()+b'$Opaque\n0\n$EndOpaque\n')
d,q,_=call('explicit-drop',{'field_index':1,'groups':[55,44],'drop_unknown':True},src=opaque);receive(d,q,[55,44],1,src=opaque)
# Separately hand-written2.2 input keeps the same-version output contract and
# known extra element tags; it is not made using the product encoder.
m22=copy.deepcopy(hand['source']);m22['source_version']='2.2';m22['entities']=[]
for n in m22['nodes']:n.update(dim=-1,entity=0,parameters=[])
for e in m22['elements']:e.update(physical=e['physical'][:1],extra=[1,17])
s='$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$PhysicalNames\n4\n'+''.join(f'{n["dim"]} {n["tag"]} '+json.dumps(n['name'],ensure_ascii=False)+'\n' for n in m22['physical_names'])+'$EndPhysicalNames\n$Nodes\n5\n'
s+=''.join(str(n['tag'])+' '+' '.join(map(str,n['xyz']))+'\n' for n in m22['nodes'])+'$EndNodes\n$Elements\n4\n'
for e in m22['elements']:s+=f'{e["tag"]} {e["kind"]} 4 '+ ' '.join(map(str,[e['physical'][0],e['entity'],*e['extra'],*e['nodes']]))+'\n'
s+='$EndElements\n'
for f in m22['fields']:
    s+='$'+f['location']+'\n'
    for values,conv in [(f['strings'],lambda v:json.dumps(v,ensure_ascii=False)),(f['reals'],str),(f['integers'],str)]:s+=str(len(values))+'\n'+''.join(conv(v)+'\n' for v in values)
    s+=''.join(str(d['tag'])+' '+' '.join(map(str,d['values']))+'\n' for d in f['entries'])+'$End'+f['location']+'\n'
source22=out/'hand22.msh';source22.write_bytes(s.encode('utf-8'));check(parse(source22.read_bytes())==m22,'independent hand2.2 source extra tags/context')
expected22=copy.deepcopy(hand['groups']['44']['mesh']);expected22['source_version']='2.2';expected22['entities']=[]
for n in expected22['nodes']:n.update(dim=-1,entity=0,parameters=[])
for e in expected22['elements']:e.update(physical=[44],extra=[1,17])
d,q,_=call('source22',{'field_index':1,'groups':[44]},src=source22);receive(d,q,[44],1,src=source22,meshes={'44':expected22})
bad_cases=[('no-field',{'groups':[44]}),('negative-field',{'field_index':-1,'groups':[44]}),('fractional-field',{'field_index':.5,'groups':[44]}),('outside-field',{'field_index':4,'groups':[44]}),('no-groups',{'field_index':1}),('empty-groups',{'field_index':1,'groups':[]}),('duplicate-groups',{'field_index':1,'groups':[44,44]}),('group-zero',{'field_index':1,'groups':[0]}),('fractional-group',{'field_index':1,'groups':[44.5]}),('too-many-groups',{'field_index':1,'groups':list(range(1,18))}),('unknown-option',{'field_index':1,'groups':[44],'version':'4.1'}),('null-budget',{'field_index':1,'groups':[44],'max_samples':None}),('bool-budget',{'field_index':1,'groups':[44],'max_samples':True}),('string-drop',{'field_index':1,'groups':[44],'drop_unknown':'false'}),('later-absent-group',{'field_index':1,'groups':[66,999]}),('later-missing-node',{'field_index':2,'groups':[66,44]}),('later-sample-budget',{'field_index':1,'groups':[66,44],'max_samples':6}),('nonscalar-scheme',{'field_index':0,'groups':[44]})]
for name,o in bad_cases:call(name,o,expected=2)
call('opaque-kept',src=opaque,expected=2);call('loss-not-drop',{'field_index':1,'groups':[44],'allow_loss':True},src=opaque,expected=2)
named=out/'named-interpolation.msh';named.write_bytes(source.read_bytes().replace('"压力"\n""\n"source-extra"'.encode(), '"压力"\n"named"\n"source-extra"'.encode(),1));call('scalar-scheme',src=named,expected=2)
_,_,r=call('invalid-utf8',request_bytes=b'{"field_index":1,"groups":[44]}\xff',expected=2);check('valid UTF-8' in r.stderr,'strict UTF8 validation precedes replacement parsing')
saved={p.name:sha(p.read_bytes()) for p in dest.iterdir()};call('no-overwrite',destination=dest,expected=2);check({p.name:sha(p.read_bytes()) for p in dest.iterdir()}==saved,'existing complete delivery byte unchanged')
check(sha(source.read_bytes())==source_sha,'original hand source still byte identical after all calls')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'commands':commands,'checkLabels':checks,
         'publicReceipt':{'path':str(public),'sha256':sha(public.read_bytes())},'handExpectedSha256':sha((root/'examples/group_resultants/expected.json').read_bytes()),
         'manualSourceSha256':source_sha,'workflowSha256':sha((root/'examples/group_resultants/run.mjs').read_bytes()),
         'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),
         'independentOrigin':'Literal original MSH/complete hand context plus elementary affine planar integrals. Raw struct/ASCII parser consumes all saved files. No product dump/encoder as oracle; no curved-science rerun.',
         'receivingBoundary':'Self-authored actual public/file receiving, not third-party adoption or numerical certification.'}
with evidence.open('x',encoding='utf-8') as stream:stream.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'completeBundles':5,'laterGroupFailureHasNoDestination':True}))

