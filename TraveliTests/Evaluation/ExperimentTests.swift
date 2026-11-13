import Foundation
import XCTest
@testable import Traveli

// MARK: - Fakes

struct ClosureSuggester: StopSuggester {
    var body: @Sendable (String, String) async throws -> [StopCandidate]

    func suggestStops(prompt: String, instructions: String) async throws -> [StopCandidate] {
        try await body(prompt, instructions)
    }
}

/// A tiny fake map: any search without a location returns the city centre; otherwise it
/// resolves a known place name contained in the query. Names must not contain one another.
struct FakeMap: PlacesService {
    var centre = GeoPoint(latitude: 38.7223, longitude: -9.1393)
    var known: [String: GeoPoint]

    func search(query: String, near: GeoPoint?) async throws -> [PlaceSuggestion] {
        if near == nil {
            return [PlaceSuggestion(name: query, subtitle: "", category: .other, location: centre)]
        }
        for (name, location) in known where query.localizedCaseInsensitiveContains(name) {
            return [PlaceSuggestion(name: name, subtitle: "", category: .landmark, location: location)]
        }
        return []
    }

    static let standard = FakeMap(known: [
        "Alpha Gate": GeoPoint(latitude: 38.7223, longitude: -9.1393),
        "Beta Park": GeoPoint(latitude: 38.7243, longitude: -9.1393),   // ~220 m from Alpha
        "Gamma Hall": GeoPoint(latitude: 38.7263, longitude: -9.1393),  // ~220 m from Beta
        "Far Fort": GeoPoint(latitude: 38.8223, longitude: -9.1393),    // ~11 km away
    ])
}

/// Resolves the city centre, then fails every verification lookup, like a throttled map service.
struct FlakyMap: PlacesService {
    func search(query: String, near: GeoPoint?) async throws -> [PlaceSuggestion] {
        if near == nil {
            return [PlaceSuggestion(name: query, subtitle: "", category: .other, location: GeoPoint(latitude: 38.72, longitude: -9.14))]
        }
        throw StubError()
    }
}

private func candidate(_ name: String, slot: String = "morning") -> StopCandidate {
    StopCandidate(name: name, category: "landmark", timeSlot: slot)
}

private let lisbonRequest = ItineraryRequest(
    destination: "Testville",
    startDate: TestSupport.date(2027, 3, 1),
    endDate: TestSupport.date(2027, 3, 2)
)

private func service(_ map: FakeMap = .standard, variant: PromptVariant = .baseline,
                     suggest: @escaping @Sendable (String, String) async throws -> [StopCandidate]) -> AIItineraryService {
    AIItineraryService(places: map, suggester: ClosureSuggester(body: suggest), variant: variant,
                       availability: { .available }, calendar: TestSupport.calendar)
}

// MARK: - AIItineraryService

final class AIItineraryServiceTests: XCTestCase {
    func testMeasuresVerifiedRateDuplicatesAndLegs() async throws {
        let ai = service { _, _ in
            [candidate("Alpha Gate"), candidate("Made Up Place", slot: "afternoon"), candidate("Alpha Gate", slot: "evening"), candidate("Beta Park", slot: "evening")]
        }
        let report = try await ai.run(for: ItineraryRequest(destination: "Testville", startDate: TestSupport.date(2027, 3, 1), endDate: TestSupport.date(2027, 3, 1)))
        let day = try XCTUnwrap(report.days.first)
        XCTAssertEqual(day.suggested, 4)
        XCTAssertEqual(day.verified, 2)
        XCTAssertEqual(day.rejectedNotFound, 1)
        XCTAssertEqual(day.rejectedDuplicate, 1)
        XCTAssertEqual(day.verifiedRate, 0.5, accuracy: 0.0001)
        XCTAssertTrue(day.isUsable)
        XCTAssertEqual(day.searchErrors, 0)
        XCTAssertEqual(try XCTUnwrap(day.meanLegMetres), 222, accuracy: 15)
        XCTAssertGreaterThanOrEqual(day.seconds, 0)
        XCTAssertNotNil(report.itinerary)
    }

