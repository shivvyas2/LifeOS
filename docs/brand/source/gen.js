// Faithful vector rebuild of the Almanac icon stack, 1024 box. Exports: icon tile, transparent stack, mono stack, wordmark, lockups.
const fs=require('fs'),path=require('path'),opentype=require('opentype.js');
const OUT=path.join(__dirname,'..'); fs.mkdirSync(OUT,{recursive:true});
const FONT=opentype.loadSync(path.join(__dirname,'fonts/InterDisplay-SemiBold.ttf'));
const r2=n=>Math.round(n*100)/100;
const SQ=(()=>{const n=5,a=512,pts=[];for(let i=0;i<=360;i++){const t=i*Math.PI/180,c=Math.cos(t),si=Math.sin(t);pts.push(`${r2(a+a*Math.sign(c)*Math.pow(Math.abs(c),2/n))} ${r2(a+a*Math.sign(si)*Math.pow(Math.abs(si),2/n))}`);}return 'M'+pts.join('L')+'Z';})();
const INK='#141210', CREAM='#fbf5ee', ORANGE='#f45b2e';

// One leaf: a rounded square rotated 45deg and squashed to the icon's isometric ratio, centred at (512, cy).
// Square side 520 with radius 150 gives a diamond ~715 wide and ~380 tall at scale 0.53.
function leaf(cy, fill, stroke, strokeW=6, opacity=1){
  return `<g transform="translate(512 ${r2(cy)}) scale(1 0.53) rotate(45)" opacity="${opacity}"><rect x="-300" y="-300" width="600" height="600" rx="165" fill="${fill}" stroke="${stroke}" stroke-width="${strokeW}"/></g>`;
}
function stackDefs(id){ return `
  <linearGradient id="${id}mid" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e2453b"/><stop offset="1" stop-color="#b8161c"/></linearGradient>
  <linearGradient id="${id}top" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.5"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.22"/></linearGradient>
  <radialGradient id="${id}orb" cx="0.32" cy="0.3" r="0.9"><stop offset="0" stop-color="#8a3a45"/><stop offset="0.45" stop-color="#5a0f22"/><stop offset="1" stop-color="#3f0716"/></radialGradient>`; }
// Full colour stack. Leaves from back to front: plum, red, glass. Orb ring cream with a small crescent ring tucked behind at top right.
function stack(mono=false, id='s'){
  const yTop=350, yMid=452, yBot=554;
  if(mono) return `<g fill="currentColor">${leaf(yBot,'currentColor','none',0,0.35)}${leaf(yMid,'currentColor','none',0,0.6)}${leaf(yTop,'currentColor','none',0,1)}</g>`+
    `<circle cx="600" cy="305" r="42" fill="none" stroke="${CREAM}" stroke-width="10"/>`+
    `<ellipse cx="512" cy="350" rx="108" ry="58" fill="currentColor" stroke="${CREAM}" stroke-width="12"/><ellipse cx="512" cy="350" rx="86" ry="42" fill="${CREAM}"/><ellipse cx="512" cy="350" rx="70" ry="32" fill="currentColor"/>`;
  return `<defs>${stackDefs(id)}</defs>`+
    leaf(yBot,'#640820','#8a2a3a',6)+
    leaf(yMid,`url(#${id}mid)`,'#f28a80',6)+
    leaf(yTop,`url(#${id}top)`,'rgba(255,255,255,0.75)',5)+
    `<circle cx="604" cy="298" r="46" fill="none" stroke="#fff0d8" stroke-width="12"/>`+
    `<ellipse cx="512" cy="350" rx="122" ry="66" fill="#fff0d8"/>`+
    `<ellipse cx="512" cy="350" rx="110" ry="55" fill="#b8302c"/>`+
    `<ellipse cx="512" cy="350" rx="102" ry="49" fill="url(#${id}orb)"/>`+
    `<ellipse cx="468" cy="334" rx="28" ry="15" fill="#8a3a45" opacity="0.9"/>`;
}
function tileDefs(){ return `
  <linearGradient id="bgL" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffd23f"/><stop offset="0.35" stop-color="#ff6a10"/><stop offset="0.7" stop-color="#e93905"/><stop offset="1" stop-color="#b04d14"/></linearGradient>
  <radialGradient id="bgR" cx="0.15" cy="0.05" r="0.7"><stop offset="0" stop-color="#ffe45a" stop-opacity="0.9"/><stop offset="1" stop-color="#ffe45a" stop-opacity="0"/></radialGradient>
  <radialGradient id="bgG" cx="0.85" cy="0.9" r="0.5"><stop offset="0" stop-color="#ff9a3a" stop-opacity="0.55"/><stop offset="1" stop-color="#ff9a3a" stop-opacity="0"/></radialGradient>
  <clipPath id="squircle"><path d="${SQ}"/></clipPath>`; }
