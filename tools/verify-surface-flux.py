"""Independent Gmsh basis/Jacobian comparison of signed surface normal flux.
Self-authored curved inputs; no Gmsh implementation is copied or used at runtime.
"""
from pathlib import Path
import argparse,base64,hashlib,json,math,shutil,subprocess
import gmsh,numpy as np
arg=argparse.ArgumentParser();arg.add_argument('--evidence',required=True);args=arg.parse_args();evidence=Path(args.evidence).resolve();assert not evidence.exists(),'Choose a new evidence path';root=Path(__file__).resolve().parents[1]
host=subprocess.Popen([shutil.which('node') or 'node',str(root/'tools/oracle-host.mjs')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8');checks=[];records=[]
def check(ok,label):
 checks.append(label)
 if not ok:raise AssertionError(label)
def api(q):
 host.stdin.write(json.dumps(q)+'\n');host.stdin.flush();v=json.loads(host.stdout.readline());check(v['ok'],'public request succeeds');return v['result']
orders={2:[0,2,1],3:[0,3,2,1],9:[0,2,1,5,4,3],16:[0,3,2,1,7,6,5,4],10:[0,3,2,1,7,6,5,4,8]}
gmsh.initialize(readConfigFiles=False);gmsh.option.setNumber('General.Terminal',0)
try:
 for kind in [2,3,9,10,16]:
  _,dim,_,n,local,_=gmsh.model.mesh.getElementProperties(kind);refs=local.reshape(-1,dim);xyz=np.array([[u+.04*u*v,v+.03*u*u,.13*(u*u+v*v)+.07*u*v] for u,v in refs]);tags=[10+7*i for i in range(n)];values=np.array([[1+u*u,2+v,-.5+u*v] for u,v in refs]);constant=np.array([.25,-.5,1.])
  fields=[{'location':'NodeData','strings':['velocity'],'reals':[.25],'integers':[3,3,n],'entries':[{'tag':t,'values':v.tolist()} for t,v in zip(tags,values)]},{'location':'ElementData','strings':['constant'],'reals':[.25],'integers':[3,3,1],'entries':[{'tag':201,'values':constant.tolist()}]}]
  for reverse in [False,True]:
   order=orders[kind] if reverse else list(range(n));conn=[tags[i] for i in order];model={'nodes':[{'tag':t,'xyz':v.tolist()} for t,v in zip(tags,xyz)],'elements':[{'tag':201,'kind':kind,'nodes':conn,'physical':[44]}],'fields':fields};created=api({'action':'create','options':model})
   gmsh.clear();gmsh.model.add('flux');gmsh.model.addDiscreteEntity(2,1);gmsh.model.mesh.addNodes(2,1,tags,xyz.ravel());gmsh.model.mesh.addElementsByType(1,kind,[201],conn);rule='Gauss4' if kind in [2,9] else 'CompositeGauss4';loc,w=gmsh.model.mesh.getIntegrationPoints(kind,rule);jac,_,_=gmsh.model.mesh.getJacobian(201,loc);columns=jac.reshape(-1,3,3);cross=np.cross(columns[:,0,:],columns[:,1,:]);area=float(np.sum(w*np.linalg.norm(cross,axis=1)));area_vector=np.sum(w[:,None]*cross,axis=0);_,basis,_=gmsh.model.mesh.getBasisFunctions(kind,loc,'Lagrange');sample=basis.reshape(-1,n)@values[order]
   for frame in [0,1]:
    flux=float(np.sum(w*np.sum(sample*cross,axis=1))) if frame==0 else float(constant@area_vector);q={'data':created['bytes'],'options':{'command':'integrate-surface-flux','field_index':frame}};got=api(q);check(math.isclose(got['surface_measure'],area,rel_tol=5e-12,abs_tol=1e-12),'Gmsh area');check(math.isclose(got['flux'],flux,rel_tol=5e-12,abs_tol=1e-12),'Gmsh oriented flux')
    for k in range(3):check(math.isclose(got['area_vector'][k],float(area_vector[k]),rel_tol=5e-12,abs_tol=1e-12),'Gmsh area vector component'+str(k))
    check(got['normal_convention']=='stored_node_winding' and got['samples']==len(w),'normal and quadrature metadata');check(got['time_step']==3 and got['time']==.25,'exact frame metadata');check(not got['certified_error_bound'],'no false certificate');records.append({'kind':kind,'reverse':reverse,'field_index':frame,'request':q,'actual':got,'gmsh_expected':{'flux':flux,'surface_measure':area,'area_vector':area_vector.tolist(),'rule':rule},'inputSha256':hashlib.sha256(base64.b64decode(created['bytes'])).hexdigest()})
finally:
 gmsh.finalize();host.stdin.close();host.wait(timeout=10)
out={'gmsh':gmsh.__version__,'requests':len(records),'checks':len(checks),'assertions':checks,'records':records,'bridgeSha256':hashlib.sha256((root/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()).hexdigest(),'scope':'Five curved surface families, forward/reversed full-node winding and NodeData/ElementData3. Independent derivative cross products and Lagrange basis; no global orientation/error certificate.'};evidence.parent.mkdir(parents=True,exist_ok=True)
with evidence.open('x',encoding='utf-8') as f:f.write(json.dumps(out,indent=2)+'\n')
print(json.dumps({'status':'PASS','requests':len(records),'checks':len(checks)},indent=2))
