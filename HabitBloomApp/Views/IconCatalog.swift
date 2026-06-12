import Foundation

enum IconPickerMode: String, CaseIterable, Identifiable {
    case emoji
    case symbol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emoji: "表情"
        case .symbol: "系统图标"
        }
    }

    var customPlaceholder: String {
        switch self {
        case .emoji: "粘贴任意表情"
        case .symbol: "输入 SF Symbol 名称"
        }
    }
}

struct IconCandidate: Identifiable, Hashable {
    var value: String
    var name: String
    var keywords: [String]
    var mode: IconPickerMode

    var id: String { "\(mode.rawValue)-\(value)" }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        return ([value, name] + keywords)
            .map { $0.lowercased() }
            .contains { $0.contains(normalizedQuery) }
    }
}

struct IconCategory: Identifiable {
    var title: String
    var mode: IconPickerMode
    var candidates: [IconCandidate]

    var id: String { "\(mode.rawValue)-\(title)" }
}

enum IconCatalog {
    static func categories(for mode: IconPickerMode) -> [IconCategory] {
        switch mode {
        case .emoji: emojiCategories
        case .symbol: symbolCategories
        }
    }

    private static func emoji(_ value: String, _ name: String, _ keywords: String...) -> IconCandidate {
        IconCandidate(value: value, name: name, keywords: keywords, mode: .emoji)
    }

    private static func symbol(_ value: String, _ name: String, _ keywords: String...) -> IconCandidate {
        IconCandidate(value: value, name: name, keywords: keywords, mode: .symbol)
    }

