'use strict';
// Real inputs, normal HP, isolated browser storage. Read-only probe, no game mutation.
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const [url,out]=process.argv.slice(2);fs.mkdirSync(out,{recursive:true});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=d3d11']});
 const context=await browser.newContext({viewport:{width:1280,height:720}});
 const page=await context.newPage(),lines=[],errors=[],rects={};let state=null,combat=null,canvas;
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('console',m=>{const t=m.text();lines.push(t);
  const r=t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+) on_screen=(true|false)/);
  if(r)rects[r[1]]={x:+r[8],y:+r[9],visible:r[10]==='true',text:r[3]};
  if(t.startsWith('[loadout] '))state=JSON.parse(t.slice(10));
  if(t.startsWith('[probe] sess=')){
   const gun=t.match(/gun=(-?\d+) bullets=(-?\d+)\//),mode=t.match(/sm=(\w+)/),stage=t.match(/stage=(\d+)/),hp=t.match(/hp=([\d.-]+)/);
   if(gun&&mode&&stage)combat={gun:+gun[1],bullets:+gun[2],mode:mode[1],stage:+stage[1],hp:hp?+hp[1]:null};
  }
 });
 async function until(fn,label,ms=30000){const end=Date.now()+ms;while(!fn()){if(Date.now()>end)throw Error(label);await sleep(100);}return fn();}
 async function click(tag){await until(()=>rects[tag]?.visible,'missing '+tag);const r=rects[tag],scale=Math.min(canvas.width/410,canvas.height/230);await page.mouse.click(canvas.x+(canvas.width-410*scale)/2+r.x*scale,canvas.y+(canvas.height-230*scale)/2+r.y*scale,{delay:100});await sleep(400);}
 async function enter(){await until(()=>rects['menu-start-button']?.visible,'title',60000);canvas=await page.locator('#canvas-host canvas').boundingBox();await click('menu-start-button');await until(()=>state,'camp');}
 async function find(tag){for(let i=0;i<24&&!rects[tag]?.visible;i++){await page.mouse.move(canvas.x+75/410*canvas.width,canvas.y+150/230*canvas.height);await page.mouse.wheel(0,120);await sleep(250);}await click(tag);}
 async function buy(id){await click('camp-search-box');await page.keyboard.press('Control+A');await page.keyboard.type(String(id));await sleep(400);await find('camp-weapon-'+id);await click('camp-weapon-action');await until(()=>state.owned.includes(id),'buy '+id);}
 const observations=[];
 try{
  await page.goto(url+'?probe=1');await enter();
  const identity=await page.locator('meta[name="dontstop-build"]').getAttribute('content');
  for(const id of [113,115,119,124]){await buy(id);await page.screenshot({path:path.join(out,'camp-'+id+'.png')});}
  assert.deepStrictEqual(state.slots.slice(0,4),[113,115,119,124]);
  await click('camp-stage-tab');await find('stage-39');await until(()=>state.selection==='39','selected39');await click('camp-depart-button');await until(()=>combat?.mode==='COMBAT'&&combat.stage===39,'real39');
  await page.keyboard.down('d');
  for(const [index,id] of [113,115,119,124].entries()){
   await page.keyboard.press(String(index+1));await until(()=>combat.gun===id,'switch '+id);
   const ammo=combat.bullets;
   await page.mouse.move(canvas.x+canvas.width*.7,canvas.y+canvas.height*.45);
   await page.mouse.down();await sleep(id===113?950:750);await page.mouse.up();
   await until(()=>combat.bullets<ammo,'real shot '+id,5000);
   observations.push({id,...combat});await page.screenshot({path:path.join(out,'stage39-'+id+'.png')});
  }
  await page.keyboard.up('d');
  // Restart through the normal saved camp, never injecting a stage or editing storage.
  state=null;combat=null;for(const k of Object.keys(rects))delete rects[k];
  await page.reload();await enter();await click('camp-stage-tab');await find('stage-40');await until(()=>state.selection==='40','selected40');await click('camp-depart-button');
  await until(()=>combat?.mode==='COMBAT'&&combat.stage===40,'real40');
  await page.mouse.move(canvas.x+canvas.width*.6,canvas.y+canvas.height*.3);
  await page.keyboard.down('a');await page.mouse.down();await sleep(1500);await page.mouse.up();await page.keyboard.up('a');
  await page.screenshot({path:path.join(out,'stage40-opening.png')});observations.push({...combat});
  assert(!errors.length&&!lines.some(l=>l.includes('SCRIPT ERROR:')),'script/page error');
  fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({success:true,identity,observations,method:'Playwright Chromium ANGLE D3D11, real input, normal HP, isolated profile; short rendered gameplay, not completion or performance acceptance'},null,2));
 }catch(e){await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({success:false,error:String(e),observations,state,combat,errors},null,2));throw e;}
 finally{fs.writeFileSync(path.join(out,'console.log'),lines.join('\n'));await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
