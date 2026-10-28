// IO only; MoonBit performs selection, scalar-normal integration and exchange.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {new_file,transform,report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
const [destination]=process.argv.slice(2);
if(!destination)throw new Error('Usage: node examples/normal_field/run.mjs NEW_DIRECTORY');
const inspect=(b,o)=>JSON.parse(report(b,JSON.stringify(o)));
const change=(b,o)=>Buffer.from(transform(b,JSON.stringify(o)));
const payloads={},summaries=[];
for(const [prefix,file]of [['forward','source.json'],['reversed','source-reversed.json']]){
  const source=Buffer.from(new_file(fs.readFileSync(new URL('./'+file,import.meta.url),'utf8')));
  const wall=change(source,{command:'physical',dimension:2,group:44});
  const binary=change(wall,{command:'convert',version:'4.1',binary:true});
  const preflight={frames:inspect(wall,{command:'field-frames'}),coverage:inspect(wall,{command:'surface-field-coverage',field_index:0})};
  const normalFrames=[0,1,2].map(field_index=>inspect(wall,{command:'integrate-surface-normal-field',field_index}));
  const scalarAreaIntegral=inspect(wall,{command:'integrate-surface-field',field_index:0});
  const binaryFrame0=inspect(binary,{command:'integrate-surface-normal-field',field_index:0});
  payloads[prefix+'-source.msh']=source;
  payloads[prefix+'-wall.msh']=wall;
  payloads[prefix+'-binary-4.1.msh']=binary;
  payloads[prefix+'-preflight.json']=JSON.stringify(preflight,null,2)+'\n';
  payloads[prefix+'-normal.json']=JSON.stringify({normalFrames,scalarAreaIntegral,binaryFrame0},null,2)+'\n';
  summaries.push({prefix,resultants:normalFrames.map(f=>f.normal_integral),binaryResultant:binaryFrame0.normal_integral});
}
fs.mkdirSync(destination,{recursive:false});
for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
const digest=v=>crypto.createHash('sha256').update(v).digest('hex');
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({outputs:Object.fromEntries(Object.entries(payloads).map(([n,v])=>[n,digest(v)])),scope:'supplied scalar times stored oriented area; full quadratic nodes, exact frames, physical selection and actual binary readback; no automatic pressure sign/units/outwardness'},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output:destination,summaries}));