    func testUnusableDayMakesGenerateThrowAndStopsEarly() async throws {
        let ai = service { _, _ in [candidate("Nothing Real")] }
        do {
            _ = try await ai.generateItinerary(for: lisbonRequest)
            XCTFail("Expected aiFailed")
        } catch {
            XCTAssertEqual(error as? ItineraryError, .aiFailed)
        }
        let report = try await ai.run(for: lisbonRequest, stopOnFailure: true)
        XCTAssertEqual(report.days.count, 1, "Production path stops at the first unusable day")
        let full = try await ai.run(for: lisbonRequest, stopOnFailure: false)
        XCTAssertEqual(full.days.count, 2, "Experiments attempt every day")
        XCTAssertNil(full.itinerary)
    }

    func testSecondDayAvoidsRepeatsAndSuggesterErrorsCountAsUnusable() async throws {
        let calls = CallCounter()
        let ai = service { prompt, _ in
            let n = await calls.next()
            if n == 1 { return [candidate("Alpha Gate"), candidate("Beta Park", slot: "afternoon"), candidate("Gamma Hall", slot: "evening")] }
            XCTAssertTrue(prompt.contains("do not repeat"), "Day 2 prompt lists the places already used")
            throw ItineraryError.aiFailed
        }
        let report = try await ai.run(for: lisbonRequest, stopOnFailure: false)
        XCTAssertEqual(report.days.map(\.verified), [3, 0])
        XCTAssertEqual(report.days.map(\.suggested), [3, 0])
        XCTAssertNil(report.itinerary)
    }

    func testLookupFailuresAreNotBlamedOnTheModel() async throws {
        let ai = AIItineraryService(places: FlakyMap(), suggester: ClosureSuggester { _, _ in
            [candidate("Alpha Gate"), candidate("Beta Park", slot: "afternoon"), candidate("Gamma Hall", slot: "evening")]
        }, availability: { .available }, calendar: TestSupport.calendar)
        let report = try await ai.run(for: ItineraryRequest(destination: "Testville", startDate: TestSupport.date(2027, 3, 1), endDate: TestSupport.date(2027, 3, 1)))
        let day = try XCTUnwrap(report.days.first)
        XCTAssertEqual(day.searchErrors, 3)
        XCTAssertEqual(day.rejectedNotFound, 0, "A failed lookup is not evidence the place is fake")
        XCTAssertEqual(day.verified, 0)
        XCTAssertFalse(day.isUsable)
    }

