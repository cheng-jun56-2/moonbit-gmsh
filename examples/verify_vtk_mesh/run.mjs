// IO only: MoonBit verifies saved field headers/tuples and full exported geometry.
import fs from 'node:fs';
import {isUtf8} from 'node:buffer';
import {verify_vtk_mesh} from '../../_build/js/release/build/cmd/bridge/bridge.js';
function read(file) {
  const fd=fs.openSync(file,'r');
  try {
    const stat=fs.fstatSync(fd);
    if(!stat.isFile()||stat.size>134_217_728)throw new Error('input must be a file <=134217728 bytes');
    const bytes=Buffer.alloc(stat.size+1);let n=0,k;
    while(n<bytes.length&&(k=fs.readSync(fd,bytes,n,bytes.length-n,null)))n+=k;
    if(n!==stat.size)throw new Error('input changed size during read; retry stable input');
    return bytes.subarray(0,n);
  } finally {fs.closeSync(fd);}
}
try {
  const [source,vtk,audit,output,...extra]=process.argv.slice(2);
  if(!source||!vtk||!audit||!output||extra.length)throw new Error('Usage: node examples/verify_vtk_mesh/run.mjs SOURCE.msh SAVED.vtk AUDIT.json NEW_RESULT.json');
  const sourceBytes=read(source),vtkBytes=read(vtk),auditBytes=read(audit);
  if(!isUtf8(auditBytes))throw new Error('audit must contain valid UTF-8');
  const result=verify_vtk_mesh(sourceBytes,vtkBytes,auditBytes.toString('utf8'));
  fs.writeFileSync(output,result+'\n',{flag:'wx'});
} catch(error) {console.error(`verify-vtk-mesh: ${error.message}`);process.exitCode=2;}
