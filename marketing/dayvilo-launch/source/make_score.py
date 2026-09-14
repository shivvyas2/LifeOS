"""Original 60-second instrumental; synthesized locally, no samples or licensed tracks."""
import numpy as np
import wave
from pathlib import Path
SR=48000
DURATION=60
rng=np.random.default_rng(20260914)
out=np.zeros((SR*DURATION,2),dtype=np.float32)
def add(signal,start,level=.1,pan=0):
    a=int(start*SR); n=min(len(signal),len(out)-a)
    if a<0 or n<=0:return
    out[a:a+n,0]+=signal[:n]*level*np.sqrt((1-pan)/2)
    out[a:a+n,1]+=signal[:n]*level*np.sqrt((1+pan)/2)
def note(midi,duration,kind='pluck'):
    t=np.arange(int(SR*duration))/SR;f=440*2**((midi-69)/12)
    if kind=='pad':
        env=np.minimum(t/.65,1)*np.minimum((duration-t)/1.6,1)
        return (np.sin(2*np.pi*f*t)+.22*np.sin(2*np.pi*f*2.001*t)+.08*np.sin(2*np.pi*f*3*t))*env
    env=(1-np.exp(-t*100))*np.exp(-t*3.7)
    return (np.sin(2*np.pi*f*t)+.35*np.sin(2*np.pi*f*2*t)*np.exp(-t*5)+.13*np.sin(2*np.pi*f*3*t)*np.exp(-t*8))*env
beat=60/96
chords=[[48,55,59,62,64],[45,52,55,59,60],[41,48,52,55,57],[43,50,55,57,62],[48,55,59,62,64],[48,55,60,62,64]]
for phrase,chord in enumerate(chords):
    start=phrase*10
    for j,m in enumerate(chord):add(note(m+12,11,'pad'),start,.031,(j-2)*.28)
    for b in range(16):
        time=start+b*beat
        if time<56:
            m=chord[[0,2,3,1,4,2,1,3][b%8]]+24
            add(note(m,1.8),time,.10,(-1 if b%2 else 1)*.25)
            add(note(m,1.3),time+beat*.75,.028,.4)
        if b%4==0:
            add(note(chord[0]-12,2.3),time,.16)
for b in range(6,89):
    time=b*beat
    if b%2==0:
        t=np.arange(int(.24*SR))/SR
        kick=np.sin(2*np.pi*(48*t+2.8*(1-np.exp(-t*30))))*np.exp(-t*21)*(1-np.exp(-t*200))
        add(kick,time,.19)
    if b%4==2:
        t=np.arange(int(.12*SR))/SR;noise=rng.normal(size=len(t));noise=noise-np.convolve(noise,np.ones(8)/8,'same')
        add(noise*np.exp(-t*45),time,.035)
    t=np.arange(int(.05*SR))/SR;noise=rng.normal(size=len(t));noise=noise-np.convolve(noise,np.ones(3)/3,'same')
    add(noise*np.exp(-t*95),time+beat*.5,.016,(-1 if b%2 else 1)*.6)
# A soft resolving chime on the brand reveal.
for i,m in enumerate([72,76,79,83]):add(note(m,3.8),56+i*.12,.075,(i-1.5)*.25)
t=np.arange(len(out))/SR
fade=np.minimum(t/1.2,1)*np.minimum((DURATION-t)/2.8,1)
out=np.tanh(out*1.6)*fade[:,None]
out*=.82/max(np.max(np.abs(out)),1e-6)
path=Path(__file__).resolve().parents[1]/'assets/dayvilo-original-score.wav'
with wave.open(str(path),'wb') as f:
    f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR);f.writeframes((out*32767).astype('<i2').tobytes())
print(path)
