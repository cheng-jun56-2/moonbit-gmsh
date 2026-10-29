"""Independent complete file receiving for exact dimension-scoped physical names."""
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
root=Path(__file__).resolve().parents[1];out=Path(a.outputs).resolve();evidence=Path(a.evidence).resolve();public=Path(a.public_receipt).resolve();assert not out.exists() and not evidence.exists(),'Choose new paths';out.mkdir();node=shutil.which('node');assert node
hand=json.loads((root/'examples/physical_name/expected.json').read_text(encoding='utf-8'));source=out/'原 名称网格.msh';source.write_bytes((root/'examples/physical_name/source.msh').read_bytes());commands=[];checks=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def ident(p):
    p=Path(p);b=p.read_bytes();return {'path':str(p),'sha256':sha(b),'bytes':len(b)}
def check(v,label):checks.append(label);assert v,label
check(parse(source.read_bytes())==hand['source'],'complete literal original MSH and declared names/entities/fields')
pub=json.loads(public.read_text(encoding='utf-8'))
for key,row in hand['expected'].items():check(pub[key]==row['mesh'],'public entire Mesh for exact label '+key)
check(pub['source_unchanged'] is True and pub['ownership_isolated'] is True,'public source and getter/result ownership')

def call(name,options=None,src=source,expected=0,expected_mesh=None,command='physical-name',raw_options=None,destination=None):
    options=hand['expected']['wall']['request'] if options is None else options;req=out/(name+'-请求.json');req.write_bytes(raw_options if raw_options is not None else (json.dumps(options,ensure_ascii=False)+'\n').encode('utf-8'));dest=out/(name+'.msh') if destination is None else destination;before=[ident(src),ident(req)];argv=[node,str(root/'tools/gmsh.mjs'),command,str(src),str(req),str(dest)];p=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');commands.append({'name':name,'argv':argv,'exitCode':p.returncode,'stdout':p.stdout,'stderr':p.stderr});(out/'file-calls-so-far.json').write_text(json.dumps(commands,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    check(p.returncode==expected,name+' actual expected exit');check([ident(src),ident(req)]==before,name+' original/options raw bytes unchanged');check(not p.stdout,name+' no unexpected stdout')
    if expected:check(destination is not None or not dest.exists(),name+' no partial output')
    else:
        received=parse(dest.read_bytes());check(received==(hand['expected']['wall']['mesh'] if expected_mesh is None else expected_mesh),name+' independent entire selected Mesh/headers/data/context')
    return dest,p

dest,_=call('wall')
for key in ['line','outlet','declared','empty_name']:call(key,hand['expected'][key]['request'],expected_mesh=hand['expected'][key]['mesh'])
call('binary41-be4',{**hand['expected']['wall']['request'],'binary':True,'little':False,'size_width':4})
expected22=copy.deepcopy(hand['expected']['wall']['mesh']);expected22['source_version']='2.2';expected22['entities']=[]
for n in expected22['nodes']:n.update(dim=-1,entity=0,parameters=[])
call('loss-required',{**hand['expected']['wall']['request'],'version':'2.2'},expected=2)
call('explicit-loss22-be',{**hand['expected']['wall']['request'],'version':'2.2','binary':True,'little':False,'allow_loss':True},expected_mesh=expected22)

# Ambiguity is legal source metadata. Do not reject the file or change numeric
# selection merely to make the new name request pass.
original=source.read_text(encoding='utf-8');extra='2 66 '+json.dumps('热壁 面',ensure_ascii=False)+'\n';ambiguous=out/'合法 同维重名.msh';ambiguous.write_text(original.replace('$PhysicalNames\n5\n','$PhysicalNames\n6\n').replace('$EndPhysicalNames\n',extra+'$EndPhysicalNames\n'),encoding='utf-8',newline='\n');ambig_data=copy.deepcopy(hand['source']);ambig_data['physical_names'].append({'dim':2,'tag':66,'name':'热壁 面'});check(parse(ambiguous.read_bytes())==ambig_data,'duplicate-name source independently legal full metadata')
_,error=call('ambiguous',src=ambiguous,expected=2);check('ambiguous' in error.stderr,'new request rejects ambiguity rather than preferring populated group')
wall_ambig=copy.deepcopy(hand['expected']['wall']['mesh']);wall_ambig['physical_names']=ambig_data['physical_names'];call('old-numeric-still-valid',{'dimension':2,'group':44},src=ambiguous,command='physical',expected_mesh=wall_ambig)
line_ambig=copy.deepcopy(hand['expected']['line']['mesh']);line_ambig['physical_names']=ambig_data['physical_names'];call('cross-dimension-still-unique',hand['expected']['line']['request'],src=ambiguous,expected_mesh=line_ambig)
literal=out/'数字 字面名称.msh';literal.write_text(ambiguous.read_text(encoding='utf-8').replace(extra,'2 66 "44"\n'),encoding='utf-8',newline='\n');literal_expected=copy.deepcopy(hand['expected']['declared']['mesh']);literal_expected['physical_names'].append({'dim':2,'tag':66,'name':'44'});call('numeric-name-is-label',{'dimension':2,'name':'44'},src=literal,expected_mesh=literal_expected)
opaque=out/'opaque.msh';opaque.write_bytes(source.read_bytes()+b'$Opaque\nreferences\n$EndOpaque\n');call('opaque-kept',src=opaque,expected=2);call('loss-not-drop',{'dimension':2,'name':'热壁 面','allow_loss':True},src=opaque,expected=2);call('explicit-drop',{'dimension':2,'name':'热壁 面','drop_unknown':True},src=opaque)

