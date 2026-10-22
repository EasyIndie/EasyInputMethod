from pathlib import Path
import subprocess,tempfile,json,hashlib
root=Path.cwd();out=root/'docs/reviews/132-evidence'
s=(root/'platforms/macos/Sources/CandidateWindow.swift').read_text()
s=s.replace('''        panel.orderOut(nil)
        update(candidates: [], relayout: false)''','''        let a = DispatchTime.now().uptimeNanoseconds
        panel.orderOut(nil)
        let b = DispatchTime.now().uptimeNanoseconds
        update(candidates: [], relayout: false)
        let c = DispatchTime.now().uptimeNanoseconds
        print("HIDE \\(Double(b-a)/1e6) \\(Double(c-b)/1e6)")''')
s=s.replace('''    func update(_ status: CandidateStatus) {
        chips''','''    func update(_ status: CandidateStatus) {
        let a = DispatchTime.now().uptimeNanoseconds
        chips''')
s=s.replace('''        layoutChips()
    }

    var preferredWidth''','''        let b = DispatchTime.now().uptimeNanoseconds
        layoutChips()
        let c = DispatchTime.now().uptimeNanoseconds
        print("STRIP \\(Double(b-a)/1e6) \\(Double(c-b)/1e6)")
    }

    var preferredWidth''')
probe=(root/'docs/reviews/131-evidence/phase.swift').read_text().replace('.prohibited)', '.accessory); app.finishLaunching()')
probe=probe.replace('0..<100','0..<10').replace('window.updateStatus(status)','window.updateStatus(status, relayout: false)')
probe=probe.replace('     window.hide()','     window.show(at: caret)\n     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))\n     window.hide()\n     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))')
probe=probe.replace('"samples":600,','"samples":60,"first_ms":stages.map { $0[0] },')
(out/'phase.swift').write_text(probe)
with tempfile.TemporaryDirectory(prefix='lampyris-132-') as d:
 p=Path(d);(p/'Candidate.swift').write_text(s);(p/'probe.swift').write_text(probe)
 subprocess.run(['swiftc','-O','-warnings-as-errors','-module-cache-path',str(p/'cache'),'-I',str(root/'crates/ime-ffi/include'),str(p/'probe.swift'),str(p/'Candidate.swift'),str(root/'platforms/macos/Sources/ImeSession.swift'),str(root/'platforms/macos/Sources/Config.swift'),str(root/'target/release/libime_ffi.a'),'-framework','AppKit','-o',str(p/'probe')],check=True)
 sources={'default':s,'guarded':s.replace('panel.setContentSize(NSSize(width: width, height: total))','let contentSize = NSSize(width: width, height: total)\n        if panel.contentView?.bounds.size != contentSize { panel.setContentSize(contentSize) }')}
 for label,text in sources.items():
  (p/'Candidate.swift').write_text(text)
  subprocess.run(['swiftc','-O','-warnings-as-errors','-module-cache-path',str(p/'cache'),'-I',str(root/'crates/ime-ffi/include'),str(p/'probe.swift'),str(p/'Candidate.swift'),str(root/'platforms/macos/Sources/ImeSession.swift'),str(root/'platforms/macos/Sources/Config.swift'),str(root/'target/release/libime_ffi.a'),'-framework','AppKit','-o',str(p/label)],check=True)
 import math
 summary=[]
 for i in range(3):
  for label in (['default','guarded'] if i % 2 == 0 else ['guarded','default']):
   cfg=p/f'{label}-{i}.toml';cfg.write_text('mode="mixed"\n')
   r=subprocess.run([str(p/label),str(cfg)],check=True,capture_output=True,text=True);(out/f'resize-{label}-{i}.txt').write_text(r.stdout);(out/f'resize-{label}-{i}.stderr.txt').write_text(r.stderr)
   rows=[list(map(float,l.split()[1:])) for l in r.stdout.splitlines() if l.startswith('HIDE ')]
   def stats(v):
    a=sorted(v);return {'p95_ms':a[math.ceil(.95*len(a))-1],'max_ms':max(a),'first_ms':v[0]}
   item={'variant':label,'round':i,'samples':len(rows),'orderOut':stats([r[0] for r in rows]),'clear':stats([r[1] for r in rows]),'hide':stats([sum(r) for r in rows]),'layout':json.loads(r.stdout.splitlines()[-1])};summary.append(item);print(item,flush=True)
 (out/'resize-summary.json').write_text(json.dumps({'scope':'visible nonactivating temporary panel; fresh process each run; not IMK/client dispatch','source_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in sources.items()},'runs':summary},indent=2)+'\n')
