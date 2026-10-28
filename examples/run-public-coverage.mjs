// IO-only consumer: source incidence, tags and classification remain MoonBit.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import crypto from 'node:crypto';
import {report,transform} from '../_build/js/release/build/cmd/bridge/bridge.js';
const root=path.dirname(fileURLToPath(import.meta.url));
const destination=process.argv[2];
if(!destination) throw new Error('Usage: node examples/run-public-coverage.mjs NEW_DIRECTORY');
fs.mkdirSync(destination,{recursive:false});
const data=fs.readFileSync(path.join(root,'public/t1-4.1-1.msh'));
const coverage=JSON.parse(report(data,JSON.stringify({command:'coverage',required_groups:[5]})));
const provenance=JSON.parse(report(data,JSON.stringify({command:'boundary'})));
for(const [name,value] of Object.entries({coverage,provenance}))
  fs.writeFileSync(path.join(destination,name+'.json'),JSON.stringify(value,null,2)+'\n',{flag:'wx'});
// This example explicitly accepts omissions printed in provenance.json.
fs.writeFileSync(path.join(destination,'boundary.msh'),Buffer.from(transform(data,JSON.stringify({command:'boundary-msh',allow_loss:true}))),{flag:'wx'});
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({
  input:'bundled upstream Gmsh tutorial, not engineering customer data',
  sha256:crypto.createHash('sha256').update(data).digest('hex'),
  boundaryFacets:coverage.facets,labeledGroups:coverage.groups,
  unlabeledFacets:coverage.unlabeled.length,
  decision:'Review the 10 unlabeled facets; assigning a physical/solver condition is the caller responsibility',
  exportLosses:provenance.losses
},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({facets:coverage.facets,unlabeled:coverage.unlabeled.length,output:destination}));
