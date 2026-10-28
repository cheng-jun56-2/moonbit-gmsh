"""Self-authored file/public receiving integration with frozen hand values.
Only the test's2.2 ASCII input is parsed here; no product evaluator/exporter
generates expected values or source/header witnesses. No mesher is invoked.
"""
import argparse,copy,hashlib,json,shutil,subprocess
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--evidence',required=True);p.add_argument('--outputs',required=True);p.add_argument('--public-receipt',required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(args.outputs).resolve();evidence=Path(args.evidence).resolve();public=Path(args.public_receipt).resolve()
assert not out.exists() and not evidence.exists(),'Choose new paths';out.mkdir();node=shutil.which('node');assert node
checks=[];commands=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def check(v,label):checks.append(label);assert v,label
def parse(data):
    lines=data.decode('utf-8').splitlines();i=0;nodes=[];elements=[];fields=[]
    while i<len(lines):
        marker=lines[i];i+=1
        if marker=='$Nodes':
            count=int(lines[i]);i+=1
            for _ in range(count):
                row=lines[i].split();i+=1;nodes.append((int(row[0]),list(map(float,row[1:]))))
        elif marker=='$Elements':
            count=int(lines[i]);i+=1
            for _ in range(count):
                row=list(map(int,lines[i].split()));i+=1;elements.append((row[0],row[1],row[3+row[2]:]))
        elif marker in ['$NodeData','$ElementData']:
            groups=[]
            for convert in [json.loads,float,int]:
                count=int(lines[i]);i+=1;groups.append([convert(v) for v in lines[i:i+count]]);i+=count
            entries=[]
            for _ in range(groups[2][2]):
                row=lines[i].split();i+=1;entries.append((int(row[0]),list(map(float,row[1:]))))
            fields.append({'location':marker[1:],'strings':groups[0],'reals':groups[1],'integers':groups[2],'entries':entries})
    return {'nodes':nodes,'elements':elements,'fields':fields}
def encode(m):
    s='$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$Nodes\n'+str(len(m['nodes']))+'\n'
    s+=''.join(str(t)+' '+' '.join(map(str,xyz))+'\n' for t,xyz in m['nodes'])+'$EndNodes\n$Elements\n'+str(len(m['elements']))+'\n'
    s+=''.join(f'{t} {kind} 0 '+' '.join(map(str,roles))+'\n' for t,kind,roles in m['elements'])+'$EndElements\n'
    for f in m['fields']:
        s+='$'+f['location']+'\n'
        for values,convert in [(f['strings'],lambda x:json.dumps(x,ensure_ascii=False)),(f['reals'],str),(f['integers'],str)]:s+=str(len(values))+'\n'+''.join(convert(v)+'\n' for v in values)
        s+=''.join(str(t)+' '+' '.join(map(str,row))+'\n' for t,row in f['entries'])+'$End'+f['location']+'\n'
    return s.encode('utf-8')
base_bytes=(root/'examples/tet4_field/source.msh').read_bytes();base=parse(base_bytes);source=out/'手写 原件.msh';source.write_bytes(base_bytes)
tags=[90,10,700,2147483647];role_xyz=[[0,0,0],[2,0,0],[0,3,0],[0,0,4]]
points=[([0,0,0],[1,0,0,0],[0,0,0],1),([1,0,0],[0,1,0,0],[2,0,0],3),([0,1,0],[0,0,1,0],[0,3,0],7),([0,0,1],[0,0,0,1],[0,0,4],13),([.5,0,0],[.5,.5,0,0],[1,0,0],2),([.25,.25,0],[.5,.25,.25,0],[.5,.75,0],3),([.5,.25,.25],[0,.5,.25,.25],[1,.75,1],6.5),([.25,.125,.125],[.5,.25,.125,.125],[.5,.375,.5],3.75)]
interior=points[-1]
def witness(r,index,m,ref,weights,xyz,values):
    f=m['fields'][index];roles=m['elements'][0][2];coords=dict(m['nodes']);data=dict(f['entries'])
    frame={'field_index':index,'name':f['strings'][0],'location':f['location'],'components':f['integers'][1],'time_step':f['integers'][0],'entries':len(f['entries'])}
    if f['reals']:frame['time']=f['reals'][0]
    if len(f['strings'])>1 and f['strings'][1]:frame['interpolation_scheme']=f['strings'][1]
    if len(f['integers'])>3:frame['partition']=f['integers'][3]
    check(r['field']==frame,'exact current frame and optional raw metadata')
    check(r['source_version']=='2.2' and r['element_tag']==m['elements'][0][0] and r['element_type']==4,'original source/element identity')
    check(r['node_tags']==roles and r['reference']==ref and r['weights']==weights,'original role order and frozen reference weights')
    check(r['node_xyz']==[coords[t] for t in roles] and r['nodal_values']==[data[t] for t in roles],'complete original coordinate and tagged-value witnesses')
    check(all(r[k]==f[k] for k in ['strings','reals','integers']),'complete original raw heads unchanged')
    check(r['xyz']==xyz and r['values']==values,'independent hand point values and forward coordinates')
