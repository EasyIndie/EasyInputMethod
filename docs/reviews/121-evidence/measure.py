import subprocess,json,tempfile,hashlib,os
from pathlib import Path
root=Path.cwd(); out=root/'docs/reviews/121-evidence'
with tempfile.TemporaryDirectory(prefix='lampyris-121-') as d:
 p=Path(d);os.environ['CLANG_MODULE_CACHE_PATH']=str(p/'module-cache'); baseline=p/'baseline.swift';baseline.write_bytes(subprocess.check_output(['git','show','01fb016:platforms/macos/Sources/CandidateWindow.swift']))
 original=(root/'docs/reviews/112-evidence/phase.swift').read_text()
 original=original.replace('for code in ["w", "wq", "ni", "nih", "niha", "nihao"] {','for (step, code) in ["w", "wq", "ni", "nih", "niha", "nihao"].enumerated() {')
 original=original.replace('window.updateStatus(status)','window.updateStatus(step % 2 == 0 ? status : CandidateStatus(mode: "wubi", english: false, fullWidth: false, traditional: false, chinesePunctuation: true)BATCH)')
 original=original.replace('"samples":600,','"samples":600,"first_ms":stages.map { $0[0] },"sum_p95_ms":zip(stages[0],stages[1]).map(+).sorted()[569],')
 runs=[];sha={'ffi':hashlib.sha256((root/'target/release/libime_ffi.a').read_bytes()).hexdigest()}
 for label,candidate,batch in [('baseline',baseline,''),('candidate',root/'platforms/macos/Sources/CandidateWindow.swift',', relayout: false')]:
  probe=p/f'{label}-probe.swift';probe.write_text(original.replace('BATCH',batch));exe=p/label
  cmd=['swiftc','-O','-warnings-as-errors','-I',str(root/'crates/ime-ffi/include'),str(probe),*[str(root/'platforms/macos/Sources'/s) for s in ['ImeSession.swift','Config.swift']],str(candidate),str(root/'target/release/libime_ffi.a'),'-framework','AppKit','-o',str(exe)]
  subprocess.run(cmd,check=True);sha[label+'_source']=hashlib.sha256(candidate.read_bytes()).hexdigest();sha[label+'_exe']=hashlib.sha256(exe.read_bytes()).hexdigest();sha[label+'_probe']=hashlib.sha256(probe.read_bytes()).hexdigest()
 for i in range(3):
  for label in ['baseline','candidate']:
   cfg=p/f'{label}-{i}.toml';cfg.write_text('mode = "mixed"\n')
   result=subprocess.run([str(p/label),str(cfg)],check=True,capture_output=True,text=True)
   (out/f'{label}-{i}.json').write_text(result.stdout);(out/f'{label}-{i}.stderr.txt').write_text(result.stderr)
   runs.append({'variant':label,'round':i,**json.loads(result.stdout)})
 (out/'summary.json').write_text(json.dumps({'baseline_commit':'01fb0164d1b52cc22e4a34a69054a71abbd45631','scope':'真实表离屏，交替mixed/wubi状态刷新后同输入候选/定位；不显示窗口、不发按键；非120原生对照','probe_base':'docs/reviews/112-evidence/phase.swift','probe_changes':'enumerated输入；step奇数wubi状态；candidate调用增加relayout:false；保留各阶段首值与status+content逐样本合计P95（索引569）','sha256':sha,'runs':runs},ensure_ascii=False,indent=2)+'\n')
 print([(r['variant'],r['round'],r['sum_p95_ms'],r['first_ms']) for r in runs])
