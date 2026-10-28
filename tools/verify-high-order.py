"""Independent Gmsh4.15.2/meshio5.3.5 high-order reference and consumer gate.
Gmsh evaluates basis derivatives and faces; no MoonBit formula is copied here.
All meshes are self-authored numeric inputs; no NASA data or adoption claim.
"""
import argparse,base64,json,pathlib,subprocess,hashlib,sys,platform
import numpy as np
import gmsh,meshio
ROOT=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--evidence',required=True);args=a.parse_args();out=pathlib.Path(args.evidence).resolve();work=out.parent/'work'/'high-order-reference';work.mkdir(parents=True,exist_ok=True)
host=subprocess.Popen(['node',str(ROOT/'tools/oracle-host.mjs')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8')
checks=0;requests=0;maximum=0.;cases=[]
def check(ok,message):
 global checks
 checks+=1
 if not ok:raise AssertionError(message)
def call(data=b'',command='sample-gauss',action='report',reject=False,**opts):
 global requests
 requests+=1;host.stdin.write(json.dumps({'action':action,'data':base64.b64encode(data).decode(),'options':{'command':command,**opts}})+'\n');host.stdin.flush();v=json.loads(host.stdout.readline())
 if reject:check(not v['ok'],'expected refusal '+str(opts));return
 check(v['ok'],v.get('error','unexpected error'));res=v['result'];return base64.b64decode(res['bytes']) if 'bytes' in res else res
def close(actual,expected,label):
 global maximum
 x=np.asarray(actual,float);y=np.asarray(expected,float);check(x.shape==y.shape,label+' shape');err=float(np.max(np.abs(x-y))) if x.size else 0.;maximum=max(maximum,err);check(np.allclose(x,y,atol=1e-11,rtol=1e-11),label+f' error={err}');return err
def msh(xyz,cells,extra=None,tail=''):
 tags=[101+7*i for i in range(len(xyz))]
 s='$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$Nodes\n'+str(len(tags))+'\n'
 s+=''.join(str(t)+' '+' '.join(format(v,'.17g') for v in p)+'\n' for t,p in zip(tags,xyz))+'$EndNodes\n$Elements\n'+str(len(cells))+'\n'
 for tag,kind,inds in cells:
  ex=(extra or {}).get(tag,[]);s+=f'{tag} {kind} {len(ex)} '+(' '.join(map(str,ex))+' ' if ex else '')+' '.join(str(tags[i]) for i in inds)+'\n'
 return (s+'$EndElements\n'+tail).encode(),tags
def official(kind,xyz,tags):
 gmsh.clear();gmsh.model.add('reference');dim=gmsh.model.mesh.getElementProperties(kind)[1];gmsh.model.addDiscreteEntity(dim,1);gmsh.model.mesh.addNodes(dim,1,tags,np.asarray(xyz).ravel().tolist());gmsh.model.mesh.addElementsByType(1,kind,[201],tags);return dim
gmsh.initialize();gmsh.option.setNumber('General.Terminal',0)
try:
 references={}
 for kind in [8,9,10,11,12,16,17]:
  name,dim,order,n,coords,primary=gmsh.model.mesh.getElementProperties(kind);ref=np.asarray(coords).reshape(n,dim);references[kind]=ref
  xyz=np.pad(ref,((0,0),(0,3-dim)))
  for name,points in [('reference',xyz),('curved',xyz.copy()),('affine',xyz@np.array([[1.2,.1,.2],[.1,.9,-.1],[0,.1,1.1]])+np.array([2.,-3.,.7])),('degenerate',xyz*0),('inverted',xyz*np.array([-1,1,1]))]:
   if name=='curved':
    for i in range(primary,n):points[i]+=np.array([.025*np.sin(i),.02*np.cos(i),.035*np.sin(i+1)])
   raw,tags=msh(points,[(201,kind,list(range(n)))]);dim=official(kind,points,tags)
   result=call(raw,tag=201)
   check(result['globally_certified']==False,'sampling never certifies globally')
   q=np.array([s['reference']+[0]*(3-dim) for s in result['samples']]);jg,dg,pg=gmsh.model.mesh.getJacobians(kind,q.ravel().tolist());jg=np.asarray(jg).reshape(len(q),3,3);pg=np.asarray(pg).reshape(len(q),3)
   official_q,_=gmsh.model.mesh.getIntegrationPoints(kind,result['rule']);official_q=np.asarray(official_q).reshape(-1,3)
   close(sorted(q.tolist()),sorted(official_q.tolist()),'Gauss2 rule')
   for i,s in enumerate(result['samples']):
    close(s['xyz'],pg[i],'mapped point');close(s['columns'][:dim],jg[i,:dim],'Gmsh derivative columns')
    close(s['measure'],abs(dg[i]),'Jacobian measure')
    if dim==3:close(s['signed_jacobian'],dg[i],'signed determinant')
    elif dim==2:check(s.get('signed_jacobian') is None,'surface no implicit global normal')
   if kind==11 and name=='reference':
    close(result['corner_edge_ratio'],np.sqrt(2),'corner edge ratio');close(result['corner_minimum_dihedral_degrees'],np.degrees(np.arccos(1/np.sqrt(3))),'corner tetra minimum dihedral')
   if name=='inverted' and dim==3:check(result['nonpositive_samples']==len(q),'inverted volume samples')
   if name=='degenerate':check(result['nonpositive_samples']==len(q),'collapsed samples')
   if name=='curved':
    # Full boundary nodes, independent Gmsh edge/face API. Compare sets and
    # oriented corner cycles separately; project local facet order is documented.
    braw=call(raw,command='boundary-msh',action='transform');bd=call(braw,command='dump')
    check(len(bd['elements'])>0,'curved boundary returned')
    if dim==3:
     ft=3 if kind==11 else 4;expected=gmsh.model.mesh.getElementFaceNodes(kind,ft,primary=False).reshape(-1,6 if kind==11 else 9 if kind==12 else 8)
    elif dim==2:expected=gmsh.model.mesh.getElementEdgeNodes(kind,primary=False).reshape(-1,3)
    else:expected=np.array([[tags[0]],[tags[1]]])
    check(sorted(sorted(e['nodes']) for e in bd['elements'])==sorted(sorted(row.tolist()) for row in expected),'Gmsh full face/edge nodes')
    orientations=call(raw,command='boundary-orientations')
    if dim==3:check(all(x['status']=='outward_at_center' for x in orientations),'reference curved volume center outward')
    report=call(raw,command='boundary');check(all(f['owner']==201 and f['local_facet']>=0 for f in report['facets']),'parent provenance')
    # VTK is independently decoded; compare to meshio's own Gmsh reader,
    # which applies the official format order rather than our permutation table.
    vin=work/f'{kind}.msh';vin.write_bytes(raw);vt=work/f'{kind}.vtk';vt.write_text(call(raw,command='vtk')['text']);src=meshio.read(vin);dst=meshio.read(vt)
    close(dst.points,src.points,'VTK coordinate readback');check(dst.cells[0].type==src.cells[0].type,'VTK cell family');check(np.array_equal(dst.cells[0].data,src.cells[0].data),'VTK independent permutation')
    call(raw,command='audited-obj',reject=True)
    obj=call(raw,command='audited-obj',permissive=True);check(obj['loss_report']['certified_bound']==False,'chord estimate not a certificate');check(obj['loss_report']['error_samples']>0,'chord samples present')
    check(len(obj['loss_report']['discarded_curved_node_tags'])>0,'curved node omission audit')
    if dim>=2:
     for cmd,ext in [('audited-obj','obj'),('audited-stl','stl')]:
      v=call(raw,command=cmd,permissive=True);path=work/f'{kind}.{ext}';path.write_text(v['text']);back=meshio.read(path)
      check(sum(len(c.data) for c in back.cells)==v['loss_report']['output_elements'],'audited geometry readback');check(all(c.type=='triangle' for c in back.cells),'actual planar triangles')
   cases.append({'kind':kind,'geometry':name,'samples':len(q)})
 # Original analytic counterexample retained: sampling passes but t=.9 is negative.
 ref=references[11];points=ref.copy();points[:,2]=ref[:,2]*(1-.75*ref[:,2]);raw,tags=msh(points,[(201,11,list(range(10)))]);res=call(raw,tag=201)
 check(res['nonpositive_samples']==0 and not res['globally_certified'],'retained Gauss false-negative boundary')
 official(11,points,tags);_,det,_=gmsh.model.mesh.getJacobians(11,[.025,.025,.9]);close(det[0],-.35,'independent interior negative determinant')
 # Quad9 center bubble: all edges planar, center loss must still be .1.
 ref=references[10];points=np.pad(ref,((0,0),(0,1)));points[:,2]=.1*(1-ref[:,0]**2)*(1-ref[:,1]**2);raw,_=msh(points,[(201,10,list(range(9)))]);v=call(raw,command='audited-obj',permissive=True);close(v['loss_report']['estimated_chord_error'],.1,'face center omission audit')
 # Explicit reversed Tri6 on a Tet10: retain tag, physical label, field,
 # exact curved association, and report inward center orientation.
 xyz=references[11];tail='$ElementData\n1\n"flux"\n1\n0.25\n3\n0\n1\n1\n700 9\n$EndElementData\n'
 raw,_=msh(xyz,[(201,11,list(range(10))),(700,9,[0,1,2,4,5,6])],{700:[44,9]},tail)
 b=call(raw,command='boundary-msh',action='transform',allow_loss=True);d=call(b,command='dump');e=next(x for x in d['elements'] if x['tag']==700);check(e['physical']==[44] and e['entity']==9,'explicit label identity');check(d['fields'][0]['entries']==[{'tag':700,'values':[9]}],'explicit field association');o=call(raw,command='boundary-orientations');check(any(x['element']==700 and x['explicit_reversed'] and x['status']=='inward_at_center' for x in o),'preserve and diagnose reversed explicit curved face')
 # Two curved tets: cancel only the matching complete shared face.
 corners=[np.array([[0,0,0],[1,0,0],[0,1,0],[0,0,1.]]),np.array([[0,0,0],[0,1,0],[1,0,0],[0,0,-1.]])];points=[];cells=[]
 for ii,c in enumerate(corners):
  inds=[]
  for u,v,w in references[11]:
   p=c[0]+u*(c[1]-c[0])+v*(c[2]-c[0])+w*(c[3]-c[0]);p[2]+=.1*p[0]*p[1];key=tuple(p)
   if key not in points:points.append(key)
   inds.append(points.index(key))
  cells.append((201+ii,11,inds))
 raw,_=msh(points,cells);check(len(call(raw,command='boundary')['facets'])==6,'two curved tetrahedra shared face canceled')
 broken=[(t,k,i.copy()) for t,k,i in cells];points.append(tuple(np.array(points[broken[1][2][4]])+[0,0,.01]));broken[1][2][4]=len(points)-1;raw,_=msh(points,broken);call(raw,command='boundary',reject=True)
 # Required error paths and strict gates.
 raw,_=msh(references[11],[(201,11,list(range(10)))]);call(raw,tag=999,reject=True);call(raw,tag=201,reference_normal=[0,0,1],reject=True)
 raw,_=msh(np.pad(references[9],((0,0),(0,1))),[(201,9,list(range(6)))]);call(raw,tag=201,reference_normal=[0,0,0],reject=True);call(raw,tag=201,reference_normal=[0,0,1]);call(raw,command='boundary',max_facets=2,reject=True)
 # MSH conversion keeps raw order: all seven new operation families.
 for kind,ref in references.items():
  xyz=np.pad(ref,((0,0),(0,3-ref.shape[1])));raw,tags=msh(xyz,[(201,kind,list(range(len(ref))))])
  for version,binary in [('2.2',True),('4.1',False),('4.1',True)]:
   converted=call(raw,command='convert',action='transform',version=version,binary=binary,allow_loss=True);d=call(converted,command='dump');check(d['elements'][0]['nodes']==tags,'MSH raw high-order order unchanged')
 receipt={'gmsh':gmsh.__version__,'meshio':meshio.__version__,'numpy':np.__version__,'python':platform.python_version(),'cases':cases,'requests':requests,'checks':checks,'maximum_absolute_difference':maximum,'tolerance':{'atol':1e-11,'rtol':1e-11},'scope':'Gmsh same-point derivatives/face nodes, meshio export readback, provenance/fields, analytic counterexamples and required refusals; no global validity certification','source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in ROOT.rglob('*.mbt') if '_build' not in p.parts},'data_license':'self-authored numeric inputs; reference tools external, not MIT-relicensed','output_dir':str(work)}
 out.write_text(json.dumps(receipt,indent=2));print(json.dumps({k:v for k,v in receipt.items() if k not in ['cases','source_sha256']},indent=2))
finally:
 gmsh.finalize();host.stdin.close();host.wait()
