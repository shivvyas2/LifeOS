"""A 15-second cutdown from the approved local full-film render."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
# Hook, health, coach, friends, and the brand close. All cuts land on full frames.
parts=[(1,3.5),(13.5,16.5),(30.5,33.5),(36.5,39),(56,60)]
filters=[]
for i,(start,end) in enumerate(parts):filters.append(f'[0:v]trim=start={start}:end={end},setpts=PTS-STARTPTS[v{i}]')
filters.append(''.join(f'[v{i}]' for i in range(len(parts)))+'concat=n=5:v=1:a=0[v]')
filters.append('[1:a]atrim=start=45:end=60,asetpts=PTS-STARTPTS,afade=t=in:d=0.5,afade=t=out:st=13:d=2,loudnorm=I=-18:TP=-1.5:LRA=8[a]')
subprocess.run(['ffmpeg','-y','-v','warning','-threads','2','-i',str(root/'exports/dayvilo-launch-9x16.mp4'),'-i',str(root/'assets/dayvilo-original-score.wav'),'-filter_complex_threads','2','-filter_complex',';'.join(filters),'-map','[v]','-map','[a]','-r','30','-c:v','libx264','-preset','fast','-crf','18','-threads','2','-color_range','tv','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-ar','48000','-t','15','-movflags','+faststart',str(root/'exports/dayvilo-teaser-9x16.mp4')],check=True)