    private static let emojiCategories: [IconCategory] = [
        IconCategory(title: "健康", mode: .emoji, candidates: [
            emoji("💧", "喝水", "water", "hydrate"),
            emoji("🥗", "轻食", "salad", "diet"),
            emoji("🍎", "水果", "fruit"),
            emoji("🥦", "蔬菜", "vegetable"),
            emoji("🥛", "牛奶", "milk"),
            emoji("🍵", "茶", "tea"),
            emoji("🫖", "泡茶", "tea"),
            emoji("💊", "吃药", "medicine"),
            emoji("🦷", "牙齿", "tooth"),
            emoji("🪥", "刷牙", "toothbrush"),
            emoji("🧼", "清洁", "soap"),
            emoji("🛁", "洗澡", "bath"),
            emoji("🧴", "护肤", "skin"),
            emoji("🪒", "整理", "shave"),
            emoji("😴", "睡眠", "sleep"),
            emoji("💤", "早睡", "sleep"),
            emoji("🛌", "休息", "rest"),
            emoji("🧘", "冥想", "meditation"),
            emoji("🧠", "大脑", "brain"),
            emoji("❤️", "心脏", "heart")
        ]),
        IconCategory(title: "学习", mode: .emoji, candidates: [
            emoji("📚", "阅读", "book", "read"),
            emoji("📖", "读书", "book"),
            emoji("📝", "笔记", "note"),
            emoji("✍️", "写作", "write"),
            emoji("📓", "日记", "journal"),
            emoji("📒", "手账", "notebook"),
            emoji("📔", "记录", "record"),
            emoji("📕", "红书", "book"),
            emoji("📗", "绿书", "book"),
            emoji("📘", "蓝书", "book"),
            emoji("📙", "橙书", "book"),
            emoji("🧮", "计算", "math"),
            emoji("🔬", "科学", "science"),
            emoji("🧪", "实验", "experiment"),
            emoji("🧬", "生物", "biology"),
            emoji("🌍", "地理", "geo"),
            emoji("🗣️", "语言", "language"),
            emoji("🎓", "学习", "study"),
            emoji("🧩", "解题", "puzzle"),
            emoji("💡", "灵感", "idea")
        ]),
        IconCategory(title: "运动", mode: .emoji, candidates: [
            emoji("🏃", "跑步", "run"),
            emoji("🚶", "散步", "walk"),
            emoji("💪", "力量", "strength"),
            emoji("🏋️", "举铁", "lift"),
            emoji("🚴", "骑行", "bike"),
            emoji("🏊", "游泳", "swim"),
            emoji("🧗", "攀岩", "climb"),
            emoji("🤸", "体操", "gym"),
            emoji("🕺", "跳舞", "dance"),
            emoji("⚽️", "足球", "football"),
            emoji("🏀", "篮球", "basketball"),
            emoji("🎾", "网球", "tennis"),
            emoji("🏓", "乒乓", "pingpong"),
            emoji("🏸", "羽毛球", "badminton"),
            emoji("🥊", "拳击", "boxing"),
            emoji("⛳️", "高尔夫", "golf"),
            emoji("🛹", "滑板", "skate"),
            emoji("🎿", "滑雪", "ski"),
            emoji("🥾", "徒步", "hike"),
            emoji("🏆", "成就", "trophy")
        ]),
        IconCategory(title: "饮食", mode: .emoji, candidates: [
            emoji("☕️", "咖啡", "coffee"),
            emoji("🍋", "柠檬", "lemon"),
            emoji("🍊", "橙子", "orange"),
            emoji("🍓", "草莓", "berry"),
            emoji("🥑", "牛油果", "avocado"),
            emoji("🥕", "胡萝卜", "carrot"),
            emoji("🌽", "玉米", "corn"),
            emoji("🍚", "米饭", "rice"),
            emoji("🍜", "面条", "noodle"),
            emoji("🍽️", "正餐", "meal"),
            emoji("🥣", "早餐", "bowl"),
            emoji("🍞", "面包", "bread"),
            emoji("🥚", "鸡蛋", "egg"),
            emoji("🧃", "饮料", "drink"),
            emoji("🧊", "冰水", "ice"),
            emoji("🍫", "巧克力", "chocolate"),
            emoji("🧁", "甜点", "cake"),
            emoji("🍯", "蜂蜜", "honey")
        ]),
        IconCategory(title: "生活", mode: .emoji, candidates: [
            emoji("🏠", "居家", "home"),
            emoji("🧹", "打扫", "clean"),
            emoji("🧺", "洗衣", "laundry"),
            emoji("🪴", "植物", "plant"),
            emoji("🛏️", "整理床铺", "bed"),
            emoji("⏰", "闹钟", "alarm"),
            emoji("📅", "日历", "calendar"),
            emoji("✅", "完成", "done"),
            emoji("🔔", "提醒", "reminder"),
            emoji("🧭", "计划", "plan"),
            emoji("🚗", "开车", "car"),
            emoji("✈️", "旅行", "travel"),
            emoji("🗺️", "地图", "map"),
            emoji("🧳", "行李", "bag"),
            emoji("📦", "收纳", "box"),
            emoji("🛒", "购物", "shop"),
            emoji("🎁", "礼物", "gift"),
            emoji("🔑", "钥匙", "key"),
            emoji("💰", "记账", "money"),
            emoji("🧾", "账单", "bill")
        ]),
        IconCategory(title: "工作", mode: .emoji, candidates: [
            emoji("💻", "电脑", "computer"),
            emoji("📱", "手机", "phone"),
            emoji("⌚️", "手表", "watch"),
            emoji("📧", "邮件", "email"),
            emoji("📞", "电话", "phone"),
            emoji("🗂️", "整理文件", "file"),
            emoji("📊", "数据", "chart"),
            emoji("📈", "增长", "chart"),
            emoji("📉", "复盘", "review"),
            emoji("📌", "重点", "pin"),
            emoji("📎", "附件", "clip"),
            emoji("🗒️", "清单", "list"),
            emoji("🧑‍💻", "编码", "code"),
            emoji("⚙️", "设置", "settings"),
            emoji("🔧", "修复", "fix"),
            emoji("🧰", "工具", "tool"),
            emoji("🚀", "发布", "launch"),
            emoji("🎯", "目标", "target")
        ]),
        IconCategory(title: "爱好", mode: .emoji, candidates: [
            emoji("🎧", "听歌", "music"),
            emoji("🎹", "钢琴", "piano"),
            emoji("🎸", "吉他", "guitar"),
            emoji("🎨", "绘画", "paint"),
            emoji("📷", "摄影", "camera"),
            emoji("🎬", "电影", "movie"),
            emoji("🎮", "游戏", "game"),
            emoji("🧵", "缝纫", "sew"),
            emoji("🪡", "针线", "needle"),
            emoji("🕯️", "香薰", "candle"),
            emoji("🪄", "创意", "magic"),
            emoji("🧱", "搭建", "build"),
            emoji("🛠️", "手作", "make"),
            emoji("🎲", "桌游", "boardgame"),
            emoji("♟️", "棋", "chess"),
            emoji("🃏", "卡牌", "card")
        ]),
        IconCategory(title: "情绪", mode: .emoji, candidates: [
            emoji("🔥", "热情", "fire"),
            emoji("⭐️", "星标", "star"),
            emoji("✨", "闪光", "sparkle"),
            emoji("💎", "珍贵", "diamond"),
            emoji("🌈", "彩虹", "rainbow"),
            emoji("😊", "开心", "happy"),
            emoji("😌", "平静", "calm"),
            emoji("🤔", "思考", "think"),
            emoji("😎", "自信", "cool"),
            emoji("🥳", "庆祝", "party"),
            emoji("🙏", "感恩", "thanks"),
            emoji("👏", "鼓掌", "clap"),
            emoji("🤝", "合作", "partner"),
            emoji("🫶", "关爱", "love"),
            emoji("💛", "温暖", "warm"),
            emoji("🩵", "清爽", "fresh")
        ]),
        IconCategory(title: "自然", mode: .emoji, candidates: [
            emoji("☀️", "太阳", "sun"),
            emoji("🌙", "月亮", "moon"),
            emoji("🌿", "绿叶", "leaf"),
            emoji("🌱", "成长", "grow"),
            emoji("🌳", "树", "tree"),
            emoji("🌸", "花", "flower"),
            emoji("🌻", "向日葵", "flower"),
            emoji("🪷", "莲花", "lotus"),
            emoji("🌊", "海浪", "wave"),
            emoji("⛰️", "山", "mountain"),
            emoji("🌧️", "雨", "rain"),
            emoji("❄️", "雪", "snow"),
            emoji("🌕", "满月", "moon"),
            emoji("🌤️", "天气", "weather"),
            emoji("🍀", "幸运", "luck"),
            emoji("🐾", "足迹", "paw")
        ])
    ]

