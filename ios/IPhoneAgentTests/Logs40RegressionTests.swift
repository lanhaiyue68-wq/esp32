import XCTest
@testable import IPhoneAgent

@MainActor final class Logs40RegressionTests: XCTestCase {
    func testBuild79StraightParametersNeedRemeasurementWhenRestoringBezier() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"w":300,"h":650,"quality":0.01,"stale":false,"motionVersion":2}"#.utf8).write(to: file)
        let pointer = Pointer(device: FakeDevice(), calibrationFile: file)
        XCTAssertTrue(pointer.stale)
    }

    func testReducedSamplingStillCoversEachFreshValidationLocation() throws {
        // A stable nonlinear response (not a simulation of random iOS motion). Build the candidate using
        // the real probe plan, then independently check the requested positions.
        func x(_ units: Double) -> Double { units / 300 + 0.03 * pow(units / 300, 2) }
        func y(_ units: Double) -> Double { units / 650 + 0.02 * pow(units / 650, 2) }
        var samples = AutoCalibrator.roughStops.map { u in
            (ux: Double(u), uy: Double(u), fx: x(Double(u)), fy: y(Double(u)))
        }
        let roughX = try XCTUnwrap(ProbeFit.line(samples.map { ($0.ux, $0.fx) }))
        let roughY = try XCTUnwrap(ProbeFit.line(samples.map { ($0.uy, $0.fy) }))
        for (tx, ty) in AutoCalibrator.targets {
            let ux = Double(roughX.units(for: tx)), uy = Double(roughY.units(for: ty))
            samples.append((ux, uy, x(ux), y(uy)))
        }
        let pointer = Pointer(device: FakeDevice(), calibrationFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertTrue(pointer.applyProbe(x: roughX, y: roughY, samples: samples))
        for (tx, ty) in AutoCalibrator.checks {
            let (ux, uy) = pointer.probeUnits(tx, ty)
            XCTAssertEqual(x(Double(ux)), tx, accuracy: 0.015)
            XCTAssertEqual(y(Double(uy)), ty, accuracy: 0.015)
        }
        pointer.discardProbe()
    }
}
