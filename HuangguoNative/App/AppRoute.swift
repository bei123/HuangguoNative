import Foundation

enum AppRoute: Hashable {
	case detail(String)
	case rank
	case topics
	case topicDetail(String) // slug
	case latest
	case login
	case register
	case author(Int)
	case myList(MyListKind)
	case messages
	case profileEdit
	case posts
	case postDetail(String)
	case feed
	case more
	case original
	case sort(String) // route
}
