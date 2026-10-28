// IO-only file consumer. Every geometry, source and audit decision is MoonBit.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {report,transform} from '../_build/js/release/build/cmd/bridge/bridge.js';
const [input,destination]=process.argv.slice(2);
if(!input||!destination) throw new Error('Usage: node examples/run-high-order.mjs INPUT.msh NEW_DIRECTORY');
const data=fs.readFileSync(input);
const inspect=command=>JSON.parse(report(data,JSON.stringify({command})));
const dump=inspect('dump');
// One cell per supported quadratic family illustrates API reuse. This example
// does not claim to inspect every element or certify a whole mesh.
const seen=new Set(),tags=[];
for(const e of dump.elements) if([8,9,10,11,12,16,17].includes(e.kind)&&!seen.has(e.kind)){seen.add(e.kind);tags.push(e.tag);}
const sampling=tags.map(tag=>JSON.parse(report(data,JSON.stringify({command:'sample-gauss',tag}))));
const provenance=inspect('boundary'),orientations=inspect('boundary-orientations'),coverage=inspect('coverage');
const obj=JSON.parse(report(data,JSON.stringify({command:'audited-obj',permissive:true})));
const stl=JSON.parse(report(data,JSON.stringify({command:'audited-stl',permissive:true})));
const vtk=JSON.parse(report(data,JSON.stringify({command:'vtk',allow_loss:true})));
const boundary=Buffer.from(transform(data,JSON.stringify({command:'boundary-msh',allow_loss:true})));
fs.mkdirSync(destination,{recursive:false});
const save=(n,v)=>fs.writeFileSync(path.join(destination,n),v,{flag:'wx'});
for(const [name,value] of Object.entries({sampling,provenance,orientations,coverage,objLoss:obj.loss_report,stlLoss:stl.loss_report}))save(name+'.json',JSON.stringify(value,null,2)+'\n');
save('surface.obj',obj.text);save('surface.stl',stl.text);save('mesh.vtk',vtk.text);save('boundary.msh',boundary);
save('manifest.json',JSON.stringify({input,sha256:crypto.createHash('sha256').update(data).digest('hex'),sampledElementTags:tags,qualityScope:'one cell per quadratic family, sampled only, not a global certificate',vtkMetadata:'geometry-only output explicitly allowed; fields/groups/entities omitted',boundaryLosses:provenance.losses},null,2)+'\n');
console.log(JSON.stringify({output:destination,boundaryFacets:provenance.facets.length,sampledElementTags:tags,estimatedChordError:obj.loss_report.estimated_chord_error}));
