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
probe=probe.replace('0..<100','0..<100').replace('window.updateStatus(status)','window.updateStatus(status, relayout: false)')
probe=probe.replace('     window.hide()','     window.show(at: caret)\n     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))\n     window.hide()\n     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))')
probe=probe.replace('"samples":600,','"samples":60,"first_ms":stages.map { $0[0] },')
(out/'phase.swift').write_text(probe)
with tempfile.TemporaryDirectory(prefix='lampyris-132-') as d:
 p=Path(d);(p/'Candidate.swift').write_text(s);(p/'probe.swift').write_text(probe)
 subprocess.run(['swiftc','-O','-warnings-as-errors','-module-cache-path',str(p/'cache'),'-I',str(root/'crates/ime-ffi/include'),str(p/'probe.swift'),str(p/'Candidate.swift'),str(root/'platforms/macos/Sources/ImeSession.swift'),str(root/'platforms/macos/Sources/Config.swift'),str(root/'target/release/libime_ffi.a'),'-framework','AppKit','-o',str(p/'probe')],check=True)
 import time
 cfg=p/'config.toml';cfg.write_text('mode="mixed"\n')
 with (out/'profile-run.txt').open('w') as stream, (out/'profile-run.stderr.txt').open('w') as errors:
  child=subprocess.Popen([str(p/'probe'),str(cfg)],stdout=stream,stderr=errors)
  try:
   time.sleep(1)
   assert child.poll() is None
   sampled=subprocess.run(['/usr/bin/sample',str(child.pid),'5','1','-file',str(out/'visible-sample.txt')],capture_output=True,text=True,timeout=15)
   (out/'sample-command.txt').write_text(sampled.stdout+sampled.stderr)
   assert sampled.returncode==0
   assert child.wait(timeout=90)==0
  finally:
   if child.poll() is None:child.terminate();child.wait(timeout=5)
 print('profile captured for exact owned child process')
