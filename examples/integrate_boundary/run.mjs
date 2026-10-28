// IO-only demonstration. Mesh conversion, selection and integration are MoonBit.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {new_file,transform,report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
const [destination]=process.argv.slice(2);
if(!destination)throw new Error('Usage: node examples/integrate_boundary/run.mjs NEW_DIRECTORY');
const options=fs.readFileSync(new URL('./source.json',import.meta.url));
const inspect=(data,o)=>JSON.parse(report(data,JSON.stringify(o)));
const source=Buffer.from(new_file(options.toString('utf8')));
const provenance=inspect(source,{command:'boundary'});
const coverage=inspect(source,{command:'coverage',required_groups:[44]});
// This example explicitly accepts the exclusions recorded in provenance.
const boundary=Buffer.from(transform(source,JSON.stringify({command:'boundary-msh',allow_loss:true})));
const wall=Buffer.from(transform(boundary,JSON.stringify({command:'physical',dimension:2,group:44})));
const heat=inspect(wall,{command:'integrate-surface-field',field_index:0});
const traction=inspect(wall,{command:'integrate-surface-field',field_index:1});
const payloads={'source.msh':source,'boundary.msh':boundary,'wall.msh':wall,
  'boundary-report.json':JSON.stringify(provenance,null,2)+'\n',
  'coverage.json':JSON.stringify(coverage,null,2)+'\n',
  'heat-integral.json':JSON.stringify(heat,null,2)+'\n',
  'traction-integral.json':JSON.stringify(traction,null,2)+'\n'};
fs.mkdirSync(destination,{recursive:false});
for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({sourceOptionsSha256:sha(options),outputs:Object.fromEntries(Object.entries(payloads).map(([name,data])=>[name,sha(data)])),scope:'selected physical group44; supplied nodal heat flux and global traction components; fixed quadrature estimate without certified error bound'},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output:destination,area:heat.surface_measure,heat:heat.integral,traction:traction.integral}));