def write22(m):
    s='$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$PhysicalNames\n'+str(len(m['physical_names']))+'\n'+''.join(f'{n["dim"]} {n["tag"]} '+json.dumps(n['name'],ensure_ascii=False)+'\n' for n in m['physical_names'])+'$EndPhysicalNames\n$Nodes\n'+str(len(m['nodes']))+'\n'+''.join(str(n['tag'])+' '+' '.join(map(str,n['xyz']))+'\n' for n in m['nodes'])+'$EndNodes\n$Elements\n'+str(len(m['elements']))+'\n'
    for e in m['elements']:
        tags=[e['physical'][0] if e['physical'] else 0,e['entity'],*e['extra']];s+=f'{e["tag"]} {e["kind"]} {len(tags)} '+' '.join(map(str,[*tags,*e['nodes']]))+'\n'
    s+='$EndElements\n'
    for f in m['fields']:
        s+='$'+f['location']+'\n'
        for values,convert in [(f['strings'],lambda x:json.dumps(x,ensure_ascii=False)),(f['reals'],str),(f['integers'],str)]:s+=str(len(values))+'\n'+''.join(convert(x)+'\n' for x in values)
        s+=''.join(str(d['tag'])+' '+' '.join(map(str,d['values']))+'\n' for d in f['entries'])+'$End'+f['location']+'\n'
    return s.encode('utf-8')
m22=copy.deepcopy(hand['source']);m22['source_version']='2.2';m22['entities']=[]
for n in m22['nodes']:n.update(dim=-1,entity=0,parameters=[])
for e in m22['elements']:e['extra']=[1,17]
source22=out/'hand22.msh';source22.write_bytes(write22(m22));check(parse(source22.read_bytes())==m22,'independent original2.2 input including legacy extra tags')
wall22=copy.deepcopy(expected22)
for e in wall22['elements']:e['extra']=[1,17]
call('source22-name',src=source22,expected_mesh=wall22)
replacement=out/'合法 替换字符名称.msh';replacement.write_text(original.replace('2 44 "热壁 面"','2 44 "\ufffd"'),encoding='utf-8',newline='\n');replacement_expected=copy.deepcopy(hand['expected']['wall']['mesh']);replacement_expected['physical_names'][0]['name']='\ufffd';call('legal-replacement-name',{'dimension':2,'name':'\ufffd'},src=replacement,expected_mesh=replacement_expected)
for name,options in [('missing-dimension',{'name':'热壁 面'}),('negative-dimension',{'dimension':-1,'name':'热壁 面'}),('too-high-dimension',{'dimension':4,'name':'热壁 面'}),('fractional-dimension',{'dimension':.5,'name':'热壁 面'}),('string-dimension',{'dimension':'2','name':'热壁 面'}),('missing-name',{'dimension':2}),('name-type',{'dimension':2,'name':44}),('unknown-name',{'dimension':2,'name':'unknown'}),('partial-name',{'dimension':2,'name':'热壁'}),('case-sensitive',{'dimension':2,'name':'OUTLET'}),('no-numeric-fallback',{'dimension':2,'name':'44'}),('wrong-dimension',{'dimension':3,'name':'热壁 面'}),('empty-not-declared-here',{'dimension':2,'name':''})]:call(name,options,expected=2)
_,error=call('invalid-utf8',raw_options=b'{"dimension":2,"name":"\xff"}',expected=2);check('valid UTF-8' in error.stderr,'existing strict raw options UTF8 gate retained')
old=ident(dest);call('no-overwrite',destination=dest,expected=2);check(ident(dest)==old,'existing full selected output unchanged')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'commands':commands,'checkLabels':checks,'publicReceipt':ident(public),'manualSource':ident(source),'handExpectedSha256':sha((root/'examples/physical_name/expected.json').read_bytes()),'coreSourceSha256':sha((root/'physical_name.mbt').read_bytes()),'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),'consumerSource':ident(Path(__file__)),'actualTestInputCopies':[{'original':ident(root/'examples/physical_name/source.msh'),'copy':ident(source)}],'independentOrigin':'Literal originalMSH4.1 and explicit dimension/name/tag choices; full raw2.2/4.1 ASCII/binary reader compares every node/role/context/header/row. Independent2.2 source writer. No new lookup/encoder/verifier as expected-value oracle.','receivingBoundary':'Self-authored real public/file integration; not external adoption,names-as-authenticity or physical certification.'}
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'completePositiveMeshes':13}))
