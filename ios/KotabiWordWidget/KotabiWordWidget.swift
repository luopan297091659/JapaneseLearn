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
    @Environment(\.colorScheme) private var colorScheme
    let entry: WordWidgetEntry

    private var titleTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.09, green: 0.13, blue: 0.20)
    }

    private var tagsTextColor: Color {
        colorScheme == .dark ? Color(red: 0.98, green: 0.82, blue: 0.82) : Color(red: 0.48, green: 0.18, blue: 0.18)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.20) : Color(red: 0.93, green: 0.95, blue: 0.98)
    }

    private var cardOverlayBackground: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.18, blue: 0.28) : Color(red: 0.98, green: 0.90, blue: 0.94)
    }

    private var dictionaryTextColor: Color {
        colorScheme == .dark ? Color(red: 0.96, green: 0.84, blue: 0.84) : Color(red: 0.48, green: 0.18, blue: 0.18)
    }

    private var dictionaryBackground: Color {
        colorScheme == .dark ? Color(red: 0.22, green: 0.14, blue: 0.20) : Color(red: 0.97, green: 0.86, blue: 0.83)
    }

    private var widgetBackground: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.20),
                    Color(red: 0.15, green: 0.16, blue: 0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
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

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleBar
            Text(entry.word)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if !entry.reading.isEmpty {
                Text(entry.reading)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            tags
            Text(entry.meaning)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
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
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 8) {
                checkinTile
                dictionaryTile
            }
            .frame(width: 82)
        }
        .widgetURL(URL(string: "kotabi://word-widget"))
        .containerBackground(for: .widget) { background }
    }

    private var tags: some View {
        Text([entry.jlptLevel, entry.partOfSpeech].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.caption2.weight(.bold))
            .foregroundStyle(tagsTextColor)
            .lineLimit(1)
    }

    private var titleBar: some View {
        HStack(spacing: 5) {
            Text("✦")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.05, green: 0.58, blue: 0.91))
                .frame(width: 22, height: 22)
                .background(colorScheme == .dark ? Color(red: 0.14, green: 0.24, blue: 0.40) : Color(red: 0.88, green: 0.97, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("今日一词")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(titleTextColor)
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
                    .padding(.vertical, 7)
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
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(entry.checkedInToday ? Color(red: 0.44, green: 0.55, blue: 0.40) : Color(red: 0.82, green: 0.23, blue: 0.23))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var checkinTile: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: CheckinIntent()) {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .bold))
                    Text(entry.checkedInToday ? "已签到" : "签到")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .frame(width: 72, height: 62)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(entry.checkedInToday ? Color(red: 0.44, green: 0.55, blue: 0.40) : Color(red: 0.82, green: 0.23, blue: 0.23))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            Link(destination: URL(string: "kotabi://checkin")!) {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .bold))
                    Text(entry.checkedInToday ? "已签到" : "签到")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .frame(width: 72, height: 62)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(entry.checkedInToday ? Color(red: 0.44, green: 0.55, blue: 0.40) : Color(red: 0.82, green: 0.23, blue: 0.23))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var dictionaryTile: some View {
        Link(destination: URL(string: "kotabi://dictionary")!) {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                Text("辞书搜索")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 72, height: 62)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colorScheme == .dark ? Color(red: 0.96, green: 0.84, blue: 0.84) : Color(red: 0.48, green: 0.18, blue: 0.18))
        .background(colorScheme == .dark ? Color(red: 0.30, green: 0.20, blue: 0.18) : Color(red: 0.97, green: 0.86, blue: 0.83))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var background: some View {
        widgetBackground
    }
}

@main
struct KotabiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KotabiWordWidget()
        KotabiDictionarySearchWidget()
        KotabiJlptCountdownWidget()
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
    @Environment(\.colorScheme) private var colorScheme

    private var titleTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.09, green: 0.13, blue: 0.20)
    }

    private var containerColor: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.10, blue: 0.18) : Color(red: 0.95, green: 0.84, blue: 0.95)
    }

    private var cardColor: Color {
        colorScheme == .dark ? Color(red: 0.22, green: 0.12, blue: 0.18) : Color(red: 0.97, green: 0.79, blue: 0.94)
    }

    private var accentTextColor: Color {
        colorScheme == .dark ? Color(red: 0.90, green: 0.80, blue: 0.90) : Color(red: 0.09, green: 0.13, blue: 0.20)
    }

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
                    .foregroundStyle(accentTextColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(cardColor)
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
            containerColor
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

struct JlptEntry: TimelineEntry {
    let date: Date
    let label: String
    let examDate: Date
    let days: Int
}

struct JlptProvider: TimelineProvider {
    func placeholder(in context: Context) -> JlptEntry {
        makeEntry(on: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (JlptEntry) -> Void) {
        completion(makeEntry(on: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JlptEntry>) -> Void) {
        let entry = makeEntry(on: Date())
        let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(60 * 60 * 24)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }

    private func makeEntry(on date: Date) -> JlptEntry {
        let exam = Self.nextExam(after: date)
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.startOfDay(for: exam.date)
        let days = max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
        return JlptEntry(date: date, label: exam.label, examDate: exam.date, days: days)
    }

    private static func nextExam(after date: Date) -> (label: String, date: Date) {
        let calendar = Calendar.current
        let exams: [(String, Date)] = [
            ("JLPT 7月", calendar.date(from: DateComponents(year: 2026, month: 7, day: 5))!),
            ("JLPT 12月", calendar.date(from: DateComponents(year: 2026, month: 12, day: 6))!),
        ]
        if let exam = exams.first(where: { calendar.startOfDay(for: $0.1) >= calendar.startOfDay(for: date) }) {
            return exam
        }
        var next = calendar.date(from: DateComponents(year: calendar.component(.year, from: date) + 1, month: 7, day: 1))!
        while calendar.component(.weekday, from: next) != 1 {
            next = calendar.date(byAdding: .day, value: 1, to: next)!
        }
        return ("JLPT 7月", next)
    }
}

struct KotabiJlptCountdownWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: JlptEntry

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.12, green: 0.16, blue: 0.22)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(red: 0.82, green: 0.84, blue: 0.88) : Color(red: 0.21, green: 0.26, blue: 0.33)
    }

    private var countdownBackground: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.18),
                    Color(red: 0.16, green: 0.12, blue: 0.18),
                    Color(red: 0.10, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.97, blue: 0.91),
                    Color(red: 0.98, green: 0.87, blue: 0.95),
                    Color(red: 0.88, green: 0.96, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            Text(entry.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.88, green: 0.11, blue: 0.28))
                .clipShape(Capsule())
            Text("\(entry.days)")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(primaryTextColor)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(entry.days == 0 ? "今天考试" : "天后考试")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(secondaryTextColor)
            Text(dateLabel(entry.examDate))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "kotabi://home"))
        .containerBackground(for: .widget) {
            countdownBackground
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

struct KotabiJlptCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KotabiJlptCountdownWidget", provider: JlptProvider()) { entry in
            KotabiJlptCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("JLPT 倒计时")
        .description("显示下一场 JLPT 考试倒计天数。")
        .supportedFamilies([.systemSmall])
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
