import readline from 'node:readline';
import {report,transform,new_file} from '../_build/js/release/build/cmd/bridge/bridge.js';
for await(const line of readline.createInterface({input:process.stdin,crlfDelay:Infinity})) {
  try {
    const q=JSON.parse(line),o=JSON.stringify(q.options??{}),data=Buffer.from(q.data??'','base64');
    const value=q.action==='create'?{bytes:Buffer.from(new_file(o)).toString('base64')}
      :q.action==='transform'?{bytes:Buffer.from(transform(data,o)).toString('base64')}
      :JSON.parse(report(data,o));
    console.log(JSON.stringify({ok:true,result:value}));
  } catch(e) {console.log(JSON.stringify({ok:false,error:e.message}));}
}