    private static let symbolCategories: [IconCategory] = [
        IconCategory(title: "常用", mode: .symbol, candidates: [
            symbol("flame.fill", "火焰", "hot", "streak"),
            symbol("star.fill", "星标", "favorite"),
            symbol("heart.fill", "爱心", "love"),
            symbol("bolt.fill", "能量", "energy"),
            symbol("sparkles", "闪光", "magic"),
            symbol("target", "目标", "goal"),
            symbol("checkmark.circle.fill", "完成", "done"),
            symbol("circle", "未完成", "empty"),
            symbol("plus.circle.fill", "新增", "add"),
            symbol("bell.fill", "提醒", "reminder"),
            symbol("alarm.fill", "闹钟", "alarm"),
            symbol("calendar", "日历", "date"),
            symbol("timer", "计时", "time"),
            symbol("clock.fill", "时间", "time"),
            symbol("bookmark.fill", "收藏", "save"),
            symbol("flag.fill", "旗帜", "flag")
        ]),
        IconCategory(title: "健康", mode: .symbol, candidates: [
            symbol("drop.fill", "水滴", "water"),
            symbol("leaf.fill", "叶子", "leaf"),
            symbol("cross.case.fill", "药箱", "health"),
            symbol("pills.fill", "药丸", "medicine"),
            symbol("heart.text.square.fill", "健康记录", "health"),
            symbol("bed.double.fill", "睡眠", "sleep"),
            symbol("moon.fill", "夜晚", "moon"),
            symbol("sun.max.fill", "阳光", "sun"),
            symbol("brain.head.profile", "大脑", "brain"),
            symbol("figure.mind.and.body", "身心", "meditation"),
            symbol("lungs.fill", "呼吸", "breath"),
            symbol("waterbottle.fill", "水瓶", "water"),
            symbol("fork.knife", "餐食", "food"),
            symbol("cup.and.saucer.fill", "咖啡", "coffee")
        ]),
        IconCategory(title: "运动", mode: .symbol, candidates: [
            symbol("figure.run", "跑步", "run"),
            symbol("figure.walk", "散步", "walk"),
            symbol("figure.flexibility", "拉伸", "stretch"),
            symbol("figure.strengthtraining.traditional", "力量训练", "strength"),
            symbol("dumbbell.fill", "哑铃", "gym"),
            symbol("bicycle", "骑行", "bike"),
            symbol("figure.pool.swim", "游泳", "swim"),
            symbol("figure.hiking", "徒步", "hike"),
            symbol("figure.climbing", "攀爬", "climb"),
            symbol("figure.cooldown", "放松", "cooldown"),
            symbol("soccerball", "足球", "football"),
            symbol("basketball.fill", "篮球", "basketball"),
            symbol("tennisball.fill", "网球", "tennis"),
            symbol("trophy.fill", "奖杯", "trophy")
        ]),
        IconCategory(title: "学习", mode: .symbol, candidates: [
            symbol("book.closed.fill", "书本", "book"),
            symbol("books.vertical.fill", "书架", "books"),
            symbol("text.book.closed.fill", "教材", "textbook"),
            symbol("graduationcap.fill", "毕业帽", "study"),
            symbol("pencil", "铅笔", "write"),
            symbol("pencil.and.list.clipboard", "清单", "list"),
            symbol("note.text", "笔记", "note"),
            symbol("doc.text.fill", "文档", "doc"),
            symbol("doc.richtext.fill", "富文档", "doc"),
            symbol("character.book.closed.fill", "语言", "language"),
            symbol("globe.asia.australia.fill", "地理", "globe"),
            symbol("lightbulb.fill", "灵感", "idea"),
            symbol("function", "函数", "math"),
            symbol("sum", "求和", "math")
        ]),
        IconCategory(title: "工作", mode: .symbol, candidates: [
            symbol("laptopcomputer", "电脑", "computer"),
            symbol("desktopcomputer", "桌面电脑", "desktop"),
            symbol("iphone", "手机", "phone"),
            symbol("applewatch", "手表", "watch"),
            symbol("keyboard.fill", "键盘", "keyboard"),
            symbol("terminal.fill", "终端", "code"),
            symbol("curlybraces", "代码", "code"),
            symbol("folder.fill", "文件夹", "folder"),
            symbol("tray.full.fill", "收件箱", "inbox"),
            symbol("envelope.fill", "邮件", "mail"),
            symbol("phone.fill", "电话", "phone"),
            symbol("paperclip", "附件", "clip"),
            symbol("pin.fill", "固定", "pin"),
            symbol("gearshape.fill", "设置", "settings"),
            symbol("hammer.fill", "工具", "tool"),
            symbol("wrench.and.screwdriver.fill", "维修", "tool")
        ]),
        IconCategory(title: "数据", mode: .symbol, candidates: [
            symbol("chart.bar.fill", "柱状图", "chart"),
            symbol("chart.line.uptrend.xyaxis", "趋势", "trend"),
            symbol("chart.pie.fill", "饼图", "pie"),
            symbol("waveform.path.ecg", "波形", "wave"),
            symbol("number", "数字", "number"),
            symbol("percent", "百分比", "percent"),
            symbol("calendar.badge.clock", "日程", "schedule"),
            symbol("list.bullet.clipboard.fill", "任务板", "tasks"),
            symbol("checklist", "检查清单", "checklist"),
            symbol("square.and.pencil", "编辑", "edit"),
            symbol("arrow.triangle.2.circlepath", "循环", "repeat"),
            symbol("icloud.and.arrow.up", "上传", "upload"),
            symbol("square.and.arrow.up", "导出", "export"),
            symbol("square.and.arrow.down", "导入", "import")
        ]),
        IconCategory(title: "生活", mode: .symbol, candidates: [
            symbol("house.fill", "家", "home"),
            symbol("cart.fill", "购物", "shop"),
            symbol("creditcard.fill", "银行卡", "card"),
            symbol("banknote.fill", "现金", "money"),
            symbol("wallet.pass.fill", "钱包", "wallet"),
            symbol("car.fill", "汽车", "car"),
            symbol("airplane", "飞机", "travel"),
            symbol("map.fill", "地图", "map"),
            symbol("location.fill", "位置", "location"),
            symbol("shippingbox.fill", "箱子", "box"),
            symbol("gift.fill", "礼物", "gift"),
            symbol("key.fill", "钥匙", "key"),
            symbol("paintbrush.fill", "绘画", "paint"),
            symbol("camera.fill", "相机", "camera"),
            symbol("music.note", "音乐", "music"),
            symbol("headphones", "耳机", "music")
        ])
    ]
}
