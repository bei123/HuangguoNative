import Foundation

struct HgUser: Sendable, Hashable {
	var id: Int = 0
	var username: String = ""
	var nickname: String = ""
	var avatar: String = ""
	var avatarColor: String = "#8C8C8C"
	var sign: String = ""
	var desc: String = ""
	var likeCount: Int = 0
	var collectCount: Int = 0
	var followingCount: Int = 0
	var historyCount: Int = 0
	var favoriteVideoIds: [Int] = []
	var likeVideoIds: [Int] = []
	var followUserIds: [Int] = []
}

struct CommentItem: Identifiable, Sendable, Hashable {
	let id: String
	var userId: Int
	var userName: String
	var avatar: String
	var text: String
	var createdAt: String
	var likeCount: Int
	var ep: Int
}

struct HistoryItem: Identifiable, Sendable, Hashable {
	let id: Int
	var videoId: String
	var title: String
	var cover: String
	var lastEp: Int
	var categoryName: String
	var updatedAt: String
}

struct CollectItem: Identifiable, Sendable, Hashable {
	let id: Int
	var videoId: String
	var title: String
	var cover: String
	var lastEp: Int
	var categoryName: String
}

struct FollowUser: Identifiable, Sendable, Hashable {
	let id: Int
	var nickname: String
	var avatar: String
	var sign: String
}

struct MessageItem: Identifiable, Sendable, Hashable {
	let id: Int
	var title: String
	var content: String
	var createdAt: String
	var read: Bool
}

struct AuthorProfile: Identifiable, Sendable, Hashable {
	let id: Int
	var nickname: String
	var avatar: String
	var avatarColor: String
	var sign: String
	var desc: String
	var likeCount: Int
	var followers: Int
	var following: Int
	var videoCount: Int
	var postCount: Int
}

struct TopicDetail: Sendable {
	var topic: TopicLite
	var videos: PageResult<VideoCard>
	var related: [TopicLite]
	var faq: [(q: String, a: String)]
}

struct PostCard: Identifiable, Sendable, Hashable {
	let id: String
	var title: String
	var cover: String
	var desc: String
	var hot: Int
	var tags: [String]
	var createdAt: String
}

struct PostDetail: Identifiable, Sendable {
	let id: String
	var title: String
	var cover: String
	var desc: String
	var contentHTML: String
	var tags: [String]
	var authorId: Int
	var authorName: String
	var hot: Int
	var like: Int
	var collect: Int
}

struct SortItem: Identifiable, Sendable, Hashable {
	let id: String
	var name: String
	var route: String
}

enum MyListKind: String, CaseIterable, Identifiable, Hashable {
	case history, collects, likes, follows
	var id: String { rawValue }
	var title: String {
		switch self {
		case .history: return "观看历史"
		case .collects: return "我的收藏"
		case .likes: return "我的点赞"
		case .follows: return "我的关注"
		}
	}
}
