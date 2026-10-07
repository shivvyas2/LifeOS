import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubWireFormatTests {
    @Test func decodesACommitSearch() throws {
        let json = """
        {"total_count":1,"items":[{"sha":"abc","html_url":"https://github.com/o/r/commit/abc",
          "commit":{"message":"fix(notes): close the gaps\\n\\nBody text","author":{"date":"2026-10-07T14:03:00Z"}},
          "repository":{"name":"r","full_name":"o/r","html_url":"https://github.com/o/r"}}]}
        """
        let search = try GitHubWire.decoder.decode(GitHubCommitSearch.self, from: Data(json.utf8))
        #expect(search.items.first?.repository.fullName == "o/r")
        #expect(search.items.first?.commit.author.date == ISO8601DateFormatter().date(from: "2026-10-07T14:03:00Z"))
    }

    @Test func decodesMilestonesWithAndWithoutADueDate() throws {
        let json = """
        [{"title":"1.1","open_issues":4,"closed_issues":5,"due_on":"2026-10-20T07:00:00Z","html_url":"https://github.com/o/r/milestone/1"},
         {"title":"Later","open_issues":2,"closed_issues":0,"due_on":null,"html_url":"https://github.com/o/r/milestone/2"}]
        """
        let milestones = try GitHubWire.decoder.decode([GitHubMilestone].self, from: Data(json.utf8))
        #expect(milestones.map { $0.dueOn == nil } == [false, true])
    }

    @Test func decodesAnIssueSearch() throws {
        let json = """
        {"total_count":3,"items":[{"title":"Crash on launch","html_url":"https://github.com/o/r/issues/9"}]}
        """
        let search = try GitHubWire.decoder.decode(GitHubIssueSearch.self, from: Data(json.utf8))
        #expect(search.totalCount == 3)
    }
}
