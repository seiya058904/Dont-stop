'use strict';
// Exported candidate, fresh storage, actual mouse/keyboard; probes only observe.
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const [url,out]=process.argv.slice(2);fs.mkdirSync(out,{recursive:true});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=d3d11']});
 const context=await browser.newContext({viewport:{width:1280,height:720},recordVideo:{dir:out,size:{width:1280,height:720}}});
 const page=await context.newPage(),lines=[],rects={};let camp,carry,canvas,combat;const meteors=[];
 page.on('console',m=>{const t=m.text();lines.push(t);
  const r=t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+) on_screen=(true|false)/);
  if(r)rects[r[1]]={x:+r[8],y:+r[9],visible:r[10]==='true',text:r[3]};
  if(t.startsWith('[camp] '))camp=JSON.parse(t.slice(7));
  if(t.startsWith('[loadout] '))carry=JSON.parse(t.slice(10));
  if(t.startsWith('B16_METEOR '))meteors.push(JSON.parse(t.slice(11)));
  if(t.startsWith('[probe] sess=')){const mode=t.match(/sm=(\w+)/);if(mode)combat=mode[1];}
 });
 async function until(fn,label,ms=30000){const end=Date.now()+ms;while(!fn()){if(Date.now()>end)throw Error(label);await sleep(100);}return fn();}
 async function click(tag){await until(()=>rects[tag]?.visible,'missing '+tag);const r=rects[tag],scale=Math.min(canvas.width/410,canvas.height/230);await page.mouse.click(canvas.x+(canvas.width-410*scale)/2+r.x*scale,canvas.y+(canvas.height-230*scale)/2+r.y*scale,{delay:100});await sleep(450);}
 async function find(tag){for(let i=0;i<30&&!rects[tag]?.visible;i++){await page.mouse.move(canvas.x+canvas.width*.2,canvas.y+canvas.height*.65);await page.mouse.wheel(0,100);await sleep(250);}await click(tag);}
 async function search(text){await click('camp-search-box');await page.keyboard.press('Control+A');await page.keyboard.press('Backspace');if(text)await page.keyboard.type(text);await sleep(500);}
 const checks=[];
 try{
  await page.goto(url+'?probe=1');await until(()=>rects['menu-start-button']?.visible,'title',60000);
  canvas=await page.locator('#canvas-host canvas').boundingBox();await click('menu-start-button');await until(()=>camp,'camp');
  await search('112');await find('camp-entry-112');await click('camp-action-0');await until(()=>carry.owned.includes(112),'arc purchased');
  await search('');
  await page.screenshot({path:path.join(out,'weapon.png')});
  await click('camp-attachment-tab');await search('9');await until(()=>camp.order.includes('9'),'A9 search');await find('camp-entry-9');await until(()=>camp.selection==='9','A9 selection');const goldBefore=carry.gold;await click('camp-action-0');await until(()=>carry.gold===goldBefore-2000,'A9 purchase charged');
  await page.screenshot({path:path.join(out,'attachment.png')});await search('');
  await click('camp-magazine-tab');await page.screenshot({path:path.join(out,'magazine.png')});
  await click('camp-talent-tab');await search('T04');await find('camp-entry-T04');
  for(const rank of [0,1,2,3]){
   await until(()=>camp.rank===rank,'rank '+rank);
   assert(camp.detail>=66&&camp.actions<=24,'readable talent payment layout');
   await page.screenshot({path:path.join(out,'talent-rank'+rank+'.png')});
   checks.push({rank,...camp});
   if(rank<3)await click('camp-action-'+(rank===0?0:1));
  }
  for(const viewport of [{width:1280,height:720},{width:1366,height:768},{width:1536,height:864},{width:1920,height:1080}]){
   await page.setViewportSize(viewport);await sleep(700);canvas=await page.locator('#canvas-host canvas').boundingBox();
   await page.screenshot({path:path.join(out,'talent-full-window-'+viewport.width+'.png')});
   assert(camp.detail>=66&&camp.status==='已满级');
  }
  await page.setViewportSize({width:1280,height:720});await sleep(500);canvas=await page.locator('#canvas-host canvas').boundingBox();
  await search('T09');await find('camp-entry-T09');for(let rank=0;rank<3;rank++){await click('camp-action-1');await until(()=>camp.rank===rank+1,'magnet rank');}
  await search('');await click('camp-stage-tab');await find('stage-31');await page.screenshot({path:path.join(out,'stage.png')});
  await click('camp-depart-button');await until(()=>combat==='COMBAT','normal stage31');
  await page.mouse.move(canvas.x+canvas.width*.75,canvas.y+canvas.height*.5);await page.mouse.down();
  for(let i=0;i<8;i++){
   const key=['d','s','a','w'][i%4];await page.keyboard.down(key);await sleep(3000);await page.keyboard.up(key);
   if(meteors.some(m=>m.event==='descent'))await page.screenshot({path:path.join(out,'normal31-'+i+'.png')});
  }
  await page.mouse.up();
  assert(meteors.some(m=>m.event==='descent')&&meteors.some(m=>m.event==='impact'),'normal encounter complete meteor timeline');
  assert(!lines.some(l=>l.includes('SCRIPT ERROR:')||l.startsWith('ERROR:')),'engine errors');
  fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({success:true,checks,meteors,method:'exported Web; real input; fresh storage; normal stage31'},null,2));
 }catch(e){await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({success:false,error:String(e),camp,carry,meteors},null,2));throw e;}
 finally{fs.writeFileSync(path.join(out,'console.log'),lines.join('\n'));await context.close();await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
