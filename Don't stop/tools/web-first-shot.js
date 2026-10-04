'use strict';
// Real input, fresh browser/storage, read-only probe and RAF/long-task timing.
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const [url,out,gun='6',trace='']=process.argv.slice(2);
fs.mkdirSync(out,{recursive:true});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist']});
 const viewport={width:Number(process.env.B192_WIDTH||1280),height:Number(process.env.B192_HEIGHT||720)};
 const context=await browser.newContext({viewport,deviceScaleFactor:1,serviceWorkers:'block'});
 const page=await context.newPage(),lines=[],rects={},errors=[];let camp,carry,canvas,state;
 const report={url,gun,viewport,windows:[],errors};
 // Both timestamps use the page's clock. The projectile probe runs after velocity
 // becomes readable, so this is an observation upper bound, not display/input lag.
 await page.addInitScript(()=>{
  const log=console.log.bind(console);
  console.log=(...args)=>{
   if(window.shotMeasure && String(args[0]).startsWith('[probe] proj-shot ') && window.shotMeasure.pointerdown!=null && window.shotMeasure.projectileObserved==null)
    window.shotMeasure.projectileObserved=performance.now();
   log(...args);
  };
  document.addEventListener('pointerdown',()=>{if(window.shotMeasure)window.shotMeasure.pointerdown=performance.now();},true);
 });
 const cdp=await browser.newBrowserCDPSession();report.gpu=(await cdp.send('SystemInfo.getInfo')).gpu.devices;
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('console',m=>{const t=m.text();lines.push(t);
  if(t.includes('SCRIPT ERROR:')||t.startsWith('ERROR:'))errors.push(t);
  const r=t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+) on_screen=(true|false)/);
  if(r)rects[r[1]]={x:+r[8],y:+r[9],visible:r[10]==='true',text:r[3]};
  if(t.startsWith('[camp] '))camp=JSON.parse(t.slice(7));
  if(t.startsWith('[loadout] '))carry=JSON.parse(t.slice(10));
  if(t.startsWith('[probe] sess='))state=t;
 });
 async function until(fn,label,ms=30000){const end=Date.now()+ms;while(!fn()){if(Date.now()>end)throw Error(label);await sleep(100);}return fn();}
 async function click(tag){await until(()=>rects[tag]?.visible,'missing '+tag);const r=rects[tag],s=Math.min(canvas.width/410,canvas.height/230);await page.mouse.click(canvas.x+(canvas.width-410*s)/2+r.x*s,canvas.y+(canvas.height-230*s)/2+r.y*s,{delay:80});await sleep(450);}
 async function measure(name,action){await page.evaluate(()=>{window.shotMeasure={frames:[],tasks:[],last:performance.now()};});await action();await sleep(3500);const data=await page.evaluate(()=>window.shotMeasure);const sorted=data.frames.slice().sort((a,b)=>a-b);report.windows.push({name,frames:sorted.length,max_ms:Math.max(...sorted),p95_ms:sorted[Math.floor(sorted.length*.95)],input_to_projectile_observed_ms:data.projectileObserved!=null?data.projectileObserved-data.pointerdown:null,long_tasks:data.tasks,state});console.log(JSON.stringify(report.windows.at(-1)));}
 try{
  await page.goto(url+'?probe=1');await until(()=>rects['menu-start-button']?.visible,'title',60000);
  report.navigation_to_title_observed_ms=await page.evaluate(()=>performance.now());
  await page.evaluate(()=>{window.shotMeasure=null;let last=performance.now();function frame(t){if(window.shotMeasure)window.shotMeasure.frames.push(t-last);last=t;requestAnimationFrame(frame);}requestAnimationFrame(frame);new PerformanceObserver(list=>{if(window.shotMeasure)window.shotMeasure.tasks.push(...list.getEntries().map(e=>e.duration));}).observe({entryTypes:['longtask']});});
  canvas=await page.locator('#canvas-host canvas').boundingBox();await click('menu-start-button');await until(()=>camp,'camp');
  await click('camp-search-box');await page.keyboard.type(gun);await sleep(500);await click('camp-entry-'+gun);await click('camp-action-0');await until(()=>carry?.owned.includes(+gun),'purchase');
  await page.screenshot({path:path.join(out,'equipped.png')});
  await click('camp-close-button');await until(()=>state?.includes('gun='+gun+' '),'equipped active');
  await page.mouse.move(canvas.x+canvas.width*.75,canvas.y+canvas.height*.5);await sleep(500);
  if(trace)await cdp.send('Tracing.start',{categories:'toplevel,devtools.timeline,v8,blink,cc,gpu,disabled-by-default-gpu.service',transferMode:'ReturnAsStream',streamCompression:'gzip'});
  for(const name of ['first-shot','second-shot','third-shot']){
   const ammo=+state.match(/bullets=(\d+)/)[1];
   await measure(name,async()=>{await page.mouse.down();await sleep(120);await page.mouse.up();});
   assert(+state.match(/bullets=(\d+)/)[1]<ammo,name+' actually fired');
  }
  await page.screenshot({path:path.join(out,'after-shots.png')});
  await measure('first-dash',async()=>{await page.keyboard.down('d');await page.keyboard.press('Shift');await sleep(250);await page.keyboard.up('d');});
  if(trace){const done=new Promise(r=>cdp.once('Tracing.tracingComplete',r));await cdp.send('Tracing.end');const e=await done,chunks=[];while(true){const c=await cdp.send('IO.read',{handle:e.stream,size:1048576});chunks.push(Buffer.from(c.data,c.base64Encoded?'base64':'utf8'));if(c.eof)break;}await cdp.send('IO.close',{handle:e.stream});fs.writeFileSync(path.join(out,'trace.json.gz'),Buffer.concat(chunks));}
  // Capture actual effects separately so readback cannot contaminate timing.
  await page.mouse.down();await sleep(200);await page.screenshot({path:path.join(out,'beam-active.png')});await page.mouse.up();await sleep(1200);
  await page.keyboard.press('Tab');await sleep(500);await click('camp-stage-tab');await click('camp-depart-button');await until(()=>state?.includes('sm=COMBAT'),'combat');
  await page.mouse.move(canvas.x+canvas.width*.75,canvas.y+canvas.height*.5);
  await page.mouse.down();await page.keyboard.down('d');await sleep(1800);await page.keyboard.up('d');await page.mouse.up();
  await page.keyboard.press('r');await sleep(3500);
  await page.mouse.down();await sleep(200);await page.screenshot({path:path.join(out,'combat.png')});await page.mouse.up();
  if(process.env.MAX_FRAME_MS)assert(report.windows.every(w=>w.max_ms<=+process.env.MAX_FRAME_MS),'cold-frame budget');
  assert(!errors.length,'runtime errors');report.success=true;
 }catch(e){report.error=String(e);await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});process.exitCode=1;}
 finally{fs.writeFileSync(path.join(out,'result.json'),JSON.stringify(report,null,2));fs.writeFileSync(path.join(out,'console.log'),lines.join('\n'));await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
