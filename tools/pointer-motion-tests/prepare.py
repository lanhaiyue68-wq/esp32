"""Build a Foundation-only harness around the production fit, map and motion code.

The protocol/error shim stands in for the Bluetooth transport, which needs iOS.
The actual command selection, ordering, waits, interpolation and failure handling
come verbatim from production; this is not a second implementation of the policy.
"""
from pathlib import Path
import shutil
import sys

repo = Path(__file__).resolve().parents[2]
target = Path(sys.argv[1]).resolve()
(target / 'Sources').mkdir(parents=True, exist_ok=True)
(target / 'Tests').mkdir(exist_ok=True)
source = (repo / 'ios/IPhoneAgent/Agent/ProbeMap.swift').read_text(encoding='utf-8')
motion = source[source.index('struct ProbeMap'):]
fit_source = (repo / 'ios/IPhoneAgent/Agent/ProbeFit.swift').read_text(encoding='utf-8')
fit = fit_source[fit_source.index('enum ProbeFit'):fit_source.index("/// This device's screen")]
shim = '''import Foundation
@MainActor protocol HIDDevice: AnyObject {
    @discardableResult func send(_ command: String) async throws -> String
}
struct DeviceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
'''
(target / 'Sources/Motion.swift').write_text(shim + fit + motion, encoding='utf-8')
shutil.copyfile(Path(__file__).with_name('Package.swift'), target / 'Package.swift')
shutil.copyfile(Path(__file__).with_name('main.swift'), target / 'Tests/PointerMotionTests.swift')
