// File/option orchestration only. Existing MoonBit APIs select, encode and integrate.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {isUtf8} from 'node:buffer';
import {report,transform} from '../../_build/js/release/build/cmd/bridge/bridge.js';

function read(file,limit) {
  const fd=fs.openSync(file,'r');
  try {
    const stat=fs.fstatSync(fd);
    if(!stat.isFile()||stat.size>limit)throw new Error(`input must be a file <=${limit} bytes`);
    const bytes=Buffer.alloc(stat.size+1);let n=0,k;
    while(n<bytes.length&&(k=fs.readSync(fd,bytes,n,bytes.length-n,null)))n+=k;
    if(n!==stat.size)throw new Error('input changed size during read; retry stable input');
    return bytes.subarray(0,n);
  } finally {fs.closeSync(fd);}
}
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const json=value=>Buffer.from(JSON.stringify(value,null,2)+'\n');
const query=(bytes,options)=>JSON.parse(report(bytes,JSON.stringify(options)));
const integer=(n,min,max)=>Number.isInteger(n)&&n>=min&&n<=max;

try {
  const [input,request,destination,...extra]=process.argv.slice(2);
  if(!input||!request||!destination||extra.length)throw new Error('Usage: node examples/group_resultants/run.mjs INPUT.msh OPTIONS.json NEW_DIRECTORY');
  if(fs.existsSync(destination))throw new Error('destination already exists');
  const requestBytes=read(request,8_000_000);
  if(!isUtf8(requestBytes))throw new Error('options file must contain valid UTF-8');
  const options=JSON.parse(requestBytes.toString('utf8'));
  if(!options||typeof options!=='object'||Array.isArray(options))throw new Error('options must be an object');
  const allowed=['field_index','groups','max_samples','allow_loss','drop_unknown'];
  if(Object.keys(options).some(k=>!allowed.includes(k)))throw new Error('unknown option');
  if(!integer(options.field_index,0,1023))throw new Error('field_index must be an explicit integer0..1023');
  const groups=options.groups;
  if(!Array.isArray(groups)||groups.length<1||groups.length>16||groups.some(g=>!integer(g,1,2147483647))||new Set(groups).size!==groups.length)throw new Error('groups must contain1..16 unique positive signed32bit ids');
  const maxSamples='max_samples' in options?options.max_samples:1_000_000;
  if(!integer(maxSamples,0,9_000_000))throw new Error('max_samples must be an integer0..9000000');
  for(const key of ['allow_loss','drop_unknown'])if(key in options&&typeof options[key]!=='boolean')throw new Error(`${key} must be Boolean`);
  const source=read(input,134_217_728);
  const sourceFrame=query(source,{command:'field-frames'})[options.field_index];
  if(!sourceFrame)throw new Error('field_index is outside the source section catalog');
  const payloads=new Map([['original.msh',source],['request.json',requestBytes]]),parts=[];
  let groupBytes=0;
  // Prepare every group before creating the destination. A later coverage/error
  // cannot leave an apparently complete early subset of the requested groups.
  for(const [index,group]of groups.entries()) {
    try {
      const mesh=Buffer.from(transform(source,JSON.stringify({command:'physical',dimension:2,group,binary:true,
        drop_unknown:options.drop_unknown??false,allow_loss:options.allow_loss??false})));
      // Compute from the exact bytes that will be saved, after existing loss gates.
      const estimate=query(mesh,{command:'integrate-surface-normal-field',field_index:options.field_index,max_samples:maxSamples});
      const meshFrame=query(mesh,{command:'field-frames'})[options.field_index];
      const meshFile=`group-${index}.msh`,resultFile=`group-${index}-result.json`;
      const result=json({physical_group:group,dimension:2,field_index:options.field_index,source_frame:sourceFrame,mesh_frame:meshFrame,estimate});
      groupBytes+=mesh.length+result.length;
      if(groupBytes>134_217_728)throw new Error('combined group mesh/result payload exceeds134217728 bytes');
      payloads.set(meshFile,mesh);payloads.set(resultFile,result);
      parts.push({physical_group:group,mesh_file:meshFile,result_file:resultFile});
    } catch(error) {throw new Error(`physical group ${group}: ${error.message}`);}
  }
  const manifest={schema:'gmsh-group-resultants/v1',source_path:path.resolve(input),request_path:path.resolve(request),
    source_file:'original.msh',request_file:'request.json',field_index:options.field_index,groups:parts,
    encoding:{version:'source_version',binary:true,little:true,size_width:8},
    allow_loss:options.allow_loss??false,drop_unknown:options.drop_unknown??false,max_samples_per_group:maxSamples,
    outputs:Object.fromEntries([...payloads].map(([name,bytes])=>[name,{sha256:sha(bytes),bytes:bytes.length}])),
    scope:'Independent dimension2 physical selections in request order. Overlap is retained per group; no group aggregate. Existing subset prunes unused nodes/data and updates entry counts, retaining other headers/entities/names. Stored winding and caller units/sign apply. Fixed-rule estimates are not error/geometry/source certificates. Original input/request bytes are archived. IO publication is not atomic.'};
  fs.mkdirSync(destination,{recursive:false});
  for(const [name,bytes]of payloads)fs.writeFileSync(path.join(destination,name),bytes,{flag:'wx'});
  fs.writeFileSync(path.join(destination,'manifest.json'),json(manifest),{flag:'wx'});
  console.log(JSON.stringify({output:path.resolve(destination),groups:parts,files:payloads.size+1}));
} catch(error) {console.error(`group-resultants: ${error.message}`);process.exitCode=2;}
