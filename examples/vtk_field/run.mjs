// IO only: MoonBit decides data order, IDs, geometry and every omission.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
try {
  const [input,optionsFile,destination,...extra]=process.argv.slice(2);
  if(!input||!optionsFile||!destination||extra.length)throw new Error('Usage: node examples/vtk_field/run.mjs INPUT.msh OPTIONS.json NEW_DIRECTORY');
  if(fs.existsSync(destination))throw new Error('destination already exists');
  const bytes=fs.readFileSync(input),optionsBytes=fs.readFileSync(optionsFile);
  const options=JSON.parse(optionsBytes.toString('utf8'));
  if(!options||typeof options!=='object'||Array.isArray(options))throw new Error('options must be an object');
  const {text,...audit}=JSON.parse(report(bytes,JSON.stringify({...options,command:'vtk-field'})));
  const payloads={'field.vtk':text,'audit.json':JSON.stringify(audit,null,2)+'\n'};
  const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
  const manifest={input:path.resolve(input),inputSha256:sha(bytes),optionsSha256:sha(optionsBytes),
    outputs:Object.fromEntries(Object.entries(payloads).map(([name,data])=>[name,sha(data)])),
    scope:'one exact frame; gmsh_value and gmsh_tag arrays; keep raw-header/loss sidecar; no field transfer, interpretation or geometry certificate'};
  fs.mkdirSync(destination,{recursive:false});
  for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
  fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify({output:path.resolve(destination),field:audit.field,losses:audit.losses}));
} catch(error) {console.error(`vtk-field: ${error.message}`);process.exitCode=2;}
