import SwiftUI
import SearchCore

// Intent: return to a folder quickly. Native rows keep name/path aligned;
// Add and Remove change shortcuts only, with no scanning or file deletion.
struct FavoritesView: View {
    @ObservedObject var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("常用文件夹").font(.title2.bold())
                Spacer()
                Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.chooseFolder(purpose: .favorite) } } label: { Label("添加文件夹…", systemImage: "plus") }
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("保存快速搜索入口，不增加索引范围，也不重复扫描。").font(.system(size: 11)).foregroundStyle(.secondary)
            if model.favoriteFolders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                    Text("还没有常用文件夹").font(.headline)
                    Text("也可以点击当前搜索范围旁的星标添加。").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.favoriteFolders, id: \.self) { path in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 12, weight: .semibold))
                                Text(path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
                            }
                            Spacer()
                            Button("搜索此处") { model.selectFolder(path); dismiss() }.controlSize(.small)
                            Button { model.removeFavorite(path) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).help("移出常用，不删除文件或索引").accessibilityLabel("移出常用文件夹")
                        }.padding(.vertical, 8)
                    }
                }.listStyle(.inset)
            }
        }.padding(24).frame(width: 620, height: 460)
    }
}
