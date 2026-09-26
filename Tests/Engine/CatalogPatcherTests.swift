import Foundation
import Testing

nonisolated struct CatalogPatcherTests {
	static let allVideos = AerialSet.all.flatMap(\.videos)

	@Test func patchesAnyNumberOfSets() throws {
		for sets in [AerialSet.all, AerialSet.all + [CatalogFixture.aurora]] {
			let source = CatalogFixture(sets: sets).catalog
			let patched = try CatalogPatcher.patch(source, sets: sets)
			for set in sets {
				#expect(source.hasExpectedLayout(of: set))
				#expect(patched.catalog.combines(subcategoryID: set.subcategoryID))
				for video in set.videos {
					let asset = try #require(patched.catalog.assetDictionaries.first { $0["id"] as? String == video.assetID })
					let solar = try #require(AerialCatalog.solar(of: asset) as? [String: Any])
					#expect(solar["altitude"] as? Double == video.position.altitude && solar["azimuth"] as? Double == video.position.azimuth)
				}
			}
			let combined = patched.catalog.subcategories.filter { JSONTree.isTrue($0["combineVariants"]) }.compactMap { $0["id"] as? String }
			#expect(Set(combined) == Set(sets.map(\.subcategoryID) + [CatalogFixture.dynamicSubcategoryID]))
			#expect(patched.changes.count == sets.count * 9)
			let untouched = source.assetDictionaries.filter { asset in !sets.contains { AerialCatalog.belongs(asset, to: $0.subcategoryID) } }
			#expect(untouched.allSatisfy { asset in patched.catalog.assetDictionaries.contains { JSONTree.equal($0, asset) } })
		}
	}

	@Test func writesTheSunPositionsAppleReads() throws {
		let set = AerialSet.tahoe
		let patched = try CatalogPatcher.patch(CatalogFixture().catalog, sets: [set])
		let expected: [(AerialVideo, altitude: Double, azimuth: Double)] = [(set.morning, 10.593, 90), (set.day, 10.607, 179.997), (set.evening, 10.593, 180), (set.night, -10.793, 180)]
		for (video, altitude, azimuth) in expected {
			let asset = try #require(patched.catalog.assetDictionaries.first { $0["id"] as? String == video.assetID })
			#expect(JSONTree.equal(asset["variant"], ["solar": ["altitude": altitude, "azimuth": azimuth]]), "\(video.name): \(JSONTree.text(asset["variant"] ?? NSNull()))")
		}
	}

	@Test(arguments: LayoutChange.allCases)
	func mergePlanGuardsEachSet(_ change: LayoutChange) throws {
		let sandbox = try Sandbox(catalog: change.apply(to: CatalogFixture(), .tahoe), videos: Self.allVideos)
		let plan = try sandbox.installer().mergePlan()
		#expect(plan.readiness[.tahoe] == .unexpectedLayout)
		#expect(plan.readiness[.goldenGate] == .ready)
		#expect(plan.readySets == [.goldenGate])
		let patched = try CatalogPatcher.patch(try #require(plan.source), sets: plan.readySets)
		#expect(JSONTree.equal(CatalogFixture.entries(of: .tahoe, in: patched.catalog.root), CatalogFixture.entries(of: .tahoe, in: change.apply(to: CatalogFixture(), .tahoe).root)))
	}

	@Test(arguments: CatalogVariant.allCases)
	func acceptsCatalogVariants(_ variant: CatalogVariant) throws {
		let sandbox = try Sandbox(catalog: variant.catalog, videos: Self.allVideos)
		let plan = try sandbox.installer().mergePlan()
		#expect(plan.readySets == AerialSet.all)
		let patched = try CatalogPatcher.patch(try #require(plan.source), sets: plan.readySets)
		#expect(AerialSet.all.allSatisfy { patched.catalog.combines(subcategoryID: $0.subcategoryID) })
	}

	@Test func stepsAsideForSetsAppleShips() throws {
		for shipped in [[AerialSet.tahoe], [.goldenGate], AerialSet.all] {
			let sandbox = try Sandbox(catalog: CatalogFixture().shippingSolar(shipped), videos: Self.allVideos)
			let plan = try sandbox.installer().mergePlan()
			#expect(plan.appleSets == shipped)
			#expect(plan.readySets == AerialSet.all.filter { !shipped.contains($0) })
			#expect(plan.appleProvidesAll == (shipped == AerialSet.all))
		}
		let bundledOnly = try Sandbox(videos: Self.allVideos)
		try CatalogFixture().shippingSolar([.tahoe]).data.write(to: bundledOnly.bundledCatalog)
		#expect(try bundledOnly.installer().mergePlan().appleSets == [.tahoe])
	}

	@Test(.enabled(if: FileManager.default.fileExists(atPath: CatalogFixture.systemCatalog.path), "the system has no aerial catalog"))
	func systemCatalogMatchesTheFixtureSchema() throws {
		let catalog = try AerialCatalog(contentsOf: CatalogFixture.systemCatalog)
		#expect(catalog.hasExpectedStructure)
		for set in AerialSet.all {
			#expect(catalog.shipsSolarData(for: set) || catalog.hasExpectedLayout(of: set), "\(set.displayName)")
		}
		let ours = AerialSet.all.filter { !catalog.shipsSolarData(for: $0) && catalog.hasExpectedLayout(of: $0) }
		let patched = try CatalogPatcher.patch(catalog, sets: ours)
		#expect(patched.changes.count == ours.count * 9)
		let fixture = CatalogFixture()
		let keys = { (dictionaries: [[String: Any]]) in Set(dictionaries.flatMap(\.keys)) }
		#expect(Set(fixture.root.keys).isSubset(of: catalog.root.keys))
		#expect(keys(fixture.assets).isSubset(of: keys(catalog.assetDictionaries)))
		#expect(keys(fixture.catalog.subcategories).isSubset(of: keys(catalog.subcategories)))
		let categories = { (catalog: AerialCatalog) in (catalog.root["categories"] as? [[String: Any]] ?? []).map { $0.filter { $0.key != "subcategories" } } }
		#expect(keys(categories(fixture.catalog)).isSubset(of: keys(categories(catalog))))
	}
}
