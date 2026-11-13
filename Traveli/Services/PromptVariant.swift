import Foundation

/// A named system prompt for the itinerary model. Variants exist so prompt changes can be
/// compared in a controlled experiment (see Evaluation/EXPERIMENT.md) instead of by feel.
struct PromptVariant: Sendable, Hashable {
    let id: String
    let instructions: String

    private static let baseText = """
        You are a careful travel planner for solo women travellers. Plan one day at a time. \
        Prefer well-known, well-lit, busy places. Put quieter spots such as parks and viewpoints in the \
        morning or afternoon, and choose lively, populated areas for the evening. \
        Keep each day geographically compact so travel between stops is short. \
        Only suggest real places that exist on Apple Maps. Do not repeat places from earlier days.
        """

    /// The prompt shipped in the app.
    static let baseline = PromptVariant(id: "baseline", instructions: baseText)

    /// Baseline plus an explicit, measurable distance constraint.
    static let compact = PromptVariant(
        id: "compact",
        instructions: baseText + " Choose the three stops of a day within about 3 km of each other, so the day can be done on foot or with one short ride. Never cross the city between stops."
    )

    /// Ablation: a bare instruction with none of the safety or geography guidance.
    static let minimal = PromptVariant(
        id: "minimal",
        instructions: "Plan one day of sightseeing with three real places."
    )

    static let all: [PromptVariant] = [.baseline, .compact, .minimal]
}
