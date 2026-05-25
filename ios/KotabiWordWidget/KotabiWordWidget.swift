import AppIntents
import SwiftUI
import WidgetKit

private let appGroup = "group.com.kotabi.app"
private let widgetKind = "KotabiWordWidget"

struct WordWidgetEntry: TimelineEntry {
    let date: Date
    let word: String
    let reading: String
    let meaning: String
    let partOfSpeech: String
    let jlptLevel: String
    let checkedInToday: Bool
    let streakDays: Int
}

struct WordWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WordWidgetEntry {
        WordWidgetEntry(
            date: Date(),
            word: "言葉",
            reading: "ことば",
            meaning: "词语，语言",
            partOfSpeech: "名词",
            jlptLevel: "N5",
            checkedInToday: false,
            streakDays: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WordWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordWidgetEntry>) -> Void) {
        let entry = readEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readEntry() -> WordWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return WordWidgetEntry(
            date: Date(),
            word: defaults?.string(forKey: "word")?.nilIfEmpty ?? "今日一词",
            reading: defaults?.string(forKey: "reading") ?? "",
            meaning: defaults?.string(forKey: "meaningZh")?.nilIfEmpty ?? "打开 App 后会同步今日单词",
            partOfSpeech: defaults?.string(forKey: "partOfSpeech") ?? "",
            jlptLevel: defaults?.string(forKey: "jlptLevel") ?? "",
            checkedInToday: defaults?.bool(forKey: "checkedInToday") ?? false,
            streakDays: defaults?.integer(forKey: "streakDays") ?? 0
        )
    }
}

struct CheckinIntent: AppIntent {
    static var title: LocalizedStringResource = "签到"
    static var description = IntentDescription("从今日一词小组件完成签到。")

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroup)
        if defaults?.bool(forKey: "checkedInToday") == true {
            return .result()
        }
        guard
            let baseUrl = defaults?.string(forKey: "baseUrl"), !baseUrl.isEmpty,
            let token = defaults?.string(forKey: "accessToken"), !token.isEmpty,
            let url = URL(string: "\(baseUrl)/progress/checkin")
        else {
            return .result()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.todayString(), forHTTPHeaderField: "X-Client-Date")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return .result()
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        defaults?.set(true, forKey: "checkedInToday")
        if let streak = json?["streak_days"] as? Int {
            defaults?.set(streak, forKey: "streakDays")
        }
        defaults?.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        return .result()
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

struct KotabiWordWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WordWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 7) {
            titleBar
            Text(entry.word)
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if !entry.reading.isEmpty {
                Text(entry.reading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            tags
            Text(entry.meaning)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
            Spacer(minLength: 2)
            checkinButton
        }
        .widgetURL(URL(string: "kotabi://word-widget"))
        .containerBackground(for: .widget) { background }
    }

    private var mediumView: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                titleBar
                Text(entry.word)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !entry.reading.isEmpty {
                    Text(entry.reading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                tags
                Text(entry.meaning)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(red: 1.0, green: 0.99, blue: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 8) {
                checkinButton
                Link(destination: URL(string: "kotabi://dictionary")!) {
                    Label("辞书搜索", systemImage: "magnifyingglass")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.48, green: 0.18, blue: 0.18))
                .background(Color(red: 0.97, green: 0.86, blue: 0.83))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .frame(width: 100)
        }
        .widgetURL(URL(string: "kotabi://word-widget"))
        .containerBackground(for: .widget) { background }
    }

    private var tags: some View {
        Text([entry.jlptLevel, entry.partOfSpeech].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(red: 0.48, green: 0.18, blue: 0.18))
            .lineLimit(1)
    }

    private var titleBar: some View {
        HStack(spacing: 5) {
            Text("✦")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.05, green: 0.58, blue: 0.91))
                .frame(width: 22, height: 22)
                .background(Color(red: 0.88, green: 0.97, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("今日一词")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.20))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var checkinButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: CheckinIntent()) {
                Label(entry.checkedInToday ? "已签到" : "签到", systemImage: "checkmark.circle")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(entry.checkedInToday ? Color(red: 0.44, green: 0.55, blue: 0.40) : Color(red: 0.82, green: 0.23, blue: 0.23))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Link(destination: URL(string: "kotabi://checkin")!) {
                Label(entry.checkedInToday ? "已签到" : "签到", systemImage: "checkmark.circle")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(entry.checkedInToday ? Color(red: 0.44, green: 0.55, blue: 0.40) : Color(red: 0.82, green: 0.23, blue: 0.23))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.98, green: 0.90, blue: 0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@main
struct KotabiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KotabiWordWidget()
        KotabiDictionarySearchWidget()
    }
}

struct KotabiWordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: WordWidgetProvider()) { entry in
            KotabiWordWidgetView(entry: entry)
        }
        .configurationDisplayName("今日一词")
        .description("显示今日一词，可签到；宽组件额外提供辞书搜索。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SearchEntry: TimelineEntry {
    let date: Date
}

struct SearchProvider: TimelineProvider {
    func placeholder(in context: Context) -> SearchEntry {
        SearchEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SearchEntry) -> Void) {
        completion(SearchEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SearchEntry>) -> Void) {
        completion(Timeline(entries: [SearchEntry(date: Date())], policy: .never))
    }
}

struct KotabiDictionarySearchWidgetView: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color(red: 0.07, green: 0.09, blue: 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("搜索 辞书")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.20))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color(red: 0.97, green: 0.79, blue: 0.94))
            .clipShape(Capsule())

            Text("あ")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.41))
                .frame(width: 42, height: 42)
                .background(Color(red: 0.98, green: 0.88, blue: 0.96))
                .clipShape(Circle())
        }
        .widgetURL(URL(string: "kotabi://dictionary"))
        .containerBackground(for: .widget) {
            Color(red: 0.95, green: 0.84, blue: 0.95)
        }
    }
}

struct KotabiDictionarySearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KotabiDictionarySearchWidget", provider: SearchProvider()) { _ in
            KotabiDictionarySearchWidgetView()
        }
        .configurationDisplayName("辞书检索")
        .description("快速打开辞书检索。")
        .supportedFamilies([.systemMedium])
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
