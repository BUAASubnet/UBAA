from pathlib import Path
import time,subprocess,re,json,datetime
signal=Path('/tmp/ubaa-e3c-macos-checkpoint-path').read_text()
marker=Path(signal)/'pending'
out=Path('/tmp/ubaa-ui-ux-20260908/old-e3c-native-macos-checkpoints');out.mkdir(exist_ok=False)
script='/Users/moorefoss/.codex/skills/screenshot/scripts/take_screenshot.py'
limit=time.monotonic()+240; names=[]
while len(names)<5 and time.monotonic()<limit:
 if not marker.exists():time.sleep(.1);continue
 name=marker.read_text().strip()
 if not re.fullmatch(r'dark-normal-[a-z-]+',name):raise RuntimeError('不是本批合成检查点')
 if name in names:raise RuntimeError('拒绝覆盖检查点')
 rows=subprocess.check_output(['python3',script,'--list-windows','--app','ubaa_flutter'],text=True).splitlines()
 windows=[]
 for row in rows:
  fields=row.split('\t');match=re.match(r'(\d+)x(\d+)',fields[-1])
  if len(fields)==4 and fields[2]=='ubaa_flutter' and match:
   w,h=map(int,match.groups());windows.append((w*h,fields[0],w,h))
 if not windows:raise RuntimeError('没有可截图的原生主窗')
 _,wid,w,h=max(windows)
 subprocess.run(['python3',script,'--window-id',wid,'--path',str(out/(name+'.png'))],check=True,stdout=subprocess.DEVNULL)
 (out/(name+'.json')).write_text(json.dumps({'name':name,'backend':'synthetic-schedule-navigation','platform':'macos','sourceSha':'2610d316+E3c-r3-window','windowId':int(wid),'windowLogicalSize':[w,h],'viewportSource':'native-window-unmodified','captureMethod':'Flutter原生测试检查点与OS只读截窗，非独立CUA鼠标','dateUtc':datetime.datetime.now(datetime.timezone.utc).isoformat()},ensure_ascii=False,indent=2))
 names.append(name);marker.unlink();print('已截取 '+name,flush=True)
if len(names)!=5:raise RuntimeError('检查点未完整完成')
(out/'manifest.json').write_text(json.dumps({'savedScreenshots':names,'acceptance':'需要原生测试退出0及逐图复核'},ensure_ascii=False,indent=2))
