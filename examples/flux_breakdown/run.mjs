// IO only. MoonBit owns extraction, selection, remapping and every integral.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {new_file,transform,report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
const [destination]=process.argv.slice(2);
if(!destination)throw new Error('Usage: node examples/flux_breakdown/run.mjs NEW_DIRECTORY');
const inspect=(b,o)=>JSON.parse(report(b,JSON.stringify(o)));
const change=(b,o)=>Buffer.from(transform(b,JSON.stringify(o)));
const payloads={},summaries=[];
for(const [prefix,file]of [['forward','source.json'],['reversed','source-reversed.json']]){
  // Reuse the existing self-authored Tet10 and same-name velocity frames.
  const source=Buffer.from(new_file(fs.readFileSync(new URL('../surface_flux/'+file,import.meta.url),'utf8')));
  const provenance=inspect(source,{command:'boundary'}),orientations=inspect(source,{command:'boundary-orientations'});
  const boundary=change(source,{command:'boundary-msh',allow_loss:true});
  const wall=change(boundary,{command:'physical',dimension:2,group:44});
  const compact=change(boundary,{command:'compact'});
  const binary=change(compact,{command:'convert',version:'4.1',binary:true,little:true});
  const frames=[0,1].map(field_index=>inspect(boundary,{command:'surface-flux-breakdown',field_index}));
  const compactFrames=[0,1].map(field_index=>inspect(binary,{command:'surface-flux-breakdown',field_index}));
  const wallFrame=inspect(wall,{command:'surface-flux-breakdown',field_index:0});
  payloads[prefix+'-source.msh']=source;
  payloads[prefix+'-boundary.msh']=boundary;
  payloads[prefix+'-compact-4.1.msh']=binary;
  payloads[prefix+'-audit.json']=JSON.stringify({provenance,orientations,currentElements:inspect(boundary,{command:'dump'}).elements},null,2)+'\n';
  payloads[prefix+'-flux.json']=JSON.stringify({frames,compactFrames,wallFrame},null,2)+'\n';
  summaries.push({prefix,total:frames.map(r=>r.total.flux),faceFlux:frames[0].contributions.map(r=>({element:r.element,flux:r.flux})),compactTags:compactFrames[0].contributions.map(r=>r.element)});
}
fs.mkdirSync(destination,{recursive:false});
for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
const digest=v=>crypto.createHash('sha256').update(v).digest('hex');
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({outputs:Object.fromEntries(Object.entries(payloads).map(([n,v])=>[n,digest(v)])),scope:'current per-face signed flux and exact frames, source orientation/provenance, closed cancellation and compact4.1 readback; no persistent original-parent IDs or automatic normal repair'},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output:destination,summaries}));
