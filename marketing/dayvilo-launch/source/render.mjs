import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_PATH||'/Users/shivvyas/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
fs.mkdirSync(path.join(root,'proofs'),{recursive:true});
const mode=process.argv[2]||'vertical',preview=process.argv.includes('--proof');
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/Users/shivvyas/Library/Caches/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-mac-arm64/chrome-headless-shell',args:['--disable-gpu','--disable-dev-shm-usage']});
try{
 const page=await browser.newPage({viewport:{width:mode==='vertical'?1080:1920,height:mode==='vertical'?1920:1080},deviceScaleFactor:1});
 page.on('pageerror',e=>console.error(e));
 await page.goto('http://127.0.0.1:8877/index.html?render=1');await page.evaluate(()=>window.ready);
 if(preview){for(const t of [1.5,5.8,10.5,16.5,21,23.5,27,33,37.5,40,44,49,54,58]){await page.evaluate(({t,mode})=>renderFrame(t,mode),{t,mode});const data=await page.evaluate(()=>document.querySelector('canvas').toDataURL('image/png').split(',')[1]);fs.writeFileSync(path.join(root,'proofs',`proof-${mode}-${t}.png`),Buffer.from(data,'base64'));}console.log('Proof frames saved');}
 else {
  const file=path.join(root,'exports',`dayvilo-launch-${mode==='vertical'?'9x16':'16x9'}.mp4`);
  const enc=spawn('/usr/local/bin/ffmpeg',['-y','-hide_banner','-loglevel','warning','-f','image2pipe','-vcodec','mjpeg','-framerate','30','-i','pipe:0','-i',path.join(root,'assets/dayvilo-original-score.wav'),'-c:v','libx264','-preset','fast','-crf','18','-threads','2','-vf','scale=in_range=full:out_range=tv,format=yuv420p','-color_range','tv','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-ar','48000','-af','loudnorm=I=-18:TP=-1.5:LRA=8','-t','60','-movflags','+faststart',file],{stdio:['pipe','inherit','inherit']});
  let failed;enc.on('error',e=>failed=e);enc.stdin.on('error',e=>failed=e);
  for(let i=0;i<1800;i++){
   if(failed)throw failed;
   await page.evaluate(({t,mode})=>renderFrame(t,mode),{t:i/30,mode});
   const data=await page.evaluate(()=>document.querySelector('canvas').toDataURL('image/jpeg',.96).split(',')[1]);
   if(!enc.stdin.write(Buffer.from(data,'base64')))await once(enc.stdin,'drain');
   if(i%150===0)console.log(`${mode}: ${i/30}s / 60s`);
  }
  enc.stdin.end();const [code]=await once(enc,'close');if(code!==0)throw Error('ffmpeg exited '+code);console.log(file);
 }
}finally{await browser.close()}
