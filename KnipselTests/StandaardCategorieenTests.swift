import Testing

@testable import Knipsel

struct StandaardCategorieenTests {
    @Test func namenZijnUniekEnGevuld() {
        let namen = StandaardCategorieen.alle.map(\.naam)
        #expect(!namen.isEmpty)
        #expect(Set(namen).count == namen.count)
        #expect(namen.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test func labelsOverlappenNietMetCategorieen() {
        let categorieen = Set(StandaardCategorieen.alle.map(\.naam))
        #expect(categorieen.isDisjoint(with: StandaardCategorieen.labels))
    }
}
