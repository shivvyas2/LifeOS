"""Check the deliverable codecs, dimensions, duration, frames and complete decode."""
import json, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
report=[]
for name,w,h,duration in [('dayvilo-launch-9x16.mp4',1080,1920,60),('dayvilo-launch-16x9.mp4',1920,1080,60),('dayvilo-teaser-9x16.mp4',1080,1920,15)]:
    file=root/'exports'/name
    info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(file)]))
    video=next(s for s in info['streams'] if s['codec_type']=='video')
    audio=next(s for s in info['streams'] if s['codec_type']=='audio')
    assert (video['width'],video['height'])==(w,h)
    assert video['codec_name']=='h264' and video['pix_fmt']=='yuv420p'
    assert video['avg_frame_rate']=='30/1'
    assert audio['codec_name']=='aac' and audio['channels']==2 and audio['sample_rate']=='48000'
    assert abs(float(info['format']['duration'])-duration)<.1
    assert int(video['nb_frames'])==duration*30
    subprocess.run(['ffmpeg','-v','error','-xerror','-threads','2','-i',str(file),'-f','null','-'],check=True)
    report.append({'file':name,'dimensions':[w,h],'duration':float(info['format']['duration']),'frames':int(video['nb_frames']),'bytes':file.stat().st_size,'decode':'pass','codecs':['h264','aac']})
(root/'exports/verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
