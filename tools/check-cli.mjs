import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'moongmsh-cli-'));
let checks=0;
function run(args,expected=0) {
  const r=spawnSync(process.execPath,['tools/gmsh.mjs',...args],{encoding:'utf8'});
  assert.equal(r.status,expected,r.stderr);checks++;
  return r.stdout;
}
function options(name,o){const p=path.join(tmp,name+'.json');fs.writeFileSync(p,JSON.stringify(o));return p;}
try {
  const file='examples/triangle.msh';
  assert.equal(JSON.parse(run(['inspect',file])).nodes,3);
  assert.equal(JSON.parse(run(['dump',file])).fields[0].entries[1].tag,90);
  assert.equal(JSON.parse(run(['quality',file,'examples/quality.json'])).measure,.5);
  assert.equal(JSON.parse(run(['topology',file])).boundary.length,3);
  assert.deepEqual(JSON.parse(run(['components',file])),[[77]]);
  run(['validate',file,'examples/strict.json']);
  const binary=path.join(tmp,'binary.msh');
  run(['convert',file,'examples/convert.json',binary]);
  assert.equal(JSON.parse(run(['inspect',binary])).version,'4.1');
  const compact=path.join(tmp,'compact.msh');
  run(['compact',file,options('empty',{}),compact]);
  assert.equal(JSON.parse(run(['dump',compact])).fields[0].entries[1].tag,3);
  const selected=path.join(tmp,'selected.msh');
  run(['subset',file,'examples/subset.json',selected]);
  const physical=path.join(tmp,'physical.msh');
  run(['physical',file,options('group',{dimension:2,group:4}),physical]);
  assert.match(run(['vtk',file,'examples/export.json']),/CELLS 1 4/);
  assert.match(run(['obj',file,'examples/export.json']),/f 1 2 3/);
  const vtk=path.join(tmp,'mesh.vtk');
  run(['vtk',file,'examples/export.json',vtk]);assert.ok(fs.statSync(vtk).size>50);
  run(['convert',file,'examples/convert.json',binary],2); // no clobber
  run(['vtk',file],2); // requires explicit metadata loss
  run(['convert',file],2);
  run(['inspect',path.join(tmp,'absent.msh')],2);
  run(['inspect',file,options('bad',[])],2);
  run(['unknown',file],2);
  const bad=path.join(tmp,'bad.msh');fs.writeFileSync(bad,'not a mesh');
  run(['inspect',bad],2);
  const create=options('create',{nodes:[{tag:1,xyz:[0,0,0]},{tag:2,xyz:[1,0,0]}],elements:[{tag:1,kind:2,nodes:[1,1,2]}]});
  const degenerate=path.join(tmp,'degenerate.msh');
  run(['create',create,degenerate]);
  const d=JSON.parse(run(['validate',degenerate,'examples/strict.json'],3));
  assert.ok(d.qualities[0].degenerate);
  // Authored UTF-8 bytes and names are independent of the production validator.
  const names=[
    {name:'温度🙂-e\u0301',hex:'e6b8a9e5baa6f09f99822d65cc81'},
    {name:'\ufffd',hex:'efbfbd'},
  ];
  function modelBytes(name,version='2.2',binary=false) {
    return Buffer.concat([
      Buffer.from('{"nodes":[{"tag":1,"xyz":[0,0,0]}],"elements":[{"tag":1,"kind":15,"nodes":[1]}],"fields":[{"location":"NodeData","strings":["','ascii'),
      name,
      Buffer.from('"],"reals":[0],"integers":[0,1,1],"entries":[{"tag":1,"values":[1]}]}],"version":"'+version+'","binary":'+binary+'}','ascii'),
    ]);
  }
  const utf8Readbacks=[],sources=[];
  for(const [index,golden] of names.entries())for(const version of ['2.2','4.1'])for(const binary of [false,true]) {
    const bytes=Buffer.from(golden.hex,'hex'),raw=modelBytes(bytes,version,binary);
    const json=path.join(tmp,`unicode-${index}-${version}-${binary}.json`),mesh=json+'.msh';
    fs.writeFileSync(json,raw);run(['create',json,mesh]);
    const stored=fs.readFileSync(mesh);
    assert.ok(stored.includes(Buffer.concat([Buffer.from('"'),bytes,Buffer.from('"\n')])),'exact field-name bytes in MSH');
    const frames=JSON.parse(run(['field-frames',mesh]));
    assert.equal(frames.length,1);assert.equal(frames[0].name,golden.name);
    assert.deepEqual(fs.readFileSync(json),raw,'valid options unchanged');
    assert.deepEqual(fs.readFileSync(mesh),stored,'field-frame query leaves input unchanged');
    sources.push({mesh,stored,name:golden.name});utf8Readbacks.push({nameHex:golden.hex,version,binary});
  }
  function refuse(args,script='tools/gmsh.mjs',encodingError=true) {
    const r=spawnSync(process.execPath,[script,...args],{encoding:'utf8'});
    assert.equal(r.status,2,r.stderr);if(encodingError)assert.match(r.stderr,/UTF-8/);checks++;
  }
  const malformed=[['invalid-lead','ff'],['lone-continuation','80'],['overlong','c0af'],['truncated','e282'],['surrogate','eda080'],['out-of-range','f4908080'],['bad-continuation','e228a1']];
  const source=sources[0],kept=path.join(tmp,'keep-existing.msh'),sentinel=Buffer.from('keep-existing-output');
  fs.writeFileSync(kept,sentinel);
  for(const [label,hex] of malformed) {
    const raw=modelBytes(Buffer.concat([Buffer.from('bad-'),Buffer.from(hex,'hex')]));
    const json=path.join(tmp,label+'.json'),fresh=json+'.msh',report=json+'.report';fs.writeFileSync(json,raw);
    refuse(['create',json,fresh]);assert.ok(!fs.existsSync(fresh),'no malformed-name output');
    refuse(['create',json,kept]);assert.deepEqual(fs.readFileSync(kept),sentinel,'occupied output unchanged');
    refuse(['inspect',source.mesh,json,report]);assert.ok(!fs.existsSync(report),'no report on malformed options');
    refuse(['inspect',source.mesh,json,kept]);assert.deepEqual(fs.readFileSync(kept),sentinel);
    assert.deepEqual(fs.readFileSync(json),raw,'malformed JSON bytes unchanged');
    assert.deepEqual(fs.readFileSync(source.mesh),source.stored,'mesh input unchanged');
  }
  for(const [entry,selection] of [['vtk_field','"field_index":0'],['vtk_fields','"field_indices":[0]']]) {
    const script=`examples/${entry}/run.mjs`,input=sources.at(-1),json=path.join(tmp,entry+'-options.json');
    const prefix=Buffer.from('{'+selection+',"allow_loss":true,"note":"');
    const raw=Buffer.concat([prefix,Buffer.from([0xff]),Buffer.from('"}')]);fs.writeFileSync(json,raw);
    const fresh=path.join(tmp,entry+'-rejected'),occupied=path.join(tmp,entry+'-occupied');
    fs.mkdirSync(occupied);fs.writeFileSync(path.join(occupied,'keep'),sentinel);
    refuse([input.mesh,json,fresh],script);assert.ok(!fs.existsSync(fresh),'example rejects before directory creation');
    refuse([input.mesh,json,occupied],script,false);
    assert.deepEqual(fs.readdirSync(occupied),['keep']);assert.deepEqual(fs.readFileSync(path.join(occupied,'keep')),sentinel);
    assert.deepEqual(fs.readFileSync(json),raw);assert.deepEqual(fs.readFileSync(input.mesh),input.stored);
    const valid=Buffer.concat([prefix,Buffer.from('efbfbd','hex'),Buffer.from('"}')]);fs.writeFileSync(json,valid);
    const destination=path.join(tmp,entry+'-valid');
    const r=spawnSync(process.execPath,[script,input.mesh,json,destination],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);checks++;
    const audit=JSON.parse(fs.readFileSync(path.join(destination,'audit.json'),'utf8'));
    assert.equal(entry==='vtk_field'?audit.field.name:audit.fields[0].field.name,input.name);
    assert.deepEqual(fs.readFileSync(json),valid);assert.deepEqual(fs.readFileSync(input.mesh),input.stored);
  }
  console.log(JSON.stringify({checks,platform:process.platform,node:process.version,utf8:{malformedByteClasses:malformed.map(([label])=>label),validMshReadbacks:utf8Readbacks,externalExampleEntries:['vtk_field','vtk_fields'],independentExpectations:'authored byte hex, literal Unicode names, exact MSH header bytes, field-frame readback and unchanged input/output bytes'}}));
} finally {
  const actual=path.resolve(tmp),parent=path.resolve(os.tmpdir());
  if(path.dirname(actual)===parent&&path.basename(actual).startsWith('moongmsh-cli-')) fs.rmSync(actual,{recursive:true});
}
