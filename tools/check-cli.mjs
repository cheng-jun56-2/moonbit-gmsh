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
  console.log(JSON.stringify({checks,platform:process.platform,node:process.version}));
} finally {
  const actual=path.resolve(tmp),parent=path.resolve(os.tmpdir());
  if(path.dirname(actual)===parent&&path.basename(actual).startsWith('moongmsh-cli-')) fs.rmSync(actual,{recursive:true});
}
