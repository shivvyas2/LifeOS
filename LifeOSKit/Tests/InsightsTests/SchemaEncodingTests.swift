import Testing
import Foundation
import FoundationModels
@testable import Insights

/// Everything in the cloud tier depends on a `@Generable` type's schema
/// surviving a round trip through JSON, so a provider that has never heard of
/// `FoundationModels` can still be told what shape to return. This suite is
/// the load-bearing assumption of the whole design, isolated and pinned.
@Suite struct SchemaEncodingTests {

    @Test func theBriefSchemaEncodesAsAJSONObject() throws {
        let data = try JSONEncoder().encode(DailyBrief.generationSchema)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["type"] as? String == "object")
    }

    @Test func theBriefSchemaCarriesOurPropertyNames() throws {
        let data = try JSONEncoder().encode(DailyBrief.generationSchema)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let properties = try #require(json["properties"] as? [String: Any])

        #expect(properties.keys.contains("headline"))
        #expect(properties.keys.contains("observations"))
    }

    /// The inverse leg: a JSON string from any provider must decode into the
    /// same type the on-device model produces.
    @Test func aJSONReplyDecodesIntoTheSameType() throws {
        let reply = """
        {"headline":"Recovery is low.","observations":["Slept 5h12m.","HRV down 18%."]}
        """
        let brief = try DailyBrief(GeneratedContent(json: reply))

        #expect(brief.headline == "Recovery is low.")
        #expect(brief.observations.count == 2)
    }
}
