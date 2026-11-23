import SwiftUI

struct RootTabView: View {
	@State private var tab: AppTab = .home
	@State private var homePath = NavigationPath()
	@State private var catePath = NavigationPath()
	@State private var searchPath = NavigationPath()
	@State private var minePath = NavigationPath()

	var body: some View {
		TabView(selection: $tab) {
			Tab("首页", systemImage: "house", value: .home) {
				navStack($homePath) { HomeView(path: $homePath) }
			}
			Tab("发现", systemImage: "square.grid.2x2", value: .category) {
				navStack($catePath) { CategoryView(path: $catePath) }
			}
			Tab("搜索", systemImage: "magnifyingglass", value: .search) {
				navStack($searchPath) { SearchView(path: $searchPath) }
			}
			Tab("我的", systemImage: "person", value: .mine) {
				navStack($minePath) { MineView(path: $minePath) }
			}
		}
		.tint(HGTheme.accent)
		.tabBarMinimizeBehavior(.onScrollDown)
	}

	@ViewBuilder
	private func navStack<Content: View>(_ path: Binding<NavigationPath>, @ViewBuilder content: () -> Content) -> some View {
		NavigationStack(path: path) {
			content()
				.navigationDestination(for: AppRoute.self) { route in
					switch route {
					case .detail(let id):
						DetailView(videoId: id)
					case .rank:
						RankView(path: path)
					case .topics:
						TopicsView(path: path)
					case .topicDetail(let slug):
						TopicDetailView(path: path, slug: slug)
					case .latest:
						LatestListView(path: path)
					case .login:
						LoginView(path: path)
					case .register:
						RegisterView(path: path)
					case .author(let uid):
						AuthorView(path: path, userId: uid)
					case .myList(let kind):
						MyListView(path: path, kind: kind)
					case .messages:
						MessagesView()
					case .profileEdit:
						ProfileEditView()
					case .posts:
						PostsView(path: path)
					case .postDetail(let id):
						PostDetailView(path: path, postId: id)
					case .feed:
						FeedView(path: path)
					case .more:
						MoreView(path: path)
					case .original:
						OriginalListView(path: path)
					case .sort(let route):
						SortListView(path: path, route: route)
					}
				}
		}
	}
}

enum AppTab: Hashable {
	case home, category, search, mine
}
