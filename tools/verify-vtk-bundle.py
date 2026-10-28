"""Read-only bundle consumer regression with authored bytes/tags and meshio.
No exporter is used to manufacture the independent expected fixture.
"""
from pathlib import Path
import argparse, copy, hashlib, json, shutil, subprocess
import meshio
import numpy as np

parser=argparse.ArgumentParser()
parser.add_argument('--evidence',required=True)
parser.add_argument('--outputs',required=True)
args=parser.parse_args();root=Path(__file__).resolve().parents[1]
evidence,output=Path(args.evidence).resolve(),Path(args.outputs).resolve()
assert not evidence.exists() and not output.exists(),'Choose new paths'
output.mkdir();node=shutil.which('node');assert node
commands=[];checks=[]
def sha(data):return hashlib.sha256(data).hexdigest()
def check(ok,label):checks.append(label);assert ok,label
def snapshot():return {p.relative_to(output).as_posix():sha(p.read_bytes()) for p in output.rglob('*') if p.is_file()}
def invoke(argv,expected=0):
    before=snapshot();r=subprocess.run([node,*map(str,argv)],cwd=root,capture_output=True,text=True,encoding='utf-8')
    check(r.returncode==expected,'consumer expected exit '+str(expected));check(snapshot()==before,'all input files and directory entries unchanged')
    if expected:check(not r.stdout,'no partial success report on failure')
    commands.append({'argv':[node,*map(str,argv)],'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
    return json.loads(r.stdout) if not expected else None
def cli(bundle,*originals,expected=0):return invoke([root/'examples/vtk_fields/verify.mjs',bundle,*originals],expected)
geometry='# vtk DataFile Version 3.0\nindependent authored fixture\nASCII\nDATASET UNSTRUCTURED_GRID\nPOINTS 3 double\n0 0 0\n1 0 0\n0 1 0\nCELLS 1 4\n3 0 1 2\nCELL_TYPES 1\n5\n'
point='POINT_DATA 3\nFIELD FieldData 3\ngmsh_value_0 1 3 double\n10 20 30\ngmsh_value_1 3 3 double\n1 2 3\n-1 0 1\n0.5 1.5 2.5\ngmsh_tag 1 3 int\n90 10 50\n'
cell='CELL_DATA 1\nFIELD FieldData 2\ngmsh_value_2 9 1 double\n1 2 3 4 5 6 7 8 9\ngmsh_tag 1 1 int\n201\n'
def record(index,name,location,components,entries):
    return {'field':{'field_index':index,'name':name,'location':location,'components':components,'time_step':4,'time':1.5,'entries':entries},'value_array':'gmsh_value_'+str(index),'strings':[name],'reals':[1.5],'integers':[4,components,entries]}
fields=[record(0,'温度','NodeData',1,3),record(1,'velocity','NodeData',3,3),record(2,'stress','ElementData',9,1)]
audit={'fields':[fields[2],fields[0],fields[1]],'source_version':'2.2','omitted_field_indices':[],'losses':['msh_field_headers_not_in_vtk']}
source=output/'源 网格.msh';options=output/'选项.json'
source.write_text('$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$Nodes\n3\n90 0 0 0\n10 1 0 0\n50 0 1 0\n$EndNodes\n$Elements\n1\n201 2 0 90 10 50\n$EndElements\n$NodeData\n1\n"温度"\n1\n1.5\n3\n4\n1\n3\n90 10\n10 20\n50 30\n$EndNodeData\n$NodeData\n1\n"velocity"\n1\n1.5\n3\n4\n3\n3\n90 1 2 3\n10 -1 0 1\n50 0.5 1.5 2.5\n$EndNodeData\n$ElementData\n1\n"stress"\n1\n1.5\n3\n4\n9\n1\n201 1 2 3 4 5 6 7 8 9\n$EndElementData\n',encoding='utf-8',newline='\n')
options.write_text('{"field_indices":[2,0,1],"allow_loss":true}',encoding='utf-8',newline='\n')
def save_bundle(name,vtk,sidecar):
    dest=output/name;dest.mkdir();(dest/'fields.vtk').write_text(vtk,encoding='utf-8',newline='\n');(dest/'audit.json').write_text(json.dumps(sidecar,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    manifest={'input':'/recorded/source/not/available/to/recipient.msh','inputSha256':sha(source.read_bytes()),'optionsSha256':sha(options.read_bytes()),'outputs':{p:sha((dest/p).read_bytes()) for p in ['fields.vtk','audit.json']},'scope':'hand-authored existing vtk_fields protocol'}
    (dest/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n');return dest
def rehash(dest):
    p=dest/'manifest.json';manifest=json.loads(p.read_text(encoding='utf-8'));manifest['outputs']={k:sha((dest/k).read_bytes()) for k in ['fields.vtk','audit.json']};p.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
def clone(name):return Path(shutil.copytree(bundle,output/name))
bundle=save_bundle('交付 包🙂',geometry+point+cell,audit)
result=cli(bundle);check(result['sourceIdentity']=='declared_only','missing original path is not opened or certified')
readback=result['readback'];check(readback['point_tags']==[90,10,50] and readback['cell_tags']==[201],'authored original tag order')
check([f['field']['field_index'] for f in readback['fields']]==[2,0,1],'authored request order kept separately from VTK association order')
check([f['values'] for f in readback['fields']]==[[[1,2,3,4,5,6,7,8,9]],[[10],[20],[30]],[[1,2,3],[-1,0,1],[.5,1.5,2.5]]],'authored scalar/vector/nine-component values linked to tags')
check(readback['fields'][1]['field']['name']=='温度','Unicode sidecar metadata')
verified=cli(bundle,source,options);check(verified['sourceIdentity']=='byte_verified','explicit source and options byte identities')
module=(root/'examples/vtk_fields/verify.mjs').as_uri();script='import {verifyBundle} from '+json.dumps(module)+'; console.log(JSON.stringify(verifyBundle(process.argv[1])));'
imported=invoke(['--input-type=module','-e',script,bundle]);check(imported==result,'public import and CLI consume the same existing files')
mesh=meshio.read(bundle/'fields.vtk')
check(np.asarray(mesh.point_data['gmsh_tag']).reshape(-1).tolist()==[90,10,50],'independent meshio point tags')
check(np.asarray(mesh.point_data['gmsh_value_1']).reshape(3,3).tolist()==[[1,2,3],[-1,0,1],[.5,1.5,2.5]],'independent meshio vector tuples')
check(np.asarray(mesh.cell_data['gmsh_value_2'][0]).reshape(1,9).tolist()==[[1,2,3,4,5,6,7,8,9]],'independent meshio cell-nine tuples')
for name in ['fields.vtk','audit.json','manifest.json']:
    dest=clone('missing-'+name);(dest/name).unlink();cli(dest,expected=2)
for name,old,new in [('fields.vtk',b'10 20 30',b'11 20 30'),('audit.json',b'velocity',b'velocitx')]:
    dest=clone('same-length-'+name);p=dest/name;data=p.read_bytes();changed=data.replace(old,new,1);check(changed!=data and len(changed)==len(data),'same-length mutation fixture');p.write_bytes(changed);cli(dest,expected=2)
dest=clone('wrong-association');p=dest/'audit.json';wrong=copy.deepcopy(audit);wrong['fields'][1]['field'].update(location='ElementData',entries=1);wrong['fields'][1]['integers'][2]=1;p.write_text(json.dumps(wrong,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n');rehash(dest);cli(dest,expected=2)
dest=clone('wrong-frame');p=dest/'audit.json';wrong=copy.deepcopy(audit);wrong['fields'][0]['field']['time']=2;p.write_text(json.dumps(wrong)+'\n',encoding='utf-8',newline='\n');rehash(dest);cli(dest,expected=2)
dest=clone('duplicate-tag');p=dest/'fields.vtk';p.write_bytes(p.read_bytes().replace(b'90 10 50',b'90 10 90'));rehash(dest);cli(dest,expected=2)
dest=clone('truncated-array');p=dest/'fields.vtk';p.write_bytes(p.read_bytes()[:-8]);rehash(dest);cli(dest,expected=2)
dest=clone('wrong-alias');p=dest/'audit.json';wrong=copy.deepcopy(audit);wrong['fields'][0]['value_array']='gmsh_value_0';p.write_text(json.dumps(wrong)+'\n',encoding='utf-8',newline='\n');rehash(dest);cli(dest,expected=2)
bad_source=output/'wrong-source.msh';bad_source.write_bytes(source.read_bytes().replace(b'90 0 0 0',b'90 1 0 0',1));cli(bundle,bad_source,options,expected=2)
bad_options=output/'wrong-options.json';bad_options.write_text('{"field_indices":[0,2,1],"allow_loss":true}',encoding='utf-8',newline='\n');cli(bundle,source,bad_options,expected=2)
dest=clone('rehashed-wrong-selection');p=dest/'manifest.json';manifest=json.loads(p.read_text());manifest['optionsSha256']=sha(bad_options.read_bytes());p.write_text(json.dumps(manifest)+'\n',encoding='utf-8',newline='\n');cli(dest,source,bad_options,expected=2)
for name,body,chosen,omitted in [('point-only',point,[fields[0],fields[1]],[2]),('cell-only',cell,[fields[2]],[0,1])]:
    sidecar={**audit,'fields':chosen,'omitted_field_indices':omitted,'losses':['msh_field_headers_not_in_vtk','other_association_tags_not_in_vtk','other_field_sections_omitted']}
    dest=save_bundle(name,geometry+body,sidecar);r=cli(dest)['readback'];check(r['has_point_tags']==(name=='point-only') and r['has_cell_tags']==(name=='cell-only'),'selected association stays distinct from absent one')
empty_vtk='# vtk DataFile Version 3.0\nempty profile\nASCII\nDATASET UNSTRUCTURED_GRID\nPOINTS 0 double\nCELLS 0 0\nCELL_TYPES 0\nPOINT_DATA 0\nFIELD FieldData 2\ngmsh_value_0 1 0 double\ngmsh_tag 1 0 int\n'
empty_field=record(0,'empty','NodeData',1,0);empty_field['field'].pop('time');empty_field['field']['time_step']=0;empty_field['reals']=[];empty_field['integers']=[0,1,0]
dest=save_bundle('empty-selected',empty_vtk,{**audit,'fields':[empty_field]});r=cli(dest)['readback'];check(r['has_point_tags'] and r['point_tags']==[] and r['fields'][0]['values']==[],'legal selected zero tuples retained')
receipt={'status':'PASS','checks':len(checks),'consumerInvocations':len(commands),'independentFixture':'Authored legacy VTK bytes, raw frame metadata,1/3/9 tuples and unsorted original tags; no exporter oracle','meshioVersion':meshio.__version__,'checkLabels':checks,'commands':commands,'sourceSha256':sha(source.read_bytes()),'originalOptionsSha256':sha(options.read_bytes()),'bundleManifestSha256':sha((bundle/'manifest.json').read_bytes()),'readerSourceSha256':sha((root/'vtk_readback.mbt').read_bytes()),'bridgeSha256':sha((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()),'limits':'Consistency/declared byte identity, not source-value, signature, geometry or physics certification.'}
with evidence.open('x',encoding='utf-8') as stream:stream.write(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'PASS','checks':len(checks),'consumerInvocations':len(commands),'meshioReadbacks':1}))
