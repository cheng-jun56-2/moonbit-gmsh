"""Independent complete saved mesh/field receiving against frozen hand originals."""
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
            arity={1:2,2:3,6:6,11:10,15:1}
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
hand=json.loads((root/'examples/verify_vtk_mesh/expected.json').read_text(encoding='utf-8'));commands=[];checks=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def ident(p):
    p=Path(p);b=p.read_bytes();return {'path':str(p),'sha256':sha(b),'bytes':len(b)}
def check(v,label):checks.append(label);assert v,label
source=out/'原 网格.msh';vtk=out/'原 图形.vtk';audit=out/'原 全头.json'
for dest,name in [(source,'source.msh'),(vtk,'saved.vtk'),(audit,'audit.json')]:dest.write_bytes((root/'examples/verify_vtk_mesh'/name).read_bytes())
check(parse(source.read_bytes())==hand['source'],'independent full hand MSH including actual data rows and metadata')
check(json.loads(audit.read_text(encoding='utf-8'))==hand['audit'],'original complete hand sidecar before execution')

def read_vtk(b):
    lines=b.decode('utf-8').splitlines();assert lines[0]=='# vtk DataFile Version 3.0' and lines[2]=='ASCII';t=iter(' '.join(lines[3:]).split())
    def word(w):assert next(t)==w
    word('DATASET');word('UNSTRUCTURED_GRID');word('POINTS');n=int(next(t));word('double');points=[[float(next(t)) for _ in range(3)] for _ in range(n)]
    word('CELLS');nc=int(next(t));size=int(next(t));cells=[]
    for _ in range(nc):cells.append([int(next(t)) for _ in range(int(next(t)))])
    assert sum(1+len(c) for c in cells)==size;word('CELL_TYPES');assert int(next(t))==nc;types=[int(next(t)) for _ in range(nc)];arrays={}
    remaining=list(t);t=iter(remaining)
    while True:
        try:association=next(t)
        except StopIteration:break
        count=int(next(t));assert association in ['POINT_DATA','CELL_DATA'];word('FIELD');word('FieldData');na=int(next(t));values={}
        for _ in range(na):
            name=next(t);components=int(next(t));tuples=int(next(t));kind=next(t);assert tuples==count and kind in ['double','int'];conv=float if kind=='double' else int;values[name]=[[conv(next(t)) for _ in range(components)] for _ in range(tuples)]
        arrays[association]=values
    return {'points':points,'connectivity':cells,'cell_types':types,'arrays':arrays}

raw=read_vtk(vtk.read_bytes());check({k:raw[k] for k in ['points','connectivity','cell_types']}=={k:hand['expected'][k] for k in ['points','connectivity','cell_types']},'independent exact saved geometry and nontrivial wedge/Tet10 permutations')
check(raw['arrays']=={'POINT_DATA':{'gmsh_value_0':[[i+1] for i in range(17)],'gmsh_value_1':[[i,2*i,-i] for i in range(17)],'gmsh_tag':[[t] for t in hand['expected']['source_node_tags']]},'CELL_DATA':{'gmsh_value_2':[list(range(1,10)),list(range(9,0,-1))],'gmsh_tag':[[700],[8]]}},'independent entire saved field and original tag arrays')
pub=json.loads(public.read_text(encoding='utf-8'));check(pub['readback']==hand['expected'] and pub['ownership_isolated'] is True and pub['geometric_validity_certified'] is False,'public full readback equals frozen geometry+fields with ownership and limits')

