// Read-only IO/hash boundary. MoonBit reads the saved layout and checks bindings.
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {isUtf8} from 'node:buffer';
import crypto from 'node:crypto';
import {read_vtk_fields} from '../../_build/js/release/build/cmd/bridge/bridge.js';

const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const digest=value=>typeof value==='string'&&/^[0-9a-f]{64}$/.test(value);
function text(bytes,label) {
  if(!isUtf8(bytes))throw new Error(`${label} must contain valid UTF-8`);
  return bytes.toString('utf8');
}
function object(value,label) {
  if(!value||typeof value!=='object'||Array.isArray(value))throw new Error(`${label} must be an object`);
  return value;
}

/** Consume the unchanged three-file bundle; optional explicit originals pin identity.
 * Hashes establish consistency with the supplied manifest, not authenticity.
 * The recorded original path is never opened automatically. No files are written.
 */
export function verifyBundle(directory,{input,options}={}) {
  if((input===undefined)!==(options===undefined))throw new Error('supply both INPUT.msh and OPTIONS.json, or neither');
  const manifestBytes=fs.readFileSync(path.join(directory,'manifest.json'));
  const manifest=object(JSON.parse(text(manifestBytes,'manifest')),'manifest');
  if(typeof manifest.input!=='string'||!digest(manifest.inputSha256)||!digest(manifest.optionsSha256))throw new Error('manifest source identity is invalid');
  const outputs=object(manifest.outputs,'manifest outputs');
  if(Object.keys(outputs).sort().join('|')!=='audit.json|fields.vtk'||!Object.values(outputs).every(digest))throw new Error('manifest must name exactly fields.vtk and audit.json with SHA256');
  // Fixed protocol names only; do not follow manifest-provided paths.
  const vtk=fs.readFileSync(path.join(directory,'fields.vtk'));
  const audit=fs.readFileSync(path.join(directory,'audit.json'));
  if(sha(vtk)!==outputs['fields.vtk']||sha(audit)!==outputs['audit.json'])throw new Error('bundle payload SHA256 mismatch');
  const readback=JSON.parse(read_vtk_fields(vtk,text(audit,'audit')));
  let sourceIdentity='declared_only';
  if(input!==undefined) {
    const inputBytes=fs.readFileSync(input),optionBytes=fs.readFileSync(options);
    if(sha(inputBytes)!==manifest.inputSha256||sha(optionBytes)!==manifest.optionsSha256)throw new Error('explicit input/options SHA256 mismatch');
    const selected=object(JSON.parse(text(optionBytes,'options')),'options').field_indices;
    const actual=readback.fields.map(item=>item.field.field_index);
    if(!Array.isArray(selected)||selected.length!==actual.length||!selected.every((value,index)=>Number.isInteger(value)&&value===actual[index]))throw new Error('selected field indices do not match the sidecar request order');
    sourceIdentity='byte_verified';
  }
  return {status:'consistent',manifestSha256:sha(manifestBytes),payloadSha256:{'fields.vtk':sha(vtk),'audit.json':sha(audit)},
    sourceIdentity,input:manifest.input,inputSha256:manifest.inputSha256,optionsSha256:manifest.optionsSha256,readback,
    scope:'saved vtk_fields profile, byte identity and field/tag association coherence; no regeneration, source-value/authenticity or geometry/physics certification'};
}

if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url) {
  try {
    const args=process.argv.slice(2);
    if(args.length!==1&&args.length!==3)throw new Error('Usage: node examples/vtk_fields/verify.mjs BUNDLE_DIRECTORY [INPUT.msh OPTIONS.json]');
    console.log(JSON.stringify(verifyBundle(args[0],{input:args[1],options:args[2]}),null,2));
  } catch(error) {console.error(`verify-vtk-fields: ${error.message}`);process.exitCode=2;}
}
