"""Independent saved-bundle/source equality fixtures; no project writer oracle.
MSH ASCII/binary bytes follow the public Gmsh specification (struct packing).
The consumer only reads these existing files; no generation is requested of it.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--evidence',required=True)
parser.add_argument('--outputs',required=True)
args=parser.parse_args();root=Path(__file__).resolve().parents[1]
out=Path(args.outputs).resolve();evidence=Path(args.evidence).resolve()
assert not out.exists() and not evidence.exists(),'Choose new paths'
out.mkdir();node=shutil.which('node');assert node
checks=[];commands=[]
def sha(data):return hashlib.sha256(data).hexdigest()
def check(ok,label):checks.append(label);assert ok,label
def snapshot():return {p.relative_to(out).as_posix():sha(p.read_bytes()) if p.is_file() else None for p in out.rglob('*')}
def invoke(argv,expected=0):
    before=snapshot();r=subprocess.run([node,*map(str,argv)],cwd=root,capture_output=True,text=True,encoding='utf-8')
    check(r.returncode==expected,'expected exit '+str(expected));check(snapshot()==before,'all source/bundle bytes and directory entries unchanged')
    commands.append({'argv':[node,*map(str,argv)],'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
    if expected:check(not r.stdout,'failure has no partial success receipt');return None
    return json.loads(r.stdout)
def cli(bundle,source,options,compare=True,expected=0):return invoke([root/'examples/vtk_fields/verify.mjs',bundle,source,options,*(['--compare-source-fields'] if compare else [])],expected)

def field(location,name,components,entries):
    return {'location':location,'strings':[name,'','raw extra'],'reals':[1.5,7.25],'integers':[4,components,len(entries),17,42],'entries':entries}
fields=[field('NodeData','温度',1,[(10,[20]),(90,[10])]),field('NodeData','velocity',3,[(10,[4,5,6]),(90,[1,-2,3])]),field('ElementData','stress',9,[(201,list(range(1,10)))]),field('NodeData','温度',1,[(90,[99]),(10,[88])]),field('NodeData','温度',1,[(90,[123])])]

def msh(version='2.2',binary=False,endian='<',width=8,frames=None,empty=False):
    """Authored sparse IDs, opposite data-entry order, full raw heads.
    MSH field entry IDs remain int32 even in the4.1 size_t node/cell layout.
    """
    frames=fields if frames is None else frames
    pack=lambda fmt,*v:struct.pack(endian+fmt,*v)
    size='Q' if width==8 else 'I'
    data=f'$MeshFormat\n{version} {int(binary)} {width}\n'.encode()
    data+=(pack('i',1)+b'\n' if binary else b'')+b'$EndMeshFormat\n'
    if version=='2.2':
        nodes=b'' if empty else (pack('i3di3d',90,0,0,0,10,1,0,0) if binary else b'90 0 0 0\n10 1 0 0\n')
        cells=b'' if empty else (pack('6i',1,1,0,201,90,10) if binary else b'201 1 0 90 10\n')
        data+=b'$Nodes\n'+(b'0\n' if empty else b'2\n')+nodes+(b'\n' if binary and not empty else b'')+b'$EndNodes\n'
        data+=b'$Elements\n'+(b'0\n' if empty else b'1\n')+cells+(b'\n' if binary and not empty else b'')+b'$EndElements\n'
    else:
        assert not empty
        if binary:
            nodes=pack(size*4,1,2,10,90)+pack('iii'+size,1,7,0,2)+pack(size*2,90,10)+pack('6d',0,0,0,1,0,0)
            cells=pack(size*4,1,1,201,201)+pack('iii'+size,1,7,1,1)+pack(size*3,201,90,10)
            data+=b'$Nodes\n'+nodes+b'\n$EndNodes\n$Elements\n'+cells+b'\n$EndElements\n'
        else:
            data+=b'$Nodes\n1 2 10 90\n1 7 0 2\n90 10\n0 0 0 1 0 0\n$EndNodes\n$Elements\n1 1 201 201\n1 7 1 1\n201 90 10\n$EndElements\n'
    for f in frames:
        data+=('$'+f['location']+'\n'+str(len(f['strings']))+'\n'+''.join('"'+s+'"\n' for s in f['strings'])+str(len(f['reals']))+'\n'+''.join(str(v)+'\n' for v in f['reals'])+str(len(f['integers']))+'\n'+''.join(str(v)+'\n' for v in f['integers'])).encode('utf-8')
        if binary:
            data+=b''.join(pack('i'+str(len(v))+'d',tag,*v) for tag,v in f['entries'])
            if f['entries']:data+=b'\n'
        else:data+=''.join(str(tag)+' '+' '.join(str(v) for v in row)+'\n' for tag,row in f['entries']).encode()
        data+=('$End'+f['location']+'\n').encode()
    return data

vtk='# vtk DataFile Version 3.0\nnew independent source equality\nASCII\nDATASET UNSTRUCTURED_GRID\nPOINTS 2 double\n0 0 0 1 0 0\nCELLS 1 3\n2 0 1\nCELL_TYPES 1\n3\nPOINT_DATA 2\nFIELD FieldData 3\ngmsh_value_0 1 2 double\n10 20\ngmsh_value_1 3 2 double\n1 -2 3\n4 5 6\ngmsh_tag 1 2 int\n90 10\nCELL_DATA 1\nFIELD FieldData 2\ngmsh_value_2 9 1 double\n1 2 3 4 5 6 7 8 9\ngmsh_tag 1 1 int\n201\n'
def sidecar(version='2.2'):
    rows=[]
    for i in [2,0,1]:
        f=fields[i];rows.append({'field':{'field_index':i,'name':f['strings'][0],'location':f['location'],'components':f['integers'][1],'time_step':4,'time':1.5,'entries':len(f['entries']),'partition':17},'value_array':'gmsh_value_'+str(i),'strings':f['strings'],'reals':f['reals'],'integers':f['integers']})
    return {'source_version':version,'fields':rows,'omitted_field_indices':[3,4],'losses':['msh_field_headers_not_in_vtk','other_field_sections_omitted',*(['mesh_metadata_omitted'] if version=='4.1' else [])]}

def save(name,source_bytes,body=vtk,audit=None,indices=None):
    area=out/name;area.mkdir();bundle=area/'交付 包🙂';bundle.mkdir()
    source=area/'原 网格.msh';source.write_bytes(source_bytes)
    options=area/'选项.json';options.write_text(json.dumps({'field_indices':[2,0,1] if indices is None else indices,'allow_loss':True})+'\n',encoding='utf-8',newline='\n')
    (bundle/'fields.vtk').write_text(body,encoding='utf-8',newline='\n')
    (bundle/'audit.json').write_text(json.dumps(sidecar() if audit is None else audit,ensure_ascii=False,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    manifest={'input':'/original/path/is/not/used.msh','inputSha256':sha(source_bytes),'optionsSha256':sha(options.read_bytes()),'outputs':{n:sha((bundle/n).read_bytes()) for n in ['fields.vtk','audit.json']},'scope':'new manually authored R03 profile'}
    (bundle/'manifest.json').write_text(json.dumps(manifest)+'\n',encoding='utf-8',newline='\n')
    return bundle,source,options

legal=[]
for version in ['2.2','4.1']:
    encodings=[(False,'<',8),(True,'<',8),(True,'>',8)]
    if version=='4.1':encodings.extend([(True,'<',4),(True,'>',4)])
    for binary,endian,width in encodings:
        name=f'{version}-{binary}-{endian=="<"}-{width}';files=save(name,msh(version,binary,endian,width),audit=sidecar(version));r=cli(*files)
        check(r['sourceIdentity']=='byte_verified' and r['sourceFieldComparison']['status']=='equal','explicit source byte identity plus selected field equality')
        check(r['sourceFieldComparison']['geometry']=='not_compared','result discloses geometry boundary')
        check([f['values'] for f in r['readback']['fields']]==[[list(range(1,10))],[[10],[20]],[[1,-2,3],[4,5,6]]],'independent expected scalar/vector/nine tuples by original tag')
        legal.append({'name':name,'sourceSha256':sha(files[1].read_bytes()),'manifestSha256':sha((files[0]/'manifest.json').read_bytes())})
        if version=='2.2' and not binary:base_files=files;base_receipt=r

# Import and CLI share the opt-in implementation. Default receipt retains R02 shape.
module=(root/'examples/vtk_fields/verify.mjs').as_uri()
script='import {verifyBundle} from '+json.dumps(module)+'; console.log(JSON.stringify(verifyBundle(process.argv[1],{input:process.argv[2],options:process.argv[3],compareSourceFields:true})));'
r=invoke(['--input-type=module','-e',script,*base_files]);check(r==base_receipt,'import equals CLI opt-in receipt')
r=cli(*base_files,compare=False);check('sourceFieldComparison' not in r and r['sourceIdentity']=='byte_verified','default explicit-source receipt remains byte-only with no new field')
script='import {verifyBundle} from '+json.dumps(module)+'; console.log(JSON.stringify(verifyBundle(process.argv[1])));'
r=invoke(['--input-type=module','-e',script,base_files[0]]);check('sourceFieldComparison' not in r and r['sourceIdentity']=='declared_only','default standalone bundle receipt remains declared-only')

# Every failing bundle is internally coherent and fully rehashed. Default mode
# remains accepted; only the explicit stronger contract rejects source mismatch.
failures=[]
for name in ['wrong-scalar','one-ulp','wrong-vector','wrong-nine','swapped-tags','extra-string','extra-real','extra-integer','omitted-source-section','same-frame-wrong-index','source-version','source-node-count']:
    body=vtk;a=copy.deepcopy(sidecar());source=msh();indices=[2,0,1]
    if name=='wrong-scalar':body=body.replace('10 20\n','11 20\n')
    if name=='one-ulp':body=body.replace('10 20\n','10.000000000000002 20\n')
    if name=='wrong-vector':body=body.replace('1 -2 3\n','1 -2 4\n')
    if name=='wrong-nine':body=body.replace('1 2 3 4 5 6 7 8 9\n','1 2 3 4 5 6 7 8 8\n')
    if name=='swapped-tags':body=body.replace('90 10\n','10 90\n')
    if name=='extra-string':a['fields'][0]['strings'][2]='changed extra'
    if name=='extra-real':a['fields'][0]['reals'][1]=7.5
    if name=='extra-integer':a['fields'][0]['integers'][4]=43
    if name=='omitted-source-section':a['omitted_field_indices']=[3]
    if name=='same-frame-wrong-index':
        a['fields'][1]['field']['field_index']=3;a['fields'][1]['value_array']='gmsh_value_3';a['omitted_field_indices']=[0,4];body=body.replace('gmsh_value_0','gmsh_value_3');indices=[2,3,1]
    if name=='source-version':a['source_version']='4.1'
    if name=='source-node-count':source=source.replace(b'$Nodes\n2\n',b'$Nodes\n3\n').replace(b'10 1 0 0\n$EndNodes',b'10 1 0 0\n50 2 0 0\n$EndNodes')
    files=save(name,source,body,a,indices);old=cli(*files,compare=False);check(old['sourceIdentity']=='byte_verified','coherent mismatch remains valid under default R02 byte-only contract');cli(*files,expected=2);failures.append(name)

# Positive edge cases are about new equality semantics, not wider old matrices.
zero_fields=copy.deepcopy(fields);zero_fields[0]['entries'][1]=(90,[-0.0]);files=save('signed-zero',msh(frames=zero_fields),vtk.replace('10 20\n','0 20\n'));r=cli(*files);check(r['readback']['fields'][1]['values']==[[0],[20]],'numeric signed zero equivalence matches existing text policy')
files=save('geometry-boundary',msh(),vtk.replace('0 0 0 1 0 0\n','2 0 0 1 0 0\n'));r=cli(*files);check(r['sourceFieldComparison']['geometry']=='not_compared','coherent changed coordinates stay outside field comparison')
empty={'location':'NodeData','strings':['empty'],'reals':[],'integers':[0,1,0],'entries':[]}
empty_audit={'source_version':'2.2','fields':[{'field':{'field_index':0,'name':'empty','location':'NodeData','components':1,'time_step':0,'entries':0},'value_array':'gmsh_value_0','strings':['empty'],'reals':[],'integers':[0,1,0]}],'omitted_field_indices':[],'losses':['msh_field_headers_not_in_vtk']}
empty_vtk='# vtk DataFile Version 3.0\nnew source empty\nASCII\nDATASET UNSTRUCTURED_GRID\nPOINTS 0 double\nCELLS 0 0\nCELL_TYPES 0\nPOINT_DATA 0\nFIELD FieldData 2\ngmsh_value_0 1 0 double\ngmsh_tag 1 0 int\n'
files=save('empty',msh(frames=[empty],empty=True),empty_vtk,empty_audit,[0]);r=cli(*files);check(r['readback']['has_point_tags'] and r['readback']['fields'][0]['values']==[],'explicit zero tuples and missing time remain valid')

# Strong mode requires explicit paired originals; no inferred manifest path.
script='import {verifyBundle} from '+json.dumps(module)+'; try {verifyBundle(process.argv[1],{compareSourceFields:true});} catch(e) {console.error(e.message);process.exitCode=2;}'
invoke(['--input-type=module','-e',script,base_files[0]],2)
script='import {verifyBundle} from '+json.dumps(module)+'; try {verifyBundle(process.argv[1],{compareSourceFields:"yes"});} catch(e) {console.error(e.message);process.exitCode=2;}'
invoke(['--input-type=module','-e',script,base_files[0]],2)

# Consume the ordinary producer once for integration only, not as the oracle.
area=out/'existing-writer';area.mkdir();source=area/'original.msh';source.write_bytes(msh());options=area/'options.json';options.write_text('{"field_indices":[2,0,1],"allow_loss":true}',encoding='utf-8',newline='\n');bundle=area/'saved'
argv=[node,str(root/'examples/vtk_fields/run.mjs'),str(source),str(options),str(bundle)];r=subprocess.run(argv,cwd=root,capture_output=True,text=True,encoding='utf-8');check(r.returncode==0,'unchanged producer integration succeeds');producer={'argv':argv,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
r=cli(bundle,source,options);check([f['values'] for f in r['readback']['fields']]==[[list(range(1,10))],[[10],[20]],[[1,-2,3],[4,5,6]]],'current writer saved bundle matches independent source values')

receipt={'status':'PASS','checks':len(checks),'consumerInvocations':len(commands),'authoredSourceEncodings':legal,'newMismatchCases':failures,'checkLabels':checks,'commands':commands,'producerIntegration':producer,'comparatorSourceSha256':sha((root/'vtk_source_compare.mbt').read_bytes()),'consumerSourceSha256':sha((root/'examples/vtk_fields/verify.mjs').read_bytes()),'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),'independentExpected':'Explicit tagged1/3/9 values, full raw heads, same-name/frame different source sections; manual struct-packed MSH, no exporter oracle.','limits':'Exact decoded numeric field equality with signed-zero equivalence; no geometry comparison, tolerance, interpolation, units or source authenticity.'}
with evidence.open('x',encoding='utf-8') as stream:stream.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'consumerInvocations':len(commands),'authoredSourceEncodings':len(legal),'mismatchCases':len(failures)}))
