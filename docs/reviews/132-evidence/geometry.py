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
s=s.replace('panel.setContentSize(NSSize(width: width, height: total))', 'let proposed = NSSize(width: width, height: total)\n        print("SIZE \(panel.contentView?.bounds.size == proposed ? "same" : "changed") \(panel.contentView?.bounds.size ?? .zero) \(proposed)")\n        panel.setContentSize(proposed)')
probe=(root/'docs/reviews/131-evidence/phase.swift').read_text().replace('.prohibited)', '.accessory); app.finishLaunching()')
probe=probe.replace('0..<100','0..<10').replace('window.updateStatus(status)','window.updateStatus(status, relayout: false)')
probe=probe.replace('     window.hide()','     window.show(at: caret)\n     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))\n     window.hide()\n     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))')
probe=probe.replace('"samples":600,','"samples":60,"first_ms":stages.map { $0[0] },')
(out/'phase.swift').write_text(probe)
with tempfile.TemporaryDirectory(prefix='lampyris-132-') as d:
 p=Path(d);(p/'Candidate.swift').write_text(s);(p/'probe.swift').write_text(probe)
 subprocess.run(['swiftc','-O','-warnings-as-errors','-module-cache-path',str(p/'cache'),'-I',str(root/'crates/ime-ffi/include'),str(p/'probe.swift'),str(p/'Candidate.swift'),str(root/'platforms/macos/Sources/ImeSession.swift'),str(root/'platforms/macos/Sources/Config.swift'),str(root/'target/release/libime_ffi.a'),'-framework','AppKit','-o',str(p/'probe')],check=True)
 for i in range(1):
  cfg=p/f'config-{i}.toml';cfg.write_text('mode="mixed"\n')
  r=subprocess.run([str(p/'probe'),str(cfg)],check=True,capture_output=True,text=True);(out/f'geometry-{i}.txt').write_text(r.stdout);(out/f'geometry-{i}.stderr.txt').write_text(r.stderr)
  hide=[list(map(float,l.split()[1:])) for l in r.stdout.splitlines() if l.startswith('HIDE ')]
  print(i,[l for l in r.stdout.splitlines() if l.startswith('STRIP ')],[(sorted(v)[56],max(v)) for v in zip(*hide)],r.stdout.splitlines()[-1])
