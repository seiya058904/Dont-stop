'use strict';
// Real mouse/keyboard input on an isolated browser profile; probe is read-only.
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const url=process.argv[2],out=process.argv[3];
fs.mkdirSync(out,{recursive:true});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=d3d11']});
 const context=await browser.newContext({viewport:{width:1280,height:760}});
 const page=await context.newPage(), lines=[],rects={};let state=null,canvas,combat=null;
 page.on('console',m=>{const t=m.text();lines.push(t);
  const r=t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+) on_screen=(true|false)/);
  if(r)rects[r[1]]={x:+r[8],y:+r[9],visible:r[10]==='true',text:r[3]};
  if(t.startsWith('[loadout] '))state=JSON.parse(t.slice(10));
  if(t.startsWith('[probe] sess=')) {
   const gun=t.match(/gun=(-?\d+) bullets=(-?\d+)\//),mode=t.match(/sm=(\w+)/);
   if(gun&&mode)combat={gun:+gun[1],bullets:+gun[2],mode:mode[1]};
  }
 });
 async function until(fn,label,ms=30000){const end=Date.now()+ms;while(!fn()){if(Date.now()>end)throw Error(label);await sleep(100);}return fn();}
 async function click(tag){await until(()=>rects[tag]?.visible,'missing '+tag);const r=rects[tag];await page.mouse.move(canvas.x+r.x/410*canvas.width,canvas.y+r.y/230*canvas.height);await page.mouse.down();await sleep(110);await page.mouse.up();await sleep(450);}
 async function search(id){await click('camp-search-box');await page.keyboard.press('Control+A');await page.keyboard.type(String(id));await sleep(650);
  for(let step=0;step<12&&!rects['camp-weapon-'+id]?.visible;step++){
   await page.mouse.move(canvas.x+75/410*canvas.width,canvas.y+160/230*canvas.height);await page.mouse.wheel(0,120);await sleep(350);
  }
  await click('camp-weapon-'+id);
 }
 try{
  await page.goto(url+'?probe=1');
  await until(()=>rects['menu-start-button'],'title',60000);
  canvas=await page.locator('#canvas-host canvas').boundingBox();
  await click('menu-start-button');await until(()=>state,'camp');
  await page.screenshot({path:path.join(out,'01-empty.png')});
  for(const id of [0,1,2,3,4,5,6,7,124]){
   await search(id);await click('camp-weapon-action');
   await until(()=>state.owned.includes(id),'purchase '+id);
  }
  assert.deepStrictEqual(state.slots,[0,1,2,3,4,5,6]);
  await page.screenshot({path:path.join(out,'02-full.png')});
  await search(124);await click('camp-weapon-owned-action');
  await until(()=>state.message.includes('已满'),'full replacement prompt');
  await click('loadout-select_slot-3');
  await until(()=>state.slots[3]===124&&state.equipped===124,'replace fourth');
  await page.screenshot({path:path.join(out,'03-replaced.png')});
  await click('loadout-remove_slot-3');
  await until(()=>state.slots[3]===-1&&state.equipped===-1,'remove current');
  await click('loadout-clear');await until(()=>state.slots.every(v=>v===-1),'clear');
  await page.screenshot({path:path.join(out,'04-cleared.png')});
  await click('loadout-clear');
  await page.reload();for(const k of Object.keys(rects))delete rects[k];state=null;
  await until(()=>rects['menu-start-button'],'reload title');
  canvas=await page.locator('#canvas-host canvas').boundingBox();
  await click('menu-start-button');await until(()=>state,'restored camp');
  assert(state.owned.length===9&&state.slots.every(v=>v===-1)&&state.equipped===-1);
  await click('loadout-select_slot-6');await search(7);await click('camp-weapon-owned-action');
  await until(()=>state.slots[6]===7&&state.equipped===7,'reconfigure eighth');
  await page.screenshot({path:path.join(out,'05-restored-reconfigured.png')});
  await click('loadout-select_slot-0');await search(124);await click('camp-weapon-owned-action');
  await until(()=>state.slots[0]===124,'add 24th to first slot');
  await click('camp-stage-tab');await click('stage-1');await click('camp-depart-button');
  await until(()=>combat?.mode==='COMBAT','depart');
  for(const key of ['7','1']){
   await page.keyboard.press(key);const id=key==='7'?7:124;
   await until(()=>combat.gun===id,'hotkey '+key);
   const before= combat.bullets;
   await page.mouse.move(canvas.x+canvas.width*.7,canvas.y+canvas.height*.45);
   await page.mouse.down();await sleep(700);await page.mouse.up();
   await until(()=>combat.bullets<before,'real firing '+id);
  }
  await page.keyboard.press('7');await until(()=>combat.gun===7,'switch before HUD click');await sleep(200);
  await click('hud-slot-0');await until(()=>combat.gun===124,'mouse HUD switches current');
  await page.screenshot({path:path.join(out,'06-combat-hud.png')});
  assert(!lines.some(l=>l.includes('SCRIPT ERROR:')),'script errors');
  fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({success:true,state,method:'Playwright Chromium ANGLE D3D11; real mouse/keyboard; isolated fresh browser profile'},null,2));
 }catch(e){await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({success:false,error:String(e),state,rects},null,2));throw e;}
 finally{fs.writeFileSync(path.join(out,'console.log'),lines.join('\n'));await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