    func testUnavailableModelThrows() async {
        var ai = service { _, _ in [] }
        ai.availability = { .unavailable(reason: "Turn on Apple Intelligence.") }
        do {
            _ = try await ai.run(for: lisbonRequest)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? ItineraryError, .aiUnavailable(reason: "Turn on Apple Intelligence."))
        }
    }

    func testPromptIncludesPreferencesAndVariantInstructionsReachTheModel() async throws {
        let seen = Captured()
        var request = lisbonRequest
        request.preferences = "food markets"
        let ai = service(variant: .compact) { prompt, instructions in
            await seen.set(prompt: prompt, instructions: instructions)
            return [candidate("Alpha Gate"), candidate("Beta Park", slot: "afternoon")]
        }
        _ = try await ai.run(for: request, stopOnFailure: true)
        let (prompt, instructions) = await seen.values
        XCTAssertTrue(prompt.contains("food markets"))
        XCTAssertEqual(instructions, PromptVariant.compact.instructions)
    }

    func testCancellationPropagates() async {
        let ai = service { _, _ in throw CancellationError() }
        do {
            _ = try await ai.run(for: lisbonRequest)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testPromptVariantsAreDistinct() {
        XCTAssertEqual(Set(PromptVariant.all.map(\.id)).count, PromptVariant.all.count)
        XCTAssertEqual(Set(PromptVariant.all.map(\.instructions)).count, PromptVariant.all.count)
        XCTAssertTrue(PromptVariant.compact.instructions.hasPrefix(PromptVariant.baseline.instructions))
    }
}

private actor CallCounter {
    private var count = 0
    func next() -> Int { count += 1; return count }
}

private actor Captured {
    private(set) var values = ("", "")
    func set(prompt: String, instructions: String) { values = (prompt, instructions) }
}

// MARK: - Latin square, CSV and runner

final class LatinSquareTests: XCTestCase {
    func testEveryItemAppearsInEveryPositionEquallyOften() {
        let items = ["a", "b", "c"]
        let rows = (0..<3).map { LatinSquare.order(items, row: $0) }
        for position in 0..<3 {
            XCTAssertEqual(Set(rows.map { $0[position] }), Set(items), "position \(position)")
        }
        XCTAssertEqual(LatinSquare.order(items, row: 4), LatinSquare.order(items, row: 1), "rows wrap around")
        XCTAssertEqual(LatinSquare.order([Int](), row: 3), [])
    }
}

final class ExperimentRunnerTests: XCTestCase {
    private func makeRunner() -> ExperimentRunner {
        ExperimentRunner(
            destinations: [.init(name: "Testville", region: "Europe"), .init(name: "Sampleton", region: "Asia"), .init(name: "Mockburg", region: "Africa")],
            variants: PromptVariant.all,
            daysPerTrip: 1,
            makeService: { variant in
                service(variant: variant) { _, instructions in
                    switch instructions {
                    case PromptVariant.compact.instructions: return [candidate("Alpha Gate"), candidate("Beta Park", slot: "afternoon"), candidate("Gamma Hall", slot: "evening")]
                    case PromptVariant.baseline.instructions: return [candidate("Alpha Gate"), candidate("Far Fort", slot: "afternoon"), candidate("Gamma Hall", slot: "evening")]
                    default: return [candidate("Alpha Gate"), candidate("Nowhere"), candidate("Nothing", slot: "evening")]
                    }
                }
            },
            calendar: TestSupport.calendar
        )
    }

    func testProducesOneRowPerDestinationVariantDayWithBalancedPositions() async throws {
        let rows = try await makeRunner().run()
        XCTAssertEqual(rows.count, 3 * 3 * 1)
        for variant in PromptVariant.all {
            let positions = rows.filter { $0.variant == variant.id }.map(\.position).sorted()
            XCTAssertEqual(positions, [1, 2, 3], "\(variant.id) must be in each position once")
        }
    }

    func testPromptVariantEffectsAreVisibleInTheData() async throws {
        let rows = try await makeRunner().run()
        func mean(_ variant: String, _ value: (ExperimentRow) -> Double) -> Double {
            let selected = rows.filter { $0.variant == variant }.map(value)
            return selected.reduce(0, +) / Double(selected.count)
        }
        XCTAssertEqual(mean("compact") { $0.metrics.verifiedRate }, 1.0, accuracy: 0.0001)
        XCTAssertEqual(mean("minimal") { $0.metrics.verifiedRate }, 1.0 / 3, accuracy: 0.0001)
        XCTAssertLessThan(mean("compact") { $0.metrics.meanLegMetres ?? 0 }, mean("baseline") { $0.metrics.meanLegMetres ?? 0 })
    }

    func testSkipsFailedTrialsWithoutAborting() async throws {
        var runner = makeRunner()
        runner.destinations = [.init(name: "Testville", region: "Europe")]
        runner.makeService = { variant in
            AIItineraryService(places: FakeMap.standard, suggester: ClosureSuggester { _, _ in [] }, variant: variant,
                               availability: { .unavailable(reason: "off") }, calendar: TestSupport.calendar)
        }
        var messages: [String] = []
        let rows = try await runner.run { messages.append($0) }
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(messages.count, 3)
        XCTAssertTrue(messages.allSatisfy { $0.contains("SKIPPED") })
    }

    func testCSVHasStableColumnsAndEscaping() throws {
        let metrics = DayMetrics(dayNumber: 2, suggested: 3, verified: 2, rejectedNotFound: 1, rejectedDuplicate: 0, searchErrors: 0, meanLegMetres: 1500, seconds: 4.25)
        let row = ExperimentRow(destination: "Washington, D.C.", region: "Americas", variant: "baseline", position: 2, metrics: metrics)
        let columns = ExperimentRow.header.split(separator: ",").count
        XCTAssertEqual(columns, 14)
        XCTAssertEqual(row.csvLine, "\"Washington, D.C.\",Americas,baseline,2,2,3,2,1,0,0,0.6667,1.5000,4.250,1")
        let noLeg = ExperimentRow(destination: "X", region: "Y", variant: "v", position: 1,
                                  metrics: DayMetrics(dayNumber: 1, suggested: 0, verified: 0, rejectedNotFound: 0, rejectedDuplicate: 0, meanLegMetres: nil, seconds: 0))
        XCTAssertTrue(noLeg.csvLine.contains(",0.0000,,0.000,0"), noLeg.csvLine)
        XCTAssertEqual(ExperimentRow.csv([row]).split(separator: "\n").count, 2)
    }
}

// MARK: - The real experiment (opt-in, slow)

/// Runs the prompt experiment against the real on-device model. Skipped unless enabled:
///
///     TEST_RUNNER_TRAVELI_RUN_EXPERIMENT=1 \
///     TEST_RUNNER_TRAVELI_EXPERIMENT_OUT=/path/results.csv \
///     xcodebuild test -scheme Traveli -destination '...' -only-testing:TraveliTests/PromptExperimentTests
final class PromptExperimentTests: XCTestCase {
    func testRunPromptExperiment() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["TRAVELI_RUN_EXPERIMENT"] == "1", "Set TEST_RUNNER_TRAVELI_RUN_EXPERIMENT=1 to run the experiment")
        guard #available(iOS 26.0, *) else { throw XCTSkip("Needs iOS 26") }
        try XCTSkipUnless(AIAvailability.current.isAvailable, "Apple Intelligence is not available")

        let count = Int(env["TRAVELI_EXPERIMENT_DESTINATIONS"] ?? "") ?? ExperimentDestination.defaults.count
        let days = Int(env["TRAVELI_EXPERIMENT_DAYS"] ?? "") ?? 2
        let out = env["TRAVELI_EXPERIMENT_OUT"] ?? NSTemporaryDirectory() + "traveli-experiment.csv"
        let log = out + ".log"
        try? FileManager.default.removeItem(atPath: log)

        let places = MapKitPlacesService()
        let runner = ExperimentRunner(
            destinations: Array(ExperimentDestination.defaults.prefix(count)),
            variants: PromptVariant.all,
            daysPerTrip: days,
            makeService: { variant in
                AIItineraryService(places: places, suggester: FoundationModelsStopSuggester(), variant: variant)
            },
            pauseBetweenTrials: .seconds(Int(env["TRAVELI_EXPERIMENT_PAUSE_SECONDS"] ?? "") ?? 1)
        )
        let rows = try await runner.run { message in
            let line = "\(Date()) \(message)\n"
            if let data = line.data(using: .utf8) {
                if let handle = FileHandle(forWritingAtPath: log) {
                    handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
                } else {
                    FileManager.default.createFile(atPath: log, contents: data)
                }
            }
        }
        try ExperimentRow.csv(rows).write(toFile: out, atomically: true, encoding: .utf8)
        XCTAssertFalse(rows.isEmpty, "No trials completed; see \(log)")
    }
}
