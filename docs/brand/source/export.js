// Renders every SVG in ../ to PNG in ../exports with headless Google Chrome. macOS path; change CHROME for other systems.
const fs=require('fs'),path=require('path'),{execFileSync}=require('child_process');
const ROOT=path.join(__dirname,'..'),EXP=path.join(ROOT,'exports'),TMP=path.join(__dirname,'.tmp'); fs.mkdirSync(EXP,{recursive:true}); fs.mkdirSync(TMP,{recursive:true});
const CHROME=process.env.CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
function dims(svg){const m=fs.readFileSync(svg,'utf8').match(/width="([\d.]+)" height="([\d.]+)"/);return[+m[1],+m[2]];}
function shot(html,w,h,out,transparent=true){fs.writeFileSync(path.join(TMP,'r.html'),html);
  execFileSync(CHROME,['--headless=new','--disable-gpu','--hide-scrollbars',...(transparent?['--default-background-color=00000000']:[]),'--force-device-scale-factor=1',`--window-size=${w},${h}`,`--screenshot=${out}`,'file://'+path.join(TMP,'r.html')],{stdio:'ignore'});}
function render(name,width,out){const svg=path.join(ROOT,name+'.svg');const[w,h]=dims(svg);const H=Math.round(width*h/w);
  shot(`<!doctype html><style>html,body{margin:0;background:transparent}img{display:block;width:${width}px;height:${H}px}</style><img src="file://${svg}">`,width,H,path.join(EXP,out||`${name}-${width}.png`));}
for(const n of['almanac-icon','almanac-icon-square','almanac-mark','almanac-mark-mono'])for(const s of[256,512,1024,2048])render(n,s);
for(const n of['almanac-wordmark-ink','almanac-wordmark-cream','almanac-wordmark-orange','almanac-lockup-horizontal-ink','almanac-lockup-horizontal-cream'])for(const s of[800,1600,3200])render(n,s);
for(const n of['almanac-lockup-stacked-ink','almanac-lockup-stacked-cream'])for(const s of[600,1200,2400])render(n,s);
for(const s of[32,64,192])render('almanac-icon',s,`favicon-${s}.png`);
render('almanac-icon-square',180,'apple-touch-icon-180.png');
shot(`<!doctype html><style>html,body{margin:0;width:1200px;height:630px;background:#fbf5ee;display:flex;align-items:center;justify-content:center}img{height:220px}</style><img src="file://${path.join(ROOT,'almanac-lockup-horizontal-ink.svg')}">`,1200,630,path.join(EXP,'og-image-1200x630.png'),false);
fs.rmSync(TMP,{recursive:true,force:true}); console.log('exports written to',EXP);
