// IO only: the existing MoonBit audited-stl API decides geometry and losses.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
try {
  const [input,destination,flag,...extra]=process.argv.slice(2);
  if(!input||!destination||extra.length||(flag!==undefined&&flag!=='--permissive'))
    throw new Error('Usage: node examples/audited_stl/run.mjs INPUT.msh NEW_DIRECTORY [--permissive]');
  const bytes=fs.readFileSync(input);
  const permissive=flag==='--permissive';
  // Compute first: parse/policy failures do not create an output directory.
  const result=JSON.parse(report(bytes,JSON.stringify({command:'audited-stl',permissive})));
  const payloads={'surface.stl':result.text,'audit.json':JSON.stringify(result.loss_report,null,2)+'\n'};
  const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
  const manifest={input:path.resolve(input),inputSha256:sha(bytes),policy:permissive?'PermissiveWithAudit':'Strict',
    outputs:Object.fromEntries(Object.entries(payloads).map(([name,data])=>[name,sha(data)])),
    scope:'existing corner-only planar STL; stored winding, explicit loss audit; no outward, closedness or printability certificate'};
  fs.mkdirSync(destination,{recursive:false});
  for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
  fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify({output:path.resolve(destination),policy:manifest.policy,
    triangles:result.loss_report.output_elements,vertices:result.loss_report.output_vertices,
    losses:result.loss_report.losses,estimatedChordError:result.loss_report.estimated_chord_error}));
} catch(error) {console.error(`audited-stl: ${error.message}`);process.exitCode=2;}
