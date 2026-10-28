// IO only. MoonBit selects raw field sections, encodes and computes the result.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {new_file,transform,report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
const [destination]=process.argv.slice(2);
if(!destination)throw new Error('Usage: node examples/select_fields/run.mjs NEW_DIRECTORY');
const source=Buffer.from(new_file(fs.readFileSync(new URL('../normal_field/source.json',import.meta.url),'utf8')));
const inspect=(bytes,command,extra={})=>JSON.parse(report(bytes,JSON.stringify({command,...extra})));
const select=(field_indices,extra={})=>Buffer.from(transform(source,JSON.stringify({command:'select-fields',field_indices,...extra})));
const snapshot=select([1],{version:'4.1',binary:true});
const reordered=select([2,1],{version:'4.1',binary:true});
const geometry=select([]);
const summary={
  source_frames:inspect(source,'field-frames'),
  requested_source_indices:[1],
  output_frames:inspect(snapshot,'field-frames'),
  normal:inspect(snapshot,'integrate-surface-normal-field',{field_index:0}),
  reordered_frames:inspect(reordered,'field-frames'),
  geometry_only_fields:inspect(geometry,'field-frames').length,
};
const payloads={'source.msh':source,'snapshot.msh':snapshot,'reordered.msh':reordered,'geometry-only.msh':geometry,'selection.json':JSON.stringify(summary,null,2)+'\n'};
fs.mkdirSync(destination,{recursive:false});
for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
const sha=v=>crypto.createHash('sha256').update(v).digest('hex');
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({outputs:Object.fromEntries(Object.entries(payloads).map(([n,v])=>[n,sha(v)])),scope:'source section positions are explicit; original time steps, data tags and all mesh geometry remain; no automatic name/time match'},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output:destination,...summary}));
