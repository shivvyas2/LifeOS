/* Deterministic Canvas motion composition. Native app pixels are only framed,
   cropped and animated; no product screen is reconstructed for the film. */
const canvas=document.querySelector('#film'),ctx=canvas.getContext('2d',{alpha:false});
const params=new URLSearchParams(location.search);if(params.has('render'))document.body.classList.add('render');
const clamp=(x,a=0,b=1)=>Math.max(a,Math.min(b,x));
const ease=x=>1-Math.pow(1-clamp(x),3);
const smooth=x=>{x=clamp(x);return x*x*(3-2*x)};
let project,assets={},format='vertical',current=0,playing=false,last=0;
const mediaCache=new Map();
const crop={leaderboard:.12,chat:.12,calendar:.14,coach:.125,notes:0,health:0,today:0,money:0,activity:0,widget:0,watch:0};
function round(x,y,w,h,r,fill,stroke){ctx.beginPath();ctx.roundRect(x,y,w,h,r);if(fill){ctx.fillStyle=fill;ctx.fill()}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=1.5;ctx.stroke()}}
function text(s,x,y,size=36,weight=500,color='#171918',align='left'){ctx.fillStyle=color;ctx.font=`${weight} ${size}px -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif`;ctx.textAlign=align;ctx.textBaseline='top';ctx.fillText(s,x,y);}
function wrap(s,x,y,width,size=30,color='#6b706b',weight=400,lh=1.4){let line='',row=0;ctx.font=`${weight} ${size}px -apple-system,BlinkMacSystemFont,sans-serif`;for(const word of s.split(' ')){const next=line?line+' '+word:word;if(ctx.measureText(next).width>width&&line){text(line,x,y+row*size*lh,size,weight,color);row++;line=word}else line=next}text(line,x,y+row*size*lh,size,weight,color);return(row+1)*size*lh}
function logo(x,y,size,color='#f45b32',phase=1){ctx.save();ctx.translate(x,y);for(let row=0;row<3;row++)for(let col=0;col<3;col++){const f=ease((phase-(row+col)*.07)*2);ctx.beginPath();ctx.arc(col*size*.32,row*size*.32,size*.075*f,0,Math.PI*2);ctx.fillStyle=(row===2&&col===2)?'#171918':color;ctx.fill()}ctx.restore()}
function background(scene,t,w,h){let colors=['#F7F4ED','#EFEAE0'];if(scene.type==='coach')colors=['#102567','#234FD0'];if(scene.type==='health')colors=['#F7F4ED','#E6EDF1'];if(scene.type==='surfaces')colors=['#E8EEF9','#F7F4ED'];if(scene.type==='end')colors=['#F8DFCE','#F7F4ED'];let g=ctx.createLinearGradient(w*.2,0,w*.7,h);g.addColorStop(0,colors[0]);g.addColorStop(1,colors[1]);ctx.fillStyle=g;ctx.fillRect(0,0,w,h);ctx.save();ctx.globalAlpha=.11;for(let i=0;i<3;i++){let r=w*(.3+i*.12);let x=w*(.8+.05*Math.sin(t*.4+i)),y=h*(.2+i*.35);let glow=ctx.createRadialGradient(x,y,0,x,y,r);glow.addColorStop(0,scene.type==='coach'?'#82D8FF':'#FFFFFF');glow.addColorStop(1,'#FFFFFF00');ctx.fillStyle=glow;ctx.fillRect(x-r,y-r,r*2,r*2)}ctx.restore()}
function phone(name,x,y,w,h,angle=0,zoom=1){const im=assets[name];if(!im)return;ctx.save();ctx.translate(x+w/2,y+h/2);ctx.rotate(angle);ctx.scale(zoom,zoom);x=-w/2;y=-h/2;ctx.shadowColor='#20252c26';ctx.shadowBlur=38;ctx.shadowOffsetY=25;round(x-10,y-10,w+20,h+20,58,'#202220');ctx.shadowColor='transparent';round(x-7,y-7,w+14,h+14,55,null,'#8c908b');ctx.save();ctx.beginPath();ctx.roundRect(x,y,w,h,48);ctx.clip();ctx.fillStyle=name.startsWith('coach')?'#0B1548':'#f5f3ed';ctx.fillRect(x,y,w,h);const cy=(crop[name]||0)*im.height;const scale=w/im.width;const available=(im.height-cy)*scale;
if(cy>0){ctx.drawImage(im,0,cy,im.width,im.height-cy,x,y+32,w,available);round(-w*.11,y+8,w*.22,13,9,'#171918');}else ctx.drawImage(im,x,y,w,im.height*scale);
ctx.restore();ctx.restore()}
function card(x,y,w,h,label,value,color,progress=1){ctx.save();ctx.globalAlpha=progress;ctx.translate(0,(1-progress)*30);ctx.shadowColor='#17191810';ctx.shadowBlur=25;ctx.shadowOffsetY=12;round(x,y,w,h,28,color);ctx.shadowColor='transparent';text(label,x+28,y+24,24,500,'#545b54');text(value,x+28,y+61,48,600);ctx.restore()}
function caption(scene,w,h,dark){const size=format==='vertical'?27:26;ctx.save();ctx.globalAlpha=.9;const max=format==='vertical'?840:1640;ctx.font=`400 ${size}px -apple-system,sans-serif`;const s=scene.caption;let lines=[],line='';for(let word of s.split(' ')){if(ctx.measureText(line+' '+word).width>max){lines.push(line);line=word}else line+=(line?' ':'')+word}lines.push(line);const yy=h-(format==='vertical'?183:78)-(lines.length-1)*35;lines.forEach((l,i)=>text(l,w/2,yy+i*35,size,400,dark?'#edf4ff':'#4F554F','center'));text('PRODUCT PREVIEW · ILLUSTRATIVE DATA',w/2,h-(format==='vertical'?91:35),format==='vertical'?18:16,500,dark?'#BCCCED':'#787C76','center');ctx.restore()}
function heading(scene,t,w,h,dark){const v=format==='vertical',x=v?90:140,y=v?210:260,size=v?82:94;const fg=dark?'#F9FAFF':'#171918';ctx.save();const enter=ease(t/0.8);ctx.globalAlpha=enter;ctx.translate(0,(1-enter)*35);text(scene.eyebrow,x,v?150:182,v?24:23,600,dark?'#BCD3FF':'#767E73');scene.title.forEach((line,i)=>text(line,x,y+i*size*1.06,size,600,fg));if(scene.detail)wrap(scene.detail,x,y+scene.title.length*size*1.06+25,v?870:850,v?30:34,dark?'#C5D7FF':'#677064');ctx.restore()}
async function motionFrame(name,t,fps,count){let index=Math.floor(Math.max(0,t)*fps)%count,key=`${name}/${index}`;if(!mediaCache.has(key)){const img=new Image();img.src=`assets/${name}/${String(index+1).padStart(4,'0')}.jpg`;await img.decode();mediaCache.set(key,img);if(mediaCache.size>45)mediaCache.delete(mediaCache.keys().next().value)}return mediaCache.get(key)}
async function sceneDraw(scene,t,w,h){const v=format==='vertical',dark=scene.type==='coach',p=ease(t/.9);background(scene,t,w,h);const fg=dark?'#fff':'#171918';logo(v?92:142,v?73:75,44);text(project.name,v?142:193,v?70:72,29,650,fg);text('A LITTLE MORE TOGETHER',w-(v?90:140),v?78:80,16,500,dark?'#c5d7ff':'#798174','right');
if(scene.type==='scatter'){
const settled=ease((t-2.1)/1.4);const cards=[['Sleep','#E1DAF5'],['Plans','#CCE2D6'],['Money','#FADBB9'],['Movement','#D8E7FC'],['Notes','#F4D4CD'],['Friends','#E0E3C9']];
text(scene.eyebrow,v?90:140,v?265:215,24,600,'#71796D');scene.title.forEach((line,i)=>text(line,v?90:140,(v?335:295)+i*(v?110:130),v?103:122,600));
cards.forEach(([label,color],i)=>{const col=i%2,row=Math.floor(i/2),ww=v?370:340,hh=v?180:150;const baseX=v?110+col*460:1020+col*390,baseY=v?780+row*235:240+row*190;ctx.save();ctx.translate(baseX+ww/2,baseY+hh/2+Math.sin(t*1.3+i)*12*(1-settled));ctx.rotate((i%2?1:-1)*(.09-.07*settled));ctx.globalAlpha=ease((t-i*.1)/.5);round(-ww/2,-hh/2,ww,hh,30,color);logo(-ww/2+30,-hh/2+30,35,'#171918');text(label,-ww/2+30,-hh/2+95,v?38:32,500);ctx.restore()});
}else if(scene.type==='brand'){
heading(scene,t,w,h,false);assets.cat=await motionFrame('cat-frames',t,30,180);crop.cat=.15;
phone('cat',v?245:1180,(v?650:130)+(1-p)*120,v?590:410,v?1000:840,.04*Math.sin(t*.6),1);
if(!v){logo(160,660,130,'#f45b32',t);text(project.name,292,675,84,600)}
}else if(scene.type==='end'){
const x=v?90:140;logo(x,v?460:305,v?125:165,'#f45b32',t);text(project.name,x+(v?128:180),v?462:316,v?124:156,650);text('Bring your day',x,v?655:550,v?82:72,500);text('together.',x,v?748:637,v?82:72,500);round(x,v?908:770,v?510:510,76,20,'#F45B32');text('Follow along for the launch',x+30,v?928:790,30,600,'#fff');
assets.cat=await motionFrame('cat-frames',t+1,30,180);crop.cat=.22;phone('cat',v?584:1280,v?1130:255,v?330:380,v?440:650,.08);
}else if(scene.type==='connections'){
heading(scene,t,w,h,false);let items=[['Apple Health','#CCE2D6'],['WHOOP','#D8E7FC'],['Fitbit','#E1DAF5'],['Plaid','#FADEB9']];items.forEach(([label,color],i)=>{const a=ease((t-i*.18)/.7),x=v?110+(i%2)*450:140+i*420,y=v?830+Math.floor(i/2)*230:630;ctx.save();ctx.globalAlpha=a;ctx.translate(0,50*(1-a));round(x,y,v?410:390,190,30,color);logo(x+30,y+30,44);text(label,x+30,y+104,36,600);ctx.restore()});text('Available sources require setup and permission.',v?110:140,v?1370:865,v?25:27,400,'#687060');
}else{
heading(scene,t,w,h,dark);const baseX=v?260:1230,baseY=v?650:110,ww=v?560:414,hh=v?1060:875;let primary=scene.asset;
if(scene.type==='planning')primary=t<3?'calendar':'notes';
if(scene.type==='social')primary=t<3?'leaderboard':'chat';
if(scene.type==='coach'){assets.coachMotion=await motionFrame('coach-frames',t,30,180);crop.coachMotion=.125;primary='coachMotion';}
const switchP=(scene.type==='social'||scene.type==='planning')?ease((t%3)/.55):p;
phone(primary,baseX+(1-switchP)*(v?85:120),baseY+(1-p)*100+Math.sin(t*.65)*9,ww,hh,Math.sin(t*.45)*.012);
if(scene.type==='health'){
const x=v?90:140,y=v?1270:645;
card(x,y,v?315:280,145,'Steps',Math.round(8240*ease(t/1.2)).toLocaleString('en-US'),'#FADEB9',ease((t-.45)/.6));
card(x+(v?0:305),y+(v?166:0),v?315:280,145,'Sleep','7h 12m','#E1DAF5',ease((t-.7)/.6));
if(!v)text('Apple Health · WHOOP · Fitbit',140,830,28,500,'#697168');
}
if(scene.type==='surfaces'){
const im=assets.watch,x=v?74:910,y=v?1150:610,wi=v?305:285,hi=wi*im.height/im.width;ctx.save();ctx.translate(x,y);ctx.rotate(-.06);ctx.shadowColor='#17191830';ctx.shadowBlur=25;round(-12,-12,wi+24,hi+24,70,'#272b29');ctx.shadowColor='transparent';ctx.beginPath();ctx.roundRect(0,0,wi,hi,58);ctx.clip();ctx.drawImage(im,0,0,wi,hi);ctx.restore();
}
if(scene.type==='phone'&&scene.asset==='activity'&&!v){const im=assets.lock;ctx.save();ctx.beginPath();ctx.roundRect(145,645,765,200,30);ctx.clip();ctx.drawImage(im,im.width*.05,im.height*.641,im.width*.90,im.height*.107,145,645,765,200);ctx.restore();}
}
caption(scene,w,h,dark);
const lineY=h-12;ctx.fillStyle=dark?'#ffffff20':'#17191810';ctx.fillRect(0,lineY,w,12);ctx.fillStyle='#F45B32';ctx.fillRect(0,lineY,w*clamp((scene.start+t)/project.duration),12);
}
window.renderFrame=async function(time,mode='vertical'){format=mode;current=clamp(time,0,59.999);let w=format==='vertical'?1080:1920,h=format==='vertical'?1920:1080;if(canvas.width!==w){canvas.width=w;canvas.height=h}const scene=project.scenes.find(s=>current>=s.start&&current<s.end)||project.scenes.at(-1);await sceneDraw(scene,current-scene.start,w,h);return true;};
window.ready=(async()=>{project=await(await fetch('source/project.json')).json();await Promise.all(['health','calendar','leaderboard','chat','activity','widget','watch','lock','coach','today','money','notes'].map(async n=>{let im=new Image();im.src='assets/'+n+'.png';await im.decode();assets[n]=im}));await renderFrame(0);})();
const audio=new Audio('assets/dayvilo-original-score.wav');
document.querySelector('#format').onchange=async e=>{await renderFrame(current,e.target.value)};
document.querySelector('#seek').oninput=async e=>{current=+e.target.value;audio.currentTime=current;await renderFrame(current,format)};
document.querySelector('#play').onclick=()=>{playing=!playing;document.querySelector('#play').textContent=playing?'Pause':'Play';if(playing){if(current>=59.8)current=0;audio.currentTime=current;audio.play();last=performance.now();requestAnimationFrame(tick)}else audio.pause()};
async function tick(now){if(!playing)return;current+=(now-last)/1000;last=now;if(current>=60){playing=false;audio.pause();document.querySelector('#play').textContent='Replay';return}await renderFrame(current,format);document.querySelector('#seek').value=current;document.querySelector('#time').textContent=`0:${Math.floor(current).toString().padStart(2,'0')}`;requestAnimationFrame(tick)}