def call(name,index=0,ref=None,input_file=source,extra=None,expected=0,command='evaluate-tet4-field',omit=None):
    options={'field_index':index,'element_tag':201,'reference':interior[0] if ref is None else ref};options.update(extra or {})
    if omit:options.pop(omit)
    opt=out/(name+'-选项.json');opt.write_text(json.dumps(options,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8',newline='\n');target=out/(name+'-结果.json')
    before={p:sha(p.read_bytes()) for p in [input_file,opt]};argv=[node,str(root/'tools/gmsh.mjs'),command,str(input_file),str(opt),str(target)];r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8')
    commands.append({'name':name,'argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'inputSha256':before[input_file],'optionsSha256':before[opt],'output':str(target),'outputSha256':sha(target.read_bytes()) if target.exists() else None})
    check(r.returncode==expected,'expected CLI exit '+str(expected));check(all(sha(p.read_bytes())==digest for p,digest in before.items()),'original MSH/options raw bytes unchanged')
    if expected:check(not target.exists() and not r.stdout,'no partial result file or success stdout');return None
    check(target.is_file(),'actual output file received');return json.loads(target.read_text(encoding='utf-8'))
def variant(name,change):
    m=copy.deepcopy(base);change(m);file=out/(name+'.msh');file.write_bytes(encode(m));return file,m
received=json.loads(public.read_text(encoding='utf-8'));check(received['evidence']=='self-authored public-package receiver' and received['source_unchanged'] and not received['geometry_certified'],'actual public receiver claims bounded integration only')
for index,values in [(0,[3.75]),(1,[.5,.375,.5]),(2,[3.75,7.5,11.25,15,18.75,22.5,26.25,30,33.75]),(3,[103.75])]:
    witness(received['evaluations'][index],index,base,*interior[:3],values)
    r=call('interior-'+str(index),index);witness(r,index,base,*interior[:3],values);check(r==received['evaluations'][index],'public API and real file receiver agree on complete result')
for i,(ref,weights,xyz,f) in enumerate(points):
    witness(call('point-'+str(i),ref=ref),0,base,ref,weights,xyz,[f])
    witness(call('constant-'+str(i),index=4,ref=ref),4,base,ref,weights,xyz,[-7])

for name,ref in [('shape0',[]),('shape2',[0,0]),('shape4',[0,0,0,0]),('negative',[-.001,0,0]),('outside',[.5,.5,.001]),('next-double',[1.0000000000000002,0,0])]:call(name,ref=ref,expected=2)
for name,extra in [('negative-index',{'field_index':-1}),('unknown-index',{'field_index':5}),('fraction-index',{'field_index':.5}),('unknown-tag',{'element_tag':202}),('fraction-tag',{'element_tag':201.5}),('unsafe-tag',{'element_tag':9007199254740993}),('wrong-reference-type',{'reference':'0,0,0'})]:call(name,extra=extra,expected=2)
for key in ['field_index','element_tag','reference']:call('missing-'+key,omit=key,expected=2)
# Valid model outside query range, not a new input decoder restriction.
for name,kind,roles in [('triangle',2,tags[:3]),('high-order',11,[90,10,700,2147483647,90,10,700,90,10,700])]:
    file,m=variant(name,lambda m,kind=kind,roles=roles:m.update(elements=[(201,kind,roles)]));call(name,input_file=file,expected=2)
file,m=variant('named-scheme',lambda m:m['fields'][0].update(strings=['温度','custom']));call('named-scheme',input_file=file,expected=2)
file,m=variant('element-data',lambda m:m['fields'][0].update(location='ElementData',entries=[(201,[1])],integers=[2,1,1]));call('element-data',input_file=file,expected=2)
def sparse(m):
    f=m['fields'][0];f['entries']=[d for d in f['entries'] if d[0]!=2147483647];f['integers'][2]=4
file,m=variant('missing-required-with-unrelated-fourth',sparse)
call('missing-interior',input_file=file,expected=2);call('missing-zero-weight',input_file=file,ref=[0,0,0],expected=2)
for name,reals,strings,integers in [('absent-time',[],['温度'],[2,1,5]),('explicit-zero',[0],['温度',''],[2,1,5,0,91])]:
    file,m=variant(name,lambda m,reals=reals,strings=strings,integers=integers:m['fields'][0].update(reals=reals,strings=strings,integers=integers));witness(call(name,input_file=file),0,m,*interior[:3],[3.75])
for name,roles,xyz,value in [('inverted',[90,700,10,2147483647],[.25,.75,.5],4.25),('repeated',[90,10,700,90],[.5,.375,0],2.25)]:
    file,m=variant(name,lambda m,roles=roles:m.update(elements=[(201,4,roles)]));witness(call(name,input_file=file),0,m,interior[0],interior[1],xyz,[value])
file,m=variant('degenerate',lambda m:m.update(nodes=[(t,[0,0,0]) for t,xyz in m['nodes']]))
witness(call('degenerate',input_file=file),0,m,interior[0],interior[1],[0,0,0],[3.75]);witness(call('degenerate-distinct-reference',input_file=file,ref=[1,0,0]),0,m,[1,0,0],[0,1,0,0],[0,0,0],[3])
file,m=variant('large',lambda m:m.update(nodes=[(t,[1.6e308,0,0] if t==90 else [-1.6e308,0,0] if t==10 else xyz) for t,xyz in m['nodes']]))
witness(call('large',input_file=file,ref=[.5,0,0]),0,m,[.5,0,0],[.5,.5,0,0],[0,0,0],[2])
file,m=variant('field-underflow',lambda m:m['fields'][0].update(entries=[(t,[5e-324 if t==10 else 0]) for t,v in m['fields'][0]['entries']]))
call('field-underflow',input_file=file,ref=[.25,0,0],expected=2)
file,m=variant('coordinate-underflow',lambda m:m.update(nodes=[(t,[5e-324 if t==10 else 0,0,0]) for t,v in m['nodes']]))
call('coordinate-underflow',input_file=file,ref=[.25,0,0],expected=2)
# JSON has no NaN token. Overflowing valid JSON numbers must also reject before
# output, whether the existing parser or the new finite gate reports it.
options=out/'nonfinite.json';options.write_text('{"field_index":0,"element_tag":201,"reference":[1e999,0,0]}',encoding='utf-8');target=out/'nonfinite-result.json';argv=[node,str(root/'tools/gmsh.mjs'),'evaluate-tet4-field',str(source),str(options),str(target)];r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');commands.append({'name':'nonfinite','argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr});check(r.returncode==2 and not target.exists() and not r.stdout,'nonfinite reference leaves no partial result')
# Old route ignores these new-route options under its unchanged policy.
r=call('old-inspect-options',command='inspect',extra={'field_index':999,'element_tag':0,'reference':'ignored'});check(r['nodes']==5 and r['elements']==1,'new options do not alter old inspect route')
target=out/'interior-0-结果.json';before=sha(target.read_bytes());argv=[node,str(root/'tools/gmsh.mjs'),'evaluate-tet4-field',str(source),str(out/'interior-0-选项.json'),str(target)];r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');commands.append({'name':'no-overwrite','argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr});check(r.returncode==2 and sha(target.read_bytes())==before,'new route retains existing output no-overwrite contract')
check(source.read_bytes()==base_bytes,'entire original input unchanged after all success/failure calls')
receipt={'status':'PASS','checks':len(checks),'fileCalls':len(commands),'commands':commands,'checkLabels':checks,'publicReceipt':{'path':str(public),'sha256':sha(public.read_bytes())},'manualSource':{'path':str(source),'sha256':sha(base_bytes)},'querySourceSha256':sha((root/'tet4_field.mbt').read_bytes()),'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),'expectedOrigin':'Frozen hand values: f=1+x+2y+3z on four axial corners; vector xyz, nine i*f, explicit source indices and raw ASCII headers. No product-generated expectations.','adoptionBoundary':'Actual self-authored public/file integration, no customer/deployment claim.','limits':'One TET4 standard NodeData query; forward parametric mapping and protected range, not inverse/geometric/source/accuracy certification.'}
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'fileCalls':len(commands),'publicEvaluations':4}))