const svg=(body,w=1024,h=1024,extra='')=>`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}"${extra}>${body}</svg>`;
const bgRects=`<rect width="1024" height="1024" fill="url(#bgL)"/><rect width="1024" height="1024" fill="url(#bgR)"/><rect width="1024" height="1024" fill="url(#bgG)"/>`;
// icon: full-bleed square (what Xcode wants) and a rounded squircle tile (what the web wants)
fs.writeFileSync(path.join(OUT,'almanac-icon-square.svg'), svg(`<defs>${tileDefs()}</defs>${bgRects}${stack(false,'i')}`));
fs.writeFileSync(path.join(OUT,'almanac-icon.svg'), svg(`<defs>${tileDefs()}</defs><g clip-path="url(#squircle)">${bgRects}${stack(false,'i')}</g>`));
// transparent stack: crop to the stack's bounds (155..870 x 165..735) with padding, keep a square box so it centres well
fs.writeFileSync(path.join(OUT,'almanac-mark.svg'), svg(`<g transform="translate(0 62)">${stack(false,'m')}</g>`,1024,1024));
fs.writeFileSync(path.join(OUT,'almanac-mark-mono.svg'), svg(`<g transform="translate(0 62)">${stack(true,'mm')}</g>`,1024,1024,` color="${INK}"`));

// wordmark
const W=(()=>{const p=FONT.getPath('Almanac',0,0,120,{kerning:true,letterSpacing:-0.03});const b=p.getBoundingBox();return{d:p.toPathData(2),b,w:b.x2-b.x1,h:b.y2-b.y1};})();
const word=(color,tx,ty)=>`<path transform="translate(${r2(tx-W.b.x1)} ${r2(ty-W.b.y1)})" d="${W.d}" fill="${color}"/>`;
const wordmark=(c)=>{const pad=24;return svg(word(c,pad,pad),r2(W.w+pad*2),r2(W.h+pad*2));};
fs.writeFileSync(path.join(OUT,'almanac-wordmark-ink.svg'),wordmark(INK));
fs.writeFileSync(path.join(OUT,'almanac-wordmark-cream.svg'),wordmark(CREAM));
fs.writeFileSync(path.join(OUT,'almanac-wordmark-orange.svg'),wordmark(ORANGE));
// lockups: tile + word (horizontal), tile above word (stacked); ink and cream text
function lockupH(c){const th=W.h*1.6,gap=W.h*0.42,pad=24,w=th+gap+W.w+pad*2,h=th+pad*2;
  return svg(`<defs>${tileDefs()}</defs><g transform="translate(${pad} ${pad}) scale(${r2(th/1024)})"><g clip-path="url(#squircle)">${bgRects}${stack(false,'l')}</g></g>${word(c,pad+th+gap,pad+(th-W.h)/2)}`,r2(w),r2(h));}
function lockupV(c){const th=W.h*3.2,gap=W.h*0.7,pad=32,w=Math.max(th,W.w)+pad*2,h=th+gap+W.h+pad*2;
  return svg(`<defs>${tileDefs()}</defs><g transform="translate(${r2((w-th)/2)} ${pad}) scale(${r2(th/1024)})"><g clip-path="url(#squircle)">${bgRects}${stack(false,'l')}</g></g>${word(c,(w-W.w)/2,pad+th+gap)}`,r2(w),r2(h));}
fs.writeFileSync(path.join(OUT,'almanac-lockup-horizontal-ink.svg'),lockupH(INK));
fs.writeFileSync(path.join(OUT,'almanac-lockup-horizontal-cream.svg'),lockupH(CREAM));
fs.writeFileSync(path.join(OUT,'almanac-lockup-stacked-ink.svg'),lockupV(INK));
fs.writeFileSync(path.join(OUT,'almanac-lockup-stacked-cream.svg'),lockupV(CREAM));
console.log(fs.readdirSync(OUT).join(' '));
