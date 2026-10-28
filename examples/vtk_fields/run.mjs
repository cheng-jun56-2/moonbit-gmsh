// IO only: MoonBit selects, validates, groups and encodes every field/tag array.
import fs from 'node:fs';
import {isUtf8} from 'node:buffer';
import path from 'node:path';
import crypto from 'node:crypto';
import {report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
try {
  const [input,optionsFile,destination,...extra]=process.argv.slice(2);
  if(!input||!optionsFile||!destination||extra.length)throw new Error('Usage: node examples/vtk_fields/run.mjs INPUT.msh OPTIONS.json NEW_DIRECTORY');
  if(fs.existsSync(destination))throw new Error('destination already exists');
  const bytes=fs.readFileSync(input),optionsBytes=fs.readFileSync(optionsFile);
  if(!isUtf8(optionsBytes))throw new Error('options file must contain valid UTF-8');
  const options=JSON.parse(optionsBytes.toString('utf8'));
  if(!options||typeof options!=='object'||Array.isArray(options))throw new Error('options must be an object');
  const {text,...audit}=JSON.parse(report(bytes,JSON.stringify({...options,command:'vtk-fields'})));
  const payloads={'fields.vtk':text,'audit.json':JSON.stringify(audit,null,2)+'\n'};
  const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
  const manifest={input:path.resolve(input),inputSha256:sha(bytes),optionsSha256:sha(optionsBytes),
    outputs:Object.fromEntries(Object.entries(payloads).map(([name,data])=>[name,sha(data)])),
    scope:'explicit same-Mesh source indices; per-field original times retained without alignment; source-index aliases and original tag arrays; keep raw-header/loss sidecar'};
  fs.mkdirSync(destination,{recursive:false});
  for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
  fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify({output:path.resolve(destination),fields:audit.fields.map(f=>({field:f.field,value_array:f.value_array})),losses:audit.losses}));
} catch(error) {console.error(`vtk-fields: ${error.message}`);process.exitCode=2;}
