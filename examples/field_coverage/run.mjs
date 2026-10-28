// IO only: frame metadata, coverage, transformations and integrals are MoonBit.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {new_file,transform,report} from '../../_build/js/release/build/cmd/bridge/bridge.js';
const [destination]=process.argv.slice(2);
if(!destination)throw new Error('Usage: node examples/field_coverage/run.mjs NEW_DIRECTORY');
const inspect=(b,o)=>JSON.parse(report(b,JSON.stringify(o)));
const change=(b,o)=>Buffer.from(transform(b,JSON.stringify(o)));
const source=Buffer.from(new_file(fs.readFileSync(new URL('./source.json',import.meta.url),'utf8')));
const selected=change(source,{command:'subset',tags:[700,900]});
const boundary=change(source,{command:'boundary-msh',allow_loss:true});
const wall=change(boundary,{command:'physical',dimension:2,group:44});
const compact=change(selected,{command:'compact'});
const binary=change(compact,{command:'convert',version:'4.1',binary:true});
const catalogs={},coverage={};
for(const [name,data]of [['mixed',selected],['wall',wall],['compactBinary',binary]]){
  catalogs[name]=inspect(data,{command:'field-frames'});
  coverage[name]=catalogs[name].map(f=>inspect(data,{command:'surface-field-coverage',field_index:f.field_index}));
}
coverage.countOnlyPartial=inspect(selected,{command:'surface-field-coverage',field_index:1,max_missing:0});
const payloads={
  'source.msh':source,'mixed.msh':selected,'wall.msh':wall,'compact-4.1.msh':binary,
  'catalog.json':JSON.stringify(catalogs,null,2)+'\n',
  'coverage.json':JSON.stringify(coverage,null,2)+'\n',
  'provenance.json':JSON.stringify(inspect(source,{command:'boundary'}),null,2)+'\n',
  'flux.json':JSON.stringify({chosenFrame2:inspect(wall,{command:'integrate-surface-flux',field_index:2}),explicitCellFrame4:inspect(wall,{command:'integrate-surface-flux',field_index:4})},null,2)+'\n',
};
fs.mkdirSync(destination,{recursive:false});
for(const [name,data]of Object.entries(payloads))fs.writeFileSync(path.join(destination,name),data,{flag:'wx'});
const digest=v=>crypto.createHash('sha256').update(v).digest('hex');
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({outputs:Object.fromEntries(Object.entries(payloads).map(([n,v])=>[n,digest(v)])),scope:'exact source frames, unique full-node/face tag coverage, capped missing IDs and current compact identifiers; no missing-value fill or geometry certificate'},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output:destination,partial:coverage.mixed[1],compactPartial:coverage.compactBinary[1],chosenTime:catalogs.wall[2].time}));
