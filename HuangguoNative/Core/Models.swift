import Foundation

extension Array {
	/// ForEach 要求 Identifiable.id 唯一；接口偶发重复条目时保序去重。
	func uniquedPreservingOrder() -> [Element] where Element: Identifiable, Element.ID: Hashable {
		var seen = Set<Element.ID>()
		return filter { seen.insert($0.id).inserted }
	}

	mutating func mergeUnique(_ more: [Element]) where Element: Identifiable, Element.ID: Hashable {
		var seen = Set(map(\.id))
		for item in more where seen.insert(item.id).inserted {
			append(item)
		}
	}
}

struct VideoCard: Identifiable, Hashable, Sendable {
	let id: String
	var title: String
	var cover: String
	var score: Double
	var hot: Int
	var episodeCount: Int
	var isFinished: Bool
	var tags: [String]
	var desc: String
	var badge: String
	var durationSec: Int
	var cateId: String
}

struct HomeBanner: Identifiable, Hashable, Sendable {
	let id: String
	var videoId: String
	var title: String
	var image: String
	var score: Double
	var desc: String
}

struct CateRec: Identifiable, Hashable, Sendable {
	var id: String { cateId }
	var cateId: String
	var cateName: String
	var videos: [VideoCard]
}

struct TopicLite: Identifiable, Hashable, Sendable {
	let id: String
	var title: String
	var slug: String
	var cover: String
	var intro: String
	var videoCount: Int
}

struct HomeData: Sendable {
	var banners: [HomeBanner]
	var featured: [VideoCard]
	var latest: [VideoCard]
	var cateRec: [CateRec]
	var topicRec: [TopicLite]
}

struct CategoryItem: Identifiable, Hashable, Sendable {
	let id: String
	var name: String
	var route: String
}

struct RankItem: Identifiable, Hashable, Sendable {
	var id: String { videoId }
	var rank: Int
	var videoId: String
	var title: String
	var cover: String
	var cateName: String
	var episodeCount: Int
	var isFinished: Bool
	var score: Double
	var tags: [String]
	var metricLabel: String
	var metricValue: Int
}

struct EpisodeItem: Identifiable, Hashable, Sendable {
	var id: Int { epNum }
	var epNum: Int
	var title: String
	var durationSec: Int
	var locked: Bool
}

struct VideoDetail: Identifiable, Sendable {
	let id: String
	var title: String
	var description: String
	var cover: String
	var score: Double
	var episodeCount: Int
	var isFinished: Bool
	var tags: [String]
	var hot: Int
	var like: Int
	var collect: Int
	var authorId: Int
	var authorName: String
	var episodes: [EpisodeItem]
	var liked: Bool
	var collected: Bool
}

struct PlaybackInfo: Sendable {
	var url: String
	var hevcURL: String
	var expiresAt: Int
}

struct PageResult<T: Sendable>: Sendable {
	var items: [T]
	var page: Int
	var pages: Int
	var total: Int
}

enum APIJSON {
	static func string(_ any: Any?, _ keys: String...) -> String {
		for k in keys {
			if let d = any as? [String: Any], let v = d[k] {
				if let s = v as? String { return s }
				if let n = v as? NSNumber { return n.stringValue }
			}
		}
		return ""
	}

	static func int(_ any: Any?, _ keys: String...) -> Int {
		for k in keys {
			if let d = any as? [String: Any], let v = d[k] {
				if let i = v as? Int { return i }
				if let n = v as? NSNumber { return n.intValue }
				if let s = v as? String, let i = Int(s) { return i }
			}
		}
		return 0
	}

	static func double(_ any: Any?, _ keys: String...) -> Double {
		for k in keys {
			if let d = any as? [String: Any], let v = d[k] {
				if let d0 = v as? Double { return d0 }
				if let n = v as? NSNumber { return n.doubleValue }
				if let s = v as? String, let d0 = Double(s) { return d0 }
			}
		}
		return 0
	}

	static func bool(_ any: Any?, _ keys: String...) -> Bool {
		for k in keys {
			if let d = any as? [String: Any], let v = d[k] {
				if let b = v as? Bool { return b }
				if let n = v as? NSNumber { return n.boolValue }
				if let s = v as? String { return s == "1" || s.lowercased() == "true" }
			}
		}
		return false
	}

	static func dict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
	static func arr(_ any: Any?) -> [Any] { (any as? [Any]) ?? [] }
}
