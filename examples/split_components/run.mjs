// IO/orchestration only: MoonBit computes connectivity, subset, remapping and MSH.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {report,transform} from '../../_build/js/release/build/cmd/bridge/bridge.js';
try {
  const [input,destination,...extra]=process.argv.slice(2);
  if(!input||!destination||extra.length)throw new Error('Usage: node examples/split_components/run.mjs INPUT.msh NEW_DIRECTORY');
  if(fs.existsSync(destination))throw new Error('destination already exists');
  const data=fs.readFileSync(input);
  const inspect=(bytes,command)=>JSON.parse(report(bytes,JSON.stringify({command})));
  const change=(bytes,options)=>Buffer.from(transform(bytes,JSON.stringify(options)));
  const components=inspect(data,'components'),parts=[],payloads={};
  payloads['components.json']=JSON.stringify(components,null,2)+'\n';
  for(const [index,tags]of components.entries()) {
    const original=change(data,{command:'subset',tags,version:'4.1',binary:true});
    const dense=change(original,{command:'compact',version:'4.1',binary:true});
    const before=inspect(original,'dump'),after=inspect(dense,'dump');
    const originalName=`component-${index}.msh`,denseName=`component-${index}-compact.msh`;
    payloads[originalName]=original;payloads[denseName]=dense;
    parts.push({index,source_element_tags:tags,original_file:originalName,dense_file:denseName,
      before_compact_node_tags:before.nodes.map(n=>n.tag),dense_node_tags:after.nodes.map(n=>n.tag),
      before_compact_element_tags:before.elements.map(e=>e.tag),dense_element_tags:after.elements.map(e=>e.tag)});
  }
  const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
  const manifest={input:path.resolve(input),inputSha256:sha(data),parts,
    outputs:Object.fromEntries(Object.entries(payloads).map(([name,bytes])=>[name,sha(bytes)])),
    scope:'shared full node IDs across all dimensions; no coordinate weld/face-only/physical-group partition. Subset filters data, compact remaps; stored file node order is explicit.'};
  fs.mkdirSync(destination,{recursive:false});
  for(const [name,bytes]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),bytes,{flag:'wx'});
  fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify({output:path.resolve(destination),components,files:Object.keys(payloads).length}));
} catch(error) {console.error(`split-components: ${error.message}`);process.exitCode=2;}
