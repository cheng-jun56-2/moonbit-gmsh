"""Compare five surface families and scalar/vector/tensor frames with Gmsh.
Run after moon build --target js --release; development dependencies are in
requirements-public.txt. Inputs are self-authored; no upstream code is copied.
"""
from pathlib import Path
import json,base64,subprocess,math,hashlib,argparse,shutil
import gmsh,numpy as np
parser=argparse.ArgumentParser(description='Independent Gmsh comparison for surface field integration');parser.add_argument('--evidence',required=True);args=parser.parse_args();evidence=Path(args.evidence).resolve();assert not evidence.exists(),'Choose a new evidence path';p=Path(__file__).resolve().parents[1];host=subprocess.Popen([shutil.which('node') or 'node',str(p/'tools/oracle-host.mjs')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8');records=[];checks=[]
def check(ok,label):
 checks.append(label)
 if not ok:raise AssertionError(label)
def api(q):
 host.stdin.write(json.dumps(q)+'\n');host.stdin.flush();v=json.loads(host.stdout.readline());check(v['ok'],'public request completed');return v['result']
gmsh.initialize(readConfigFiles=False);gmsh.option.setNumber('General.Terminal',0)
try:
 for kind in [2,3,9,10,16]:
  _,dim,_,n,local,_=gmsh.model.mesh.getElementProperties(kind);refs=local.reshape(-1,dim);xyz=[]
  for u,v in refs:xyz.append([u+.04*u*v,v+.03*u*u,.13*(u*u+v*v)+.07*u*v])
  tags=[10+7*i for i in range(n)];fields=[];nodal=np.array([[1+u+2*v+.5*u*u+.25*u*v] for u,v in refs]);tensor=np.array([[(k+1)*(1+u*u+v) for k in range(9)] for u,v in refs]);cell=np.array([2.,-3.,.5])
  for name,location,values in [('scalar','NodeData',nodal),('traction','ElementData',cell.reshape(1,3)),('tensor','NodeData',tensor)]:
   entries=[{'tag':tags[i] if location=='NodeData' else 201,'values':row.tolist()} for i,row in enumerate(values)]
   fields.append({'location':location,'strings':[name],'reals':[.25],'integers':[3,values.shape[1],len(entries)],'entries':entries})
  model={'nodes':[{'tag':tag,'xyz':pt} for tag,pt in zip(tags,xyz)],'elements':[{'tag':201,'kind':kind,'nodes':tags,'physical':[44]}],'fields':fields}
  created=api({'action':'create','options':model});raw=base64.b64decode(created['bytes']);fixture='self-authored-kind-'+str(kind)
  gmsh.clear();gmsh.model.add('surface');gmsh.model.addDiscreteEntity(2,1);gmsh.model.mesh.addNodes(2,1,tags,np.array(xyz).ravel());gmsh.model.mesh.addElementsByType(1,kind,[201],tags)
  rule='Gauss4' if kind in [2,9] else 'CompositeGauss4';loc,weights=gmsh.model.mesh.getIntegrationPoints(kind,rule);_,det,_=gmsh.model.mesh.getJacobian(201,loc);_,basis,_=gmsh.model.mesh.getBasisFunctions(kind,loc,'Lagrange');basis=basis.reshape(-1,n);weighted=weights*np.abs(det);area=float(np.sum(weighted))
  for index,values in enumerate([nodal,cell,tensor]):
   expect=np.sum((basis@values)*weighted[:,None],axis=0) if index!=1 else values*area
   request={'data':created['bytes'],'options':{'command':'integrate-surface-field','field_index':index}}
   actual=api(request);check(math.isclose(actual['surface_measure'],area,rel_tol=5e-12,abs_tol=1e-13),f'kind{kind} frame{index} Gmsh area');check(actual['samples']==len(weights),f'kind{kind} quadrature sample count');check(actual['elements']==1 and actual['time_step']==3 and actual['time']==.25,f'kind{kind} exact frame metadata');check(not actual['certified_error_bound'],f'kind{kind} no false certificate')
   for k,(got,want) in enumerate(zip(actual['integral'],expect)):
    check(math.isclose(got,float(want),rel_tol=5e-12,abs_tol=1e-12),f'kind{kind} frame{index} component{k}')
   records.append({'kind':kind,'field_index':index,'request':request,'actual':actual,'gmsh_expected':{'area':area,'integral':expect.tolist(),'rule':rule,'points':loc.reshape(-1,3).tolist(),'weights':weights.tolist()},'fixture':fixture,'inputSha256':hashlib.sha256(raw).hexdigest()})
finally:
 gmsh.finalize();host.stdin.close();host.wait(timeout=10)
out={'gmsh':gmsh.__version__,'requests':len(records),'checks':len(checks),'assertions':checks,'records':records,'bridgeSha256':hashlib.sha256((p/'_build/js/release/build/cmd/bridge/bridge.js').read_bytes()).hexdigest(),'scope':'Five linear/quadratic curved surface families. Independent Gmsh basis, Jacobians and quadrature weights; scalar/vector/tensor frames. Fixed-rule comparison, not an exact-curved-integral proof.'}
evidence.parent.mkdir(parents=True,exist_ok=True)
with evidence.open('x',encoding='utf-8') as file:file.write(json.dumps(out,indent=2)+'\n');print(json.dumps({'status':'PASS','requests':len(records),'checks':len(checks)},indent=2))
