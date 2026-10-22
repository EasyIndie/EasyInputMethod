from pathlib import Path
import subprocess,tempfile,json,hashlib,math
root=Path.cwd();out=root/'docs/reviews/131-evidence'
probe=(root/'docs/reviews/112-evidence/phase.swift').read_text().replace('     let d = DispatchTime.now().uptimeNanoseconds','     let d = DispatchTime.now().uptimeNanoseconds\n     window.hide()')
(out/'phase.swift').write_text(probe)
sources={'baseline':subprocess.check_output(['git','show','18fcbbf:platforms/macos/Sources/CandidateWindow.swift'],text=True),'candidate':(root/'platforms/macos/Sources/CandidateWindow.swift').read_text()}
runs=[]
with tempfile.TemporaryDirectory(prefix='lampyris-131-pair-') as d:
 p=Path(d);(p/'probe.swift').write_text(probe)
 for label,s in sources.items():
  call='update(candidates: [])' if label=='baseline' else 'update(candidates: [], relayout: false)'
  old='        panel.orderOut(nil)\n        '+call
  new='''        let a = DispatchTime.now().uptimeNanoseconds
        panel.orderOut(nil)
        let b = DispatchTime.now().uptimeNanoseconds
        CALL
        let c = DispatchTime.now().uptimeNanoseconds
        print("HIDE \\(Double(b-a)/1e6) \\(Double(c-b)/1e6)")'''.replace('CALL',call)
  assert s.count(old)==1
  (p/(label+'.swift')).write_text(s.replace(old,new))
  subprocess.run(['swiftc','-O','-warnings-as-errors','-module-cache-path',str(p/'cache'),'-I',str(root/'crates/ime-ffi/include'),str(p/'probe.swift'),str(p/(label+'.swift')),str(root/'platforms/macos/Sources/ImeSession.swift'),str(root/'platforms/macos/Sources/Config.swift'),str(root/'target/release/libime_ffi.a'),'-framework','AppKit','-o',str(p/label)],check=True)
 for i in range(3):
  for label in ['baseline','candidate']:
   cfg=p/f'{label}-{i}.toml';cfg.write_text('mode="mixed"\n')
   r=subprocess.run([str(p/label),str(cfg)],check=True,capture_output=True,text=True);(out/f'paired-{label}-{i}.txt').write_text(r.stdout);(out/f'paired-{label}-{i}.stderr.txt').write_text(r.stderr)
   rows=[list(map(float,l.split()[1:])) for l in r.stdout.splitlines() if l.startswith('HIDE ')]
   def stats(v):
    s=sorted(v);return {'p95_ms':s[math.ceil(len(s)*.95)-1],'max_ms':max(s)}
   item={'variant':label,'round':i,'samples':len(rows),'orderOut':stats([r[0] for r in rows]),'clear':stats([r[1] for r in rows]),'total_hide':stats([sum(r) for r in rows])};runs.append(item);print(item)
 (out/'paired-summary.json').write_text(json.dumps({'baseline_commit':'18fcbbfdc64147eed557b1783d665e1314198f69','scope':'offscreen real tables, 600 hide samples per run, no IMK dispatch/client/orderOut of visible panel','source_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in sources.items()},'runs':runs},indent=2)+'\n')
