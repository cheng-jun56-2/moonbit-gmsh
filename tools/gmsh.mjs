#!/usr/bin/env node
import fs from 'node:fs';
import {isUtf8} from 'node:buffer';
import {report,transform,new_file,append_fields} from '../_build/js/release/build/cmd/bridge/bridge.js';
const usage=`Usage: node tools/gmsh.mjs COMMAND INPUT [OPTIONS.json] [OUTPUT]
       node tools/gmsh.mjs create OPTIONS.json OUTPUT
       node tools/gmsh.mjs append-fields RECIPIENT.msh DONOR.msh OPTIONS.json OUTPUT.msh
Reports: inspect dump validate quality topology components boundary coverage vtk obj
         vtk-field (field_index and allow_loss=true; JSON text+raw headers/losses)
         vtk-fields (unique nonempty field_indices and allow_loss=true; combined JSON)
         field-frames / surface-field-coverage (field_index required for coverage; max_missing optional)
         field-records (location, tag, unique nonempty original field_indices; raw JSON)
         evaluate-tet4-field (field_index, element_tag, reference:[r,s,t]; standard NodeData only)
         integrate-surface-field / integrate-surface-flux / surface-flux-breakdown
         integrate-surface-normal-field (exactly1 supplied scalar -> vector)
         (field_index required; max_samples optional; breakdown adds max_elements)
Writes: copy convert subset node-cloud remap-tags physical physical-name compact boundary-msh select-fields (OUTPUT required)
select-fields requires field_indices (unique ordered source positions; [] removes all)
boundary reports source mapping and losses; boundary-msh requires allow_loss
when that report lists omissions. Derived MSH defaults to version 2.2.
Options are a JSON FILE, not inline JSON; existing outputs are never overwritten.
validate reports geometry defects in JSON; strict=true also exits 3 for supported
defects. Unsupported quality types remain explicit and are not certified valid.`;
function read(file,limit) {
  const fd=fs.openSync(file,'r');
  try {
    const stat=fs.fstatSync(fd);
    if(!stat.isFile()||stat.size>limit) throw new Error(`input must be a file <=${limit} bytes`);
    const b=Buffer.alloc(stat.size+1);let n=0,k;
    while(n<b.length&&(k=fs.readSync(fd,b,n,b.length-n,null))) n+=k;
    if(n>stat.size) throw new Error('file grew during read; retry stable input');
    if(n<stat.size) throw new Error('file shrank during read; retry stable input');
    return b.subarray(0,n);
  } finally {fs.closeSync(fd);}
}
function options(file) {
  const bytes=file?read(file,8_000_000):null;
  // Check raw bytes before replacement decoding; a correctly encoded U+FFFD is legal.
  if(bytes&&!isUtf8(bytes)) throw new Error('options file must contain valid UTF-8');
  const o=bytes?JSON.parse(bytes.toString('utf8')):{};
  if(!o||typeof o!=='object'||Array.isArray(o)) throw new Error('options must be an object');
  return o;
}
const save=(path,data)=>fs.writeFileSync(path,data,{flag:'wx'});
try {
  const a=process.argv.slice(2);
  if(a.length===1&&['--help','-h'].includes(a[0])) console.log(usage);
  else if(a[0]==='create') {
    if(a.length!==3) throw new Error(usage);
    save(a[2],Buffer.from(new_file(JSON.stringify(options(a[1])))));
  } else if(a[0]==='append-fields') {
    if(a.length!==5) throw new Error(usage);
    const o=options(a[3]);
    const recipient=read(a[1],134_217_728),donor=read(a[2],134_217_728);
    save(a[4],Buffer.from(append_fields(recipient,donor,JSON.stringify(o))));
  } else {
    if(a.length<2||a.length>4) throw new Error(usage);
    const [command,input,opts,output]=a,o=options(opts);o.command=command;
    const bytes=read(input,134_217_728);
    if(['copy','convert','subset','node-cloud','remap-tags','physical','physical-name','compact','boundary-msh','select-fields'].includes(command)) {
      if(!output) throw new Error('transformation requires OUTPUT');
      save(output,Buffer.from(transform(bytes,JSON.stringify(o))));
    } else {
      const value=JSON.parse(report(bytes,JSON.stringify(o)));
      const text=['vtk','obj'].includes(command)?value.text:JSON.stringify(value,null,2)+'\n';
      if(output) save(output,text);else process.stdout.write(text);
      if(command==='validate'&&o.strict===true&&(value.isolated.length||value.duplicate_nodes.length||value.repeated_connectivity.length||value.qualities.some(q=>q.degenerate||q.inverted))) process.exitCode=3;
      if(command==='coverage'&&o.strict===true&&(value.unlabeled.length||value.multiple.length||value.missing_groups.length)) process.exitCode=3;
      if(command==='surface-field-coverage'&&o.strict===true&&value.missing_count>0) process.exitCode=3;
    }
  }
} catch(e) {console.error(`gmsh: ${e.message}`);process.exitCode=2;}
