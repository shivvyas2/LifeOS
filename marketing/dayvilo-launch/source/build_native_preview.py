from pathlib import Path
import subprocess, os
app=Path('LIfeOS/App/LIfeOSApp.swift')
project=Path('LIfeOS.xcodeproj/project.pbxproj')
a=app.read_text(); p=project.read_text()
try:
    app.write_text(a.replace('if let container = session.container {', 'if true { LaunchFilmPreview() } else if let container = session.container {',1))
    subprocess.run(['ruby','-e', '''require 'xcodeproj'; p=Xcodeproj::Project.open('LIfeOS.xcodeproj'); t=p.targets.find{|x|x.name=='LIfeOS'}; g=p.main_group.children.find{|x|x.display_name=='AlmanacWidgets'}; f=g.children.find{|x|x.display_name=='HealthWidget.swift'}; t.source_build_phase.add_file_reference(f); t.build_configurations.each{|c|c.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=['$(inherited)','DEBUG','LAUNCH_FILM_PREVIEW']}; p.save'''], check=True)
    env=os.environ.copy(); env['DEVELOPER_DIR']='/Users/shivvyas/Applications/Xcode.app/Contents/Developer'
    with open('/private/tmp/lifeos-launch-preview-build.log','w') as log:
        subprocess.run(['xcodebuild','-project','LIfeOS.xcodeproj','-scheme','LIfeOS','-configuration','Debug','-destination','id=0057B788-D450-4897-BA43-7B22DC08381D','-derivedDataPath','/private/tmp/lifeos-onboarding-build','CODE_SIGN_IDENTITY=-','-jobs','2','build'],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run(['ditto','/private/tmp/lifeos-onboarding-build/Build/Products/Debug-iphonesimulator/LIfeOS.app','/private/tmp/lifeos-launch-preview.app'], check=True)
finally:
    app.write_text(a); project.write_text(p)
