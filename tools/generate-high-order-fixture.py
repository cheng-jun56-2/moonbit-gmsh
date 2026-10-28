"""Regenerate self-authored curved-cell numeric fixtures through Gmsh4.15.2.
The resulting test data are not Gmsh source code or a redistributed library.
"""
import gmsh,numpy as np,pathlib,json
root=pathlib.Path(__file__).resolve().parents[1];gmsh.initialize();gmsh.option.setNumber('General.Terminal',0);rows=[]
for kind in [8,9,10,11,12,16,17]:
 name,dim,order,n,coords,primary=gmsh.model.mesh.getElementProperties(kind);p=np.pad(np.asarray(coords).reshape(n,dim),((0,0),(0,3-dim)))
 for i in range(primary,n):p[i]+=[.025*np.sin(i),.02*np.cos(i),.035*np.sin(i+1)]
 gmsh.clear();gmsh.model.add('curved');gmsh.model.addDiscreteEntity(dim,1);gmsh.model.mesh.addNodes(dim,1,list(range(1,n+1)),p.ravel().tolist());gmsh.model.mesh.addElementsByType(1,kind,[201],list(range(1,n+1)))
 rule='CompositeGauss2' if kind in [10,16] else 'Gauss2';q,_=gmsh.model.mesh.getIntegrationPoints(kind,rule);j,det,xyz=gmsh.model.mesh.getJacobians(kind,q)
 rows.append((kind,p.tolist(),np.asarray(q).reshape(-1,3).tolist(),np.asarray(j).reshape(-1,3,3).tolist(),np.asarray(xyz).reshape(-1,3).tolist(),det.tolist()))
gmsh.finalize()
s='''// Generated numeric fixtures: Gmsh4.15.2, tools/generate-high-order-fixture.py.
// Self-authored curved input coordinates. Gmsh is verification-only.
///|
fn qmesh(kind : Int, points : Array[Array[Double]]) -> @gmsh.Mesh raise {
 @gmsh.mesh(points.mapi((i,xyz)=>{tag:i+1,xyz,dim:-1,entity:0,parameters:[]}),[
 {tag:201,kind,nodes:[for i in 0..<points.length()=>i+1],entity:0,physical:[],extra:[]}
 ])
}
///|
fn qclose(a : Double,b : Double) -> Unit raise {
 assert_true((a-b).abs()<=1.0e-11)
}
///|
test "Gmsh4.15.2 curved-cell Jacobian fixtures on every backend" {
 let cases : Array[(Int,Array[Array[Double]],Array[Array[Double]],Array[Array[Array[Double]]],Array[Array[Double]],Array[Double])]=[
'''
for row in rows:s+='('+','.join(json.dumps(x) for x in row)+'),\n'
s+=''' ]
 for (kind,points,ps,js,xyz,det) in cases {
  let report=qmesh(kind,points).sample_gauss_jacobians(201)
  assert_true(!report.globally_certified)
  assert_eq(report.samples.length(),ps.length())
  for sample in report.samples {
   let mut found=false
   for i,p in ps {
    if sample.reference.mapi((j,x)=>(x-p[j]).abs()<1.0e-10).all(x=>x) {
     found=true
     for j in 0..<3 {qclose(sample.xyz[j],xyz[i][j])}
     for j in 0..<report.dimension {for k in 0..<3 {qclose(sample.columns[j][k],js[i][j][k])}}
     qclose(sample.measure,det[i].abs())
     if report.dimension==3 {qclose(sample.signed_jacobian.unwrap(),det[i])}
    }
   }
   assert_true(found)
  }
 }
}
'''
(root/'high_order_reference_test.mbt').write_text(s,encoding='utf-8')
print('generated seven curved family fixtures via Gmsh',gmsh.__version__)