def call(name,src=source,view=vtk,sidecar=audit,expected=0,expected_result=None,destination=None):
    dest=out/(name+'-result.json') if destination is None else destination;before=[ident(p) for p in [src,view,sidecar]];argv=[node,str(root/'examples/verify_vtk_mesh/run.mjs'),str(src),str(view),str(sidecar),str(dest)];r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');commands.append({'name':name,'argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr});(out/'file-calls-so-far.json').write_text(json.dumps(commands,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    check(r.returncode==expected,name+' expected actual exit');check([ident(p) for p in [src,view,sidecar]]==before,name+' all three original input bytes unchanged');check(not r.stdout,name+' no unexpected stdout')
    if expected:check(destination is not None or not dest.exists(),name+' no partial result file')
    else:check(json.loads(dest.read_text(encoding='utf-8'))==(hand['expected'] if expected_result is None else expected_result),name+' complete independently expected geometry/tag/field DTO')
    return dest,r

dest,_=call('original')
text=vtk.read_text(encoding='utf-8')
def variant(name,value):
    p=out/(name+'.vtk');p.write_text(value,encoding='utf-8',newline='\n');return p
call('numeric-spelling',view=variant('numeric-spelling',text.replace('0 0 0\n','-0.0 0e0 0.000\n',1)))
call('descriptive-title',view=variant('descriptive-title',text.replace('independent saved export','title is not identity')))
bad_geometry=[('isolated-coordinate',text.replace('9 9 9\n','9 9 9.5\n')),('ordered-role',text.replace('6 0 2 1 3 5 4\n','6 0 1 2 3 5 4\n')),('positive-wrong-type',text.replace('CELL_TYPES 2\n13\n24','CELL_TYPES 2\n12\n24')),('cell-arity',text.replace('CELLS 2 18','CELLS 2 17').replace('6 0 2 1 3 5 4\n','5 0 2 1 3 5\n'))]
for name,value in bad_geometry:
    view=variant(name,value);parsed=read_vtk(view.read_bytes());check(parsed['arrays']==raw['arrays'],name+' independently retains every original field/tag array');_,r=call(name,view=view,expected=2);check('VTK source' in r.stderr,name+' rejection is exact source geometry comparison')
changed_source=out/'changed-source.msh';changed_source.write_bytes(source.read_bytes().replace(b'2147483647 9 9 9\n',b'2147483647 9 9 9.5\n'));call('source-coordinate',src=changed_source,expected=2)
call('field-value',view=variant('field-value',text.replace('gmsh_value_0 1 17 double\n1\n','gmsh_value_0 1 17 double\n99\n')),expected=2)
call('tag-order',view=variant('tag-order',text.replace('gmsh_tag 1 17 int\n90\n7\n','gmsh_tag 1 17 int\n7\n90\n')),expected=2)
bad_audit=copy.deepcopy(hand['audit']);bad_audit['fields'][1]['strings'][0]='wrong';bad_audit_file=out/'bad-head.json';bad_audit_file.write_text(json.dumps(bad_audit,ensure_ascii=False),encoding='utf-8');call('audit-raw-head',sidecar=bad_audit_file,expected=2)
call('connectivity-bounds',view=variant('bounds',text.replace('6 0 2 1 3 5 4\n','6 0 2 1 3 5 17\n')),expected=2)
call('wrong-profile',view=variant('profile',text.replace('\nASCII\n','\nBINARY\n',1)),expected=2)
call('trailing-data',view=variant('trailing',text+'unexpected\n'),expected=2)
invalid=out/'invalid-utf8.json';invalid.write_bytes(b'{"note":"\xff"}');_,r=call('audit-invalid-utf8',sidecar=invalid,expected=2);check('valid UTF-8' in r.stderr,'strict raw audit UTF8 checked before replacement parsing')
legal=out/'legal-replacement.json';legal.write_text(json.dumps({**hand['audit'],'note':'\ufffd'},ensure_ascii=False),encoding='utf-8');call('audit-legal-replacement',sidecar=legal)
shape=out/'wrong-shape.json';shape.write_text('[]',encoding='utf-8');call('audit-shape',sidecar=shape,expected=2)

# Fixed small independent additional originals, authored before execution.
def small(name,cell):
    src=out/(name+'.msh');view=out/(name+'.vtk');side=out/(name+'.json');n=1 if cell else 0;loc='ElementData' if cell else 'NodeData';components=3 if cell else 1;fname='cell' if cell else 'empty'
    s='$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$Nodes\n'+str(n)+'\n'+('7 1 2 3\n' if cell else '')+'$EndNodes\n$Elements\n'+str(n)+'\n'+('50 15 0 7\n' if cell else '')+'$EndElements\n$'+loc+'\n1\n"'+fname+'"\n0\n3\n0\n'+str(components)+'\n'+str(n)+'\n'+('50 4 5 6\n' if cell else '')+'$End'+loc+'\n';src.write_text(s,encoding='utf-8',newline='\n')
    v='# vtk DataFile Version 3.0\nmanual\nASCII\nDATASET UNSTRUCTURED_GRID\nPOINTS '+str(n)+' double\n'+('1 2 3\n' if cell else '')+'CELLS '+str(n)+' '+str(2*n)+'\n'+('1 0\n' if cell else '')+'CELL_TYPES '+str(n)+'\n'+('1\n' if cell else '')+('CELL_DATA' if cell else 'POINT_DATA')+' '+str(n)+'\nFIELD FieldData 2\ngmsh_value_0 '+str(components)+' '+str(n)+' double\n'+('4 5 6\n' if cell else '')+'gmsh_tag 1 '+str(n)+' int\n'+('50\n' if cell else '');view.write_text(v,encoding='utf-8',newline='\n')
    frame={'field_index':0,'name':fname,'location':loc,'components':components,'time_step':0,'entries':n};loss=['msh_field_headers_not_in_vtk']+(['other_association_tags_not_in_vtk'] if cell else []);meta={'source_version':'2.2','omitted_field_indices':[],'losses':loss,'fields':[{'field':frame,'value_array':'gmsh_value_0','strings':[fname],'reals':[],'integers':[0,components,n]}]};side.write_text(json.dumps(meta),encoding='utf-8')
    expected_fields={'points':n,'cells':n,'has_point_tags':not cell,'has_cell_tags':cell,'point_tags':[],'cell_tags':[50] if cell else [],'fields':[{'field':frame,'value_array':'gmsh_value_0','values':[[4,5,6]] if cell else []}],'source_version':'2.2','omitted_field_indices':[],'losses':loss}
    expected={'fields':expected_fields,'source_node_tags':[7] if cell else [],'source_element_tags':[50] if cell else [],'points':[[1,2,3]] if cell else [],'connectivity':[[0]] if cell else [],'cell_types':[1] if cell else []};call(name,src=src,view=view,sidecar=side,expected_result=expected)
small('cell-only-missing-point-tags',True);small('empty-selected-tuples',False)
old=ident(dest);call('no-overwrite',destination=dest,expected=2);check(ident(dest)==old,'existing complete readback file stays exact')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'commands':commands,'checkLabels':checks,'publicReceipt':ident(public),'manualOriginals':{k:ident(v) for k,v in [('source',source),('vtk',vtk),('audit',audit)]},'handExpectedSha256':sha((root/'examples/verify_vtk_mesh/expected.json').read_bytes()),'coreSourceSha256':sha((root/'vtk_mesh_compare.mbt').read_bytes()),'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),'consumerSource':ident(Path(__file__)),'actualTestInputCopies':[{'original':ident(root/'examples/verify_vtk_mesh'/n),'copy':ident(d)} for d,n in [(source,'source.msh'),(vtk,'saved.vtk'),(audit,'audit.json')]],'independentOrigin':'Frozen literal originalMSH/VTK/audit,independent MSH/VTK readers,explicit wedge/Tet10 role/type arrays and full field/tag values. Small original profiles are literal,not product generated. No product exporter/new checker as expected-value oracle.','receivingBoundary':'Actual self-authored complete public/file receiving of existing ordered representation; not external adoption,authenticity/full-MSH/geometry validity certification.'}
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'completePositiveReports':6}))
