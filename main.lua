--[[--
专注力正反馈插件 V4

V1 功能：
- 只记录 KOReader 本地活跃阅读时间
- 在 1/10/20/30/45/60 分钟提醒，之后每 30 分钟提醒一次
- 每次提醒附带一句随机句子池文案
- 翻页追补计时：基于真实时间差计算

V2 新增：
- 领养一本书：通过阅读获得积分，商超购买道具，投喂推进进度，翻开揭晓书名
- 书的台词：特定情景触发 + 普通随机池
- 图鉴：翻开的书自动存入
- 书的心情系统：根据阅读行为显示不同心情
- 书的日记：翻开记录领养/翻开日期和阅读时长

V3 新增：
- 读完评分：读完一本书后弹出评分弹窗（五星制，支持半分）
- 单书阅读追踪：记录每本书的阅读时长和阅读天数
- 图鉴双页面：养成书籍 / 读完书籍

V4 新增：
- 积分系统：里程碑获得积分（1小时前1分，1~3h2分，3~5h3分，5h后4分），替代旧食物掉落
- 商超系统：用积分购买棉花糖/饼干/废纸篓/逗书棒
- 心情值系统：抚摸/阅读/玩耍增加心情，休眠/碎纸屑衰减心情，10%持续30天弃养
- 睡觉系统：10%酣睡（需阅读1h苏醒）/20%小盹（需阅读30min苏醒）
- 碎纸屑系统：每次打开约15%概率触发，需废纸篓清理
- 抚摸连击系统：3次呼噜呼噜，10次以上晕
- 状态优先级系统：睡觉/饥饿/碎纸屑/心情/抚摸连击/随机/默认
--]]--

local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ProgressWidget = require("ui/widget/progresswidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Font = require("ui/font")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")
local _ = require("gettext")
local Dispatcher = require("dispatcher")

-- ========== 主插件类 ==========


local FocusFeedback = WidgetContainer:extend{
    name = "focus_feedback",
    is_doc_only = false,  -- V9: 允许在 FileManager 中加载，使快捷手势全局可用
    enabled = false,
    suspended = false,
    scheduled = false,
    task = nil,
    last_input_wall = nil,
    last_event_wall = nil,
    last_page_turn_wall = nil,  -- V9: 仅翻页/标注更新，用于精确判定真正阅读
    last_quote = nil,
    current_banner = nil,
    adoption_page = nil,
    plugin_dir = nil,
    book_data = nil,
    dialogue_data = nil,
    reveal_book = nil,
    reveal_index = nil,
    reveal_nickname = nil,
    _pending_dialogue = nil,
    quotes_normal = nil,
    quotes_rare = nil,
    _current_book_key = nil,
    _end_book_triggered = false,
    _shop_dialog = nil,
}

local SETTINGS_PREFIX = "focus_feedback_"
local TICK_SECONDS = 60
local IDLE_TIMEOUT_SECONDS = 8 * 60
local FIRST_MILESTONES = { 1, 10, 20, 30, 45, 60 }
local AFTER_60_INTERVAL = 30

-- V2 常量
local COTTON_PROGRESS = 0.3
local BISCUIT_PROGRESS = 0.5
local PROGRESS_MILESTONES = { 10, 30, 50, 70, 90 }
local ABANDON_NO_READ_DAYS = 7
local ABANDON_NO_FEED_DAYS = 30
local IDLE_1DAY_SECONDS = 24 * 3600
local IDLE_1WEEK_SECONDS = 7 * 24 * 3600

-- V4 积分系统
local POINTS_BEFORE_1H = 1   -- 1小时前每次里程碑1积分
local POINTS_1H_TO_3H = 2    -- 1~3小时每次里程碑2积分
local POINTS_3H_TO_5H = 3    -- 3~5小时每次里程碑3积分
local POINTS_AFTER_5H = 4    -- 5小时后每次里程碑4积分

-- V4 商超价格
local PRICE_COTTON = 2
local PRICE_BISCUIT = 3
local PRICE_WASTEBASKET = 3
local PRICE_TOY = 5

-- V4 心情值
local MOOD_PER_PET = 0.1        -- 抚摸+0.1%
local MOOD_PER_READ_MIN = 0.4   -- 阅读1分钟+0.4%
local MOOD_PER_TOY = 5          -- 逗书棒+5%
local MOOD_DECAY_SUSPEND = 6    -- 休眠每小时-6%
local MOOD_DECAY_SCRAPS = 20    -- 碎纸屑时每小时-20%
local MOOD_MIN = 10             -- 最低保持10%
local MOOD_HIGH = 90            -- 90以上喂食+0.1%
local MOOD_LOW = 50             -- 50以下喂食-0.1%
local MOOD_ABANDON_DAYS = 30    -- 10%持续30天弃养

-- V4 睡觉
local SLEEP_DEEP_CHANCE = 0.10  -- 10%酣睡
local SLEEP_NAP_CHANCE = 0.20   -- 20%小盹
local SLEEP_DEEP_NEED_SEC = 3600  -- 酣睡需阅读1h苏醒
local SLEEP_NAP_NEED_SEC = 1800   -- 小盹需阅读30min苏醒

-- V4 碎纸屑
local SCRAPS_TRIGGER_CHANCE = 0.15  -- 每次打开约15%概率（平均每天一次）

-- V5 睡觉最小间隔
local SLEEP_MIN_INTERVAL = 4 * 3600  -- 两次睡觉之间最小间隔4小时

-- V5 随机事件频率（每次tick=60秒检查概率）
-- 假设每天阅读3h=180次tick，按目标频率换算
local EVT_BOOKMARK_CHANCE  = 1/180   -- ~2天一次
local EVT_STRANGER_CHANCE  = 1/900   -- ~5天一次
local EVT_BOOK_FRIEND_CHANCE = 1/720 -- ~4天一次
local EVT_BABEL_CHANCE      = 1/2700 -- ~15天一次
local EVT_FLY_AWAY_CHANCE   = 1/900  -- ~5天一次
local EVT_MIN_INTERVAL      = 2 * 3600 -- 随机事件最小间隔2小时

-- V5 去重因子（V7已废弃，仅陌生人不重复抽取）
local EVT_DEDUP_FACTOR = 1.0  -- 不再使用去重

-- V6 商超新增物品价格
local PRICE_COFFEE = 8
local PRICE_CLOVER = 10
local PRICE_CAT = 50
local PRICE_RABBIT = 35

-- V6 四叶草持续时间
local CLOVER_DURATION = 24 * 3600  -- 24小时

-- ========== V14 模式系统 ==========
local MODE_CHALLENGE = "challenge"
local MODE_SLACK = "slack"
local MODE_NIGHT = "night"
local MODE_HEARTBEAT = "heartbeat"
local MODE_DAY = "day"
local MODE_FLOW = "flow"
local MODE_SPRINT = "sprint"
local MODE_SAND = "sand"
local MODE_DRAW = "draw"

local MODE_NAMES = {
    [MODE_CHALLENGE] = "挑战模式",
    [MODE_SLACK] = "摸鱼模式",
    [MODE_NIGHT] = "夜间模式",
    [MODE_HEARTBEAT] = "心跳模式",
    [MODE_DAY] = "白天模式",
    [MODE_FLOW] = "心流模式",
    [MODE_SPRINT] = "短跑模式",
    [MODE_SAND] = "沙漏模式",
    [MODE_DRAW] = "抽签模式",
}

-- 挑战模式常量
local CHALLENGE_DURATION = 24 * 3600    -- 24小时
local CHALLENGE_COOLDOWN = 7 * 24 * 3600 -- 冷却7天
local CHALLENGE_MIN_GOAL_H = 3          -- 目标最低3小时

-- 摸鱼模式常量
local SLACK_MAX_DURATION = 30 * 24 * 3600  -- 最多30天
local SLACK_COOLDOWN = 7 * 24 * 3600        -- 冷却7天

-- 夜间模式常量
local NIGHT_DURATION = 24 * 3600            -- 一个完整昼夜周期
local NIGHT_CLOSE_WINDOW = 1 * 3600         -- 手动关闭窗口±1小时

-- 白天模式常量（镜像夜间，时段相反）
local DAY_START_HOUR = 6                    -- 白昼区间 6:00-18:00
local DAY_END_HOUR = 18
local DAY_DURATION = 24 * 3600              -- 与夜间同为 24h 周期

-- 心流模式常量
local FLOW_TIER_SEC = 30 * 60               -- 每持续30分钟一档
local FLOW_RESUME_GRACE = 2 * 60            -- 退出文档/休眠/熄屏后2分钟内回来不算断

-- 短跑模式常量（挑战Lite）
local SPRINT_GOAL_MAX_H = 5                 -- 目标时长上限随挑战规则放宽（此处为建议值）
local SPRINT_WINDOW = 5 * 3600              -- 开启后5小时内读完目标
local SPRINT_COOLDOWN = 72 * 3600           -- 冷却72小时
local SPRINT_MIN_GOAL_H = 1                 -- 目标最少1小时

-- 沙漏模式常量
local SAND_TOTAL_LIMIT_SEC = 8 * 3600       -- 用户自定义加成时段累计总长 ≤8小时
local SAND_DURATION = 24 * 3600             -- 周期24h倍数才可关闭

-- 抽签模式常量
local DRAW_DURATION = 7 * 86400             -- 每次开启持续7天
local DRAW_COOLDOWN = 20 * 86400            -- 冷却20天

-- 心跳模式常量
local HEARTBEAT_DURATION = 72 * 3600        -- 72小时后自动关闭
local HEARTBEAT_COOLDOWN = 15 * 24 * 3600   -- 冷却15天

-- 挑战成功心情拉满持续时间
local CHALLENGE_BOOST_DURATION = 8 * 3600   -- 8小时不掉落
-- 低落免疫卡持续时间
local MOOD_IMMUNE_DURATION = 72 * 3600      -- 72小时心情下限90%

-- ========== V15 书之属性系统 ==========
local ATTR_KEYS = {"知识", "审美", "情感", "阅历", "逻辑", "辩证"}
local BOOK_CATEGORIES = {"文学", "类型小说", "历史", "哲学", "社会科学", "自然科学", "实用技术", "艺术"}
-- 书籍分类 -> 阅读时影响的属性
local CATEGORY_ATTRS = {
    ["文学"]     = {"情感", "审美"},
    ["类型小说"] = {"情感"},
    ["历史"]     = {"知识", "阅历"},
    ["哲学"]     = {"逻辑", "辩证"},
    ["社会科学"] = {"知识", "辩证"},
    ["自然科学"] = {"阅历", "逻辑"},
    ["实用技术"] = {"知识"},
    ["艺术"]     = {"审美", "知识"},
}
local ATTR_WEIGHT_STRENGTH = 2      -- 画像加权强度：weight = 1 + 2*sim（温和梯度，不压倒性）
local ATTR_READ_GAIN_PER_H = 1      -- 阅读1h +1%
local ATTR_EVENT_GAIN = 0.4         -- 普通事件 +0.4%
local ATTR_SPECIAL_GAIN = 1         -- 特殊事件 +1%
local ATTR_BOOKMARK_GAIN = 0.1      -- 书签掉落 +0.1%

-- 长期模式周期配置（天数/目标阅读天数/目标时长/入场费/物品奖励数/积分/低落卡/睡眠卡）
local LONG_CYCLES = {
    {days = 21,  target_days = 20, target_sec = 25 * 3600,    fee = 0,  reward_items = 1, reward_pts = 0,  mood_card = 0,  sleep_card = 0},
    {days = 31,  target_days = 29, target_sec = 88 * 3600,    fee = 5,  reward_items = 2, reward_pts = 30, mood_card = 0,  sleep_card = 0},
    {days = 90,  target_days = 87, target_sec = 250 * 3600,   fee = 30, reward_items = 3, reward_pts = 50, mood_card = 5,  sleep_card = 0},
    {days = 365, target_days = 360,target_sec = 1000 * 3600,  fee = 50, reward_items = 5, reward_pts = 85, mood_card = 15, sleep_card = 10},
}
local LONG_CYCLE_NAMES = {"21天", "31天（一个月）", "90天（一季度）", "365天（一年）"}

-- 长期挑战奖励的物品（除猫兔外的商店道具）
local LONG_REWARD_ITEMS = {"cotton", "biscuit", "wastebasket", "toy", "coffee", "clover"}

-- ========== V8 每日任务数据 ==========

-- 每日任务池（普通/稀有/特殊/好运）
-- 概率：普通 70%，稀有 23.33%（普通约1/3），特殊 5%（约20日一次），好运 1.67%（约60日一次）
local DAILY_TASKS = {
    normal = {
        {id = "n1",  desc = "今日阅读时长达1h"},
        {id = "n2",  desc = "今日阅读时长达2h"},
        {id = "n3",  desc = "添加书籍笔记3条"},
        {id = "n4",  desc = "单次不间断阅读时长达1h"},
        {id = "n5",  desc = "心情值达100%"},
        {id = "n6",  desc = "喂养进度增加5%"},
        {id = "n7",  desc = "使用咖啡唤醒书一次"},
        {id = "n8",  desc = "抚摸书5次"},
        {id = "n9",  desc = "使用一次逗书棒"},
        {id = "n10", desc = "保持今日心情值≥50%的时间≥14h"},
        {id = "n11", desc = "完成一次测验"},
    },
    rare = {
        {id = "r1",  desc = "今日阅读时长达3h"},
        {id = "r2",  desc = "添加书籍笔记5条"},
        {id = "r3",  desc = "单次不间断阅读时长达2h"},
        {id = "r4",  desc = "触发书际关系一次"},
        {id = "r5",  desc = "清理一次碎纸屑"},
        {id = "r6",  desc = "喂养进度增加7%"},
        {id = "r7",  desc = "抚摸书十次"},
        {id = "r8",  desc = "使用一次四叶草并成功触发一次任意事件"},
        {id = "r9",  desc = "一日投喂棉花糖数量≥5"},
        {id = "r10", desc = "一日投喂饼干数量≥5"},
        {id = "r11", desc = "完成一次测验并获得满分"},
    },
    special = {
        {id = "s1", desc = "坚持一日不投喂你的书"},
        {id = "s2", desc = "坚持一日不抚摸你的书"},
        {id = "s3", desc = "单次不间断阅读达到5h"},
        {id = "s4", desc = "读完一本书"},
        {id = "s5", desc = "添加书籍标注50条"},
        {id = "s6", desc = "使用咖啡将书的今日两次睡眠皆打断"},
        {id = "s7", desc = "在19:00至22:00之间阅读1h"},
        {id = "s8", desc = "在24:00-3:00之间阅读1h"},
    },
    luck = {
        {id = "l1", desc = "今日阅读时长达1分钟"},
        {id = "l2", desc = "今日阅读页数达1页"},
        {id = "l3", desc = "抚摸书一次"},
        {id = "l4", desc = "查看图鉴一次"},
        {id = "l5", desc = "不强制唤醒书的睡眠至少一次"},
    },
}

-- 每日任务分类中文标注
local DAILY_CAT_NAMES = {normal = "普通", rare = "稀有", special = "特殊", luck = "好运"}

-- 特殊任务奖励（纪念品）
local SPECIAL_TASK_REWARDS = {
    s1 = {key = "m_military_uniform", name = "军训服", intro = "来自特殊任务奖励。百万小书，穿上军装，随我出征！"},
    s2 = {key = "m_book_airplane_ear", name = "书的飞机耳", intro = "来自特殊任务奖励。能忍住一天不摸书的人是戒过毒吧？！"},
    s3 = {key = "m_prefrontal", name = "大脑前额叶", intro = "来自特殊任务奖励。能够帮助人类和书类有效集中专注力。"},
    s4 = {key = "m_fast_eye", name = "一目十行中的一目", intro = "来自特殊任务奖励。使用后可大幅提升阅读速度，每日一本，一年就是三百六十五本！"},
    s5 = {key = "m_giant_pencil", name = "巨型铅笔", intro = "来自特殊任务奖励。划线狂人不能离开之物，可擦掉，不伤书。"},
    s6 = {key = "m_book_bible", name = "熬书宝典", intro = "来自特殊任务奖励。人类剥夺书籍睡觉权，人坏。"},
    s7 = {key = "m_petit_bourgeois", name = "浪漫的小资生活", intro = "来自特殊任务奖励。今天晚上我们一起读书吧？"},
    s8 = {key = "m_spring_night", name = "春风沉醉的晚上", intro = "来自特殊任务奖励。春风和夜晚，或许是我们最最后的资产。"},
}

-- 好运任务奖励（纯送钱）
local LUCK_TASK_REWARDS = {
    l1 = {type = "item", key = "cotton", name = "棉花糖", count = 10},
    l2 = {type = "item", key = "biscuit", name = "饼干", count = 10},
    l3 = {type = "item", key = "toy", name = "逗书棒", count = 8},
    l4 = {type = "points", points = 20},
    l5 = {type = "item", key = "coffee", name = "咖啡", count = 3},
}

-- ========== V8 长期任务数据 ==========

-- 长期任务：targets 为前几阶段目标，之后按 step 递增上不封顶
-- reward: 每阶段奖励积分
-- namef: 根据阶段目标生成任务名
local LONG_TASKS = {
    {id = 1, reward = 1, step = 10, targets = {1, 5, 10, 20},
        namef = function(t) return string.format("读完%d本书", t) end,
        prog = function(self) return #self:_readFinishedBooks() end},
    {id = 2, reward = 2, step = 100, targets = {10, 30, 50, 70, 100},
        namef = function(t) return string.format("累计阅读%dh", t) end,
        prog = function(self) return math.floor((self:_readLongStat().read_seconds or 0) / 3600) end},
    {id = 3, reward = 1, step = 5, targets = {1, 3, 5, 10},
        namef = function(t) return string.format("连续阅读%d天", t) end,
        prog = function(self) return self:_readStreakDays() end},
    {id = 4, reward = 3, step = 2, targets = {1, 3, 5},
        namef = function(t) return string.format("翻开%d本书", t) end,
        prog = function(self) return #self:_readCollection() end},
    {id = 5, reward = 3, step = 3, targets = {1, 3, 5},
        namef = function(t) return string.format("阅读%d本≥2000页的书籍", t) end,
        prog = function(self) return self:_readLongStat().big_books or 0 end},
    {id = 6, reward = 1, step = 3, targets = {1, 4, 7, 10},
        namef = function(t) return string.format("遇见%d个陌生人", t) end,
        prog = function(self) return #self:_readLongMetStrangers() end},
    {id = 7, reward = 1, step = 5, targets = {1, 5},
        namef = function(t) return string.format("掉落书签%d次", t) end,
        prog = function(self) return self:_readLongStat().bookmark or 0 end},
    {id = 8, reward = 1, step = 3, targets = {1, 3, 5, 7, 10},
        namef = function(t) return string.format("掉进巴别图书馆%d次", t) end,
        prog = function(self) return self:_readLongStat().babel or 0 end},
    {id = 9, reward = 1, step = 1, targets = {1, 2, 3},
        namef = function(t) return string.format("触发特殊事件%d次", t) end,
        prog = function(self) return self:_readLongStat().special or 0 end},
    -- 10: 用户自确认式任务（定语池轮换，去重，轮完重复）
    {id = 10, reward = 2, confirm = true,
        namef = function(desc) return "阅读1本" .. desc .. "的作品" end},
}

-- 长期任务10定语池（已去重）
local CONFIRM_POOL = {
    "安吉拉·卡特", "马尔克斯", "黎紫书", "推理类型", "波拉尼奥", "国内", "三岛由纪夫",
    "约翰·欧文", "卡尔维诺", "冯古内特", "萨拉马戈", "石黑一雄", "詹姆斯·凯恩", "纳博科夫",
    "科幻类型", "玛格丽特·杜拉斯", "陀思妥耶夫斯基", "福克纳", "托妮·莫里森", "J·M·库切",
    "王安忆", "V·S·奈保尔", "略萨", "富恩斯特", "帕慕克", "科普类型", "实用类型",
    "女性主义类型", "张爱玲", "莫言", "村上春树", "本雅明", "童话类型", "历史类型",
    "社会学研究类型", "哲学类型", "文化研究类型", "理想国出品", "伍尔夫", "传记类型",
    "虚构类型", "纪实类型", "回忆录类型", "访谈类型", "电影相关", "音乐相关", "美术相关",
    "野望Book出品", "写作指导类型", "意识流类型", "诗歌类型", "加拿大", "美国", "非洲地区",
    "男性", "女性", "非二元性别写作者", "跨性别写作者", "戏剧类型", "绘本类型",
    "日记等私人写作类型", "跨界写作者", "拉丁美洲地区", "荷兰", "老挝", "韩国", "日本",
    "西班牙", "王小波", "北欧地区", "俄罗斯", "阿富汗", "印度", "卢森堡", "阿尔及利亚",
    "尼日利亚", "中非", "反乌托邦类型", "智利", "澳大利亚", "新西兰", "白先勇",
    "文本细读类型", "文学评论类型", "短篇小说", "中篇小说类型", "长篇小说类型",
    "惊悚悬疑类型", "斯蒂芬·金", "埃莱娜·费兰特",
}

local FALLBACK_QUOTES = {
    "你已经完成了一段专注阅读。",
    "今天的累计阅读时间正在增加。",
    "继续保持现在的节奏。",
}

local FALLBACK_BOOK_DATA = {
    { title = "未知之书", author = "神秘作者", quote = "每一本书都是一个等待被打开的世界。" },
}

local FALLBACK_DIALOGUE_DATA = {
    specific = {},
    normal = { "书在静静等待。", "翻翻我吧。" },
}

-- ========== 工具函数 ==========

-- 居中包装 widget（必须在所有使用它的函数之前定义）
local function centerIn(widget, width)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = widget:getSize().h },
        widget,
    }
end

local function todayKey()
    return os.date("%Y-%m-%d")
end

local function settingKey(name)
    return SETTINGS_PREFIX .. name
end

local function secondsToText(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%d 小时 %d 分钟", hours, minutes)
    end
    return string.format("%d 分钟", minutes)
end

local function isMilestone(minute)
    for _, milestone in ipairs(FIRST_MILESTONES) do
        if minute == milestone then
            return true
        end
    end
    return minute > 60 and ((minute - 60) % AFTER_60_INTERVAL == 0)
end

local function crossedMilestone(old_minute, new_minute)
    local result = nil
    for _, m in ipairs(FIRST_MILESTONES) do
        if m > old_minute and m <= new_minute then
            result = m
        end
    end
    if new_minute > 60 then
        local m = 60 + AFTER_60_INTERVAL
        while m <= new_minute do
            if m > old_minute then
                result = m
            end
            m = m + AFTER_60_INTERVAL
        end
    end
    return result
end

-- ========== V1 数据方法 ==========

function FocusFeedback:_readToday()
    local date = G_reader_settings:readSetting(settingKey("date"), todayKey())
    local today = todayKey()
    if date ~= today then
        G_reader_settings:saveSetting(settingKey("date"), today)
        G_reader_settings:saveSetting(settingKey("today_seconds"), 0)
        G_reader_settings:saveSetting(settingKey("last_notified_minute"), 0)
        return today, 0, 0
    end
    local seconds = G_reader_settings:readSetting(settingKey("today_seconds"), 0) or 0
    local last_notified = G_reader_settings:readSetting(settingKey("last_notified_minute"), 0) or 0
    return date, seconds, last_notified
end

function FocusFeedback:_saveToday(seconds, last_notified)
    G_reader_settings:saveSetting(settingKey("date"), todayKey())
    G_reader_settings:saveSetting(settingKey("today_seconds"), math.max(0, math.floor(seconds or 0)))
    if last_notified then
        G_reader_settings:saveSetting(settingKey("last_notified_minute"), last_notified)
    end
end

function FocusFeedback:_randomQuote()
    local normal = self.quotes_normal or {}
    local rare = self.quotes_rare or {}
    if #normal == 0 and #rare == 0 then
        return FALLBACK_QUOTES[math.random(1, #FALLBACK_QUOTES)]
    end
    local pool
    if #rare == 0 then
        pool = normal
    elseif #normal == 0 then
        pool = rare
    else
        if math.random() < 0.85 then
            pool = normal
        else
            pool = rare
        end
    end
    local quote
    for _ = 1, 5 do
        quote = pool[math.random(1, #pool)]
        if quote ~= self.last_quote then
            break
        end
    end
    self.last_quote = quote
    return quote
end

function FocusFeedback:_loadSentencePool()
    local ok, source = pcall(function()
        return debug.getinfo(1, "S").source
    end)
    if not ok or type(source) ~= "string" then
        self.quotes_normal = FALLBACK_QUOTES
        self.quotes_rare = {}
        return
    end
    local path = source:gsub("^@", "")
    local dir = path:match("^(.*[/\\])")
    if not dir then
        self.quotes_normal = FALLBACK_QUOTES
        self.quotes_rare = {}
        return
    end
    self.plugin_dir = dir

    local pool_path = dir .. "sentence_pool.lua"
    local ok_pool, pool = pcall(dofile, pool_path)
    if ok_pool and type(pool) == "table" then
        if pool.normal and pool.rare then
            self.quotes_normal = pool.normal
            self.quotes_rare = pool.rare
        elseif #pool > 0 then
            self.quotes_normal = pool
            self.quotes_rare = {}
        else
            self.quotes_normal = FALLBACK_QUOTES
            self.quotes_rare = {}
        end
    else
        self.quotes_normal = FALLBACK_QUOTES
        self.quotes_rare = {}
    end

    -- 加载 V2 数据
    self:_loadV2Data()
    -- 加载 V5 数据
    self:_loadV5Data()
end

-- ========== V2 数据加载 ==========

function FocusFeedback:_loadV2Data()
    if not self.plugin_dir then return end

    local ok_book, book_data = pcall(dofile, self.plugin_dir .. "book_data.lua")
    if ok_book and type(book_data) == "table" and #book_data > 0 then
        self.book_data = book_data
    else
        self.book_data = FALLBACK_BOOK_DATA
    end

    local ok_dia, dia_data = pcall(dofile, self.plugin_dir .. "dialogue_data.lua")
    if ok_dia and type(dia_data) == "table" then
        self.dialogue_data = dia_data
    else
        self.dialogue_data = FALLBACK_DIALOGUE_DATA
    end
end

-- ========== V2 状态读写 ==========

function FocusFeedback:_readAdopted()
    return G_reader_settings:isTrue(settingKey("v2_adopted"))
end

function FocusFeedback:_saveAdopted(val)
    G_reader_settings:saveSetting(settingKey("v2_adopted"), val and true or false)
end

function FocusFeedback:_readBookIndex()
    return G_reader_settings:readSetting(settingKey("v2_book_index"), 0) or 0
end

function FocusFeedback:_saveBookIndex(idx)
    G_reader_settings:saveSetting(settingKey("v2_book_index"), idx)
end

function FocusFeedback:_readNickname()
    return G_reader_settings:readSetting(settingKey("v2_nickname"), "") or ""
end

function FocusFeedback:_saveNickname(name)
    G_reader_settings:saveSetting(settingKey("v2_nickname"), name or "")
end

function FocusFeedback:_readProgress()
    return G_reader_settings:readSetting(settingKey("v2_progress"), 0) or 0
end

function FocusFeedback:_saveProgress(val)
    G_reader_settings:saveSetting(settingKey("v2_progress"), math.max(0, val or 0))
end

function FocusFeedback:_readFirstFeed()
    return G_reader_settings:isTrue(settingKey("v2_first_feed"))
end

function FocusFeedback:_saveFirstFeed(val)
    G_reader_settings:saveSetting(settingKey("v2_first_feed"), val and true or false)
end

function FocusFeedback:_readLastFeedTime()
    return G_reader_settings:readSetting(settingKey("v2_last_feed_time"), 0) or 0
end

function FocusFeedback:_saveLastFeedTime(t)
    G_reader_settings:saveSetting(settingKey("v2_last_feed_time"), t or 0)
end

function FocusFeedback:_readLastReadTime()
    return G_reader_settings:readSetting(settingKey("v2_last_read_time"), 0) or 0
end

function FocusFeedback:_saveLastReadTime(t)
    G_reader_settings:saveSetting(settingKey("v2_last_read_time"), t or 0)
end

function FocusFeedback:_readConsecutive()
    local t = G_reader_settings:readSetting(settingKey("v2_consecutive"), {}) or {}
    return { type = t.type, count = t.count or 0 }
end

function FocusFeedback:_saveConsecutive(c)
    G_reader_settings:saveSetting(settingKey("v2_consecutive"), { type = c.type, count = c.count })
end

function FocusFeedback:_readCollection()
    return G_reader_settings:readSetting(settingKey("v2_collection"), {}) or {}
end

function FocusFeedback:_saveCollection(c)
    G_reader_settings:saveSetting(settingKey("v2_collection"), c or {})
end

function FocusFeedback:_readProgressMilestones()
    return G_reader_settings:readSetting(settingKey("v2_progress_ms"), {}) or {}
end

function FocusFeedback:_saveProgressMilestones(ms)
    G_reader_settings:saveSetting(settingKey("v2_progress_ms"), ms or {})
end

function FocusFeedback:_readReadTrigger(key)
    return G_reader_settings:readSetting(settingKey("v2_" .. key .. "_date"), "") or ""
end

function FocusFeedback:_saveReadTrigger(key, date)
    G_reader_settings:saveSetting(settingKey("v2_" .. key .. "_date"), date)
end

-- ========== V4 数据读写方法 ==========

-- 积分
function FocusFeedback:_readPoints()
    return G_reader_settings:readSetting(settingKey("v4_points"), 0) or 0
end
function FocusFeedback:_savePoints(p)
    G_reader_settings:saveSetting(settingKey("v4_points"), math.max(0, math.floor(p or 0)))
end

-- 库存 {cotton=N, biscuit=N, wastebasket=N, toy=N}
function FocusFeedback:_readInventory()
    return G_reader_settings:readSetting(settingKey("v4_inventory"), {}) or {}
end
function FocusFeedback:_saveInventory(inv)
    G_reader_settings:saveSetting(settingKey("v4_inventory"), inv or {})
end

-- 心情值 0-100
function FocusFeedback:_readMood()
    return G_reader_settings:readSetting(settingKey("v4_mood"), 50) or 50
end
function FocusFeedback:_saveMood(m)
    m = math.max(MOOD_MIN, math.min(100, m or 50))
    local now = os.time()
    local stat = self:_getDailyStat()

    -- V11: 累计心情≥50%的时长（每日任务 n10）
    local prev_mood = self:_readMood()
    local last_accum = G_reader_settings:readSetting(settingKey("v8_mood_last_accum"), 0) or 0
    if last_accum > 0 then
        local t = os.date("*t", now)
        local today_midnight = os.time({year=t.year, month=t.month, day=t.day, hour=0})
        local start_ts = math.max(last_accum, today_midnight)
        local elapsed = now - start_ts
        if elapsed > 0 and prev_mood >= 50 then
            stat.mood_above_50_secs = (stat.mood_above_50_secs or 0) + elapsed
        end
    end
    G_reader_settings:saveSetting(settingKey("v8_mood_last_accum"), now)

    G_reader_settings:saveSetting(settingKey("v4_mood"), m)
    -- V8: 记录当日心情极值（每日任务 n5/n10 判定）
    stat.mood_min = math.min(stat.mood_min or m, m)
    stat.mood_max = math.max(stat.mood_max or m, m)
    self:_saveDailyStat(stat)
end

-- 心情低值计时（用于弃养判定）
function FocusFeedback:_readMoodLowStart()
    return G_reader_settings:readSetting(settingKey("v4_mood_low_start"), 0) or 0
end
function FocusFeedback:_saveMoodLowStart(ts)
    G_reader_settings:saveSetting(settingKey("v4_mood_low_start"), ts or 0)
end

-- 上次心情更新时间
function FocusFeedback:_readLastMoodUpdate()
    return G_reader_settings:readSetting(settingKey("v4_mood_update"), 0) or 0
end
function FocusFeedback:_saveLastMoodUpdate(ts)
    G_reader_settings:saveSetting(settingKey("v4_mood_update"), ts or 0)
end

-- 睡觉状态 {type="deep"/"nap"/nil, reading_at_start=N, deep_date="YYYY-MM-DD", nap_date="YYYY-MM-DD"}
function FocusFeedback:_readSleepState()
    return G_reader_settings:readSetting(settingKey("v4_sleep"), {}) or {}
end
function FocusFeedback:_saveSleepState(s)
    G_reader_settings:saveSetting(settingKey("v4_sleep"), s or {})
end

-- 碎纸屑状态 {active=bool, trigger_ts=N, last_trigger_date="YYYY-MM-DD"}
function FocusFeedback:_readScrapsState()
    return G_reader_settings:readSetting(settingKey("v4_scraps"), {}) or {}
end
function FocusFeedback:_saveScrapsState(s)
    G_reader_settings:saveSetting(settingKey("v4_scraps"), s or {})
end

-- 抚摸连击 {count=N, last_ts=N, streak3_end=N, streak10_end=N}
function FocusFeedback:_readPetStreak()
    return G_reader_settings:readSetting(settingKey("v4_pet_streak"), {}) or {}
end
function FocusFeedback:_savePetStreak(s)
    G_reader_settings:saveSetting(settingKey("v4_pet_streak"), s or {})
end

-- 连续阅读天数
function FocusFeedback:_readStreakDays()
    return G_reader_settings:readSetting(settingKey("v4_streak_days"), 0) or 0
end
function FocusFeedback:_saveStreakDays(n)
    G_reader_settings:saveSetting(settingKey("v4_streak_days"), n or 0)
end
function FocusFeedback:_readLastReadDate()
    return G_reader_settings:readSetting(settingKey("v4_last_read_date"), "") or ""
end
function FocusFeedback:_saveLastReadDate(d)
    G_reader_settings:saveSetting(settingKey("v4_last_read_date"), d or "")
end

-- 休眠时间戳（用于心情衰减）
function FocusFeedback:_readSuspendTs()
    return G_reader_settings:readSetting(settingKey("v4_suspend_ts"), 0) or 0
end
function FocusFeedback:_saveSuspendTs(ts)
    G_reader_settings:saveSetting(settingKey("v4_suspend_ts"), ts or 0)
end

-- ========== V5 数据读写 ==========

-- 事件日志（领养期间的时间线）
function FocusFeedback:_readEventLog()
    return G_reader_settings:readSetting(settingKey("v5_event_log"), {}) or {}
end
function FocusFeedback:_saveEventLog(log)
    G_reader_settings:saveSetting(settingKey("v5_event_log"), log or {})
end
function FocusFeedback:_addEventLog(entry_type, detail)
    local log = self:_readEventLog()
    table.insert(log, {date = todayKey(), type = entry_type, detail = detail})
    self:_saveEventLog(log)
end

-- 食物消耗计数
function FocusFeedback:_readFoodConsumed()
    local t = G_reader_settings:readSetting(settingKey("v5_food_consumed"), {}) or {}
    return {cotton = t.cotton or 0, biscuit = t.biscuit or 0}
end
function FocusFeedback:_saveFoodConsumed(t)
    G_reader_settings:saveSetting(settingKey("v5_food_consumed"), t or {})
end

-- 领养期间阅读书单（有序数组，用于日记"一起读了《xxx》《xxx》《xxx》等N本书籍"）
function FocusFeedback:_readAdoptionBooks()
    return G_reader_settings:readSetting(settingKey("v5_adoption_books"), {}) or {}
end
function FocusFeedback:_saveAdoptionBooks(books)
    G_reader_settings:saveSetting(settingKey("v5_adoption_books"), books or {})
end
function FocusFeedback:_addAdoptionBook(title)
    if not title or title == "" then return end
    local books = self:_readAdoptionBooks()
    -- 有序数组：检查是否已存在
    for _, t in ipairs(books) do
        if t == title then return end
    end
    table.insert(books, title)
    self:_saveAdoptionBooks(books)
end
function FocusFeedback:_countAdoptionBooks()
    local books = self:_readAdoptionBooks()
    return #books
end

-- 事件去重历史 {event_key = count}
function FocusFeedback:_readEventHistory()
    return G_reader_settings:readSetting(settingKey("v5_event_history"), {}) or {}
end
function FocusFeedback:_saveEventHistory(h)
    G_reader_settings:saveSetting(settingKey("v5_event_history"), h or {})
end
function FocusFeedback:_recordEvent(event_key)
    local h = self:_readEventHistory()
    h[event_key] = (h[event_key] or 0) + 1
    self:_saveEventHistory(h)

    -- V8: 长期任务全局累计（不受弃养影响）
    local lstat = self:_readLongStat()
    if event_key == "bookmark" then
        lstat.bookmark = (lstat.bookmark or 0) + 1
    elseif event_key == "babel" then
        lstat.babel = (lstat.babel or 0) + 1
    end
    -- 特殊事件（6个）
    local special_keys = {wish_willow = true, macondo = true, oppo_a5 = true,
        robber = true, jackpot = true, big_result = true}
    if special_keys[event_key] then
        lstat.special = (lstat.special or 0) + 1
    end
    self:_saveLongStat(lstat)

    -- V8: 今日书际关系计数（每日任务 r4 判定）
    if event_key == "book_friend" then
        local stat = self:_getDailyStat()
        stat.book_friend = (stat.book_friend or 0) + 1
        self:_saveDailyStat(stat)
    end

    -- V8: 四叶草生效期间触发事件（每日任务 r8 判定）
    if self:_isCloverActive() then
        local stat = self:_getDailyStat()
        stat.clover_event = (stat.clover_event or 0) + 1
        self:_saveDailyStat(stat)
    end
end
function FocusFeedback:_eventTriggeredCount(event_key)
    local h = self:_readEventHistory()
    return h[event_key] or 0
end

-- 随机事件开关 {bookmark=true, stranger=true, ...}
function FocusFeedback:_readEventToggles()
    local t = G_reader_settings:readSetting(settingKey("v5_event_toggles"), nil)
    if not t then
        -- 默认全部开启
        t = {bookmark=true, stranger=true, book_friend=true, babel=true, fly_away=true, special=true, inbox=true}
        self:_saveEventToggles(t)
    end
    return t
end
function FocusFeedback:_saveEventToggles(t)
    G_reader_settings:saveSetting(settingKey("v5_event_toggles"), t or {})
end

-- 每日特殊事件检查标记
function FocusFeedback:_readDailyCheck()
    return G_reader_settings:readSetting(settingKey("v5_daily_check"), "") or ""
end
function FocusFeedback:_saveDailyCheck(d)
    G_reader_settings:saveSetting(settingKey("v5_daily_check"), d or "")
end

-- 许愿柳永久标记
function FocusFeedback:_readWishWillowDone()
    return G_reader_settings:isTrue(settingKey("v5_wish_willow_done"))
end
function FocusFeedback:_saveWishWillowDone()
    G_reader_settings:saveSetting(settingKey("v5_wish_willow_done"), true)
end

-- 上次随机事件触发时间戳
function FocusFeedback:_readLastEventTs()
    return G_reader_settings:readSetting(settingKey("v5_last_event_ts"), 0) or 0
end
function FocusFeedback:_saveLastEventTs(ts)
    G_reader_settings:saveSetting(settingKey("v5_last_event_ts"), ts or 0)
end

-- 上次睡觉触发时间戳（用于最小间隔）
function FocusFeedback:_readLastSleepTs()
    return G_reader_settings:readSetting(settingKey("v5_last_sleep_ts"), 0) or 0
end
function FocusFeedback:_saveLastSleepTs(ts)
    G_reader_settings:saveSetting(settingKey("v5_last_sleep_ts"), ts or 0)
end

-- ========== V6 数据读写 ==========

-- 宠物 {cat=bool, rabbit=bool}
-- 猫和兔可各养一只，都只跟一本书，书翻开/弃养后消失
function FocusFeedback:_readPet()
    local pet = G_reader_settings:readSetting(settingKey("v6_pet"), {}) or {}
    -- 兼容旧结构 {type="cat"/"rabbit"}
    if pet.type == "cat" then
        pet.cat = true
        pet.type = nil
    elseif pet.type == "rabbit" then
        pet.rabbit = true
        pet.type = nil
    end
    return pet
end
function FocusFeedback:_savePet(pet)
    G_reader_settings:saveSetting(settingKey("v6_pet"), pet or {})
end

-- V7: 已遇见的陌生人列表（一本书内不重复遇见同一个陌生人）
function FocusFeedback:_readMetStrangers()
    return G_reader_settings:readSetting(settingKey("v6_met_strangers"), {}) or {}
end
function FocusFeedback:_saveMetStrangers(list)
    G_reader_settings:saveSetting(settingKey("v6_met_strangers"), list or {})
end

-- V7: 节日陌生人每日触发记录
function FocusFeedback:_readHolidayCheck()
    return G_reader_settings:readSetting(settingKey("v7_holiday_check"), "") or ""
end
function FocusFeedback:_saveHolidayCheck(d)
    G_reader_settings:saveSetting(settingKey("v7_holiday_check"), d or "")
end

-- 四叶草到期时间戳（0 = 未生效）
function FocusFeedback:_readCloverExpire()
    return G_reader_settings:readSetting(settingKey("v6_clover_expire"), 0) or 0
end
function FocusFeedback:_saveCloverExpire(ts)
    G_reader_settings:saveSetting(settingKey("v6_clover_expire"), ts or 0)
end
-- 四叶草是否生效中
function FocusFeedback:_isCloverActive()
    return os.time() < self:_readCloverExpire()
end

-- ===================== V8 每日任务 =====================

-- 今日日期 key（YYYY-MM-DD）
function FocusFeedback:_todayKey()
    return os.date("%Y-%m-%d")
end

-- 当日统计表（自动处理跨日轮换：昨日备份到 prev，今日清零重建）
function FocusFeedback:_getDailyStat()
    local stat = G_reader_settings:readSetting(settingKey("v8_daily_stat"), nil)
    local today = self:_todayKey()
    if not stat or stat.date ~= today then
        if stat and stat.date and stat.date ~= "" then
            -- V8: 记录当日最终进度（补领昨日喂养进度任务时用昨日数据判定）
            stat.feed_end = stat.feed_end or self:_readProgress()
            G_reader_settings:saveSetting(settingKey("v8_daily_stat_prev"), stat)
        end
        stat = {
            date = today,
            notes = 0,           -- 添加书籍笔记/标注数
            pets = 0,            -- 抚摸次数
            cotton = 0,          -- 投喂棉花糖数
            biscuit = 0,         -- 投喂饼干数
            scraps = 0,          -- 清理碎纸屑次数
            coffee = 0,          -- 使用咖啡唤醒次数
            toy = 0,             -- 使用逗书棒次数
            clover = 0,          -- 使用四叶草次数
            clover_event = 0,    -- 四叶草生效期间触发的事件数
            book_friend = 0,     -- 触发书际关系次数
            feed_start = self:_readProgress(),  -- 当日初始进度
            mood_min = self:_readMood(),        -- 当日最低心情
            mood_max = self:_readMood(),        -- 当日最高心情
            mood_above_50_secs = 0,  -- V11: 当日心情≥50%的累计秒数
            session_cur = 0,     -- 当前进行中的单次不间断阅读秒
            session_max = 0,     -- 当日最长单次不间断阅读秒
            pages = 0,           -- 今日翻页数
            collection = 0,      -- 查看图鉴次数
            sleep_natural = false, -- 是否有自然醒（非强制唤醒）
            wake_coffee = 0,     -- 今日用咖啡打断睡眠次数
            total_sleep = 0,     -- 今日入睡次数
            h19_22 = 0,          -- 19:00-22:00 阅读秒
            h0_3 = 0,            -- 0:00-3:00 阅读秒
            finish = 0,          -- 今日读完书数
            quiz = 0,            -- V14: 今日完成测验次数
            quiz_perfect = 0,    -- V14: 今日满分测验次数（已答题全部答对）
        }
        G_reader_settings:saveSetting(settingKey("v8_daily_stat"), stat)
    end
    return stat
end
function FocusFeedback:_saveDailyStat(stat)
    G_reader_settings:saveSetting(settingKey("v8_daily_stat"), stat or {})
end

-- 昨日统计（跨日判定用）
function FocusFeedback:_readPrevDailyStat()
    return G_reader_settings:readSetting(settingKey("v8_daily_stat_prev"), nil) or {}
end

-- 当前每日任务
function FocusFeedback:_readDailyTask()
    return G_reader_settings:readSetting(settingKey("v8_daily_task"), nil)
end
function FocusFeedback:_saveDailyTask(t)
    G_reader_settings:saveSetting(settingKey("v8_daily_task"), t or {})
end

-- 从池中抽取一个每日任务
function FocusFeedback:_generateDailyTask(date)
    -- V14 摸鱼模式：不生成每日任务（仅保留长期挑战）
    if self:_getActiveMode() == MODE_SLACK then
        return
    end
    local r = math.random()
    local cat
    if r < 1 / 60 then
        cat = "luck"              -- 约1.67%（60天一次）
    elseif r < 1 / 60 + 1 / 20 then
        cat = "special"           -- 约5%（20天一次）
    elseif r < 1 / 60 + 1 / 20 + (1 - 1 / 60 - 1 / 20) * 0.25 then
        cat = "rare"              -- 剩余约1/4（约23.33%，普通约1/3）
    else
        cat = "normal"            -- 约70%
    end
    local pool = DAILY_TASKS[cat]
    local def = pool[math.random(1, #pool)]
    self:_saveDailyTask({date = date, cat = cat, id = def.id, claimed = false})
end

-- 跨日处理：仅保留「昨天」完成未领取的任务供补领，其余一律刷新今日新任务
function FocusFeedback:_updateDailyTask(force_refresh)
    local t = self:_readDailyTask()
    local today = self:_todayKey()
    if not t or not t.date or t.date == "" then
        self:_generateDailyTask(today)
        return
    end
    if t.date ~= today then
        local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
        local prev_done = false
        if t.date == yesterday then
            prev_done = self:_isDailyTaskDone(t, self:_readPrevDailyStat(), t.date)
        end
        if not force_refresh and prev_done and not t.claimed then
            -- 保留昨日已完成未领取的任务，等待补领后刷新
            return
        end
        self:_generateDailyTask(today)
    end
end

-- 每日任务完成判定（stat 为任务执行日的统计，stat_date 为执行日）
function FocusFeedback:_isDailyTaskDone(t, stat, stat_date)
    if not t or not stat then return false end
    stat_date = stat_date or t.date
    local today = self:_todayKey()
    local id = t.id
    local function sec(h) return h * 3600 end
    local _, today_seconds = self:_readToday()
    -- 补领昨日任务时用昨日记录的阅读秒数，否则用今日实时秒数
    local reading_secs
    if stat_date < today then
        reading_secs = stat.reading_seconds or 0
    else
        reading_secs = today_seconds
    end
    if id == "n1" then return reading_secs >= sec(1) end
    if id == "n2" then return reading_secs >= sec(2) end
    if id == "n3" then return (stat.notes or 0) >= 3 end
    if id == "n4" then return (stat.session_max or 0) >= sec(1) end
    if id == "n5" then return (stat.mood_max or 0) >= 100 end
    if id == "n6" then
        -- V8: 补领昨日任务时用昨日记录的 feed_end，否则用当前进度
        local end_prog = stat.feed_end or self:_readProgress()
        local gain = end_prog - (stat.feed_start or end_prog)
        return gain >= 5
    end
    if id == "n7" then return (stat.coffee or 0) >= 1 end
    if id == "n8" then return (stat.pets or 0) >= 5 end
    if id == "n9" then return (stat.toy or 0) >= 1 end
    if id == "n10" then
        -- V11: 心情≥50%的累计时长≥14小时
        local now = os.time()
        local last_accum = G_reader_settings:readSetting(settingKey("v8_mood_last_accum"), 0) or 0
        local extra = 0
        if last_accum > 0 and self:_readMood() >= 50 then
            local t = os.date("*t", now)
            local today_midnight = os.time({year=t.year, month=t.month, day=t.day, hour=0})
            local start_ts = math.max(last_accum, today_midnight)
            extra = now - start_ts
        end
        return ((stat.mood_above_50_secs or 0) + extra) >= 14 * 3600
    end
    if id == "r1" then return reading_secs >= sec(3) end
    if id == "r2" then return (stat.notes or 0) >= 5 end
    if id == "r3" then return (stat.session_max or 0) >= sec(2) end
    if id == "r4" then return (stat.book_friend or 0) >= 1 end
    if id == "r5" then return (stat.scraps or 0) >= 1 end
    if id == "r6" then
        -- V8: 补领昨日任务时用昨日记录的 feed_end，否则用当前进度
        local end_prog = stat.feed_end or self:_readProgress()
        local gain = end_prog - (stat.feed_start or end_prog)
        return gain >= 7
    end
    if id == "r7" then return (stat.pets or 0) >= 10 end
    if id == "r8" then return (stat.clover or 0) >= 1 and (stat.clover_event or 0) >= 1 end
    if id == "r9" then return (stat.cotton or 0) >= 5 end
    if id == "r10" then return (stat.biscuit or 0) >= 5 end
    if id == "s1" then
        -- 坚持一日不投喂：当天投喂数为0，且这一天已经过完
        return stat_date < today and (stat.cotton or 0) + (stat.biscuit or 0) == 0
    end
    if id == "s2" then
        -- 坚持一日不抚摸：当天抚摸数为0，且这一天已经过完
        return stat_date < today and (stat.pets or 0) == 0
    end
    if id == "s3" then return (stat.session_max or 0) >= sec(5) end
    if id == "s4" then return (stat.finish or 0) >= 1 end
    if id == "s5" then return (stat.notes or 0) >= 50 end
    if id == "s6" then
        return (stat.total_sleep or 0) >= 2 and (stat.wake_coffee or 0) >= (stat.total_sleep or 0)
    end
    if id == "s7" then return (stat.h19_22 or 0) >= sec(1) end
    if id == "s8" then return (stat.h0_3 or 0) >= sec(1) end
    if id == "l1" then return reading_secs >= 60 end
    if id == "l2" then return (stat.pages or 0) >= 1 end
    if id == "l3" then return (stat.pets or 0) >= 1 end
    if id == "l4" then return (stat.collection or 0) >= 1 end
    if id == "l5" then return stat.sleep_natural == true end
    if id == "n11" then return (stat.quiz or 0) >= 1 end
    if id == "r11" then return (stat.quiz_perfect or 0) >= 1 end
    return false
end

-- 固定积分发放（任务奖励专用，不受领养状态/小猫加成影响）
function FocusFeedback:_addPoints(n)
    if not n or n <= 0 then return end
    local current = self:_readPoints()
    self:_savePoints(current + n)
    logger.info("FocusFeedback V8: points +" .. n, "total:", current + n)
end

-- 发放每日任务奖励（返回提示文本）
function FocusFeedback:_grantDailyReward(t)
    local msg
    if t.cat == "normal" then
        self:_addPoints(2)
        msg = "任务完成！积分+2"
    elseif t.cat == "rare" then
        self:_addPoints(3)
        msg = "任务完成！积分+3"
    elseif t.cat == "special" then
        local def = SPECIAL_TASK_REWARDS[t.id]
        if def then
            local inv = self:_readInventory()
            inv[def.key] = (inv[def.key] or 0) + 1
            self:_saveInventory(inv)
            msg = "任务完成！获得" .. def.name .. "×1"
        else
            self:_addPoints(3)
            msg = "任务完成！积分+3"
        end
    elseif t.cat == "luck" then
        local def = LUCK_TASK_REWARDS[t.id]
        if def and def.type == "item" then
            local inv = self:_readInventory()
            inv[def.key] = (inv[def.key] or 0) + def.count
            self:_saveInventory(inv)
            msg = "任务完成！获得" .. def.name .. "×" .. def.count
        elseif def and def.type == "points" then
            self:_addPoints(def.points)
            msg = "任务完成！积分+" .. def.points
        else
            self:_addPoints(2)
            msg = "任务完成！积分+2"
        end
    else
        self:_addPoints(2)
        msg = "任务完成！积分+2"
    end
    return msg
end

-- 每日任务弹窗
function FocusFeedback:_showDailyTaskDialog()
    -- V14 摸鱼模式：每日挑战关闭，仅保留长期挑战
    if self:_getActiveMode() == MODE_SLACK then
        self:_showMessage("摸鱼模式已关闭每日挑战。\n仅保留长期挑战。", 5)
        return
    end
    self:_updateDailyTask()
    local t = self:_readDailyTask()
    if not t or not t.date then return end
    local today = self:_todayKey()
    local stat, stat_date
    if t.date == today then
        stat = self:_getDailyStat()
        stat_date = today
    else
        stat = self:_readPrevDailyStat()
        stat_date = t.date
    end
    local done = self:_isDailyTaskDone(t, stat, stat_date)

    local dialog
    local buttons = {}
    if done and not t.claimed then
        table.insert(buttons, {
            {
                text = "领取奖励",
                callback = function()
                    UIManager:close(dialog)
                    local msg = self:_grantDailyReward(t)
                    t.claimed = true
                    self:_saveDailyTask(t)
                    self:_updateDailyTask(true)
                    self:_showMessage(msg)
                end,
            },
            {
                text = "确定",
                callback = function() UIManager:close(dialog) end,
            },
        })
    else
        table.insert(buttons, {
            {
                text = "确定",
                callback = function() UIManager:close(dialog) end,
            },
        })
    end
    -- V8: 与事件弹窗一致，自定义内容必须用 addWidget 挂载（content 构造参数会被忽略导致空白弹窗）
    dialog = ButtonDialog:new{
        title = "",
        title_align = "center",
        width = Screen:scaleBySize(560),
        buttons = buttons,
    }
    -- 精确可用宽度（与事件弹窗一致）
    local avail_w = dialog.width - 2 * (Size.border.window + Size.padding.default)
    local parts = {}

    -- 标题
    local title_w = TextWidget:new{
        text = "每日任务",
        face = Font:getFace("cfont", 26),
    }
    table.insert(parts, centerIn(title_w, avail_w))
    -- 横线（与事件弹窗一致的加载方式，避免未 require 崩溃）
    local ok_hl, HorizontalLine = pcall(require, "ui/widget/horizontal_line")
    if ok_hl and HorizontalLine then
        table.insert(parts, centerIn(HorizontalLine:new{
            width = avail_w * 0.4,
            height = Screen:scaleBySize(2),
            color = Blitbuffer.COLOR_DARK_GRAY,
        }, avail_w))
    end
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 任务内容 + 分类标注
    local def
    for _, d in ipairs(DAILY_TASKS[t.cat] or {}) do
        if d.id == t.id then def = d end
    end
    local task_text = (def and def.desc or "未知任务") .. "（" .. (DAILY_CAT_NAMES[t.cat] or "") .. "）"
    local task_w = TextWidget:new{
        text = task_text,
        face = Font:getFace("cfont", 18),
        width = avail_w * 0.9,
    }
    table.insert(parts, centerIn(task_w, avail_w))

    if done then
        table.insert(parts, VerticalSpan:new{ width = Size.padding.default })
        local state_w = TextWidget:new{
            text = t.claimed and "今日任务已完成，奖励已领取" or "已完成，可领取奖励",
            face = Font:getFace("cfont", 15),
            fgcolor = Blitbuffer.COLOR_GREEN,
        }
        table.insert(parts, centerIn(state_w, avail_w))
    end

    local content = VerticalGroup:new{ align = "center", unpack(parts) }
    content.not_focusable = true
    dialog:addWidget(content)
    UIManager:show(dialog)
end

-- ===================== V8 长期任务 =====================

-- 长期任务状态：stage=当前阶段（目标索引，从1起），claimed=已领取的阶段数
function FocusFeedback:_readLongState()
    local s = G_reader_settings:readSetting(settingKey("v8_long_state"), nil)
    if not s then
        s = {stage = {}, claimed = {}}
        for i = 1, #LONG_TASKS do
            s.stage[i] = 1
            s.claimed[i] = 0
        end
        G_reader_settings:saveSetting(settingKey("v8_long_state"), s)
    end
    return s
end
function FocusFeedback:_saveLongState(s)
    G_reader_settings:saveSetting(settingKey("v8_long_state"), s or {})
end

-- 长期任务累计统计（全局，不受弃养影响）
function FocusFeedback:_readLongStat()
    return G_reader_settings:readSetting(settingKey("v8_long_stat"), {}) or {}
end
function FocusFeedback:_saveLongStat(s)
    G_reader_settings:saveSetting(settingKey("v8_long_stat"), s or {})
end

-- 全局已遇见陌生人集合（跨书籍累计）
function FocusFeedback:_readLongMetStrangers()
    return G_reader_settings:readSetting(settingKey("v8_long_met_strangers"), {}) or {}
end
function FocusFeedback:_saveLongMetStrangers(list)
    G_reader_settings:saveSetting(settingKey("v8_long_met_strangers"), list or {})
end
function FocusFeedback:_addLongMetStranger(key)
    if not key then return end
    local list = self:_readLongMetStrangers()
    local found = false
    for _, k in ipairs(list) do
        if k == key then found = true end
    end
    if not found then
        table.insert(list, key)
        self:_saveLongMetStrangers(list)
    end
end

-- 自确认任务状态
function FocusFeedback:_readLongConfirm()
    local c = G_reader_settings:readSetting(settingKey("v8_long_confirm"), nil)
    if not c then
        c = {used = {}, current = nil}
        G_reader_settings:saveSetting(settingKey("v8_long_confirm"), c)
    end
    return c
end
function FocusFeedback:_saveLongConfirm(c)
    G_reader_settings:saveSetting(settingKey("v8_long_confirm"), c or {})
end

-- 抽取自确认任务（去重，轮完重复）
function FocusFeedback:_pickConfirmTask()
    local c = self:_readLongConfirm()
    local pool = CONFIRM_POOL
    if not c.used then c.used = {} end
    local avail = {}
    for i = 1, #pool do
        if not c.used[i] then table.insert(avail, i) end
    end
    if #avail == 0 then
        c.used = {}
        for i = 1, #pool do table.insert(avail, i) end
    end
    local pick = avail[math.random(1, #avail)]
    c.used[pick] = true
    c.current = pick
    self:_saveLongConfirm(c)
    return pool[pick]
end

-- 当前自确认任务描述（首次进入时抽取）
function FocusFeedback:_getConfirmDesc()
    local c = self:_readLongConfirm()
    if not c.current then
        return self:_pickConfirmTask()
    end
    return CONFIRM_POOL[c.current] or self:_pickConfirmTask()
end

-- 长期任务当前阶段目标（targets 前几段，之后按 step 递增）
function FocusFeedback:_longTarget(tdef, stage)
    local base = tdef.targets
    if stage <= #base then return base[stage] end
    return base[#base] + (stage - #base) * tdef.step
end

-- 长期任务当前进度（数值）
function FocusFeedback:_longProgress(tdef)
    return tdef.prog(self)
end

-- 长期任务是否可领取（当前阶段完成且未领取）
function FocusFeedback:_isLongClaimable(tdef, state)
    if tdef.confirm then
        -- 自确认任务：总是可点击确认（用户自确认）
        return true
    end
    local stage = state.stage[tdef.id] or 1
    local target = self:_longTarget(tdef, stage)
    local cur = self:_longProgress(tdef)
    return cur >= target and (state.claimed[tdef.id] or 0) < stage
end

-- 长期任务弹窗
function FocusFeedback:_showLongTaskDialog()
    local state = self:_readLongState()
    local items = {}
    local menu
    for i, tdef in ipairs(LONG_TASKS) do
        local text
        local callback
        if tdef.confirm then
            local desc = self:_getConfirmDesc()
            text = string.format("%d. %s", i, tdef.namef(desc))
            callback = function()
                local c = self:_readLongConfirm()
                local d = CONFIRM_POOL[c.current] or self:_pickConfirmTask()
                -- 二次确认（与领养命名弹窗一致：文字放 title，不用 info 参数）
                local confirm_dialog
                confirm_dialog = ButtonDialog:new{
                    title = "确认完成\n\n" .. string.format("你已完成「%s」吗？\n确认后将获得积分+%d。", tdef.namef(d), tdef.reward),
                    title_align = "center",
                    buttons = {
                        {
                            {text = "确认完成", is_enter_default = true, callback = function()
                                UIManager:close(confirm_dialog)
                                self:_addPoints(tdef.reward)
                                self:_pickConfirmTask()
                                -- 刷新长期任务列表，显示新抽取的任务
                                if menu then UIManager:close(menu) end
                                self:_showLongTaskDialog()
                                self:_showMessage("已完成「" .. d .. "」，积分+" .. tdef.reward)
                            end},
                            {text = "取消", callback = function() UIManager:close(confirm_dialog) end},
                        },
                    },
                }
                UIManager:show(confirm_dialog)
            end
        else
            local stage = state.stage[tdef.id] or 1
            local target = self:_longTarget(tdef, stage)
            local cur = self:_longProgress(tdef)
            local shown = math.min(cur, target)
            local claimable = self:_isLongClaimable(tdef, state)
            text = string.format("%d. %s（%d/%d）", i, tdef.namef(target), shown, target)
            if claimable then
                text = text .. "  ★待领取"
            end
            callback = function()
                if claimable then
                    self:_addPoints(tdef.reward)
                    state.claimed[tdef.id] = (state.claimed[tdef.id] or 0) + 1
                    state.stage[tdef.id] = (state.stage[tdef.id] or 1) + 1
                    self:_saveLongState(state)
                    -- 先关闭当前列表再重开，避免多层菜单叠加导致旧列表残留（星星提示）
                    if menu then UIManager:close(menu) end
                    self:_showLongTaskDialog()
                    self:_showMessage(string.format("任务「%s」奖励已领取，积分+%d", tdef.namef(target), tdef.reward))
                else
                    self:_showMessage(string.format("当前进度 %d/%d，继续加油！", shown, target))
                end
            end
        end
        table.insert(items, {text = text, callback = callback})
    end

    menu = Menu:new{
        title = "长期任务",
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
        show_parent = nil,
    }
    UIManager:show(menu)
end

-- V5 数据加载
function FocusFeedback:_loadV5Data()
    if not self.plugin_dir then return end
    local ok_evt, evt_data = pcall(dofile, self.plugin_dir .. "event_data.lua")
    if ok_evt and type(evt_data) == "table" then
        self.event_data = evt_data
    else
        self.event_data = nil
    end
    local ok_bm, bm_data = pcall(dofile, self.plugin_dir .. "bookmark_quotes.lua")
    if ok_bm and type(bm_data) == "table" then
        self.bookmark_quotes = bm_data
    else
        self.bookmark_quotes = {}
    end
end

-- ========== V15 书之属性系统 ==========

-- 读取当前领养期的六维属性（nil 表示尚未初始化）
function FocusFeedback:_readAttributes()
    return G_reader_settings:readSetting(settingKey("v15_attributes"), nil)
end

function FocusFeedback:_saveAttributes(attrs)
    G_reader_settings:saveSetting(settingKey("v15_attributes"), attrs or {})
end

-- 初始化属性（首次或新领养时归零）
function FocusFeedback:_initAttributes()
    local attrs = self:_readAttributes()
    if not attrs then
        attrs = {知识 = 0, 审美 = 0, 情感 = 0, 阅历 = 0, 逻辑 = 0, 辩证 = 0}
        self:_saveAttributes(attrs)
    end
    return attrs
end

-- 增加某属性数值（0-100 封顶）
function FocusFeedback:_addAttribute(attr, value)
    if not attr then return end
    local attrs = self:_initAttributes()
    attrs[attr] = math.min(100, math.max(0, (attrs[attr] or 0) + value))
    self:_saveAttributes(attrs)
end

-- 随机取一个属性（用于书签掉落/特殊事件）
function FocusFeedback:_randomAttrKey()
    return ATTR_KEYS[math.random(1, #ATTR_KEYS)]
end

-- 读取某本书（当前阅读的书）的分类
function FocusFeedback:_readBookCategory(key)
    key = key or self:_getBookKey()
    if not key then return nil end
    local all = G_reader_settings:readSetting(settingKey("v15_book_categories"), {}) or {}
    return all[key]
end

function FocusFeedback:_saveBookCategory(key, cat)
    if not key then return end
    local all = G_reader_settings:readSetting(settingKey("v15_book_categories"), {}) or {}
    all[key] = cat
    G_reader_settings:saveSetting(settingKey("v15_book_categories"), all)
end

-- 首次点开一本书时弹出分类选择
function FocusFeedback:_ensureBookCategory()
    if not self.enabled then return end
    -- 仅已领养时提示（分类影响领养书的性格）
    if not self:_readAdopted() then return end
    local key = self:_getBookKey()
    if not key then return end
    if self:_readBookCategory(key) then return end
    -- 避免重复弹窗
    if self._categorizing_key == key then return end
    self._categorizing_key = key

    -- 延迟 2 秒弹出，避免与阅读器初始化冲突导致卡住
    UIManager:scheduleIn(2, function()
        if not self.ui or not self.ui.document then
            self._categorizing_key = nil
            return end
        if not self.enabled or not self:_readAdopted() then
            self._categorizing_key = nil
            return end
        if self:_readBookCategory(key) then
            self._categorizing_key = nil
            return end
        local dialog
        local buttons = {}
        local row = {}
        for i, cat in ipairs(BOOK_CATEGORIES) do
            table.insert(row, {
                text = cat,
                callback = function()
                    self:_saveBookCategory(key, cat)
                    self._categorizing_key = nil
                    UIManager:close(dialog)
                end,
            })
            if #row == 2 then
                table.insert(buttons, row)
                row = {}
            end
        end
        if #row > 0 then
            table.insert(buttons, row)
        end
        -- 取消：本次不标，下次打开再提示
        table.insert(buttons, {
            {text = "取消", callback = function()
                self._categorizing_key = nil
                UIManager:close(dialog)
            end},
        })
        local ok, err = pcall(function()
            dialog = ButtonDialog:new{
                title = "请给本书标注类别\n\n不同类别的阅读将会影响你领养的书之性格哦！",
                title_align = "center",
                buttons = buttons,
            }
            UIManager:show(dialog)
        end)
        if not ok then
            self._categorizing_key = nil
            logger.warn("book category dialog error: " .. tostring(err))
        end
    end)
end

-- 阅读时长累计 -> 属性增长（每 1h 对应属性 +1%）
function FocusFeedback:_growAttributesFromReading(diff)
    if not self:_readAdopted() then return end
    local key = self:_getBookKey()
    if not key then return end
    local cat = self:_readBookCategory(key)
    if not cat then return end
    local attrs_list = CATEGORY_ATTRS[cat]
    if not attrs_list then return end
    local gain = (diff / 3600) * ATTR_READ_GAIN_PER_H
    if gain <= 0 then return end
    for _, attr in ipairs(attrs_list) do
        self:_addAttribute(attr, gain)
    end
end

-- 余弦相似度：用户属性向量 A 与内容标签向量 T
function FocusFeedback:_cosineSim(attrs, tags)
    if not tags or #tags == 0 then return 0 end
    local sumA2 = 0
    for _, attr in ipairs(ATTR_KEYS) do
        local a = attrs[attr] or 0
        sumA2 = sumA2 + a * a
    end
    if sumA2 <= 0 then return 0 end
    local dot = 0
    for _, tag in ipairs(tags) do
        dot = dot + (attrs[tag] or 0)
    end
    local normT = math.sqrt(#tags)
    return dot / (math.sqrt(sumA2) * normT)
end

-- 加权随机选择：weight = 1 + ATTR_WEIGHT_STRENGTH * sim
function FocusFeedback:_weightedPick(items, weight_fn)
    if #items == 0 then return nil end
    local weights = {}
    local total = 0
    for i, item in ipairs(items) do
        local w = weight_fn(item, i)
        if w < 0 then w = 0 end
        weights[i] = w
        total = total + w
    end
    if total <= 0 then
        return items[math.random(1, #items)]
    end
    local r = math.random() * total
    for i, w in ipairs(weights) do
        r = r - w
        if r <= 0 then
            return items[i]
        end
    end
    return items[#items]
end

-- 里程碑时获得积分（替换原 _awardFood）
function FocusFeedback:_awardPoints(minute)
    if not self:_readAdopted() then return end
    local mode = self:_getActiveMode()

    -- V14 摸鱼模式：里程碑积分全部为1
    if mode == MODE_SLACK then
        local cur = self:_readPoints()
        self:_savePoints(cur + 1)
        logger.info("FocusFeedback V14 slack: points +1, total:", cur + 1)
        return
    end

    -- V14 心流模式：里程碑停发，仅按单次持续阅读达标给分（30min=2,60min=3…每30min+1）
    if mode == MODE_FLOW then
        local fm = self:_readModeState()
        local fstat = self:_getDailyStat()
        local sess_min = math.floor((fstat.session_cur or 0) / 60)
        local cur_level = math.floor(sess_min / 30)
        local granted = fm.flow_awarded or 0
        if cur_level > granted then
            local gain = cur_level + 1
            fm.flow_awarded = cur_level
            self:_saveModeState(fm)
            local fcur = self:_readPoints()
            self:_savePoints(fcur + gain)
            self:_showMessage(string.format("心流满分！持续阅读%d分钟，积分+%d", sess_min, gain), 4)
        end
        return
    end

    local points
    if minute <= 60 then
        points = POINTS_BEFORE_1H
    elseif minute <= 180 then
        points = POINTS_1H_TO_3H
    elseif minute <= 300 then
        points = POINTS_3H_TO_5H
    else
        points = POINTS_AFTER_5H
    end

    -- 抽签当日效果（积分维度）：下签无积分 / 上上双倍 / 上吉·中吉每里程碑必+1 / 中下-铁饭碗必为1
    -- 注：抽签与其他模式互斥，此处 mode 只会是 DRAW 或长期共存态
    local draw_fx = self:_drawEffect()
    if draw_fx == "no_gain" then
        points = 0
    elseif draw_fx == "super_double" then
        points = points * 2
    elseif draw_fx == "all_bonus" then
        points = points + 1
    elseif draw_fx == "iron_bowl" then
        -- 中下签-公务员般的铁饭碗：里程碑积分固定为1
        points = 1
    end

    -- V14 心跳模式：猜中当日里程碑大幅加成，猜错无积分
    if mode == MODE_HEARTBEAT then
        local m = self:_readModeState()
        if m.hb_result == true then
            points = points + (minute <= 60 and 2 or 4)
        else
            logger.info("FocusFeedback V14 heartbeat: miss, no points")
            return
        end
    elseif mode == MODE_SAND then
        -- V15 沙漏模式：用户自定义加成时段内，里程碑积分必+1（不依赖猫概率）
        --           时段外：失去猫的概率加成，不加成（0加成）
        if self:_isInSandWindow() then
            points = points + 1
        end
    else
        -- V14 夜间/白天模式：各自时段内里程碑+1（不依赖养猫概率），时段外无猫加成
        if mode == MODE_NIGHT or mode == MODE_DAY then
            local in_window = (mode == MODE_NIGHT and self:_isNightTime())
                or (mode == MODE_DAY and self:_isDayTime())
            if in_window then
                points = points + 1
            end
        else
            -- V7: 小猫在身边时，40%概率积分入账+1
            -- V14: 挑战模式下小猫加成概率提到100%（必+1）
            -- 抽签：中吉「猫之眷顾」40%→80%，中平「猫的眼神」40%→41%
            local pet = self:_readPet()
            local cat_chance = 0.4
            local fxc = self:_drawEffect()
            if fxc == "cat_love" then
                cat_chance = 0.8
            elseif fxc == "cat_eye" then
                cat_chance = 0.41
            end
            if pet.cat and fxc ~= "no_gain" and (mode == MODE_CHALLENGE or mode == MODE_SPRINT or math.random() < cat_chance) then
                points = points + 1
            end
        end
    end

    -- V14 挑战/短跑模式：所得全部进寄存（挑战寄存ch_escrow，短跑寄存spr_escrow）
    if mode == MODE_CHALLENGE or mode == MODE_SPRINT then
        local m = self:_readModeState()
        if mode == MODE_CHALLENGE then
            m.ch_escrow = (m.ch_escrow or 0) + points
            logger.info("FocusFeedback V14 challenge: escrow +" .. points, "total:", m.ch_escrow)
        else
            m.spr_escrow = (m.spr_escrow or 0) + points
            logger.info("FocusFeedback V14 sprint: escrow +" .. points, "total:", m.spr_escrow)
        end
        self:_saveModeState(m)
        return
    end

    local current = self:_readPoints()
    self:_savePoints(current + points)
    logger.info("FocusFeedback V4: points awarded:", points, "total:", current + points)
end

-- ========== V4 库存显示 ==========

-- 动态库存显示：只显示数量>0的物品
function FocusFeedback:_getInventoryText()
    local inv = self:_readInventory()
    local parts = {}
    if (inv.cotton or 0) > 0 then
        table.insert(parts, string.format("棉花糖×%d", inv.cotton))
    end
    if (inv.biscuit or 0) > 0 then
        table.insert(parts, string.format("饼干×%d", inv.biscuit))
    end
    if (inv.wastebasket or 0) > 0 then
        table.insert(parts, string.format("废纸篓×%d", inv.wastebasket))
    end
    if (inv.toy or 0) > 0 then
        table.insert(parts, string.format("逗书棒×%d", inv.toy))
    end
    -- V6: 新增可用物品
    if (inv.coffee or 0) > 0 then
        table.insert(parts, string.format("咖啡×%d", inv.coffee))
    end
    if (inv.clover or 0) > 0 then
        table.insert(parts, string.format("四叶草×%d", inv.clover))
    end
    -- V6: 宠物显示（小猫/小兔，可同时存在）
    local pet = self:_readPet()
    if pet.cat then
        table.insert(parts, "小猫×1")
    end
    if pet.rabbit then
        table.insert(parts, "小兔×1")
    end
    if #parts == 0 then
        return "仓库空空如也"
    end
    return table.concat(parts, "  ")
end

-- ========== V4 心情更新 ==========

-- 更新心情值（处理碎纸屑衰减、检查弃养）
function FocusFeedback:_updateMood()
    local now = os.time()

    -- V14 摸鱼模式：心情锁死60，不衰减、无弃养
    if self:_getActiveMode() == MODE_SLACK then
        local cur = self:_readMood()
        if cur ~= 60 then self:_saveMood(60) end
        self:_saveLastMoodUpdate(now)
        self:_saveMoodLowStart(0)
        return 60
    end

    local mood = self:_readMood()
    local last_update = self:_readLastMoodUpdate()

    -- V14 挑战成功心情拉满8h：期间不掉落
    local boost_until = G_reader_settings:readSetting(settingKey("v14_mood_boost_until"), 0) or 0
    -- V14 低落免疫卡：72h内心情下限90%
    local immune_until = G_reader_settings:readSetting(settingKey("v14_mood_immune_until"), 0) or 0

    if boost_until > now then
        mood = 100
    elseif last_update and last_update > 0 then
        local hours = (now - last_update) / 3600
        if hours > 0 then
            -- 碎纸屑期间每小时-20%
            if self:_readScrapsState().active then
                -- V6: 小兔在身边时，心情值掉落速度×0.5
                local decay = MOOD_DECAY_SCRAPS
                local pet = self:_readPet()
                if pet.rabbit then
                    decay = decay * 0.5
                end
                mood = mood - hours * decay
            end
        end
    end

    -- 抽签当日效果（心情维度）：上上满格 / 下签锁死10% / 中吉底线50%
    local draw_fx = self:_drawEffect()
    if draw_fx == "happy_day" then
        mood = 100
    elseif draw_fx == "depression" then
        mood = MOOD_MIN
    elseif draw_fx == "mood_floor" then
        mood = math.max(50, mood)
    end

    -- V14 低落免疫卡：维持下限90%（免疫卡优先于负面签运，花钱买的道具能抵抗下签）
    if immune_until > now then
        mood = math.max(90, mood)
    end

    mood = math.max(MOOD_MIN, math.min(100, mood))
    self:_saveMood(mood)
    self:_saveLastMoodUpdate(now)

    -- 检查心情10%持续30天弃养
    if mood <= MOOD_MIN then
        local low_start = self:_readMoodLowStart()
        if low_start == 0 then
            self:_saveMoodLowStart(now)
        elseif (now - low_start) > MOOD_ABANDON_DAYS * 24 * 3600 then
            self:_abandonBook()
        end
    else
        self:_saveMoodLowStart(0)
    end

    return mood
end

-- ========== V4 状态优先级系统 ==========

function FocusFeedback:_getStatus(sleep_type)
    local now = os.time()

    -- 1. 检查睡觉（使用调用方传入的结果，避免重复随机触发）
    local sleep = sleep_type
    if sleep then
        local sleep_text = (sleep == "deep") and "已深度睡眠zzz……" or "打个小盹啦z…"
        -- V6: 显示苏醒倒计时（还需阅读多少分钟）
        local sleep_state = self:_readSleepState()
        local current_reading = self:_readAdoptReadingSeconds()
        local reading_since = current_reading - (sleep_state.reading_at_start or 0)
        if reading_since < 0 then reading_since = current_reading end
        local needed = (sleep == "deep") and SLEEP_DEEP_NEED_SEC or SLEEP_NAP_NEED_SEC
        local remain_min = math.max(0, math.ceil((needed - reading_since) / 60))
        if remain_min > 0 then
            sleep_text = sleep_text .. string.format("（还需阅读%d分钟苏醒）", remain_min)
        end
        -- 检查是否同时饥饿
        local last_read = self:_readLastReadTime()
        local last_feed = self:_readLastFeedTime()
        local no_read = (last_read == 0) or (now - last_read > 86400)
        local no_feed = (last_feed == 0) or (now - last_feed > 86400)
        if no_read and no_feed then
            return sleep_text .. "\n饥饿……", true
        end
        return sleep_text, true
    end

    -- 2. 饥饿（最高优先级，不可覆盖）
    local last_read = self:_readLastReadTime()
    local last_feed = self:_readLastFeedTime()
    local no_read = (last_read == 0) or (now - last_read > 86400)
    local no_feed = (last_feed == 0) or (now - last_feed > 86400)
    if no_read and no_feed then
        return "饥饿……", false
    end

    -- 3. 碎纸屑
    if self:_readScrapsState().active then
        return "脏脏的……", false
    end

    -- 4-6. 心情值状态
    local mood = self:_readMood()
    if mood <= 20 then
        return "极度暴躁（赶紧安抚它）", false
    elseif mood < 50 then
        return "不愉悦、、、（待会再投喂吧）", false
    elseif mood >= 90 then
        return "兴奋地哗哗翻动！（快来投喂吧）", false
    end

    -- 7-8. 抚摸连击状态
    local pet = self:_readPetStreak()
    if pet.streak10_end and now < pet.streak10_end then
        return "晕……", false
    end
    if pet.streak3_end and now < pet.streak3_end then
        return "呼噜呼噜呼噜……", false
    end

    -- 9. 随机状态（低优先级，覆盖默认状态）
    local r = math.random()
    if r < 0.02 then return "转圈圈^^", false end
    if r < 0.04 then return "I'm reading……", false end
    if r < 0.05 then return "We are the world♫……", false end
    if r < 0.06 then return "不欢迎！o_o", false end

    -- 10-11. 默认状态
    local _, today_seconds = self:_readToday()
    if today_seconds >= 3600 then return "幸福之！", false end
    if today_seconds == 0 then return "无聊ing", false end

    return nil, false
end

-- ========== V4 睡觉检查 ==========

function FocusFeedback:_checkSleep()
    local sleep = self:_readSleepState()
    local today = todayKey()

    -- 已在睡觉，检查是否该醒来
    if sleep.type then
        local current_reading = self:_readAdoptReadingSeconds()
        local reading_since = current_reading - (sleep.reading_at_start or 0)
        if reading_since < 0 then reading_since = current_reading end
        local needed = (sleep.type == "deep") and SLEEP_DEEP_NEED_SEC or SLEEP_NAP_NEED_SEC
        if reading_since >= needed then
            -- 醒来（V8: 记录自然醒，每日任务 l5 判定）
            local stat = self:_getDailyStat()
            stat.sleep_natural = true
            self:_saveDailyStat(stat)
            -- V14: 4h睡眠间隔以「上次睡眠结束时间」起算，自然醒时记录
            self:_saveLastSleepTs(os.time())
            self:_saveSleepState({type = nil, reading_at_start = 0,
                deep_date = sleep.deep_date, nap_date = sleep.nap_date})
            return nil
        end
        return sleep.type
    end

    -- 没在睡觉，检查是否触发
    -- V7: 4h冷却优先检查（基于时间戳，跨日也生效）
    local last_sleep = self:_readLastSleepTs()
    if last_sleep > 0 and (os.time() - last_sleep) < SLEEP_MIN_INTERVAL then
        return nil
    end

    -- V14: 睡眠免疫卡——免疫接下来的两次睡眠（可跨日）
    local sleep_immune_left = G_reader_settings:readSetting(settingKey("v14_sleep_immune_left"), 0) or 0
    if sleep_immune_left > 0 then
        G_reader_settings:saveSetting(settingKey("v14_sleep_immune_left"), sleep_immune_left - 1)
        return nil
    end

    -- 每日限制（酣睡/小盹每天各最多一次）
    local deep_available = sleep.deep_date ~= today
    local nap_available = sleep.nap_date ~= today
    if not deep_available and not nap_available then return nil end

    local r = math.random()
    if deep_available and nap_available then
        if r < SLEEP_DEEP_CHANCE then
            self:_saveSleepState({type = "deep", reading_at_start = self:_readAdoptReadingSeconds(),
                deep_date = today, nap_date = sleep.nap_date})
            self:_saveLastSleepTs(os.time())
            -- V8: 今日入睡计数（每日任务 s6 判定）
            local stat = self:_getDailyStat()
            stat.total_sleep = (stat.total_sleep or 0) + 1
            self:_saveDailyStat(stat)
            return "deep"
        elseif r < SLEEP_DEEP_CHANCE + SLEEP_NAP_CHANCE then
            self:_saveSleepState({type = "nap", reading_at_start = self:_readAdoptReadingSeconds(),
                deep_date = sleep.deep_date, nap_date = today})
            self:_saveLastSleepTs(os.time())
            -- V8: 今日入睡计数（每日任务 s6 判定）
            local stat = self:_getDailyStat()
            stat.total_sleep = (stat.total_sleep or 0) + 1
            self:_saveDailyStat(stat)
            return "nap"
        end
    elseif deep_available then
        if r < SLEEP_DEEP_CHANCE then
            self:_saveSleepState({type = "deep", reading_at_start = self:_readAdoptReadingSeconds(),
                deep_date = today, nap_date = sleep.nap_date})
            self:_saveLastSleepTs(os.time())
            -- V8: 今日入睡计数（每日任务 s6 判定）
            local stat = self:_getDailyStat()
            stat.total_sleep = (stat.total_sleep or 0) + 1
            self:_saveDailyStat(stat)
            return "deep"
        end
    elseif nap_available then
        if r < SLEEP_NAP_CHANCE then
            self:_saveSleepState({type = "nap", reading_at_start = self:_readAdoptReadingSeconds(),
                deep_date = sleep.deep_date, nap_date = today})
            self:_saveLastSleepTs(os.time())
            -- V8: 今日入睡计数（每日任务 s6 判定）
            local stat = self:_getDailyStat()
            stat.total_sleep = (stat.total_sleep or 0) + 1
            self:_saveDailyStat(stat)
            return "nap"
        end
    end
    return nil
end

-- ========== V4 碎纸屑检查 ==========

function FocusFeedback:_checkScraps()
    local scraps = self:_readScrapsState()
    -- 已激活则不重复触发
    if scraps.active then return false end

    local today = todayKey()
    -- 今天已触发过则不再触发
    if scraps.last_trigger_date == today then return false end

    if math.random() < SCRAPS_TRIGGER_CHANCE then
        self:_saveScrapsState({active = true, trigger_ts = os.time(), last_trigger_date = today})
        return true
    end
    return false
end

-- ========== V4 投喂 ==========

function FocusFeedback:_feedBook(callback)
    local inv = self:_readInventory()
    local has_cotton = (inv.cotton or 0) > 0
    local has_biscuit = (inv.biscuit or 0) > 0

    if not has_cotton and not has_biscuit then
        self._pending_dialogue = "没有库存了＞＜"
        if callback then callback() end
        return
    end

    if has_cotton and has_biscuit then
        -- 选择食物
        local dialog
        dialog = ButtonDialog:new{
            title = "选择食物",
            title_align = "center",
            buttons = {
                {
                    {text = "棉花糖", callback = function()
                        UIManager:close(dialog)
                        self:_doFeed("cotton", callback)
                    end},
                    {text = "饼干", callback = function()
                        UIManager:close(dialog)
                        self:_doFeed("biscuit", callback)
                    end},
                },
                {
                    {text = "取消", callback = function()
                        UIManager:close(dialog)
                        if callback then callback() end
                    end},
                },
            },
        }
        UIManager:show(dialog)
    else
        self:_doFeed(has_cotton and "cotton" or "biscuit", callback)
    end
end

function FocusFeedback:_doFeed(food_type, callback)
    -- 扣库存
    local inv = self:_readInventory()
    inv[food_type] = (inv[food_type] or 0) - 1
    self:_saveInventory(inv)

    -- 计算进度（含心情影响）
    local mood = self:_readMood()
    local base_progress = (food_type == "cotton") and COTTON_PROGRESS or BISCUIT_PROGRESS
    local mood_mod = 0
    if mood >= MOOD_HIGH then mood_mod = 0.1
    elseif mood < MOOD_LOW then mood_mod = -0.1 end
    local progress = self:_readProgress() + base_progress + mood_mod

    -- 首次投喂
    local is_first = not self:_readFirstFeed()
    if is_first then self:_saveFirstFeed(true) end

    -- 连续投喂追踪
    local consec = self:_readConsecutive()
    if consec.type == food_type then
        consec.count = (consec.count or 0) + 1
    else
        consec = {type = food_type, count = 1}
    end
    self:_saveConsecutive(consec)
    -- V5: 食物消耗计数
    local consumed = self:_readFoodConsumed()
    if food_type == "cotton" then
        consumed.cotton = (consumed.cotton or 0) + 1
    elseif food_type == "biscuit" then
        consumed.biscuit = (consumed.biscuit or 0) + 1
    end
    self:_saveFoodConsumed(consumed)
    -- V8: 今日投喂计数（每日任务 r9/r10/s1 判定）
    local stat = self:_getDailyStat()
    if food_type == "cotton" then
        stat.cotton = (stat.cotton or 0) + 1
    elseif food_type == "biscuit" then
        stat.biscuit = (stat.biscuit or 0) + 1
    end
    self:_saveDailyStat(stat)
    self:_saveLastFeedTime(os.time())

    -- 进度里程碑台词
    local ms = self:_readProgressMilestones()
    local milestone_dialogue = nil
    for _, m in ipairs(PROGRESS_MILESTONES) do
        if progress >= m and not ms[tostring(m)] then
            ms[tostring(m)] = true
            milestone_dialogue = self.dialogue_data.specific["progress_" .. m]
            -- V5: 里程碑日记日志
            self:_addEventLog("milestone_" .. m, nil)
        end
    end
    self:_saveProgressMilestones(ms)

    -- 台词优先级
    if is_first then
        self._pending_dialogue = self.dialogue_data.specific.first_feed
    elseif consec.count >= 3 then
        if consec.type == "cotton" then
            self._pending_dialogue = self.dialogue_data.specific.consecutive_cotton
        else
            self._pending_dialogue = self.dialogue_data.specific.consecutive_biscuit
        end
        self:_saveConsecutive({type = nil, count = 0})
    elseif milestone_dialogue then
        self._pending_dialogue = milestone_dialogue
    else
        self._pending_dialogue = self:_getRandomNormalDialogue()
    end

    -- 检查翻开
    if progress >= 100 then
        self:_saveProgress(100)
        self:_doReveal()
        if callback then callback() end
        return
    end

    self:_saveProgress(progress)
    if callback then callback() end
end

-- ========== V4 抚摸 ==========

function FocusFeedback:_petBook(callback)
    local mood = self:_readMood()
    mood = math.min(100, mood + MOOD_PER_PET)
    self:_saveMood(mood)

    -- 抚摸连击
    local pet = self:_readPetStreak()
    local now = os.time()
    -- 如果上次抚摸超过30秒，重置计数
    if pet.last_ts and (now - pet.last_ts) > 30 then
        pet.count = 0
    end
    pet.count = (pet.count or 0) + 1
    pet.last_ts = now

    -- 3次连击：呼噜呼噜，持续1分钟
    if pet.count == 3 then
        pet.streak3_end = now + 60
    end
    -- 10次以上：晕，持续10分钟
    if pet.count >= 10 then
        pet.streak10_end = now + 600
    end
    self:_savePetStreak(pet)

    -- V8: 今日抚摸计数（每日任务 n8/r7/l3/s2 判定）
    local stat = self:_getDailyStat()
    stat.pets = (stat.pets or 0) + 1
    self:_saveDailyStat(stat)

    -- 变换台词
    self._pending_dialogue = self:_getRandomNormalDialogue()

    if callback then callback() end
end

-- ========== V4 清理碎纸屑 ==========

function FocusFeedback:_cleanScraps(callback)
    local inv = self:_readInventory()
    if (inv.wastebasket or 0) <= 0 then
        self._pending_dialogue = "没有废纸篓了＞＜"
        if callback then callback() end
        return
    end
    inv.wastebasket = inv.wastebasket - 1
    self:_saveInventory(inv)

    local scraps = self:_readScrapsState()
    scraps.active = false
    self:_saveScrapsState(scraps)

    -- V8: 今日清理碎纸屑计数（每日任务 r5 判定）
    local stat = self:_getDailyStat()
    stat.scraps = (stat.scraps or 0) + 1
    self:_saveDailyStat(stat)

    self._pending_dialogue = "干净了！舒服~"
    if callback then callback() end
end

-- ========== V4 玩耍（逗书棒） ==========

function FocusFeedback:_playWithBook(callback)
    local inv = self:_readInventory()
    if (inv.toy or 0) <= 0 then
        self._pending_dialogue = "没有逗书棒了＞＜"
        if callback then callback() end
        return
    end
    inv.toy = inv.toy - 1
    self:_saveInventory(inv)

    local mood = self:_readMood()
    mood = math.min(100, mood + MOOD_PER_TOY)
    self:_saveMood(mood)

    -- V8: 今日逗书棒使用计数（每日任务 n9 判定）
    local stat = self:_getDailyStat()
    stat.toy = (stat.toy or 0) + 1
    self:_saveDailyStat(stat)

    self._pending_dialogue = "好开心！再来！"
    if callback then callback() end
end

-- ========== V6 咖啡唤醒 ==========

function FocusFeedback:_wakeWithCoffee(callback)
    local inv = self:_readInventory()
    if (inv.coffee or 0) <= 0 then
        self._pending_dialogue = "没有咖啡了＞＜"
        if callback then callback() end
        return
    end
    inv.coffee = inv.coffee - 1
    self:_saveInventory(inv)

    -- 立即苏醒，保留今日睡眠日期限制
    local sleep = self:_readSleepState()
    -- V14: 4h睡眠间隔以「上次睡眠结束时间」起算，咖啡唤醒时记录
    self:_saveLastSleepTs(os.time())
    self:_saveSleepState({type = nil, reading_at_start = 0,
        deep_date = sleep.deep_date, nap_date = sleep.nap_date})

    -- V8: 今日咖啡唤醒计数（每日任务 n7/s6 判定）
    local stat = self:_getDailyStat()
    stat.coffee = (stat.coffee or 0) + 1
    stat.wake_coffee = (stat.wake_coffee or 0) + 1
    self:_saveDailyStat(stat)
    -- V15: 使用一次咖啡唤醒 +0.4% 辩证
    self:_addAttribute("辩证", ATTR_EVENT_GAIN)

    self._pending_dialogue = "谁把我苦醒了……"
    if callback then callback() end
end

-- ========== V6 四叶草转运 ==========

function FocusFeedback:_useClover(callback)
    local inv = self:_readInventory()
    if (inv.clover or 0) <= 0 then
        self._pending_dialogue = "没有四叶草了＞＜"
        if callback then callback() end
        return
    end
    -- 已生效则不重复消耗
    if self:_isCloverActive() then
        self._pending_dialogue = "转运已经在生效啦！"
        if callback then callback() end
        return
    end
    inv.clover = inv.clover - 1
    self:_saveInventory(inv)
    self:_saveCloverExpire(os.time() + CLOVER_DURATION)

    -- V8: 今日四叶草使用计数（每日任务 r8 判定）
    local stat = self:_getDailyStat()
    stat.clover = (stat.clover or 0) + 1
    self:_saveDailyStat(stat)
    -- V15: 使用一次四叶草 +0.4% 审美
    self:_addAttribute("审美", ATTR_EVENT_GAIN)

    self._pending_dialogue = "凡事发生皆利于我！"
    if callback then callback() end
end

-- ========== V4 商超界面 ==========

-- 抽签模式动态价格覆盖（仅当日生效，猫/兔永不参与变价）
function FocusFeedback:_shopPrice(key)
    local fx = self:_drawEffect()
    if key == "cat" or key == "rabbit" then
        return (key == "cat") and PRICE_CAT or PRICE_RABBIT
    end
    local base = 2
    if key == "cotton" then base = PRICE_COTTON
    elseif key == "biscuit" then base = PRICE_BISCUIT
    elseif key == "wastebasket" then base = PRICE_WASTEBASKET
    elseif key == "toy" then base = PRICE_TOY
    elseif key == "coffee" then base = PRICE_COFFEE
    elseif key == "clover" then base = PRICE_CLOVER end
    if fx == "black_friday" then return 1 end             -- 上上④ 全场1分
    if fx == "rich_area" then return 100 end              -- 下④ 全场100分
    if fx == "gray_friday" then return (base >= 3) and 3 or base end  -- 上吉④ ≥3→3
    if fx == "ash_friday" then return (base >= 5) and 5 or base end   -- 中吉④ ≥5→5
    if fx == "white_friday" then return (base <= 5) and 5 or base end -- 中下④ ≤5→5
    if fx == "small_use" then
        return self:_drawDiscountItem() == key and 5 or base          -- 中平④ 随机一件→5
    end
    return base  -- 十折/无事/未抽签 → 原价
end

-- 中平签「有点小用」：当日随机一件物品（除猫兔）价格变为5积分，固定当日记住
-- 抽到高价物品是降价优惠，抽到低价物品则提价——中平签有好有坏，反而是一种平衡
function FocusFeedback:_drawDiscountItem()
    local d = self:_readDrawDay()
    if not d.discount_key then
        local pool = {"cotton", "biscuit", "wastebasket", "toy", "coffee", "clover"}
        d.discount_key = pool[math.random(#pool)]
        self:_saveDrawDay(d)
    end
    return d.discount_key
end

-- 加载商超图标
function FocusFeedback:_loadShopIcon(filename, display_size)
    if not self.plugin_dir then return nil end
    local img_path = self.plugin_dir .. filename
    local f = io.open(img_path, "rb")
    if not f then return nil end
    f:close()
    local scaled_w = Screen:scaleBySize(display_size or 40)
    local ok, img = pcall(function()
        return ImageWidget:new{file = img_path, width = scaled_w, scale_factor = 0}
    end)
    if not ok or not img then return nil end
    return img
end

-- V6: 宠物图标加载（小猫/小兔占位图）
function FocusFeedback:_loadPetIcon(pet_type, display_size)
    if not self.plugin_dir then return nil end
    local filename = (pet_type == "cat") and "pet_cat.jpg" or "pet_rabbit.jpg"
    local img_path = self.plugin_dir .. filename
    local f = io.open(img_path, "rb")
    if not f then return nil end
    f:close()
    local scaled_w = Screen:scaleBySize(display_size or 40)
    local ok, img = pcall(function()
        return ImageWidget:new{file = img_path, width = scaled_w, scale_factor = 0}
    end)
    if not ok or not img then return nil end
    return img
end

function FocusFeedback:_showShop()
    local points = self:_readPoints()
    local avail_w = Screen:getWidth() * 0.85

    -- V6: 商超物品数据（2×4 布局，上排基础物品，下排新增）；价格走抽签动态覆盖 _shopPrice
    local shop_items = {
        {key = "cotton", name = "棉花糖", price = self:_shopPrice("cotton"), icon = "shop_cotton.jpg"},
        {key = "biscuit", name = "饼干", price = self:_shopPrice("biscuit"), icon = "shop_biscuit.jpg"},
        {key = "wastebasket", name = "废纸篓", price = self:_shopPrice("wastebasket"), icon = "shop_wastebasket.jpg"},
        {key = "toy", name = "逗书棒", price = self:_shopPrice("toy"), icon = "shop_toy.jpg"},
        {key = "coffee", name = "咖啡", price = self:_shopPrice("coffee"), icon = "shop_coffee.jpg"},
        {key = "clover", name = "四叶草", price = self:_shopPrice("clover"), icon = "shop_clover.jpg"},
        {key = "cat", name = "小猫", price = self:_shopPrice("cat"), icon = "shop_cat.jpg", pet = "cat", pet_dialogue = "我终于不是野书了，我被小猫收养了＞＜！"},
        {key = "rabbit", name = "小兔", price = self:_shopPrice("rabbit"), icon = "shop_rabbit.jpg", pet = "rabbit", pet_dialogue = "呕兔就像喝水一样简单！"},
    }

    -- 构建内容：标题 + 2×4图标网格
    local parts = {}

    -- 标题
    local title_w = TextWidget:new{
        text = string.format("商超  积分：%d", points),
        face = Font:getFace("cfont", 18),
    }
    table.insert(parts, centerIn(title_w, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- V6: 2×4 网格（图标缩小到30，列间距保持30）
    for i = 1, #shop_items, 4 do
        local row_items = {}
        for j = 0, 3 do
            local item = shop_items[i + j]
            if item then
                local cell_parts = {}
                local icon = self:_loadShopIcon(item.icon, 30)
                if icon then
                    table.insert(cell_parts, icon)
                end
                local name_w = TextWidget:new{
                    text = item.name,
                    face = Font:getFace("cfont", 14),
                }
                table.insert(cell_parts, name_w)
                local price_w = TextWidget:new{
                    text = string.format("%d积分", item.price),
                    face = Font:getFace("cfont", 12),
                }
                table.insert(cell_parts, price_w)
                local cell = VerticalGroup:new{ align = "center", unpack(cell_parts) }
                cell.not_focusable = true
                table.insert(row_items, cell)
            end
        end
        if #row_items > 0 then
            local row_parts = {}
            for i, item in ipairs(row_items) do
                if i > 1 then
                    table.insert(row_parts, HorizontalSpan:new{ width = Screen:scaleBySize(30) })
                end
                table.insert(row_parts, item)
            end
            local row = HorizontalGroup:new{ align = "center", unpack(row_parts) }
            table.insert(parts, centerIn(row, avail_w))
            table.insert(parts, VerticalSpan:new{ width = Size.padding.default })
        end
    end

    local content = VerticalGroup:new{ align = "center", unpack(parts) }
    content.not_focusable = true

    -- 购买按钮
    local dialog
    local function buyItem(item)
        if points < item.price then
            self:_showMessage("积分不足！", 2)
            return
        end
        -- V6: 宠物（小猫/小兔）直接生效，不占用库存；猫兔可各一只
        if item.pet then
            local pet = self:_readPet()
            if pet[item.pet] then
                local pet_name = (item.pet == "cat") and "小猫" or "小兔"
                self:_showMessage("已经有" .. pet_name .. "了！", 2)
                return
            end
            pet[item.pet] = true
            self:_savePet(pet)
            -- 首次获得台词（下次打开养成页面时显示）
            self._pending_dialogue = item.pet_dialogue
        else
            local inv = self:_readInventory()
            inv[item.key] = (inv[item.key] or 0) + 1
            self:_saveInventory(inv)
        end
        points = points - item.price
        self:_savePoints(points)
        logger.info("FocusFeedback V4: bought", item.name, "for", item.price, "points, remaining:", points)
        -- 刷新商超界面以更新积分显示
        UIManager:close(dialog)
        self:_showShop()
    end

    local buttons = {
        {
            {text = string.format("%s %d", shop_items[1].name, shop_items[1].price), callback = function() buyItem(shop_items[1]) end},
            {text = string.format("%s %d", shop_items[2].name, shop_items[2].price), callback = function() buyItem(shop_items[2]) end},
            {text = string.format("%s %d", shop_items[3].name, shop_items[3].price), callback = function() buyItem(shop_items[3]) end},
            {text = string.format("%s %d", shop_items[4].name, shop_items[4].price), callback = function() buyItem(shop_items[4]) end},
        },
        {
            {text = string.format("%s %d", shop_items[5].name, shop_items[5].price), callback = function() buyItem(shop_items[5]) end},
            {text = string.format("%s %d", shop_items[6].name, shop_items[6].price), callback = function() buyItem(shop_items[6]) end},
            {text = string.format("%s %d", shop_items[7].name, shop_items[7].price), callback = function() buyItem(shop_items[7]) end},
            {text = string.format("%s %d", shop_items[8].name, shop_items[8].price), callback = function() buyItem(shop_items[8]) end},
        },
        {
            {text = "退出", callback = function() UIManager:close(dialog) end},
        },
    }

    dialog = ButtonDialog:new{
        title = "",
        title_align = "center",
        buttons = buttons,
    }

    avail_w = dialog:getAddedWidgetAvailableWidth() or avail_w
    dialog:addWidget(content)
    UIManager:show(dialog)
end

-- ========== V5 仓库子菜单 ==========

-- 物品名称映射（key -> 中文名）
function FocusFeedback:_getItemDisplayName(key)
    local names = {
        cotton = "棉花糖", biscuit = "饼干", wastebasket = "废纸篓", toy = "逗书棒",
        -- V6: 新增可用物品
        coffee = "咖啡", clover = "四叶草",
        -- V7: 测试体验卡
        test_bookmark = "书签掉落体验卡", test_stranger = "遇见陌生人体验卡",
        test_babel = "掉入巴别塔体验卡", test_special = "特殊事件体验卡",
        test_flyaway = "书飞走了体验卡",
        -- V14: 长期模式奖励卡
        mood_immune = "低落免疫卡", sleep_immune = "睡眠免疫卡",
    }
    -- 纪念品从 event_data 获取
    if self.event_data then
        for _, s in ipairs(self.event_data.strangers or {}) do
            if s.reward_key == key then return s.reward_name or key end
        end
        for _, e in ipairs(self.event_data.special_events or {}) do
            if e.reward_key == key then return e.reward_name or key end
        end
    end
    -- V8: 特殊任务奖励纪念品
    for _, def in pairs(SPECIAL_TASK_REWARDS) do
        if def.key == key then return def.name end
    end
    return names[key] or key
end

-- 物品介绍文案
function FocusFeedback:_getItemIntro(key)
    local intros = {
        cotton = "投喂可增加0.3%成长进度，不过书吃多了会变黏哦。",
        biscuit = "投喂可增加0.5%的成长进度，不过注意别让碎屑卡在书缝里哦。",
        wastebasket = "可以清理书掉落的碎纸屑，记得使用可回收废纸篓哦。",
        toy = "一次可增加5%心情值，哄书开心人人有责！",
        -- V6: 新增物品介绍
        coffee = "一杯冰美式，可以快速唤醒你的书，适合高需求主人。",
        clover = "24小时内正面事件概率×2，更适合倒霉宝宝体质的转运小道具。",
        cat = "书的宠物。小猫在身边时，40%概率在里程碑积分入账时额外+1。快谢谢小猫！",
        rabbit = "书的宠物。小兔在身边时，书很幸福……心情值掉落速度×0.5。快谢谢小兔！",
        -- V7: 测试体验卡
        test_bookmark = "测试道具。使用后立即触发一次书签掉落事件，不获得奖励，不干扰日常频率。",
        test_stranger = "测试道具。使用后立即触发一次遇见陌生人事件，不获得奖励，不干扰日常频率。",
        test_babel = "测试道具。使用后立即触发一次掉入巴别图书馆事件，不获得奖励，不干扰日常频率。",
        test_special = "测试道具。使用后立即触发一次特殊事件，不获得奖励，不干扰日常频率。",
        test_flyaway = "测试道具。使用后立即触发一次书飞走了事件，不获得奖励，不干扰日常频率。",
        -- V14: 长期模式奖励卡
        mood_immune = "强制happy！使用后72h内心情值维持下限为90%。",
        sleep_immune = "书感到精力充沛！使用后将为书免疫接下来的两次睡眠。（可跨日免疫）",
    }
    if intros[key] then return intros[key] end
    -- 纪念品介绍
    if self.event_data then
        for _, s in ipairs(self.event_data.strangers or {}) do
            if s.reward_key == key and s.item_intro then return s.item_intro end
        end
        for _, e in ipairs(self.event_data.special_events or {}) do
            if e.reward_key == key and e.item_intro then return e.item_intro end
        end
    end
    -- V8: 特殊任务奖励纪念品介绍
    for _, def in pairs(SPECIAL_TASK_REWARDS) do
        if def.key == key and def.intro then return def.intro end
    end
    return "一个神秘的物品。"
end

function FocusFeedback:_showWarehouse()
    local inv = self:_readInventory()
    local items = {}
    for key, count in pairs(inv) do
        if count and count > 0 then
            local name = self:_getItemDisplayName(key)
            -- V7: 测试体验卡点击后弹出"使用"选项
            local is_test = key:match("^test_")
            -- V14: 低落免疫卡/睡眠免疫卡点击后弹出"使用"选项
            local is_v14_card = (key == "mood_immune" or key == "sleep_immune")
            if is_test then
                table.insert(items, {
                    key = key,
                    text = name,
                    mandatory = string.format("×%d", count),
                    callback = function()
                        self:_useTestCard(key, name)
                    end,
                })
            elseif is_v14_card then
                table.insert(items, {
                    key = key,
                    text = name,
                    mandatory = string.format("×%d", count),
                    callback = function()
                        self:_useV14Card(key, name)
                    end,
                })
            else
                table.insert(items, {
                    key = key,
                    text = name,
                    mandatory = string.format("×%d", count),
                    callback = function()
                        self:_showItemIntro(key, name)
                    end,
                })
            end
        end
    end
    -- V6: 宠物条目（不占库存，与书绑定；猫兔可各一只）
    local pet = self:_readPet()
    if pet.cat then
        table.insert(items, {key = "cat", text = "小猫", mandatory = "×1",
            callback = function() self:_showItemIntro("cat", "小猫") end})
    end
    if pet.rabbit then
        table.insert(items, {key = "rabbit", text = "小兔", mandatory = "×1",
            callback = function() self:_showItemIntro("rabbit", "小兔") end})
    end
    if #items == 0 then
        self:_showMessage("仓库空空如也", 3)
        return
    end
    -- V6: 排序优先级：食物(1) > 工具/消耗品(2) > 宠物(3) > 纪念品(4)
    local function priority(key)
        if key == "cotton" or key == "biscuit" then return 1 end
        if key == "wastebasket" or key == "toy" or key == "coffee" or key == "clover"
            or key == "mood_immune" or key == "sleep_immune" then return 2 end
        if key == "cat" or key == "rabbit" then return 3 end
        return 4
    end
    table.sort(items, function(a, b)
        local pa, pb = priority(a.key), priority(b.key)
        if pa ~= pb then return pa < pb end
        return a.text < b.text
    end)
    local menu = Menu:new{
        title = "仓库",
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
        show_parent = nil,
    }
    UIManager:show(menu)
end

function FocusFeedback:_showItemIntro(key, name)
    local intro = self:_getItemIntro(key)
    local dialog
    dialog = ButtonDialog:new{
        title = string.format("%s\n\n%s", name, intro),
        title_align = "center",
        buttons = {
            {{text = "关闭", callback = function() UIManager:close(dialog) end}},
        },
    }
    UIManager:show(dialog)
end

-- ========== V7 测试体验卡 ==========

-- 添加测试体验卡到仓库
function FocusFeedback:_addTestCards()
    local inv = self:_readInventory()
    local cards = {"test_bookmark", "test_stranger", "test_babel", "test_special", "test_flyaway"}
    for _, k in ipairs(cards) do
        inv[k] = (inv[k] or 0) + 1
    end
    self:_saveInventory(inv)
    self:_showMessage("已添加5张测试体验卡到仓库", 3)
end

-- 使用测试体验卡
function FocusFeedback:_useTestCard(key, name)
    local inv = self:_readInventory()
    if (inv[key] or 0) <= 0 then return end

    local dialog
    dialog = ButtonDialog:new{
        title = string.format("使用「%s」？\n（触发事件但不获得奖励，不干扰日常频率）", name),
        title_align = "center",
        buttons = {
            {
                {text = "使用", callback = function()
                    UIManager:close(dialog)
                    -- 扣除体验卡
                    inv[key] = inv[key] - 1
                    self:_saveInventory(inv)
                    -- 触发测试事件（无奖励）
                    self:_triggerTestEvent(key)
                end},
                {text = "取消", callback = function()
                    UIManager:close(dialog)
                end},
            },
        },
    }
    UIManager:show(dialog)
end

-- 触发测试事件（无奖励、不干扰频率）
function FocusFeedback:_triggerTestEvent(card_key)
    local nickname = self:_readNickname()
    if card_key == "test_bookmark" then
        local quotes = self.bookmark_quotes or {}
        if #quotes == 0 then
            self:_showEventPopup("测试-书签掉落", "（书签掉落测试：书签库为空）", nil,
                {{text = "确定", callback = function() end}})
            return
        end
        local quote = quotes[math.random(1, #quotes)]
        -- V8: 前缀单独一行，书签内容另起一行
        local text = "（书的昵称）身上掉落了一片书签：\n" .. quote
        text = text:gsub("（书的昵称）", function() return nickname end)
        self:_showEventPopup("测试-书签掉落", text, "（测试模式：无奖励）",
            {{text = "确定", callback = function() end}})

    elseif card_key == "test_stranger" then
        if not self.event_data or not self.event_data.strangers then return end
        -- 排除节日限定
        local pool = {}
        for _, s in ipairs(self.event_data.strangers) do
            if not s.holiday then table.insert(pool, s) end
        end
        if #pool == 0 then return end
        local stranger = pool[math.random(1, #pool)]
        local text = (stranger.text or ""):gsub("（书的昵称）", function() return nickname end)
        local title = "测试-遇见" .. (stranger.name or "")
        self:_showEventPopup(title, text, "（测试模式：无奖励，纪念品不收入仓库）",
            {{text = "确定", callback = function() end}})

    elseif card_key == "test_babel" then
        local text = "宇宙（别人管它叫图书馆）由许多六边形的回廊组成，数目不能确定，也许是无限的……" .. nickname .. "掉入了巴别图书馆，这里有许多它的同类，还有一位失明的阿根廷诗人，都在知识的海洋中寻觅着什么……" .. nickname .. "想起自己诞生之初第一次仰头望见银河的感受，选择了加入它们。"
        self:_showEventPopup("测试-掉入巴别塔", text, "（测试模式：无积分奖励）",
            {{text = "确定", callback = function() end}})

    elseif card_key == "test_special" then
        if not self.event_data or not self.event_data.special_events then return end
        local events = self.event_data.special_events
        if #events == 0 then return end
        local evt = events[math.random(1, #events)]
        local text = (evt.text or ""):gsub("（书的昵称）", function() return nickname end)
        local title = "测试-" .. (evt.title or "特殊事件")
        self:_showEventPopup(title, text, "（测试模式：无奖励，纪念品不收入仓库）",
            {{text = "确定", callback = function() end}})

    elseif card_key == "test_flyaway" then
        local text = nickname .. "出门玩耍，路过堪萨斯州的大草原时，一阵猛烈的旋风突然来临。周围的房子、女孩和黑色小梗犬都被大风卷了起来，" .. nickname .. "也是，它吓得吱哇乱叫。"
        self:_showEventPopup("测试-书飞走了", text, "（测试模式：不扣积分，不扣心情）",
            {{text = "确定", callback = function() end}})
    end
end

-- ========== V2 台词系统 ==========

function FocusFeedback:_getRandomNormalDialogue()
    local normal = self.dialogue_data.normal or {}
    local gated = self.dialogue_data.gated or {}
    local attrs = self:_initAttributes()

    -- 构建台词池：普通台词 + 满足属性门槛的台词
    local pool = {}
    for _, line in ipairs(normal) do
        local text = type(line) == "table" and line.text or line
        local tags = type(line) == "table" and line.tags or nil
        table.insert(pool, {text = text, tags = tags})
    end
    for _, line in ipairs(gated) do
        local ok = true
        for attr, min_val in pairs(line.min_attr or {}) do
            if (attrs[attr] or 0) < min_val then
                ok = false
                break
            end
        end
        if ok then
            table.insert(pool, {text = line.text, tags = line.tags})
        end
    end
    if #pool == 0 then
        return "书在静静等待。"
    end

    -- V15: 画像余弦相似度加权
    local picked = self:_weightedPick(pool, function(line)
        return 1 + ATTR_WEIGHT_STRENGTH * self:_cosineSim(attrs, line.tags or {})
    end)
    return picked.text
end

-- 打开页面时的台词（检查特定条件）
function FocusFeedback:_getPageDialogue()
    -- 如果有 pending dialogue，直接返回
    if self._pending_dialogue then
        local d = self._pending_dialogue
        self._pending_dialogue = nil
        return d
    end

    local now = os.time()

    -- 检查阅读时长触发（1h / 3h）
    local _, today_seconds = self:_readToday()
    local today = todayKey()

    if today_seconds >= 3600 and self:_readReadTrigger("read_1h") ~= today then
        self:_saveReadTrigger("read_1h", today)
        return self.dialogue_data.specific.read_1h or "马上就能翻开我了"
    end
    if today_seconds >= 10800 and self:_readReadTrigger("read_3h") ~= today then
        self:_saveReadTrigger("read_3h", today)
        return self.dialogue_data.specific.read_3h or "书很高兴"
    end

    -- 检查投喂空闲触发
    local last_feed = self:_readLastFeedTime()
    if last_feed > 0 then
        local idle = now - last_feed
        if idle >= IDLE_1WEEK_SECONDS then
            return self.dialogue_data.specific.idle_1week or "书很想你"
        end
        if idle >= IDLE_1DAY_SECONDS then
            return self.dialogue_data.specific.idle_1day or "书想你"
        end
    end

    -- 默认随机
    return self:_getRandomNormalDialogue()
end

-- ========== V2 书的日记追踪 ==========

function FocusFeedback:_readAdoptDate()
    return G_reader_settings:readSetting(settingKey("v2_adopt_date"), "") or ""
end

function FocusFeedback:_saveAdoptDate(d)
    G_reader_settings:saveSetting(settingKey("v2_adopt_date"), d or "")
end

function FocusFeedback:_readAdoptReadingSeconds()
    return G_reader_settings:readSetting(settingKey("v2_adopt_reading_seconds"), 0) or 0
end

function FocusFeedback:_saveAdoptReadingSeconds(s)
    G_reader_settings:saveSetting(settingKey("v2_adopt_reading_seconds"), s or 0)
end

-- ========== V3 单书阅读追踪 ==========

-- 生成当前书唯一 key（文件路径 hash）
function FocusFeedback:_getBookKey()
    if self._current_book_key then return self._current_book_key end
    if not self.ui or not self.ui.document then return nil end
    local file = self.ui.document.file
    if not file then return nil end
    -- 简单 hash：取文件名
    local name = file:match("([^/\\]+)$") or file
    self._current_book_key = name
    return name
end

function FocusFeedback:_readBookStats(key)
    key = key or self:_getBookKey()
    if not key then return nil end
    local all = G_reader_settings:readSetting(settingKey("v3_book_stats"), {}) or {}
    return all[key]
end

function FocusFeedback:_saveBookStats(key, stats)
    if not key then return end
    local all = G_reader_settings:readSetting(settingKey("v3_book_stats"), {}) or {}
    all[key] = stats
    G_reader_settings:saveSetting(settingKey("v3_book_stats"), all)
end

-- 累加当前书阅读时长
function FocusFeedback:_addBookReadingTime(seconds)
    local key = self:_getBookKey()
    if not key then return end
    local stats = self:_readBookStats(key) or {
        key = key,
        file = self.ui.document.file,
        reading_seconds = 0,
        reading_days = {},
        first_read = todayKey(),
    }
    stats.reading_seconds = (stats.reading_seconds or 0) + seconds
    local today = todayKey()
    if not stats.reading_days then stats.reading_days = {} end
    stats.reading_days[today] = true
    stats.last_read = today
    self:_saveBookStats(key, stats)
end

-- ========== V3 读完书籍存储 ==========

function FocusFeedback:_readFinishedBooks()
    return G_reader_settings:readSetting(settingKey("v3_finished_books"), {}) or {}
end

function FocusFeedback:_saveFinishedBooks(books)
    G_reader_settings:saveSetting(settingKey("v3_finished_books"), books or {})
end

-- 检查书是否已读完评分
function FocusFeedback:_isBookFinished(key)
    local finished = self:_readFinishedBooks()
    for _, entry in ipairs(finished) do
        if entry.key == key then return true, entry end
    end
    return false, nil
end

-- ========== V2 弃养检查 ==========

function FocusFeedback:_checkAbandonment(now)
    -- V14 摸鱼模式：无弃养机制
    if self:_getActiveMode() == MODE_SLACK then
        return false
    end
    -- 7天无阅读行为（使用持久化的最后阅读时间）
    local last_read = self:_readLastReadTime()
    if last_read > 0 then
        if (now - last_read) > ABANDON_NO_READ_DAYS * 24 * 3600 then
            return true
        end
    end
    -- 30天不投喂
    local last_feed = self:_readLastFeedTime()
    if last_feed > 0 then
        if (now - last_feed) > ABANDON_NO_FEED_DAYS * 24 * 3600 then
            return true
        end
    end
    return false
end

function FocusFeedback:_abandonBook()
    self:_saveAdopted(false)
    self:_saveProgress(0)
    self:_saveNickname("")
    self:_saveConsecutive({ type = nil, count = 0 })
    self:_saveFirstFeed(false)
    self:_saveLastFeedTime(0)
    self:_saveProgressMilestones({})
    self:_saveReadTrigger("read_1h", "")
    self:_saveReadTrigger("read_3h", "")
    self.reveal_book = nil
    self.reveal_index = nil
    self.reveal_nickname = nil
    -- V4: 清除所有 V4 状态（含积分）
    self:_savePoints(0)
    self:_saveInventory({})
    self:_saveMood(50)
    self:_saveMoodLowStart(0)
    self:_saveLastMoodUpdate(0)
    self:_saveSleepState({})
    self:_saveScrapsState({})
    self:_savePetStreak({})
    self:_saveSuspendTs(0)
    -- V5: 清空事件相关状态（许愿柳永久标记不清除）
    self:_saveEventLog({})
    self:_saveFoodConsumed({cotton = 0, biscuit = 0})
    self:_saveAdoptionBooks({})
    self:_saveEventHistory({})
    self:_saveDailyCheck("")
    self:_saveLastEventTs(0)
    self:_saveLastSleepTs(0)
    -- V6: 清空宠物与四叶草状态（宠物只跟一本书）
    self:_savePet({})
    self:_saveCloverExpire(0)
    -- V7: 清空已遇见陌生人列表
    self:_saveMetStrangers({})
    logger.info("FocusFeedback V4: book abandoned")
end

function FocusFeedback:_resetAdoption()
    self:_saveAdopted(false)
    self:_saveProgress(0)
    self:_saveNickname("")
    self:_saveConsecutive({ type = nil, count = 0 })
    self:_saveFirstFeed(false)
    self:_saveLastFeedTime(0)
    self:_saveProgressMilestones({})
    self:_saveReadTrigger("read_1h", "")
    self:_saveReadTrigger("read_3h", "")
    self:_saveAdoptDate("")
    self:_saveAdoptReadingSeconds(0)
    -- 清除翻开状态（内存变量）
    self.reveal_book = nil
    self.reveal_index = nil
    self.reveal_nickname = nil
    -- V4: 清除 V4 状态（但保留积分，积分是跨领养周期的累积制）
    self:_saveInventory({})
    self:_saveMood(50)
    self:_saveMoodLowStart(0)
    self:_saveLastMoodUpdate(0)
    self:_saveSleepState({})
    self:_saveScrapsState({})
    self:_savePetStreak({})
    self:_saveSuspendTs(0)
    -- V5: 清空事件相关状态（许愿柳永久标记不清除）
    self:_saveEventLog({})
    self:_saveFoodConsumed({cotton = 0, biscuit = 0})
    self:_saveAdoptionBooks({})
    self:_saveEventHistory({})
    self:_saveDailyCheck("")
    self:_saveLastEventTs(0)
    self:_saveLastSleepTs(0)
    -- V6: 清空宠物与四叶草状态（翻开后宠物消失，积分保留）
    self:_savePet({})
    self:_saveCloverExpire(0)
    -- V7: 清空已遇见陌生人列表
    self:_saveMetStrangers({})
end

-- ========== V2 领养流程 ==========

function FocusFeedback:_startAdoption()
    -- 去重：排除已翻开（存入图鉴）的书
    local collection = self:_readCollection()
    local revealed = {}
    for _, entry in ipairs(collection) do
        revealed[entry.index] = true
    end

    local available = {}
    for i = 1, #self.book_data do
        if not revealed[i] then
            table.insert(available, i)
        end
    end

    -- 如果所有书都已翻开，重置池子
    if #available == 0 then
        logger.info("FocusFeedback V2: all books revealed, resetting pool")
        for i = 1, #self.book_data do
            table.insert(available, i)
        end
    end

    local idx = available[math.random(1, #available)]
    self:_saveBookIndex(idx)
    self:_saveProgress(0)
    self:_saveConsecutive({ type = nil, count = 0 })
    self:_saveFirstFeed(false)
    self:_saveProgressMilestones({})
    self:_saveLastFeedTime(0)
    self:_saveReadTrigger("read_1h", "")
    self:_saveReadTrigger("read_3h", "")
    -- 记录领养日期（用于书的日记）
    self:_saveAdoptDate(todayKey())
    self:_saveAdoptReadingSeconds(0)
    -- V4: 清除 V4 状态（保留积分）
    self:_saveInventory({})
    self:_saveMood(50)
    self:_saveMoodLowStart(0)
    self:_saveLastMoodUpdate(0)
    self:_saveSleepState({})
    self:_saveScrapsState({})
    self:_savePetStreak({})
    -- V5: 清空事件日志、食物消耗、领养书单、事件历史、时间戳，记录领养
    self:_saveEventLog({})
    self:_addEventLog("领养", nil)
    self:_saveFoodConsumed({cotton = 0, biscuit = 0})
    self:_saveAdoptionBooks({})
    self:_saveEventHistory({})
    self:_saveDailyCheck("")
    self:_saveLastEventTs(0)
    self:_saveLastSleepTs(0)
    -- V6: 清空宠物与四叶草状态（新领养从零开始，积分保留）
    self:_savePet({})
    self:_saveCloverExpire(0)
    -- V7: 清空已遇见陌生人列表
    self:_saveMetStrangers({})
    -- V15: 重置六维属性（新领养从零开始）
    self:_saveAttributes({知识 = 0, 审美 = 0, 情感 = 0, 阅历 = 0, 逻辑 = 0, 辩证 = 0})

    -- 关闭领养页面
    if self.adoption_page then
        pcall(function() UIManager:close(self.adoption_page) end)
        self.adoption_page = nil
    end

    -- 弹出命名对话框
    self:_showNamingDialog()
end

function FocusFeedback:_showNamingDialog()
    local dialog
    dialog = InputDialog:new{
        title = "给你的小书起个名字吧！",
        input = "",
        input_hint = "输入昵称",
        buttons = {
            {
                {
                    text = "跳过",
                    callback = function()
                        UIManager:close(dialog)
                        self:_saveNickname("小书")
                        self:_saveAdopted(true)
                        self:_showAdoptionPage()
                    end,
                },
                {
                    text = "确定",
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        if name and name:match("%S") then
                            self:_saveNickname(name)
                        else
                            self:_saveNickname("小书")
                        end
                        UIManager:close(dialog)
                        self:_saveAdopted(true)
                        self:_showAdoptionPage()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- 安全加载书籍图片，返回 ImageWidget 或 nil
-- display_size 为目标宽度（px），高度按图片原始宽高比自动计算
function FocusFeedback:_safeLoadImage(display_size)
    if not self.plugin_dir then return nil end
    -- 优先使用裁剪版（白底JPG、无多余留白），回退到原图
    local img_path = self.plugin_dir .. "book_img_cropped.jpg"
    local f = io.open(img_path, "rb")
    if not f then
        img_path = self.plugin_dir .. "book_img.jpg"
        f = io.open(img_path, "rb")
        if not f then return nil end
    end
    f:close()

    local scaled_w = Screen:scaleBySize(display_size or 80)
    local ok, img = pcall(function()
        return ImageWidget:new{
            file = img_path,
            width = scaled_w,
            scale_factor = 0,
        }
    end)
    if not ok or not img then
        logger.warn("FocusFeedback: book image load failed")
        return nil
    end
    return img
end

-- ========== V4 养成页面 ==========

function FocusFeedback:_showAdoptionPage()
    if not self.book_data or not self.dialogue_data then
        self:_loadV2Data()
    end

    -- V15: 当前阅读的书未分类时重新弹出分类选择（不新增子菜单）
    pcall(function()
        self:_ensureBookCategory()
    end)

    -- 更新心情（处理碎纸屑衰减等，可能触发心情弃养）
    local was_adopted = self:_readAdopted()
    self:_updateMood()
    -- 心情弃养触发时显示提示
    if was_adopted and not self:_readAdopted() then
        self:_showMessage("书扁扁地走开了……（心情太低，弃养）", 4)
    end

    -- V4: 检查弃养条件（仅已领养时）
    if self:_readAdopted() and self:_checkAbandonment(os.time()) then
        self:_abandonBook()
        self:_showMessage("书扁扁地走开了……（弃养）", 4)
    end

    -- ========== 领养前 ==========
    if not self:_readAdopted() and not self.reveal_book then
        local dialog
        dialog = ButtonDialog:new{
            title = "领养一本书",
            title_align = "center",
            buttons = {
                {
                    {text = "领养", callback = function()
                        UIManager:close(dialog)
                        self:_startAdoption()
                    end},
                    {text = "取消", callback = function()
                        UIManager:close(dialog)
                    end},
                },
            },
        }
        local avail_w = dialog:getAddedWidgetAvailableWidth() or Screen:getWidth() * 0.8
        local parts = {}
        local img = self:_safeLoadImage(80)
        if img then
            table.insert(parts, centerIn(img, avail_w))
            table.insert(parts, VerticalSpan:new{ width = Size.padding.default })
        end
        local desc = TextWidget:new{
            text = "点击领养开始你的阅读伙伴之旅",
            face = Font:getFace("cfont", 16),
        }
        table.insert(parts, centerIn(desc, avail_w))
        local content = VerticalGroup:new{ align = "center", unpack(parts) }
        content.not_focusable = true
        dialog:addWidget(content)
        UIManager:show(dialog)
        return
    end

    -- ========== 翻开页面 ==========
    if self.reveal_book then
        local book = self.reveal_book
        local nickname = self.reveal_nickname or "小书"
        local dialog
        dialog = ButtonDialog:new{
            title = string.format("《%s》\n%s\n\n\"%s\"\n\n昵称：%s\n已存入图鉴",
                book.title, book.author, book.quote, nickname),
            title_align = "center",
            buttons = {
                {
                    {text = "继续领养", callback = function()
                        UIManager:close(dialog)
                        self:_resetAdoption()
                        self:_showAdoptionPage()
                    end},
                },
            },
        }
        local avail_w = dialog:getAddedWidgetAvailableWidth() or Screen:getWidth() * 0.8
        local img = self:_safeLoadImage(80)
        if img then
            local content = VerticalGroup:new{ align = "center", centerIn(img, avail_w) }
            content.not_focusable = true
            dialog:addWidget(content)
        end
        UIManager:show(dialog)
        return
    end

    -- ========== 检查睡觉 ==========
    local sleep_type = self:_checkSleep()

    -- ========== 检查碎纸屑触发 ==========
    local scraps_just_triggered = false
    if not sleep_type then
        scraps_just_triggered = self:_checkScraps()
    end

    -- ========== 碎纸屑触发弹窗 ==========
    if scraps_just_triggered then
        local nickname = self:_readNickname()
        local dialog
        dialog = ButtonDialog:new{
            title = string.format("糟糕……%s被碎纸屑淹没了……", nickname),
            title_align = "center",
            buttons = {
                {
                    {text = "去商超", callback = function()
                        UIManager:close(dialog)
                        self:_showShop()
                    end},
                    {text = "退出", callback = function()
                        UIManager:close(dialog)
                        self:_showAdoptionPage()
                    end},
                },
            },
        }
        UIManager:show(dialog)
        return
    end

    -- ========== 获取状态和台词 ==========
    local status_text, is_sleeping = self:_getStatus(sleep_type)
    local dialogue
    if is_sleeping then
        dialogue = "Z…"
    else
        dialogue = self:_getPageDialogue()
    end

    local progress = self:_readProgress()
    local nickname = self:_readNickname()
    local inv_text = self:_getInventoryText()
    local mood = self:_readMood()
    local inv = self:_readInventory()

    -- ========== 构建动态按钮 ==========
    local has_wastebasket = (inv.wastebasket or 0) > 0
    local has_toy = (inv.toy or 0) > 0
    local scraps_active = self:_readScrapsState().active

    -- 养成页面（包括睡眠状态）
    local dialog

    local function closeAndReopen()
        UIManager:close(dialog)
        self:_showAdoptionPage()
    end

    local buttons = {}
    local row1 = {
        {text = "投喂", callback = function()
            if is_sleeping then
                self._pending_dialogue = "Z…"
                closeAndReopen()
            else
                UIManager:close(dialog)
                self:_feedBook(function()
                    self:_showAdoptionPage()
                end)
            end
        end},
        {text = "抚摸", callback = function()
            if is_sleeping then
                self._pending_dialogue = "Z…"
                closeAndReopen()
            else
                UIManager:close(dialog)
                self:_petBook(function()
                    self:_showAdoptionPage()
                end)
            end
        end},
    }
    table.insert(buttons, row1)

    local row2 = {}
    -- V6: 睡觉且有咖啡时显示"唤醒"
    if is_sleeping and (inv.coffee or 0) > 0 then
        table.insert(row2, {text = "唤醒", callback = function()
            UIManager:close(dialog)
            self:_wakeWithCoffee(function()
                self:_showAdoptionPage()
            end)
        end})
    end
    -- V6: 醒着且有四叶草时显示"转运"
    if not is_sleeping and (inv.clover or 0) > 0 then
        table.insert(row2, {text = "转运", callback = function()
            UIManager:close(dialog)
            self:_useClover(function()
                self:_showAdoptionPage()
            end)
        end})
    end
    if has_wastebasket and not is_sleeping then
        table.insert(row2, {text = "清理", callback = function()
            UIManager:close(dialog)
            self:_cleanScraps(function()
                self:_showAdoptionPage()
            end)
        end})
    end
    if has_toy and not is_sleeping then
        table.insert(row2, {text = "玩耍", callback = function()
            UIManager:close(dialog)
            self:_playWithBook(function()
                self:_showAdoptionPage()
            end)
        end})
    end
    -- 碎纸屑激活但无废纸篓时，提供去商超入口
    if scraps_active and not has_wastebasket and not is_sleeping then
        table.insert(row2, {text = "商超", callback = function()
            UIManager:close(dialog)
            self:_showShop()
        end})
    end
    table.insert(row2, {text = "退出", callback = function()
        UIManager:close(dialog)
    end})
    table.insert(buttons, row2)

    dialog = ButtonDialog:new{
        title = "",
        title_align = "center",
        buttons = buttons,
    }

    local avail_w = dialog:getAddedWidgetAvailableWidth() or Screen:getWidth() * 0.8
    local parts = {}

    -- 1. 台词气泡
    local dialogue_text = TextBoxWidget:new{
        text = dialogue,
        face = Font:getFace("cfont", 18),
        width = avail_w - 2 * (Size.padding.default + Size.border.window),
        alignment = "center",
    }
    local bubble = FrameContainer:new{
        bordersize = Size.border.window,
        bordercolor = Blitbuffer.COLOR_DARK_GRAY,
        padding = Size.padding.default,
        dialogue_text,
    }
    table.insert(parts, centerIn(bubble, avail_w))

    -- 箭头
    local arrow = TextWidget:new{
        text = "\226\150\188",
        face = Font:getFace("cfont", 10),
    }
    table.insert(parts, centerIn(arrow, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 2. 图片 + 状态（V6: 状态文字在书上方，宠物小猫在书右侧、小兔在书左侧，底部对齐）
    local img = self:_safeLoadImage(80)
    if img then
        local status_w
        if status_text then
            -- 状态可能含换行（睡觉+饥饿并列）
            status_w = TextWidget:new{
                text = "*" .. status_text,
                face = Font:getFace("cfont", 14),
            }
        end
        -- V8: 布局——猫回到上一版位置（书右侧、底部对齐书底、紧贴书）；
        -- 兔在书左侧、底部对齐；状态文字贴近猫上方（书右上区域），
        -- 比之前下移一点点，且不会超过书顶
        local pet = self:_readPet()
        local cat_img = pet.cat and self:_loadPetIcon("cat", 40) or nil
        local rabbit_img = pet.rabbit and self:_loadPetIcon("rabbit", 30) or nil

        local book_group
        if cat_img then
            -- 有猫：右列 = 状态(上) + 猫(下)，猫底部对齐书底、紧贴书右侧
            local right_parts = {}
            if status_w then
                table.insert(right_parts, status_w)
                -- 小间隙让状态贴近猫上方（状态下移、不会超过书顶）
                table.insert(right_parts, VerticalSpan:new{ width = Screen:scaleBySize(3) })
            end
            table.insert(right_parts, cat_img)
            local right_col = VerticalGroup:new{ align = "center", unpack(right_parts) }
            right_col.not_focusable = true
            local row_parts = {}
            if rabbit_img then
                table.insert(row_parts, rabbit_img)
                table.insert(row_parts, HorizontalSpan:new{ width = Size.padding.small })
            end
            table.insert(row_parts, img)
            table.insert(row_parts, HorizontalSpan:new{ width = Size.padding.small })
            table.insert(row_parts, right_col)
            book_group = HorizontalGroup:new{ align = "bottom", unpack(row_parts) }
            book_group.not_focusable = true
        else
            -- 无猫：兔（可选）在书左、底部对齐；状态在书右上区域（顶部占位下移）
            local row_parts = {}
            if rabbit_img then
                table.insert(row_parts, rabbit_img)
                table.insert(row_parts, HorizontalSpan:new{ width = Size.padding.small })
            end
            table.insert(row_parts, img)
            local pets_row = HorizontalGroup:new{ align = "bottom", unpack(row_parts) }
            pets_row.not_focusable = true
            if status_w then
                local status_col = VerticalGroup:new{ align = "center",
                    VerticalSpan:new{ width = Screen:scaleBySize(24) },
                    status_w,
                }
                status_col.not_focusable = true
                book_group = HorizontalGroup:new{ align = "top",
                    pets_row,
                    HorizontalSpan:new{ width = Size.padding.small },
                    status_col,
                }
                book_group.not_focusable = true
            else
                book_group = pets_row
            end
        end
        table.insert(parts, centerIn(book_group, avail_w))
    end
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 3. 昵称（V14: 非长期模式激活时在昵称后显示模式标签）
    local v14_mode = self:_getActiveMode()
    local nick_text = nickname
    if v14_mode then
        nick_text = nick_text .. "（" .. (MODE_NAMES[v14_mode] or v14_mode) .. "）"
    end
    local nick_w = TextWidget:new{
        text = nick_text,
        face = Font:getFace("cfont", 16),
    }
    table.insert(parts, centerIn(nick_w, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 4. 进度条
    local prog_w = math.min(avail_w * 0.7, Screen:scaleBySize(200))
    local prog = ProgressWidget:new{
        percentage = math.min(progress / 100, 1.0),
        width = prog_w,
        height = Screen:scaleBySize(6),
    }
    table.insert(parts, centerIn(prog, avail_w))
    local prog_label = TextWidget:new{
        text = string.format("进度 %.1f%%", progress),
        face = Font:getFace("cfont", 14),
    }
    table.insert(parts, centerIn(prog_label, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 5. 心情条
    local mood_prog = ProgressWidget:new{
        percentage = mood / 100,
        width = prog_w,
        height = Screen:scaleBySize(4),
    }
    table.insert(parts, centerIn(mood_prog, avail_w))
    local mood_label = TextWidget:new{
        text = string.format("心情 %.1f%%", mood),
        face = Font:getFace("cfont", 14),
    }
    table.insert(parts, centerIn(mood_label, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 6. 积分
    local points_w = TextWidget:new{
        text = string.format("积分：%d", self:_readPoints()),
        face = Font:getFace("cfont", 14),
    }
    table.insert(parts, centerIn(points_w, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 7. 库存
    local food_w = TextWidget:new{
        text = inv_text,
        face = Font:getFace("cfont", 14),
    }
    table.insert(parts, centerIn(food_w, avail_w))

    local content = VerticalGroup:new{ align = "center", unpack(parts) }
    content.not_focusable = true
    dialog:addWidget(content)

    UIManager:show(dialog)
end

-- 翻开
function FocusFeedback:_doReveal()
    -- V15: 翻开时按属性画像加权选择书名（不影响去重逻辑）
    local collection = self:_readCollection()
    local revealed = {}
    for _, entry in ipairs(collection) do
        revealed[entry.index] = true
    end
    local available = {}
    for i = 1, #self.book_data do
        if not revealed[i] then
            table.insert(available, i)
        end
    end
    -- 如果所有书都已翻开，重置池子
    if #available == 0 then
        for i = 1, #self.book_data do
            table.insert(available, i)
        end
    end
    local attrs = self:_initAttributes()
    local idx = self:_weightedPick(available, function(i)
        local book = self.book_data[i]
        return 1 + ATTR_WEIGHT_STRENGTH * self:_cosineSim(attrs, book.tags or {})
    end)
    self:_saveBookIndex(idx)

    local book = self.book_data[idx] or self.book_data[1]
    local nickname = self:_readNickname()

    -- 存入图鉴
    local collection = self:_readCollection()
    table.insert(collection, {
        index = idx,
        nickname = nickname,
        reveal_date = todayKey(),
        adopt_date = self:_readAdoptDate(),
        reading_seconds = self:_readAdoptReadingSeconds(),
        event_log = self:_readEventLog(),
        food_consumed = self:_readFoodConsumed(),
        adoption_books = self:_readAdoptionBooks(),
        adoption_book_count = self:_countAdoptionBooks(),
        attributes = attrs,  -- V15: 翻开时的属性快照
    })
    self:_saveCollection(collection)

    -- 设置翻开状态
    self.reveal_book = book
    self.reveal_index = idx   -- V15.2: 记录当前翻开书在图鉴中的序号（供在线阅读动态定位）
    self.reveal_nickname = nickname

    logger.info("FocusFeedback V2: book revealed:", book.title)
end

-- ========== V3 读完评分系统 ==========

-- 触发读完评分
function FocusFeedback:_triggerEndBookRating()
    if self._end_book_triggered then return end
    self._end_book_triggered = true

    local key = self:_getBookKey()
    if not key then return end

    -- 已评分过就不再弹（重读同一文件不重复弹）
    local already, entry = self:_isBookFinished(key)
    if already then
        logger.info("FocusFeedback V3: book already finished and rated:", key)
        return
    end

    -- 获取书名
    local title = "未知书名"
    if self.ui and self.ui.document then
        local props = self.ui.document:getProps()
        if props and props.title and props.title ~= "" then
            title = props.title
        elseif self.ui.document.file then
            title = self.ui.document.file:match("([^/\\]+)%.[^.]+$") or title
        end
    end

    -- 获取阅读统计
    local stats = self:_readBookStats(key) or {}
    local reading_seconds = stats.reading_seconds or 0
    local reading_days = 0
    if stats.reading_days then
        for _ in pairs(stats.reading_days) do
            reading_days = reading_days + 1
        end
    end

    self:_showRatingDialog(key, title, reading_seconds, reading_days)
end

-- 星星文字渲染
local function makeStarText(rating)
    if not rating or rating == 0 then return "☆ ☆ ☆ ☆ ☆" end
    local stars = {}
    for i = 1, 5 do
        if rating >= i then
            stars[i] = "★"
        elseif rating >= i - 0.5 then
            stars[i] = "-half"  -- 半星稍后处理
        else
            stars[i] = "☆"
        end
    end
    -- 半星用 "◐" 字符，不支持就退回 "★"
    local result = {}
    for i = 1, 5 do
        if stars[i] == "-half" then
            result[i] = "◐"
        else
            result[i] = stars[i]
        end
    end
    return table.concat(result, " ")
end

-- 显示评分弹窗（用按钮选分，兼容 ButtonDialog）
function FocusFeedback:_showRatingDialog(book_key, title, reading_seconds, reading_days)
    local avail_w = Screen:getWidth() * 0.85

    -- 标题区域（书图片 + 提示 + 阅读统计）
    local parts = {}

    local img = self:_safeLoadImage(80)
    if img then
        table.insert(parts, centerIn(img, avail_w))
        table.insert(parts, VerticalSpan:new{ width = Size.padding.default })
    end

    local title_w = TextWidget:new{
        text = "人！请为这次旅途评分。",
        face = Font:getFace("cfont", 18),
    }
    table.insert(parts, centerIn(title_w, avail_w))

    local name_w = TextWidget:new{
        text = "《" .. title .. "》",
        face = Font:getFace("cfont", 16),
    }
    table.insert(parts, centerIn(name_w, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    -- 阅读统计
    local stats_text = string.format("阅读时长：%s  |  阅读天数：%d 天",
        secondsToText(reading_seconds), reading_days)
    local stats_w = TextWidget:new{
        text = stats_text,
        face = Font:getFace("cfont", 14),
    }
    table.insert(parts, centerIn(stats_w, avail_w))

    local content = VerticalGroup:new{ align = "center", unpack(parts) }
    content.not_focusable = true

    -- 按钮：5 行，每行一个分数区间
    local dialog
    local function closeAndSave(rating)
        UIManager:close(dialog)
        self:_saveFinishedBookEntry(book_key, title, reading_seconds, reading_days, rating)
    end
    local function closeWithoutSave()
        UIManager:close(dialog)
        -- 重置标记，允许后续再次触发（分章节书籍只是读完一章）
        self._end_book_triggered = false
    end

    local buttons = {}
    for row = 1, 5 do
        local low = row - 0.5
        local high = row
        table.insert(buttons, {
            {
                text = string.format("%.1f ★ %s", low, makeStarText(low)),
                callback = function() closeAndSave(low) end,
            },
            {
                text = string.format("%.1f ★ %s", high, makeStarText(high)),
                callback = function() closeAndSave(high) end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = "跳过",
            callback = function() closeAndSave(0) end,
        },
        {
            text = "还没读完",
            callback = function() closeWithoutSave() end,
        },
    })

    dialog = ButtonDialog:new{
        title = "",
        title_align = "center",
        buttons = buttons,
    }

    avail_w = dialog:getAddedWidgetAvailableWidth() or avail_w
    dialog:addWidget(content)

    UIManager:show(dialog)
end

-- 保存读完书记录
-- 获取当前书籍总页数（V8: 长期任务≥2000页判定）
function FocusFeedback:_getCurrentBookPageCount()
    local count = 0
    pcall(function()
        if self.ui and self.ui.document then
            count = self.ui.document:getPageCount() or 0
        end
    end)
    return count
end

function FocusFeedback:_saveFinishedBookEntry(key, title, reading_seconds, reading_days, rating)
    local finished = self:_readFinishedBooks()
    -- 如果已有记录（跳过后重读再评），更新它
    local found = false
    for i, entry in ipairs(finished) do
        if entry.key == key then
            entry.rating = rating
            entry.title = title
            entry.reading_seconds = reading_seconds
            entry.reading_days = reading_days
            entry.finish_date = todayKey()
            found = true
            break
        end
    end
    if not found then
        table.insert(finished, {
            key = key,
            title = title,
            rating = rating,
            reading_seconds = reading_seconds,
            reading_days = reading_days,
            finish_date = todayKey(),
            page_count = self:_getCurrentBookPageCount(),
        })
    end
    self:_saveFinishedBooks(finished)
    logger.info("FocusFeedback V3: book finished:", title, "rating:", rating)

    -- V8: 今日读完书计数（每日任务 s4 判定）
    local stat = self:_getDailyStat()
    stat.finish = (stat.finish or 0) + 1
    self:_saveDailyStat(stat)
    -- V8: 长期任务「读完≥2000页的书」累计
    local page_count = self:_getCurrentBookPageCount()
    if page_count >= 2000 then
        local lstat = self:_readLongStat()
        lstat.big_books = (lstat.big_books or 0) + 1
        self:_saveLongStat(lstat)
    end

    -- 显示确认消息
    local msg
    if rating > 0 then
        msg = string.format("已评分：%.1f ★\n《%s》已存入读完图鉴", rating, title)
    else
        msg = string.format("《%s》已存入读完图鉴", title)
    end
    self:_showMessage(msg, 4)
end

-- ========== V2/V3 图鉴 ==========

function FocusFeedback:_showCollection()
    -- V8: 今日查看图鉴计数（每日任务 l4 判定）
    local stat = self:_getDailyStat()
    stat.collection = (stat.collection or 0) + 1
    self:_saveDailyStat(stat)

    local collection = self:_readCollection()
    local finished = self:_readFinishedBooks()

    -- 如果两边都空，直接提示
    if #collection == 0 and #finished == 0 then
        self:_showMessage("图鉴还是空的。\n去领养一本书吧！", 5)
        return
    end

    -- 双页面选择菜单
    local items = {}

    -- 养成书籍
    table.insert(items, {
        text = string.format("养成书籍（%d）", #collection),
        mandatory = nil,
        callback = function()
            self:_showAdoptionCollection()
        end,
    })

    -- 读完书籍
    table.insert(items, {
        text = string.format("读完书籍（%d）", #finished),
        mandatory = nil,
        callback = function()
            self:_showFinishedCollection()
        end,
    })

    local collection_menu = Menu:new{
        title = "图鉴",
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
        show_parent = nil,
    }
    UIManager:show(collection_menu)
end

-- 养成书籍列表
function FocusFeedback:_showAdoptionCollection()
    local collection = self:_readCollection()

    if #collection == 0 then
        self:_showMessage("养成图鉴还是空的。", 3)
        return
    end

    local items = {}
    for i, entry in ipairs(collection) do
        local book = self.book_data[entry.index] or { title = "未知", author = "" }
        table.insert(items, {
            text = entry.nickname or book.title,
            mandatory = entry.reveal_date,
            callback = function()
                self:_showBookDetailMenu(entry)
            end,
        })
    end

    local collection_menu = Menu:new{
        title = "养成书籍",
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
        show_parent = nil,
    }
    UIManager:show(collection_menu)
end

-- 养成书籍详情菜单：养成日记 / 书的信息
function FocusFeedback:_showBookDetailMenu(entry)
    local book = self.book_data[entry.index] or { title = "未知", author = "" }
    local items = {
        {
            text = "养成日记",
            callback = function()
                self:_showBookDetail(entry)
            end,
        },
        {
            text = "书的信息",
            callback = function()
                self:_showBookInfo(entry)
            end,
        },
    }
    local menu = Menu:new{
        title = string.format("《%s》", book.title),
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
        show_parent = nil,
    }
    UIManager:show(menu)
end

-- 书的信息弹窗：生日/成年日/年龄/六维属性
function FocusFeedback:_showBookInfo(entry)
    local book = self.book_data[entry.index] or { title = "未知", author = "", quote = "" }
    local attrs = entry.attributes or {}

    local function formatDate(date_str)
        if not date_str or date_str == "" then return "未知" end
        local y, m, d = date_str:match("(%d+)-(%d+)-(%d+)")
        if not y or not m or not d then return date_str end
        return string.format("%s年%s月%s日", y, m, d)
    end

    -- 年龄：领养日 -> 今天
    local age_text = "未知"
    if entry.adopt_date and entry.adopt_date ~= "" then
        local adopt_ts = self:_dateToTimestamp(entry.adopt_date)
        if adopt_ts then
            local days = math.floor((os.time() - adopt_ts) / 86400)
            if days < 0 then days = 0 end
            local years = math.floor(days / 365)
            local months = math.floor((days % 365) / 30)
            age_text = string.format("%d岁%d个月", years, months)
        end
    end

    local lines = {
        string.format("书名：《%s》", book.title),
        string.format("作者：%s", book.author or ""),
        "",
        string.format("生日（领养日）：%s", formatDate(entry.adopt_date)),
        string.format("成年日（翻开日）：%s", formatDate(entry.reveal_date)),
        string.format("年龄：%s", age_text),
        "",
        "书之属性：",
    }
    for _, attr in ipairs(ATTR_KEYS) do
        table.insert(lines, string.format("%s：%d%%", attr, attrs[attr] or 0))
    end

    local dialog
    dialog = ButtonDialog:new{
        title = table.concat(lines, "\n"),
        title_align = "left",
        buttons = {
            {
                {
                    text = "关闭",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

-- 读完书籍列表
function FocusFeedback:_showFinishedCollection()
    local finished = self:_readFinishedBooks()

    if #finished == 0 then
        self:_showMessage("读完图鉴还是空的。\n读完一本书后会自动记录。", 4)
        return
    end

    -- 计算汇总数据
    local total_rated = 0
    local sum_rating = 0
    local total_seconds = 0
    local total_days = 0
    for _, entry in ipairs(finished) do
        if entry.rating and entry.rating > 0 then
            total_rated = total_rated + 1
            sum_rating = sum_rating + entry.rating
        end
        total_seconds = total_seconds + (entry.reading_seconds or 0)
        total_days = total_days + (entry.reading_days or 0)
    end
    local avg_rating = total_rated > 0 and (sum_rating / total_rated) or 0

    local items = {}

    -- 汇总信息（作为第一项）
    local summary_text = string.format("平均 %.1f★ | %d 本 | 共 %s | %d 天",
        avg_rating, #finished, secondsToText(total_seconds), total_days)
    table.insert(items, {
        text = summary_text,
        mandatory = nil,
        callback = function()
            -- 点击汇总项不做任何事
        end,
        bold = true,
    })

    -- 每本读完的书
    for i, entry in ipairs(finished) do
        local stars = makeStarText(entry.rating or 0)
        local mandatory_text = string.format("%.1f★", entry.rating or 0)
        table.insert(items, {
            text = string.format("《%s》 %s", entry.title or "未知", stars),
            mandatory = entry.finish_date or "",
            callback = function()
                self:_showFinishedBookDetail(entry)
            end,
        })
    end

    local collection_menu = Menu:new{
        title = "读完书籍",
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
        show_parent = nil,
    }
    UIManager:show(collection_menu)
end

-- 读完书籍详情
function FocusFeedback:_showFinishedBookDetail(entry)
    local stars = makeStarText(entry.rating or 0)
    local rating_text = entry.rating and entry.rating > 0
        and string.format("%.1f 分 %s", entry.rating, stars)
        or "未评分"

    local avail_w = Screen:getWidth() * 0.85

    local parts = {}

    -- 书形象图片
    local img = self:_safeLoadImage(80)
    if img then
        table.insert(parts, centerIn(img, avail_w))
        table.insert(parts, VerticalSpan:new{ width = Size.padding.default })
    end

    local title_w = TextWidget:new{
        text = string.format("《%s》", entry.title or "未知书名"),
        face = Font:getFace("cfont", 18),
    }
    table.insert(parts, centerIn(title_w, avail_w))
    table.insert(parts, VerticalSpan:new{ width = Size.padding.default })

    local rating_w = TextWidget:new{
        text = string.format("评分：%s", rating_text),
        face = Font:getFace("cfont", 16),
    }
    table.insert(parts, centerIn(rating_w, avail_w))

    local stats_text = string.format("阅读时长：%s  |  阅读天数：%d 天",
        secondsToText(entry.reading_seconds or 0), entry.reading_days or 0)
    local stats_w = TextWidget:new{
        text = stats_text,
        face = Font:getFace("cfont", 14),
    }
    table.insert(parts, centerIn(stats_w, avail_w))

    local date_w = TextWidget:new{
        text = string.format("读完日期：%s", entry.finish_date or "未知"),
        face = Font:getFace("cfont", 14),
    }
    table.insert(parts, centerIn(date_w, avail_w))

    local content = VerticalGroup:new{ align = "center", unpack(parts) }
    content.not_focusable = true

    local dialog
    dialog = ButtonDialog:new{
        title = "",
        title_align = "center",
        buttons = {
            {
                {
                    text = "关闭",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = "删除",
                    callback = function()
                        self:_confirmDeleteFinishedBook(entry, dialog)
                    end,
                },
            },
        },
    }

    avail_w = dialog:getAddedWidgetAvailableWidth() or avail_w
    dialog:addWidget(content)

    UIManager:show(dialog)
end

-- 删除读完书记录（三次确认）
function FocusFeedback:_confirmDeleteFinishedBook(entry, parent_dialog)
    local confirm1
    confirm1 = ButtonDialog:new{
        title = "",
        title_align = "center",
        buttons = {
            {
                {
                    text = "取消",
                    callback = function()
                        UIManager:close(confirm1)
                    end,
                },
                {
                    text = "确定删除",
                    callback = function()
                        UIManager:close(confirm1)
                        local confirm2
                        confirm2 = ButtonDialog:new{
                            title = "",
                            title_align = "center",
                            buttons = {
                                {
                                    {
                                        text = "取消",
                                        callback = function()
                                            UIManager:close(confirm2)
                                        end,
                                    },
                                    {
                                        text = "真的要删除",
                                        callback = function()
                                            UIManager:close(confirm2)
                                            local confirm3
                                            confirm3 = ButtonDialog:new{
                                                title = "",
                                                title_align = "center",
                                                buttons = {
                                                    {
                                                        {
                                                            text = "取消",
                                                            callback = function()
                                                                UIManager:close(confirm3)
                                                            end,
                                                        },
                                                        {
                                                            text = "最终确认",
                                                            callback = function()
                                                                UIManager:close(confirm3)
                                                                if parent_dialog then
                                                                    pcall(function() UIManager:close(parent_dialog) end)
                                                                end
                                                                self:_deleteFinishedBook(entry)
                                                            end,
                                                        },
                                                    },
                                                },
                                            }
                                            UIManager:show(confirm3)
                                            local msg3 = TextWidget:new{
                                                text = "删除后不可恢复，确定？",
                                                face = Font:getFace("cfont", 16),
                                            }
                                            local avail_w3 = Screen:getWidth() * 0.85
                                            confirm3:addWidget(centerIn(msg3, avail_w3))
                                        end,
                                    },
                                },
                            },
                        }
                        UIManager:show(confirm2)
                        local msg2 = TextWidget:new{
                            text = string.format("真的要删除《%s》吗？", entry.title or "未知"),
                            face = Font:getFace("cfont", 16),
                        }
                        local avail_w2 = Screen:getWidth() * 0.85
                        confirm2:addWidget(centerIn(msg2, avail_w2))
                    end,
                },
            },
        },
    }
    UIManager:show(confirm1)
    local msg1 = TextWidget:new{
        text = string.format("要从图鉴中删除《%s》吗？", entry.title or "未知"),
        face = Font:getFace("cfont", 16),
    }
    local avail_w1 = Screen:getWidth() * 0.85
    confirm1:addWidget(centerIn(msg1, avail_w1))
end

-- 执行删除读完书记录
function FocusFeedback:_deleteFinishedBook(entry)
    local finished = self:_readFinishedBooks()
    for i, e in ipairs(finished) do
        if e.key == entry.key and (e.title or "") == (entry.title or "") then
            table.remove(finished, i)
            break
        end
    end
    self:_saveFinishedBooks(finished)
    self:_showMessage(string.format("《%s》已从图鉴中删除", entry.title or "未知"), 3)
end

function FocusFeedback:_showBookDetail(entry)
    local book = self.book_data[entry.index] or { title = "未知", author = "", quote = "" }
    local nickname = entry.nickname or "小书"

    -- 日期格式化：YYYY-MM-DD -> YYYY年MM月DD日
    local function formatDate(date_str)
        if not date_str or date_str == "" then return "未知日期" end
        local y, m, d = date_str:match("(%d+)-(%d+)-(%d+)")
        if not y or not m or not d then return date_str end
        return string.format("%s年%s月%s日", y, m, d)
    end

    -- 事件描述映射：event_key -> (encounter_desc, reward_desc)
    local function getEventDesc(event_key)
        -- 新格式："encounter|reward"
        if type(event_key) == "string" and event_key:find("|") then
            local encounter, reward = event_key:match("([^|]+)|(.+)")
            if encounter and reward then return encounter, reward end
        end
        -- 陌生人事件
        if self.event_data and self.event_data.strangers then
            for _, s in ipairs(self.event_data.strangers) do
                if s.key == event_key then
                    local reward = s.reward_name or "一份礼物"
                    return s.name or "陌生人", reward
                end
            end
        end
        -- 特殊事件
        if self.event_data and self.event_data.special_events then
            for _, e in ipairs(self.event_data.special_events) do
                if e.key == event_key then
                    local reward = e.reward_name
                    if not reward and e.points then
                        reward = e.points .. "积分"
                    end
                    reward = reward or "一份礼物"
                    return e.title or "特殊事件", reward
                end
            end
        end
        -- 通用事件类型映射（兼容旧数据）
        local event_map = {
            bookmark    = { "书签掉落", "一片书签" },
            stranger    = { "陌生人", "一份礼物" },
            book_friend = { "书际关系", "一些物品" },
            babel       = { "巴别图书馆", "10积分" },
            fly_away    = { "书飞走了", "平安归来" },
        }
        local mapped = event_map[event_key]
        if mapped then return mapped[1], mapped[2] end
        return event_key or "未知事件", "一份礼物"
    end

    -- 获取事件日志（优先使用 entry 中存储的快照）
    local event_log = entry.event_log
    if not event_log then
        -- 回退：使用全局事件日志，按日期范围过滤
        event_log = {}
        local global_log = self:_readEventLog()
        local adopt_date = entry.adopt_date or ""
        local reveal_date = entry.reveal_date or ""
        for _, evt in ipairs(global_log) do
            if evt.date >= adopt_date and evt.date <= reveal_date then
                table.insert(event_log, evt)
            end
        end
    end

    -- ========== Page 1: 时间线 ==========
    local timeline_lines = {}

    -- 领养行（优先从事件日志获取，否则用 adopt_date）
    local has_adopt_log = false
    for _, evt in ipairs(event_log) do
        if evt.type == "领养" then
            table.insert(timeline_lines, string.format("%s，你领养了%s。", formatDate(evt.date), nickname))
            has_adopt_log = true
            break
        end
    end
    if not has_adopt_log and entry.adopt_date and entry.adopt_date ~= "" then
        table.insert(timeline_lines, string.format("%s，你领养了%s。", formatDate(entry.adopt_date), nickname))
    end

    -- 事件日志条目
    for _, evt in ipairs(event_log) do
        local date_str = formatDate(evt.date)
        if evt.type == "first_event" then
            local encounter, reward = getEventDesc(evt.detail)
            table.insert(timeline_lines, string.format("%s，%s遇见了%s，获得了%s。", date_str, nickname, encounter, reward))
        else
            local m = evt.type:match("^milestone_(%d+)$")
            if m then
                table.insert(timeline_lines, string.format("%s，%s的成长进度来到了%s%%。", date_str, nickname, m))
            end
        end
    end

    -- 翻开行
    if entry.reveal_date and entry.reveal_date ~= "" then
        table.insert(timeline_lines, string.format("%s，你首次翻开了%s。", formatDate(entry.reveal_date), nickname))
    end

    local page1_text = table.concat(timeline_lines, "\n")

    -- ========== Page 2: 总结 ==========
    -- 天数
    local days = "未知"
    if entry.adopt_date and entry.adopt_date ~= "" then
        local adopt_ts = self:_dateToTimestamp(entry.adopt_date)
        local reveal_ts = self:_dateToTimestamp(entry.reveal_date)
        if adopt_ts and reveal_ts then
            days = tostring(math.floor((reveal_ts - adopt_ts) / 86400))
        end
    end

    -- 阅读时长（小时）
    local reading_hours = "未知"
    if entry.reading_seconds and entry.reading_seconds > 0 then
        reading_hours = string.format("%.1f", entry.reading_seconds / 3600)
    end

    -- 书籍数量和书名
    local books = entry.adoption_books or self:_readAdoptionBooks()
    local book_count = entry.adoption_book_count or #books
    local book_list_text
    if #books >= 3 then
        book_list_text = string.format("一起读了《%s》、《%s》、《%s》等%d本书籍，",
            books[1], books[2], books[3], book_count)
    elseif #books > 0 then
        local parts = {}
        for i = 1, #books do
            table.insert(parts, "《" .. books[i] .. "》")
        end
        book_list_text = string.format("一起读了%s等%d本书籍，", table.concat(parts, "、"), book_count)
    else
        book_list_text = string.format("一起走过了%d本书籍，", book_count)
    end

    -- 食物消耗
    local consumed = entry.food_consumed or self:_readFoodConsumed()
    local cotton_count = tostring(consumed.cotton or 0)
    local biscuit_count = tostring(consumed.biscuit or 0)

    local page2_lines = {
        string.format("你或许已经习惯了称呼它为%s，", nickname),
        string.format("但它更正式的名字叫作《%s》。", book.title),
        string.format("你们共度了%s天的时光，", days),
        string.format("期间共计阅读%s小时，", reading_hours),
        book_list_text,
        string.format("消耗了%s个棉花糖与%s个饼干。", cotton_count, biscuit_count),
        "",
        "感谢您的陪伴和爱护，",
        string.format("%s将去往更广阔的世界里，", nickname),
        "成为人类文明中复杂且深刻的一部分。",
        "",
        string.format("                    %s", formatDate(entry.reveal_date)),
    }
    local page2_text = table.concat(page2_lines, "\n")

    -- ========== 显示第一页 ==========
    local dialog1
    dialog1 = ButtonDialog:new{
        title = page1_text,
        title_align = "center",
        buttons = {
            {
                {
                    text = "总结",
                    callback = function()
                        UIManager:close(dialog1)
                        local dialog2
                        dialog2 = ButtonDialog:new{
                            title = page2_text,
                            title_align = "center",
                            buttons = {
                                {
                                    {
                                        text = "返回",
                                        callback = function()
                                            UIManager:close(dialog2)
                                            self:_showBookDetail(entry)
                                        end,
                                    },
                                    {
                                        text = "关闭",
                                        callback = function()
                                            UIManager:close(dialog2)
                                        end,
                                    },
                                },
                            },
                        }
                        UIManager:show(dialog2)
                    end,
                },
                {
                    text = "关闭",
                    callback = function()
                        UIManager:close(dialog1)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog1)
end

-- 日期字符串转时间戳
function FocusFeedback:_dateToTimestamp(date_str)
    if not date_str or date_str == "" then return nil end
    local y, m, d = date_str:match("(%d+)-(%d+)-(%d+)")
    if not y or not m or not d then return nil end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

-- ========== V1 UI 方法 ==========

function FocusFeedback:_showMessage(text, timeout)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout or 5,
    })
end

function FocusFeedback:_showMilestone(total_seconds, minute)
    -- 关闭已有弹窗
    if self.current_banner then
        pcall(function()
            UIManager:close(self.current_banner)
        end)
        self.current_banner = nil
    end

    -- V1 弹窗
    local msg = string.format(
        "今日累计阅读 %s\n\n%s",
        secondsToText(total_seconds),
        self:_randomQuote()
    )
    self.current_banner = InfoMessage:new{
        text = msg,
        timeout = nil,
    }
    UIManager:show(self.current_banner)
    logger.info("FocusFeedback milestone:", minute, "minutes")

    -- V4 获得积分（替换原食物掉落）
    pcall(function()
        self:_awardPoints(minute)
    end)
end

-- ========== V1 计时逻辑 ==========

function FocusFeedback:_isActiveReading(now)
    if not self.enabled or self.suspended then
        return false
    end
    -- 屏保模式下不计时
    local Device = require("device")
    if Device.screen_saver_mode then
        return false
    end
    -- V9: 仅翻页/标注视为真正阅读，排除插件交互、调试等非阅读操作
    if not self.last_page_turn_wall then
        return false
    end
    return (now - self.last_page_turn_wall) <= IDLE_TIMEOUT_SECONDS
end

function FocusFeedback:_onActivity(now)
    local _, today_seconds, last_notified = self:_readToday()

    if self:_isActiveReading(now) then
        if self.last_event_wall then
            local diff = now - self.last_event_wall
            if diff > 0 and diff <= IDLE_TIMEOUT_SECONDS then
                today_seconds = today_seconds + diff
                -- V8: 单次不间断阅读时长 + 时段阅读统计（每日任务）
                local stat = self:_getDailyStat()
                -- V8: 当日阅读总秒数（补领昨日任务时用昨日数据判定）
                stat.reading_seconds = today_seconds
                stat.session_cur = (stat.session_cur or 0) + diff
                stat.session_max = math.max(stat.session_max or 0, stat.session_cur)
                local hh = tonumber(os.date("%H")) or 0
                if hh >= 19 and hh < 22 then stat.h19_22 = (stat.h19_22 or 0) + diff end
                if hh >= 0 and hh < 3 then stat.h0_3 = (stat.h0_3 or 0) + diff end
                self:_saveDailyStat(stat)
                -- V14: 模式相关累计（挑战时长/长期模式统计/心跳每日首读）
                pcall(function()
                    local v14_mode = self:_getActiveMode()
                    if v14_mode == MODE_CHALLENGE then
                        local m = self:_readModeState()
                        m.ch_reading_sec = (m.ch_reading_sec or 0) + diff
                        self:_saveModeState(m)
                    elseif v14_mode == MODE_SPRINT then
                        local m = self:_readModeState()
                        m.spr_read = (m.spr_read or 0) + diff
                        self:_saveModeState(m)
                        if m.spr_read >= (m.spr_goal_sec or math.huge) then
                            self:_settleSprint()
                        end
                    end
                    local long = self:_readLongMode()
                    if long.cycle and not long.settled then
                        local ltoday = todayKey()
                        if long.last_read_date ~= ltoday then
                            long.read_days = (long.read_days or 0) + 1
                            long.last_read_date = ltoday
                        end
                        long.read_seconds = (long.read_seconds or 0) + diff
                        self:_saveLongMode(long)
                    end
                    if v14_mode == MODE_HEARTBEAT then
                        local m = self:_readModeState()
                        local htoday = todayKey()
                        if m.hb_date ~= htoday then
                            m.hb_date = htoday
                            m.hb_result = nil
                            self:_saveModeState(m)
                            -- 每日首次阅读触发硬币弹窗
                            UIManager:show(self:_buildCoinFlipDialog())
                        end
                    end
                    if v14_mode == MODE_DRAW then
                        -- 抽签模式：每日首次阅读触发今日抽签弹窗（未抽签时）
                        self:_showDrawDialog()
                    end
                end)
                -- 累计领养期间的阅读时长
                if self:_readAdopted() then
                    self:_saveAdoptReadingSeconds(self:_readAdoptReadingSeconds() + diff)
                    -- V8: 长期任务「累计阅读」全局累计（跨书不受弃养/重领养影响）
                    local lstat = self:_readLongStat()
                    lstat.read_seconds = (lstat.read_seconds or 0) + diff
                    self:_saveLongStat(lstat)
                    -- V4: 阅读增加心情值 0.4%/分钟
                    -- 抽签当日效果（心情增长维度）：上吉翻倍 / 中下减半 / 满格·锁死兜底
                    -- V14: 挑战成功心情拉满8h不掉落：期间心情锁死100，并刷新衰减基准
                    local mood = self:_readMood()
                    local boost_until = G_reader_settings:readSetting(settingKey("v14_mood_boost_until"), 0) or 0
                    if boost_until > os.time() then
                        mood = 100
                        self:_saveLastMoodUpdate(os.time())
                    else
                        local mood_rate = MOOD_PER_READ_MIN
                        local mfx = self:_drawEffect()
                        if mfx == "luxury_joy" then
                            mood_rate = mood_rate * 2
                        elseif mfx == "blue_book" then
                            mood_rate = mood_rate * 0.5
                        end
                        mood = math.min(100, mood + (diff / 60) * mood_rate)
                        if mfx == "happy_day" then mood = 100
                        elseif mfx == "depression" then mood = MOOD_MIN
                        elseif mfx == "mood_floor" then mood = math.max(50, mood) end
                    end
                    self:_saveMood(mood)
                end
                -- V8: 长期任务「连续阅读」天数更新（昨天连续则+1，中断则归1，当天只计一次）
                local last_date = self:_readLastReadDate()
                local today_str = todayKey()
                if last_date ~= today_str then
                    local yesterday_str = os.date("%Y-%m-%d", os.time() - 86400)
                    if last_date == yesterday_str then
                        self:_saveStreakDays(self:_readStreakDays() + 1)
                    else
                        self:_saveStreakDays(1)
                    end
                    self:_saveLastReadDate(today_str)
                end
                -- V3: 累计当前书的阅读时长
                pcall(function()
                    self:_addBookReadingTime(diff)
                end)
                -- V15: 阅读时长累计 -> 属性增长
                pcall(function()
                    self:_growAttributesFromReading(diff)
                end)
            end
        end

        local current_minute = math.floor(today_seconds / 60)
        if current_minute > last_notified then
            local crossed = crossedMilestone(last_notified, current_minute)
            if crossed then
                last_notified = current_minute
                self:_showMilestone(today_seconds, current_minute)
            end
        end

        self:_saveToday(today_seconds, last_notified)
    else
        -- V8: 阅读中断，单次不间断时长归零
        local stat = self:_getDailyStat()
        if self:_getActiveMode() == MODE_FLOW then
            -- 心流模式：退出文档/休眠/熄屏后 FLOW_RESUME_GRACE(2分钟)内回来不算断
            local last_act = self.last_page_turn_wall
            local since = last_act and (now - last_act) or math.huge
            if since > FLOW_RESUME_GRACE then
                stat.session_cur = 0
            end
        else
            stat.session_cur = 0
        end
        self:_saveDailyStat(stat)
    end

    self.last_event_wall = now
end

function FocusFeedback:_tick()
    self:_onActivity(os.time())
    -- V14: 模式自动结算/自动关闭/长期结算
    pcall(function() self:_checkModeAuto() end)
    -- V5: 随机事件检查
    pcall(function() self:_checkRandomEvents() end)
    -- V8: 轮询标注数量（某些阅读器后端不触发 onAnnotationsUpdated）
    pcall(function() self:_checkAnnotationCount() end)
    -- V15.1: 书之来信（成年书测试书注入 + 离线来信检查）
    -- 每个环节独立保护，避免任一异常吞掉来信检查
    pcall(function() self:_ensureTestBooks() end)
    pcall(function() self:_inboxInit() end)
    pcall(function()
        local ok, err = pcall(function() self:_showInboxLetters() end)
        if not ok then logger.warn("FocusFeedback inbox check error:", err) end
    end)
    -- 旅行的书：在线阅读时偶尔补记动态
    pcall(function() self:_travelInlineCheck() end)
    self:_schedule()
end

function FocusFeedback:_schedule()
    if self.task and not self.scheduled then
        UIManager:scheduleIn(TICK_SECONDS, self.task)
        self.scheduled = true
    end
end

function FocusFeedback:_unschedule()
    if self.task and self.scheduled then
        UIManager:unschedule(self.task)
        self.scheduled = false
    end
end

function FocusFeedback:_startTimer()
    self.last_input_wall = os.time()
    self.last_event_wall = os.time()
    self:_unschedule()
    self:_schedule()
end

-- ========== 事件处理 ==========

function FocusFeedback:init()
    math.randomseed(os.time())
    self:_loadSentencePool()
    self.enabled = G_reader_settings:isTrue(settingKey("enabled"))
    self.task = function()
        self.scheduled = false
        self:_tick()
    end

    UIManager.event_hook:registerWidget("InputEvent", self)
    -- V8: 监听标注事件（每日任务 n3/r2/s5 判定）
    pcall(function()
        UIManager.event_hook:registerWidget("AnnotationsUpdated", self)
    end)
    self.ui.menu:registerToMainMenu(self)
    self:_readToday()
    -- 首次加载时清空旧图鉴（v2.1 升级）
    if not G_reader_settings:isTrue(settingKey("v2_collection_cleared")) then
        self:_saveCollection({})
        G_reader_settings:saveSetting(settingKey("v2_collection_cleared"), true)
    end
    -- V6: 测试积分（一次性 +100，便于测试商超新物品）
    if not G_reader_settings:isTrue(settingKey("v6_debug_100")) then
        local pts = self:_readPoints()
        self:_savePoints(pts + 100)
        G_reader_settings:saveSetting(settingKey("v6_debug_100"), true)
        logger.info("FocusFeedback V6: test points +100, total:", pts + 100)
    end
    -- V9: 注册快捷手势动作
    pcall(function()
        Dispatcher:init()
        self:onDispatcherRegisterActions()
    end)
    if self.enabled then
        self:_startTimer()
    end
end

-- V9: 注册快捷手势动作到 KOReader Dispatcher
function FocusFeedback:onDispatcherRegisterActions()
    pcall(function()
        Dispatcher:registerAction("focus_feedback_adoption", {
            category = "none",
            event = "FocusFeedbackAdoption",
            title = _("养书：领养一本书"),
            general = true,
        })
        Dispatcher:registerAction("focus_feedback_collection", {
            category = "none",
            event = "FocusFeedbackCollection",
            title = _("养书：图鉴"),
            general = true,
        })
        Dispatcher:registerAction("focus_feedback_shop", {
            category = "none",
            event = "FocusFeedbackShop",
            title = _("养书：商超"),
            general = true,
        })
        Dispatcher:registerAction("focus_feedback_warehouse", {
            category = "none",
            event = "FocusFeedbackWarehouse",
            title = _("养书：仓库"),
            general = true,
        })
        Dispatcher:registerAction("focus_feedback_travel", {
            category = "none",
            event = "FocusFeedbackTravel",
            title = _("养书：旅行的书"),
            general = true,
        })
    end)
end

-- V9: 快捷手势回调
function FocusFeedback:onFocusFeedbackAdoption()
    pcall(function() self:_showAdoptionPage() end)
end

function FocusFeedback:onFocusFeedbackCollection()
    pcall(function() self:_showCollection() end)
end

function FocusFeedback:onFocusFeedbackShop()
    pcall(function() self:_showShop() end)
end

function FocusFeedback:onFocusFeedbackWarehouse()
    pcall(function() self:_showWarehouse() end)
end

function FocusFeedback:onFocusFeedbackTravel()
    pcall(function() self:_showTravelBookList() end)
end

-- V9: SimpleUI 公开入口（供 Custom Quick Action 调用）
function FocusFeedback:showMainPanel()
    pcall(function() self:_showAdoptionPage() end)
end

function FocusFeedback:onReaderReady()
    -- 重置书 key 和读完触发标记
    self._current_book_key = nil
    self._end_book_triggered = false
    self._last_annotation_count = nil  -- 重置标注基准，首次检测时初始化
    self:_getBookKey()
    -- V15: 首次点开一本书时弹出分类选择
    pcall(function()
        self:_ensureBookCategory()
    end)
    -- V5: 记录领养期间阅读的书
    if self:_readAdopted() and not self.reveal_book then
        pcall(function()
            local title = "未知"
            if self.ui and self.ui.document then
                local props = self.ui.document:getProps()
                if props and props.title and props.title ~= "" then
                    title = props.title
                elseif self.ui.document.file then
                    title = self.ui.document.file:match("([^/\\]+)%.[^.]+$") or title
                end
            end
            self:_addAdoptionBook(title)
        end)
    end
end

-- V8: 轮询标注数量（onAnnotationsUpdated 在某些阅读器后端不触发）
function FocusFeedback:_checkAnnotationCount()
    pcall(function()
        if not self.ui then return end
        local annotations = nil
        -- 尝试多种路径获取标注列表
        if self.ui.highlight and self.ui.highlight.annotations then
            annotations = self.ui.highlight.annotations
        elseif self.ui.annotation and self.ui.annotation.annotations then
            annotations = self.ui.annotation.annotations
        end
        if not annotations then return end

        local count = 0
        for _ in pairs(annotations) do
            count = count + 1
        end

        if self._last_annotation_count == nil then
            -- 首次初始化，不计数
            self._last_annotation_count = count
        elseif count > self._last_annotation_count then
            local diff = count - self._last_annotation_count
            local stat = self:_getDailyStat()
            stat.notes = (stat.notes or 0) + diff
            self:_saveDailyStat(stat)
            self._last_annotation_count = count
        elseif count < self._last_annotation_count then
            -- 标注被删除，更新基准但不减少计数
            self._last_annotation_count = count
        end
    end)
end

function FocusFeedback:onInputEvent()
    local now = os.time()
    self:_onActivity(now)
    self.last_input_wall = now
    -- 持久化最后阅读时间（用于跨会话弃养检查）
    self:_saveLastReadTime(now)
    -- V8: 翻页检测（每日任务 l2 判定）+ V9: 翻页更新阅读活动时间
    pcall(function()
        if self.ui and self.ui.document then
            local page = self.ui.document:getCurrentPage()
            if page and page ~= self._last_page then
                self._last_page = page
                self.last_page_turn_wall = now  -- V9: 翻页更新阅读活动时间
                local stat = self:_getDailyStat()
                stat.pages = (stat.pages or 0) + 1
                self:_saveDailyStat(stat)
            end
        end
    end)
    -- V8: 轮询标注数量（onAnnotationsUpdated 在某些阅读器不触发）
    self:_checkAnnotationCount()
end

-- V9: 翻页事件（page 模式）— 更可靠地捕获翻页
function FocusFeedback:onPageUpdate()
    self.last_page_turn_wall = os.time()
    pcall(function()
        if self.ui and self.ui.document then
            local page = self.ui.document:getCurrentPage()
            if page and page ~= self._last_page then
                self._last_page = page
                local stat = self:_getDailyStat()
                stat.pages = (stat.pages or 0) + 1
                self:_saveDailyStat(stat)
            end
        end
    end)
end

-- V9: 滚动事件（scroll 模式）— 滚动也算阅读活动
function FocusFeedback:onPosUpdate()
    self.last_page_turn_wall = os.time()
end

-- V8: 标注事件回调（每日任务 n3/r2/s5 判定）
function FocusFeedback:onAnnotationsUpdated()
    self.last_page_turn_wall = os.time()  -- V9: 标注也算阅读活动
    local stat = self:_getDailyStat()
    stat.notes = (stat.notes or 0) + 1
    self:_saveDailyStat(stat)
end

function FocusFeedback:onSuspend()
    self.suspended = true
    self:_unschedule()
    self:_saveSuspendTs(os.time())
end

function FocusFeedback:onResume()
    self.suspended = false
    -- V4: 休眠期间心情衰减
    local suspend_ts = self:_readSuspendTs()
    if suspend_ts and suspend_ts > 0 then
        local now = os.time()
        local duration = now - suspend_ts
        local hours = duration / 3600
        if hours > 0 then
            -- V14: 挑战成功心情拉满8h不掉落；摸鱼模式心情锁死60
            local boost_until = G_reader_settings:readSetting(settingKey("v14_mood_boost_until"), 0) or 0
            local v14_mode = self:_getActiveMode()
            if boost_until > now then
                self:_saveMood(100)
            elseif v14_mode == MODE_SLACK then
                self:_saveMood(60)
            else
            local start_mood = self:_readMood()
            -- 碎纸屑期间按快速掉落速率（20%/h），否则按休眠速率（6%/h）
            local decay = MOOD_DECAY_SUSPEND
            if self:_readScrapsState().active then
                decay = MOOD_DECAY_SCRAPS
            end
            -- V6: 小兔在身边时，心情值掉落速度×0.5
            local pet = self:_readPet()
            if pet.rabbit then
                decay = decay * 0.5
            end
            local end_mood = math.max(MOOD_MIN, start_mood - hours * decay)

            -- V11: 精确计算休眠期间心情≥50%的时长（线性衰减）
            local time_above_50 = 0
            if end_mood >= 50 then
                time_above_50 = duration
            elseif start_mood > 50 then
                -- 心情在休眠中途跌破50%，计算前半段时间
                time_above_50 = (start_mood - 50) / (start_mood - end_mood) * duration
            end
            if time_above_50 > 0 then
                local stat = self:_getDailyStat()
                -- 只统计今天的部分（跨午夜时截掉昨天的部分）
                local t = os.date("*t", now)
                local today_midnight = os.time({year=t.year, month=t.month, day=t.day, hour=0})
                if suspend_ts < today_midnight then
                    -- 休眠跨午夜，只算从午夜开始的部分
                    local today_duration = now - today_midnight
                    if time_above_50 > today_duration then
                        time_above_50 = today_duration
                    end
                end
                stat.mood_above_50_secs = (stat.mood_above_50_secs or 0) + time_above_50
                self:_saveDailyStat(stat)
                -- 更新累计时间戳，避免 _saveMood 重复累计
                G_reader_settings:saveSetting(settingKey("v8_mood_last_accum"), now)
            end

            self:_saveMood(end_mood)
            end
        end
        self:_saveSuspendTs(0)
        -- 更新心情时间戳，防止 _updateMood 重复计算休眠期间的衰减
        self:_saveLastMoodUpdate(os.time())
    end
    -- V9: 唤醒后需翻页才恢复计时，避免休眠后短暂操作被计入阅读
    -- 心流模式保留 last_page_turn_wall，用于「2分钟内回来不算断」的缓冲判定
    if self:_getActiveMode() ~= MODE_FLOW then
        self.last_page_turn_wall = nil
    end
    -- V15.1: 唤醒时立即检查书之来信（注入测试书 + 离线来信）
    pcall(function() self:_ensureTestBooks() end)
    pcall(function() self:_inboxInit() end)
    pcall(function() self:_showInboxLetters() end)
    self:_startTimer()
end

-- V3: 读完一本书
function FocusFeedback:onEndOfBook()
    self:_triggerEndBookRating()
end

function FocusFeedback:onCloseDocument()
    -- V3: 不再自动检测末页触发评分，避免分章节书籍误触发
    -- 读者可通过菜单"标记读完当前书"手动触发

    if self.current_banner then
        pcall(function() UIManager:close(self.current_banner) end)
        self.current_banner = nil
    end
    if self.adoption_page then
        pcall(function() UIManager:close(self.adoption_page) end)
        self.adoption_page = nil
    end
    -- 持久化最后阅读时间
    self:_saveLastReadTime(os.time())
    self:_unschedule()
end

function FocusFeedback:onCloseWidget()
    if self.current_banner then
        pcall(function() UIManager:close(self.current_banner) end)
        self.current_banner = nil
    end
    if self.adoption_page then
        pcall(function() UIManager:close(self.adoption_page) end)
        self.adoption_page = nil
    end
    self:_unschedule()
    self.task = nil
end

-- ========== V14 KOAssistant 测验联动 ==========

-- 监听 KOAssistant 章节测验完成事件（需配合 koassistant_quiz_viewer.lua 补丁）
-- 规则：
--   1. 选择题整节全对 +1 分（整节仅1分，不按题）
--   2. 简答/讨论每题答对 +1 分
--   3. 答错一题 -3% 心情（挑战成功8h拉满期间不扣）
--   4. 积分直接入账，不走寄存/模式逻辑；计入每日任务
function FocusFeedback:onKoassistantQuizFinished(payload)
    if not self:_readAdopted() then return end
    if type(payload) ~= "table" then return end
    local total_correct = payload.total_correct or 0
    local total_answered = payload.total_answered or 0
    local mc_correct = payload.mc_correct or 0
    local mc_answered = payload.mc_answered or 0
    local sa_correct = payload.sa_correct or 0
    local essay_correct = payload.essay_correct or 0

    -- 1. 积分：选择题整节全对（已答选择题全部答对）+1，简答/讨论每题+1
    local mc_points = (mc_answered > 0 and mc_correct == mc_answered) and 1 or 0
    local points = mc_points + sa_correct + essay_correct
    if points > 0 then
        self:_addPoints(points)
    end

    -- 2. 心情：答错一题-3%（挑战成功8h拉满期间不扣）
    local wrong = total_answered - total_correct
    local mood_lost = 0
    if wrong > 0 then
        local boost_until = G_reader_settings:readSetting(settingKey("v14_mood_boost_until"), 0) or 0
        if boost_until <= os.time() then
            mood_lost = 3 * wrong
            local mood = self:_readMood()
            self:_saveMood(mood - mood_lost)
        end
    end

    -- 3. 每日任务：完成一次测验 / 满分（已答题全部答对）
    local stat = self:_getDailyStat()
    stat.quiz = (stat.quiz or 0) + 1
    if total_answered > 0 and total_correct == total_answered then
        stat.quiz_perfect = (stat.quiz_perfect or 0) + 1
    end
    self:_saveDailyStat(stat)

    -- 4. 提示
    local msg = string.format("测验完成！积分+%d", points)
    if mood_lost > 0 then
        msg = msg .. string.format("，心情值-%d%%", mood_lost)
    end
    self:_showMessage(msg, 5)
end

-- ========== 菜单 ==========

function FocusFeedback:_toggleEnabled(menu)
    self.enabled = not self.enabled
    if self.enabled then
        G_reader_settings:saveSetting(settingKey("enabled"), true)
        self:_startTimer()
        self:_showMessage("专注力正反馈已开启。", 3)
    else
        G_reader_settings:makeFalse(settingKey("enabled"))
        self:_unschedule()
        self:_showMessage("专注力正反馈已暂停。", 3)
    end
    if menu then
        menu:updateItems()
    end
end

function FocusFeedback:_resetToday(menu)
    if self.current_banner then
        pcall(function() UIManager:close(self.current_banner) end)
        self.current_banner = nil
    end
    self:_saveToday(0, 0)
    self.last_input_wall = os.time()
    self.last_event_wall = os.time()
    self:_showMessage("今日专注统计已清零。", 3)
    if menu then
        menu:updateItems()
    end
end

-- ========== V5 随机事件系统 ==========

-- 统一事件弹窗
-- title: 标题文本（无黑框，居中，下方有横线）
-- text: 正文（与书图片左右排列，自动按每行18字符断行）
-- reward_text: 奖励说明（自动换行合并到正文末尾，如 "*获得xxx×1"）
-- buttons: 按钮数组，每个元素 {text=, callback=}，callback 返回 false 则不关闭弹窗
function FocusFeedback:_showEventPopup(title, text, reward_text, buttons)
    if not buttons or #buttons == 0 then
        buttons = {{text = "确定", callback = function() end}}
    end

    local dialog
    local wrapped_buttons = {}
    for i = 1, #buttons do
        local btn = buttons[i]
        local orig_callback = btn.callback
        wrapped_buttons[i] = {
            text = btn.text,
            callback = function()
                local should_close = true
                if orig_callback then
                    should_close = orig_callback()
                end
                if should_close ~= false then
                    UIManager:close(dialog)
                end
            end,
        }
    end

    dialog = ButtonDialog:new{
        title = "",
        title_align = "center",
        -- V8: 固定弹窗宽度并关闭内容滚动，文案变长时弹窗整体变高
        width = Screen:scaleBySize(560),
        scrollable_content = false,
        buttons = {wrapped_buttons},
    }

    -- V8: 精确计算可用宽度（不依赖 addWidget 前的 getAddedWidgetAvailableWidth）
    local border_w = Size.border.window
    local padding_w = Size.padding.default
    local avail_w = dialog.width - 2 * (border_w + padding_w)
    local parts = {}

    -- V7: 中文标点精确匹配（避免字节级误判）
    local puncts = {"，","。","！","？","；","：","、","）","】","』","」","…","—","“","”"}
    local function isPunct(ch)
        for _, p in ipairs(puncts) do
            if ch == p then return true end
        end
        return false
    end
    -- V7: 每行最多18个UTF-8字符断行，优先在标点后断
    local function wrap18(s)
        if not s or s == "" then return "" end
        s = tostring(s)
        local lines = {}
        local line = ""
        local n = 0
        for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            line = line .. ch
            n = n + 1
            if n >= 18 or (isPunct(ch) and n >= 16) then
                table.insert(lines, line)
                line = ""
                n = 0
            end
        end
        if line ~= "" then table.insert(lines, line) end
        return table.concat(lines, "\n")
    end
    -- V7: 保留显式换行，每行再按18字符断行
    local function wrapText(s)
        if not s or s == "" then return "" end
        local out = {}
        for seg in (s .. "\n"):gmatch("(.-)\n") do
            table.insert(out, wrap18(seg))
        end
        return table.concat(out, "\n")
    end

    -- V7: 奖励文本合并到正文末尾（单独一行）
    if reward_text and reward_text ~= "" then
        text = (text or "") .. "\n" .. reward_text
    end
    text = wrapText(text)

    -- 1. 标题（V8: 去黑框，字号24，居中；横线紧贴标题下方，上移以贴字）
    local title_w = TextWidget:new{
        text = title or "",
        face = Font:getFace("cfont", 24),
    }
    table.insert(parts, centerIn(title_w, avail_w))
    -- 横线：宽度适配标题文字（超宽则取弹窗宽度），紧贴标题底部无间距
    local line_w = math.min(title_w:getWidth(), avail_w)
    if line_w < Screen:scaleBySize(40) then line_w = Screen:scaleBySize(40) end
    local ok_hl, HorizontalLine = pcall(require, "ui/widget/horizontal_line")
    if ok_hl and HorizontalLine then
        table.insert(parts, centerIn(HorizontalLine:new{
            width = line_w,
            height = Screen:scaleBySize(2),
            color = Blitbuffer.COLOR_DARK_GRAY,
        }, avail_w))
    end
    table.insert(parts, VerticalSpan:new{ width = Size.padding.small })

    -- 2. 书图片 + 正文（左右排列，V8: 文本宽度按18字符估算，不超出可用宽度）
    local img = self:_safeLoadImage(80)
    local inner_padding = Size.padding.default
    -- cfont16 中文一字≈16px，18字≈288px，加少量余量
    local text_width = Screen:scaleBySize(300)
    local max_text_w = avail_w - Screen:scaleBySize(80) - 3 * inner_padding - 2 * border_w
    if text_width > max_text_w then
        text_width = max_text_w
    end
    if text_width < Screen:scaleBySize(80) then
        text_width = Screen:scaleBySize(80)
    end

    local text_w = TextBoxWidget:new{
        text = text or "",
        face = Font:getFace("cfont", 16),
        width = text_width,
        alignment = "left",
    }

    local content_row
    if img then
        content_row = HorizontalGroup:new{
            align = "center",
            img,
            HorizontalSpan:new{ width = inner_padding },
            text_w,
        }
    else
        content_row = text_w
    end
    content_row.not_focusable = true
    local content_frame = FrameContainer:new{
        padding = inner_padding,
        radius = Screen:scaleBySize(10),
        content_row,
    }
    content_frame.not_focusable = true
    -- V8: 图片和文案整体往右移（左侧占位），避免图片留白干扰左边框
    local offset_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = Screen:scaleBySize(12) },
        content_frame,
    }
    offset_row.not_focusable = true
    table.insert(parts, centerIn(offset_row, avail_w))

    local content = VerticalGroup:new{ align = "center", unpack(parts) }
    content.not_focusable = true
    dialog:addWidget(content)
    UIManager:show(dialog)
    return dialog
end

-- 随机事件-书签掉落
function FocusFeedback:_triggerBookmark()
    local quotes = self.bookmark_quotes or {}
    if #quotes == 0 then return "书签掉落", "一片书签" end
    local nickname = self:_readNickname()
    local quote = quotes[math.random(1, #quotes)]
    -- V15: 书签掉落 +0.1% 随机属性
    self:_addAttribute(self:_randomAttrKey(), ATTR_BOOKMARK_GAIN)

    -- V7: 前缀单独一行，书签内容另起一行（内部再按18字符断行）
    local text = "（书的昵称）身上掉落了一片书签：\n" .. quote
    text = text:gsub("（书的昵称）", function() return nickname end)

    self:_showEventPopup("随机事件-书签掉落", text, nil, {
        {text = "确定", callback = function() end},
    })
    return "书签掉落", "一片书签"
end

-- 随机事件-为了人与书的相遇-遇见陌生人
function FocusFeedback:_triggerStranger()
    if not self.event_data or not self.event_data.strangers then return "陌生人", "一份礼物" end
    local all_strangers = self.event_data.strangers
    if #all_strangers == 0 then return "陌生人", "一份礼物" end

    -- V7: 排除节日限定陌生人（仅节日当天触发），仅从普通池抽取
    local normal_strangers = {}
    for _, s in ipairs(all_strangers) do
        if not s.holiday then
            table.insert(normal_strangers, s)
        end
    end
    if #normal_strangers == 0 then return "陌生人", "一份礼物" end

    -- V7: 不重复抽取——排除已遇见的陌生人
    local met = self:_readMetStrangers()
    local met_set = {}
    for _, k in ipairs(met) do met_set[k] = true end

    local pool = {}
    for _, s in ipairs(normal_strangers) do
        if not met_set[s.key] then
            table.insert(pool, s)
        end
    end
    -- 如果全部遇见过，重置列表重新开始
    if #pool == 0 then
        pool = normal_strangers
        met = {}
        met_set = {}
    end

    -- V6: 四叶草生效期间，剔除扣分陌生人
    if self:_isCloverActive() then
        local filtered = {}
        for _, s in ipairs(pool) do
            if s.reward_type ~= "points_minus" then
                table.insert(filtered, s)
            end
        end
        if #filtered > 0 then
            pool = filtered
        end
    end

    -- V15: 画像加权选择陌生人（属性越匹配权重越高，不影响去重逻辑）
    local attrs = self:_initAttributes()
    local stranger = self:_weightedPick(pool, function(s)
        return 1 + ATTR_WEIGHT_STRENGTH * self:_cosineSim(attrs, s.tags or {})
    end)
    local nickname = self:_readNickname()
    -- V15: 遇见陌生人 +0.4% 阅历
    self:_addAttribute("阅历", ATTR_EVENT_GAIN)

    -- V7: 记录已遇见
    if not met_set[stranger.key] then
        table.insert(met, stranger.key)
        self:_saveMetStrangers(met)
        -- V8: 长期任务全局累计（跨书籍）
        self:_addLongMetStranger(stranger.key)
    end

    local text = (stranger.text or ""):gsub("（书的昵称）", function() return nickname end)
    local title = "随机事件-为了人与书的相遇-遇见" .. (stranger.name or "")

    local reward_text = ""
    if stranger.reward_type == "item" then
        local inv = self:_readInventory()
        inv[stranger.reward_key] = (inv[stranger.reward_key] or 0) + 1
        self:_saveInventory(inv)
        reward_text = "*获得" .. (stranger.reward_name or "") .. "×1"
    elseif stranger.reward_type == "points_plus" then
        local pts = stranger.reward_count or 0
        local current = self:_readPoints()
        self:_savePoints(current + pts)
        reward_text = "*积分+" .. pts
    elseif stranger.reward_type == "points_minus" then
        local amount = math.abs(stranger.reward_count or 0)
        local current = self:_readPoints()
        if current >= amount then
            self:_savePoints(current - amount)
            reward_text = "*积分-" .. amount
        else
            -- V14: 挑战成功心情拉满8h不掉落：期间负面事件不扣心情
            local boost_until = G_reader_settings:readSetting(settingKey("v14_mood_boost_until"), 0) or 0
            if boost_until <= os.time() then
                local mood = self:_readMood()
                self:_saveMood(mood - 10)
            end
            reward_text = "*心情值-10%"
        end
    elseif stranger.reward_type == "item_and_points" then
        -- V7: 同时获得道具和积分
        local inv = self:_readInventory()
        inv[stranger.reward_key] = (inv[stranger.reward_key] or 0) + (stranger.reward_count or 1)
        self:_saveInventory(inv)
        local pts = stranger.points or 0
        if pts > 0 then
            local current = self:_readPoints()
            self:_savePoints(current + pts)
        end
        reward_text = "*获得" .. (stranger.reward_name or "") .. "×1"
        if pts > 0 then
            reward_text = reward_text .. " *积分+" .. pts
        end
    end

    self:_showEventPopup(title, text, reward_text, {
        {text = "确定", callback = function() end},
    })
    -- 返回日记用描述信息
    local diary_encounter = stranger.name or "陌生人"
    local diary_reward = ""
    if stranger.reward_type == "item" then
        diary_reward = (stranger.reward_name or "一份礼物") .. "×1"
    elseif stranger.reward_type == "points_plus" then
        diary_reward = "积分+" .. (stranger.reward_count or 0)
    elseif stranger.reward_type == "points_minus" then
        diary_reward = "积分-" .. math.abs(stranger.reward_count or 0)
    elseif stranger.reward_type == "item_and_points" then
        diary_reward = (stranger.reward_name or "一份礼物") .. "×1，积分+" .. (stranger.points or 0)
    end
    if diary_reward == "" then diary_reward = "一份礼物" end
    return diary_encounter, diary_reward
end

-- 随机事件-书际关系
function FocusFeedback:_triggerBookFriend()
    if not self.event_data then return "书际关系", "一些物品" end
    local data = self.event_data
    local books = data.book_friends or {}
    local templates = data.book_friend_templates or {}
    local activities = data.book_friend_activities or {}
    local durations = data.book_friend_durations or {}

    if #books == 0 or #templates == 0 then return "书际关系", "一些物品" end

    local nickname = self:_readNickname()
    -- V15: 一次书际关系 +0.4% 情感
    self:_addAttribute("情感", ATTR_EVENT_GAIN)

    local template = templates[math.random(1, #templates)]
    local book_title = books[math.random(1, #books)]

    local items = {
        {key = "cotton", name = "棉花糖"},
        {key = "biscuit", name = "饼干"},
        {key = "wastebasket", name = "废纸篓"},
        {key = "toy", name = "逗书棒"},
    }
    local item = items[math.random(1, #items)]
    local count = math.random(1, 5)

    local duration = ""
    if #durations > 0 then
        duration = durations[math.random(1, #durations)]
    end

    local activity = ""
    if #activities > 0 then
        activity = activities[math.random(1, #activities)]
    end

    local text = template
    text = text:gsub("{duration}", function() return duration end)
    text = text:gsub("{activity}", function() return activity end)
    text = text:gsub("{item}", function() return item.name end)
    text = text:gsub("{count}", function() return tostring(count) end)
    text = text:gsub("《xxx》", function() return book_title end)
    text = text:gsub("（书的昵称）", function() return nickname end)

    local inv = self:_readInventory()
    inv[item.key] = (inv[item.key] or 0) + count
    self:_saveInventory(inv)

    local reward_text = string.format("*获得%s×%d", item.name, count)

    self:_showEventPopup("随机事件-书际关系", text, reward_text, {
        {text = "确定", callback = function() end},
    })
    return "书际关系", string.format("%s×%d", item.name, count)
end

-- 随机事件-书掉入巴别塔图书馆
function FocusFeedback:_triggerBabel()
    local nickname = self:_readNickname()
    -- V15: 一次巴别图书馆事件 +0.4% 知识
    self:_addAttribute("知识", ATTR_EVENT_GAIN)
    local text = "宇宙（别人管它叫图书馆）由许多六边形的回廊组成，数目不能确定，也许是无限的……（书的昵称）掉入了巴别图书馆，这里有许多它的同类，还有一位失明的阿根廷诗人，都在知识的海洋中寻觅着什么……（书的昵称）想起自己诞生之初第一次仰头望见银河的感受，选择了加入它们。"
    text = text:gsub("（书的昵称）", function() return nickname end)

    local current = self:_readPoints()
    self:_savePoints(current + 10)

    local reward_text = "*获得积分×10"

    self:_showEventPopup("随机事件-书掉入巴别塔图书馆", text, reward_text, {
        {text = "确定", callback = function() end},
    })
    return "巴别图书馆", "10积分"
end

-- 随机事件-书飞走了……
function FocusFeedback:_triggerFlyAway()
    local nickname = self:_readNickname()
    -- V15: 书飞走了 +0.4% 逻辑
    self:_addAttribute("逻辑", ATTR_EVENT_GAIN)
    local text = "（书的昵称）出门玩耍，路过堪萨斯州的大草原时，一阵猛烈的旋风突然来临。周围的房子、女孩和黑色小梗犬都被大风卷了起来，（书的昵称）也是，它吓得吱哇乱叫。"
    text = text:gsub("（书的昵称）", function() return nickname end)

    local points = self:_readPoints()
    local reward_text = "是否消耗2积分捡回你的（书的昵称）？"
    reward_text = reward_text:gsub("（书的昵称）", function() return nickname end)

    local left_text = string.format("消耗2积分捡回（现有积分%d）", points)

    local buttons = {
        {
            text = left_text,
            callback = function()
                if points >= 2 then
                    self:_savePoints(points - 2)
                    return true
                elseif points == 1 then
                    self:_savePoints(0)
                    return true
                else
                    self:_showMessage("积分不足", 2)
                    return false
                end
            end,
        },
        {
            text = "放弃（心情值-20）",
            callback = function()
                -- V14: 挑战成功心情拉满8h不掉落：期间放弃不扣心情
                local boost_until = G_reader_settings:readSetting(settingKey("v14_mood_boost_until"), 0) or 0
                if boost_until <= os.time() then
                    local mood = self:_readMood()
                    self:_saveMood(math.max(MOOD_MIN, mood - 20))
                end
                return true
            end,
        },
    }

    self:_showEventPopup("随机事件-书飞走了……", text, reward_text, buttons)
    return "书飞走了", "平安归来"
end

-- 特殊事件通用处理
function FocusFeedback:_triggerSpecialEvent(event_def)
    if not event_def then return "特殊事件", "一份礼物" end
    local nickname = self:_readNickname()
    -- V15: 特殊事件 +1% 随机属性
    self:_addAttribute(self:_randomAttrKey(), ATTR_SPECIAL_GAIN)

    local text = (event_def.text or ""):gsub("（书的昵称）", function() return nickname end)
    local title = event_def.title or "特殊事件"

    local reward_text = ""

    if event_def.reward_type == "item" then
        local inv = self:_readInventory()
        inv[event_def.reward_key] = (inv[event_def.reward_key] or 0) + 1
        self:_saveInventory(inv)
        reward_text = "*获得" .. (event_def.reward_name or "") .. "×1"
    elseif event_def.reward_type == "points" then
        local pts = event_def.points or 0
        local current = self:_readPoints()
        self:_savePoints(current + pts)
        reward_text = "*积分+" .. pts
    elseif event_def.reward_type == "item_and_points" then
        local inv = self:_readInventory()
        inv[event_def.reward_key] = (inv[event_def.reward_key] or 0) + 1
        self:_saveInventory(inv)
        local pts = event_def.points or 0
        local current = self:_readPoints()
        self:_savePoints(current + pts)
        reward_text = "*获得" .. (event_def.reward_name or "") .. "×1 *积分+" .. pts
    end

    -- 许愿柳：设置永久标记，永不再触发
    if event_def.key == "wish_willow" then
        self:_saveWishWillowDone()
    end

    self:_showEventPopup(title, text, reward_text, {
        {text = "确定", callback = function() end},
    })
    -- 返回日记用描述信息
    local diary_encounter = event_def.title or "特殊事件"
    local diary_reward = ""
    if event_def.reward_type == "item" then
        diary_reward = (event_def.reward_name or "一份礼物") .. "×1"
    elseif event_def.reward_type == "points" then
        diary_reward = "积分+" .. (event_def.points or 0)
    elseif event_def.reward_type == "item_and_points" then
        diary_reward = (event_def.reward_name or "一份礼物") .. "×1，积分+" .. (event_def.points or 0)
    end
    if diary_reward == "" then diary_reward = "一份礼物" end
    return diary_encounter, diary_reward
end

-- 每日特殊事件检查（每天最多触发一个）
function FocusFeedback:_checkDailySpecialEvents()
    if not self.event_data or not self.event_data.special_events then return false end

    -- 检查特殊事件总开关
    local toggles = self:_readEventToggles()
    if toggles.special == false then return false end
    -- V6: 四叶草生效期间，正面特殊事件概率×2，劫匪不触发
    local clover = self:_isCloverActive()

    for _, evt in ipairs(self.event_data.special_events) do
        local should_check = true

        -- 许愿柳：已触发过则永不再检查
        if evt.key == "wish_willow" then
            if self:_readWishWillowDone() then
                should_check = false
            end
        end

        if should_check then
            -- V6: 四叶草生效期间，劫匪（负面事件）不触发
            -- V14: 摸鱼模式负面事件不出现
            local slack_mode = (self:_getActiveMode() == MODE_SLACK)
            if (clover and evt.key == "robber") or (slack_mode and evt.key == "robber") then
                -- 跳过
            else
                local chance = evt.chance or 0
                -- V6: 四叶草生效期间，正面特殊事件概率×2
                if clover then
                    chance = chance * 2
                end
                if math.random() < chance then
                    -- 检查是否为首次随机事件
                    local event_hist = self:_readEventHistory()
                    local total_events = 0
                    for _, cnt in pairs(event_hist) do
                        total_events = total_events + cnt
                    end
                    local is_first = (total_events == 0)

                    self:_recordEvent(evt.key)
                    local encounter, reward = self:_triggerSpecialEvent(evt)
                    if is_first then
                        self:_addEventLog("first_event", (encounter or "未知事件") .. "|" .. (reward or "一份礼物"))
                    end
                    return true
                end
            end
        end
    end

    return false
end

-- V7: 节日陌生人检查（每天只要阅读就触发，不干扰正常频率）
function FocusFeedback:_checkHolidayStranger()
    if not self.event_data or not self.event_data.strangers then return false end
    local today = todayKey()
    -- 今天已检查过节日
    if self:_readHolidayCheck() == today then return false end

    -- 获取今天的日期 (M.D 格式，如 10.9, 4.23)
    local month = tonumber(os.date("%m"))
    local day = tonumber(os.date("%d"))
    local today_holiday = string.format("%d.%d", month, day)

    -- 查找匹配的节日陌生人
    for _, s in ipairs(self.event_data.strangers) do
        if s.holiday == today_holiday then
            self:_saveHolidayCheck(today)
            -- 触发节日陌生人（给予奖励，但不设 last_event_ts）
            local nickname = self:_readNickname()
            local text = (s.text or ""):gsub("（书的昵称）", function() return nickname end)
            local title = "节日事件-遇见" .. (s.name or "")

            local reward_text = ""
            if s.reward_type == "item" then
                local inv = self:_readInventory()
                inv[s.reward_key] = (inv[s.reward_key] or 0) + 1
                self:_saveInventory(inv)
                reward_text = "*获得" .. (s.reward_name or "") .. "×1"
            elseif s.reward_type == "item_and_points" then
                local inv = self:_readInventory()
                inv[s.reward_key] = (inv[s.reward_key] or 0) + (s.reward_count or 1)
                self:_saveInventory(inv)
                local pts = s.points or 0
                if pts > 0 then
                    local current = self:_readPoints()
                    self:_savePoints(current + pts)
                end
                reward_text = "*获得" .. (s.reward_name or "") .. "×1"
                if pts > 0 then reward_text = reward_text .. " *积分+" .. pts end
            end

            self:_showEventPopup(title, text, reward_text, {
                {text = "确定", callback = function() end},
            })
            -- V8: 长期任务全局累计（节日陌生人也算遇见）
            self:_addLongMetStranger(s.key)
            self:_addEventLog("holiday_stranger", (s.name or "节日陌生人") .. "|" .. (reward_text or ""))
            return true
        end
    end

    -- 今天没有节日，标记已检查
    self:_saveHolidayCheck(today)
    return false
end
function FocusFeedback:_checkRandomEvents()
    -- 仅已领养且未翻开时触发
    if not self:_readAdopted() then return end
    if self.reveal_book then return end

    local now = os.time()

    -- V7: 节日陌生人检查（不干扰正常频率，不设 last_event_ts）
    self:_checkHolidayStranger()

    -- 1. 先检查每日特殊事件（每天最多一次）
    local today = todayKey()
    if today ~= self:_readDailyCheck() then
        self:_saveDailyCheck(today)
        if self:_checkDailySpecialEvents() then
            self:_saveLastEventTs(now)
            return
        end
    end

    -- 2. 检查最小间隔
    local last_ts = self:_readLastEventTs()
    if now - last_ts < EVT_MIN_INTERVAL then return end

    -- 3. 逐个检查 per-tick 事件
    local toggles = self:_readEventToggles()
    -- V6: 四叶草生效期间，正面事件概率×2，书飞走不触发
    local clover = self:_isCloverActive()

    local tick_events = {
        {key = "bookmark",    chance = EVT_BOOKMARK_CHANCE,    enabled = toggles.bookmark,    trigger = function() return self:_triggerBookmark() end},
        {key = "stranger",    chance = EVT_STRANGER_CHANCE,    enabled = toggles.stranger,    trigger = function() return self:_triggerStranger() end},
        {key = "book_friend", chance = EVT_BOOK_FRIEND_CHANCE, enabled = toggles.book_friend, trigger = function() return self:_triggerBookFriend() end},
        {key = "babel",       chance = EVT_BABEL_CHANCE,       enabled = toggles.babel,       trigger = function() return self:_triggerBabel() end},
        {key = "fly_away",    chance = EVT_FLY_AWAY_CHANCE,    enabled = toggles.fly_away,    trigger = function() return self:_triggerFlyAway() end},
    }

    local draw_fx = self:_drawEffect()
    for _, evt in ipairs(tick_events) do
        if evt.enabled then
            local is_good = (evt.key ~= "fly_away")
            -- V6: 四叶草生效期间，书飞走不触发；V14: 摸鱼模式负面事件不出现
            local slack_mode = (self:_getActiveMode() == MODE_SLACK)
            -- 抽签中下「被掠夺者」：书飞走必触发（无视四叶草/摸鱼的跳过）
            local skip_fly = (clover or slack_mode) and evt.key == "fly_away"
            if draw_fx == "robbed" and evt.key == "fly_away" then
                skip_fly = false
            end
            -- 抽签下签「好事绝缘」：不触发任何正面事件
            if (draw_fx == "no_good" and is_good) or skip_fly then
                -- 跳过
            else
                local chance = evt.chance
                -- V6: 四叶草生效期间，正面事件概率×2
                if clover then
                    chance = chance * 2
                end
                -- 抽签上上「必有好事」/上吉「好事将至」：正面事件必触发
                -- 抽签中吉「好事翻倍」：正面事件概率×2
                if (draw_fx == "good_news" or draw_fx == "good_luck") and is_good then
                    chance = 1
                elseif draw_fx == "near_good" and is_good then
                    chance = chance * 2
                end
                -- 抽签中下「被掠夺者」：书飞走必触发
                if draw_fx == "robbed" and evt.key == "fly_away" then
                    chance = 1
                end
                if math.random() < chance then
                    -- 检查是否为首次随机事件
                    local event_hist = self:_readEventHistory()
                    local total_events = 0
                    for _, cnt in pairs(event_hist) do
                        total_events = total_events + cnt
                    end
                    local is_first = (total_events == 0)

                    self:_recordEvent(evt.key)
                    self:_saveLastEventTs(now)
                    local encounter, reward = evt.trigger()
                    if is_first then
                        self:_addEventLog("first_event", (encounter or "未知事件") .. "|" .. (reward or "一份礼物"))
                    end
                    return
                end
            end
        end
    end
end

function FocusFeedback:_showStats()
    local _, today_seconds, last_notified = self:_readToday()
    local active_text = self.enabled and "开启" or "暂停"
    local next_text
    local current_minute = math.floor(today_seconds / 60)

    if current_minute < 1 then
        next_text = "1 分钟"
    elseif current_minute < 10 then
        next_text = "10 分钟"
    elseif current_minute < 20 then
        next_text = "20 分钟"
    elseif current_minute < 30 then
        next_text = "30 分钟"
    elseif current_minute < 45 then
        next_text = "45 分钟"
    elseif current_minute < 60 then
        next_text = "60 分钟"
    else
        local next_after_60 = 60 + (math.floor((current_minute - 60) / AFTER_60_INTERVAL) + 1) * AFTER_60_INTERVAL
        next_text = string.format("%d 分钟", next_after_60)
    end

    local msg = string.format(
        "专注力正反馈：%s\n\n今日累计阅读：%s\n下一次提醒：%s\n已提醒到：%d 分钟\n\n%s",
        active_text,
        secondsToText(today_seconds),
        next_text,
        last_notified,
        self:_randomQuote()
    )
    self:_showMessage(msg, 6)
end

function FocusFeedback:addToMainMenu(menu_items)
    -- V1 菜单
    menu_items.focus_feedback = {
        text_func = function()
            local _, today_seconds = self:_readToday()
            return string.format("专注正反馈：%s", secondsToText(today_seconds))
        end,
        sorting_hint = "tools",
        checked_func = function()
            return self.enabled
        end,
        check_callback_updates_menu = true,
        callback = function()
            self:_showStats()
        end,
        hold_callback = function(menu)
            self:_toggleEnabled(menu)
        end,
        sub_item_table = {
            {
                text = "查看今日统计",
                callback = function()
                    self:_showStats()
                end,
            },
            {
                text_func = function()
                    return self.enabled and "暂停专注计时" or "开启专注计时"
                end,
                callback = function(menu)
                    self:_toggleEnabled(menu)
                end,
            },
            {
                text = "标记读完当前书",
                callback = function()
                    self:_triggerEndBookRating()
                end,
            },
            {
                text = "领养一本书",
                separator = true,
                callback = function()
                    self:_showAdoptionPage()
                end,
            },
            {
                text = "商超",
                callback = function()
                    self:_showShop()
                end,
            },
            {
                text = "仓库",
                callback = function()
                    self:_showWarehouse()
                end,
            },
            {
                text = "任务",
                separator = true,
                sub_item_table = {
                    {
                        text = "每日任务",
                        callback = function()
                            self:_showDailyTaskDialog()
                        end,
                    },
                    {
                        text = "长期任务",
                        callback = function()
                            self:_showLongTaskDialog()
                        end,
                    },
                },
            },
            {
                text = "旅行的书",
                callback = function()
                    self:_showTravelBookList()
                end,
            },
            {
                text = "图鉴",
                callback = function()
                    self:_showCollection()
                end,
            },
            -- V14: 模式系统
            -- 注意：旧版 KOReader（v2026.07.2 及更早）的 touchmenu.lua:onMenuSelect 会直接对
            -- item.sub_item_table 取长度，不支持 sub_item_table_func 字段（点了会崩溃），
            -- 因此这里必须传入构建好的 table，动态部分用 text_func/checked_func 实现。
            {
                text = "模式",
                separator = true,
                sub_item_table = self:_buildModeSubmenuItems(),
            },
            {
                text = "随机事件",
                separator = true,
                sub_item_table = {
                    {
                        text = "书签掉落",
                        checked_func = function() return self:_readEventToggles().bookmark end,
                        callback = function()
                            local t = self:_readEventToggles()
                            t.bookmark = not t.bookmark
                            self:_saveEventToggles(t)
                        end,
                    },
                    {
                        text = "遇见陌生人",
                        checked_func = function() return self:_readEventToggles().stranger end,
                        callback = function()
                            local t = self:_readEventToggles()
                            t.stranger = not t.stranger
                            self:_saveEventToggles(t)
                        end,
                    },
                    {
                        text = "书际关系",
                        checked_func = function() return self:_readEventToggles().book_friend end,
                        callback = function()
                            local t = self:_readEventToggles()
                            t.book_friend = not t.book_friend
                            self:_saveEventToggles(t)
                        end,
                    },
                    {
                        text = "巴别图书馆",
                        checked_func = function() return self:_readEventToggles().babel end,
                        callback = function()
                            local t = self:_readEventToggles()
                            t.babel = not t.babel
                            self:_saveEventToggles(t)
                        end,
                    },
                    {
                        text = "书飞走了",
                        checked_func = function() return self:_readEventToggles().fly_away end,
                        callback = function()
                            local t = self:_readEventToggles()
                            t.fly_away = not t.fly_away
                            self:_saveEventToggles(t)
                        end,
                    },
                    {
                        text = "特殊事件",
                        checked_func = function() return self:_readEventToggles().special end,
                        callback = function()
                            local t = self:_readEventToggles()
                            t.special = not t.special
                            self:_saveEventToggles(t)
                        end,
                    },
                    {
                        text = "旅行的书",
                        checked_func = function() return self:_readEventToggles().inbox ~= false end,
                        callback = function()
                            local t = self:_readEventToggles()
                            t.inbox = not (t.inbox ~= false)
                            self:_saveEventToggles(t)
                        end,
                    },
                },
            },
            {
                text = "清零今日统计",
                callback = function(menu)
                    self:_resetToday(menu)
                end,
            },
            {
                text = "在线更新",
                separator = true,
                sub_item_table = {
                    {
                        text = "检查更新",
                        callback = function()
                            self:_checkUpdate()
                        end,
                    },
                    {
                        text = "设置更新源",
                        callback = function()
                            self:_setUpdateSource()
                        end,
                    },
                },
            },
        },
    }
end

-- ========== V9 在线更新系统 ==========

-- 获取插件目录路径（优先用已初始化的，兜底用 debug.getinfo）
function FocusFeedback:_getPluginDir()
    if self.plugin_dir and self.plugin_dir ~= "" then
        return self.plugin_dir
    end
    local ok, dir = pcall(function()
        local source = debug.getinfo(1, "S").source
        local path = source:gsub("^@", "")
        return path:match("^(.*[/\\])") or "./"
    end)
    if ok and dir then
        return dir
    end
    return "./"
end

-- 默认更新源（用户可在菜单中修改）
function FocusFeedback:_getUpdateSource()
    return G_reader_settings:readSetting(settingKey("update_source"))
        or "https://raw.githubusercontent.com/yourname/yourrepo/main"
end

function FocusFeedback:_saveUpdateSource(url)
    G_reader_settings:saveSetting(settingKey("update_source"), url)
end

-- 获取本地版本号
function FocusFeedback:_getLocalVersion()
    local ok, meta = pcall(function()
        return dofile(self:_getPluginDir() .. "_meta.lua")
    end)
    if ok and meta and meta.version then
        return tonumber(meta.version) or 0
    end
    return 9  -- 兜底
end

-- V10: HTTP GET 请求（pcall防崩溃 + 超时设置 + 自动重试）
function FocusFeedback:_httpGet(url, timeout_sec)
    timeout_sec = timeout_sec or 15
    local max_retries = 3  -- 共尝试 3 次，解决 Kindle 网络不稳定导致的偶发超时
    local last_err = "未知错误"

    for attempt = 1, max_retries do
        -- 全程 pcall 包裹，任何异常都不会导致闪退
        -- 注意：必须捕获 pcall 的多个返回值（函数可能返回 nil, "HTTP xxx"），
        -- 否则真实错误码会被丢弃，只显示兜底的"未知错误"
        local ok, ret1, ret2 = pcall(function()
            local ltn12 = require("ltn12")
            local http = require("socket.http")
            local result = {}

            -- 设置网络超时（防止卡死，失败快速返回）
            pcall(function()
                local socketutil = require("socketutil")
                socketutil:set_timeout(timeout_sec, timeout_sec * 2)
            end)

            -- 判断 http/https
            local request_fn = http.request
            if url:match("^https://") then
                local https_ok, https = pcall(require, "ssl.https")
                if https_ok and https then
                    request_fn = https.request
                end
            end

            local r, code = request_fn{
                url = url,
                sink = ltn12.sink.table(result),
                method = "GET",
                headers = { ["User-Agent"] = "KOReader-FocusFeedback" },
            }

            -- 重置超时
            pcall(function()
                local socketutil = require("socketutil")
                socketutil:reset_timeout()
            end)

            if code == 200 then
                return table.concat(result), nil
            else
                return nil, string.format("HTTP %s", tostring(code))
            end
        end)

        if ok then
            if ret1 then
                return ret1, nil
            end
            last_err = ret2 or "未知错误"
        else
            last_err = tostring(ret1)
        end

        -- 失败后等待 1 秒再重试（用 socket.select 等待，不阻塞 UI 事件）
        if attempt < max_retries then
            pcall(function()
                local socket = require("socket")
                socket.select(nil, nil, 1)
            end)
        end
    end

    return nil, string.format("%s\n已自动重试%d次，请检查网络后重试。", last_err, max_retries)
end

-- V15: 单次非阻塞 HTTP GET。
-- 原理：socket.http/ssl.https 的 create() + loop(0.05) 每 50ms 轮询一次，
-- 每轮之间通过 UIManager:scheduleIn 让出 UI 事件循环，网络请求期间界面不冻结、
-- 弹窗能正常渲染，彻底解决"网络差时点更新卡死必须重启"的问题。
-- 回调 on_result(body, err)：body 非 nil 表示成功。
function FocusFeedback:_httpGetOnceAsync(url, timeout_sec, on_result)
    timeout_sec = timeout_sec or 15
    local start = os.time()
    local req = nil
    local sink_tbl = {}
    local finished = false

    local function finish(body, err)
        if finished then return end
        finished = true
        on_result(body, err)
    end

    -- 创建请求对象；若 create 接口不可用，回退到同步请求（在定时器里执行，不阻塞点击回调）
    local ok_create = pcall(function()
        local request_fn
        if url:match("^https://") then
            local https_ok, https = pcall(require, "ssl.https")
            if not (https_ok and https and https.create) then
                error("ssl.https.create 不可用")
            end
            request_fn = https.create
        else
            local http_ok, http = pcall(require, "socket.http")
            if not (http_ok and http and http.create) then
                error("socket.http.create 不可用")
            end
            request_fn = http.create
        end
        req = request_fn{
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = "KOReader-FocusFeedback" },
            sink = ltn12.sink.table(sink_tbl),
        }
        if req and req.settimeout then
            pcall(function()
                req:settimeout(timeout_sec)
            end)
        end
    end)

    if not ok_create then
        UIManager:scheduleIn(0.05, function()
            local body, err = self:_httpGet(url, timeout_sec)
            finish(body, err)
        end)
        return
    end

    local function step()
        if finished then return end

        -- 总超时保护（防止任何情况下无限轮询）
        if os.time() - start > timeout_sec then
            pcall(function()
                if req then req:done() end
            end)
            finish(nil, string.format("请求超时（超过 %d 秒）", timeout_sec))
            return
        end

        local ok, r1, r2 = pcall(function()
            return req:loop(0.05)
        end)
        if not ok then
            finish(nil, tostring(r1))
            return
        end

        if r1 == nil then
            -- 未完成：仅 "timeout" 表示正常等待，继续轮询并让出 UI 事件循环；
            -- 其他错误立即返回，避免空转到总超时
            if r2 == "timeout" or r2 == nil then
                UIManager:scheduleIn(0.05, step)
            else
                finish(nil, r2)
            end
            return
        end

        -- 完成：r1 = HTTP 状态码
        if tonumber(r1) == 200 then
            finish(table.concat(sink_tbl), nil)
        else
            finish(nil, "HTTP " .. tostring(r1))
        end
    end

    UIManager:scheduleIn(0.01, step)
end

-- V15: 带自动重试的非阻塞 GET（串行重试，重试等待同样让出事件循环）
function FocusFeedback:_httpGetAsync(url, timeout_sec, attempts, on_result)
    attempts = attempts or 2
    local last_err = "未知错误"

    local function try(remaining)
        self:_httpGetOnceAsync(url, timeout_sec, function(body, err)
            if body then
                on_result(body, nil)
            else
                last_err = err or "未知错误"
                if remaining > 1 then
                    UIManager:scheduleIn(1.0, function()
                        try(remaining - 1)
                    end)
                else
                    on_result(nil, string.format("%s\n已重试%d次，请检查网络后重试。", last_err, attempts))
                end
            end
        end)
    end

    try(attempts)
end

-- 检查更新（先弹确认框，可取消）
function FocusFeedback:_checkUpdate()
    if self.update_busy then
        self:_showMessage("更新操作正在进行中，请稍候…", 3)
        return
    end
    local base_url = self:_getUpdateSource()
    if not base_url or base_url == "" then
        self:_showMessage("未设置更新源。\n请在菜单中设置 GitHub 仓库地址。", 5)
        return
    end
    local local_version = self:_getLocalVersion()
    local dialog
    dialog = ButtonDialog:new{
        title = string.format("检查更新？\n当前版本 V%d\n更新源：\n%s\n\n将连接更新源检查是否有新版本。",
            local_version, base_url),
        title_align = "center",
        buttons = {
            {
                {text = "取消", callback = function() UIManager:close(dialog) end},
                {text = "检查", callback = function()
                    UIManager:close(dialog)
                    self:_doCheckUpdate(base_url)
                end},
            },
        },
    }
    UIManager:show(dialog)
end

-- 执行检查（用户在确认框点"检查"后）
function FocusFeedback:_doCheckUpdate(base_url)
    local ok, err = pcall(function()
        -- 去掉末尾斜杠
        base_url = base_url:gsub("/$", "")

        self.update_busy = true

        -- 立即弹"检查中"提示（timeout=0 不自动关闭，结果出来后手动关闭）
        local checking = InfoMessage:new{
            text = "正在检查更新…\n请稍候",
            timeout = 0,
        }
        UIManager:show(checking)

        -- 下载 version.json（非阻塞，期间 UI 正常响应）
        local version_url = base_url .. "/version.json"
        self:_httpGetAsync(version_url, 15, 2, function(body, http_err)
            -- 先释放 busy，避免后续逻辑异常导致锁死
            self.update_busy = false
            UIManager:close(checking)

            if not body then
                self:_showMessage(string.format("检查更新失败：\n%s\n\n请确认网络和更新源地址是否正确。", http_err or "未知错误"), 6)
                return
            end

            -- 解析 JSON（简单解析，不依赖外部库）
            local remote_version = tonumber(body:match('"version"%s*:%s*"?([0-9]+)"?'))
            if not remote_version then
                self:_showMessage("无法解析远端版本号。\n请确认 version.json 格式正确。", 5)
                return
            end

            local local_version = self:_getLocalVersion()

            if remote_version <= local_version then
                self:_showMessage(string.format("当前已是最新版本 V%d。", local_version), 3)
                return
            end

            -- 发现新版本：先弹确认框（可取消），确认后才开始下载
            self:_confirmUpdate(base_url, remote_version, local_version)
        end)
    end)

    if not ok then
        self:_showMessage(string.format("检查更新出错：\n%s", tostring(err)), 6)
    end
end

-- 发现新版本：弹确认框（明确告知将下载覆盖文件、需重启，可取消）
function FocusFeedback:_confirmUpdate(base_url, remote_version, local_version)
    local dialog
    dialog = ButtonDialog:new{
        title = string.format("发现新版本 V%d！\n当前版本 V%d\n\n将下载并覆盖插件文件，\n更新完成后需重启 KOReader 生效。\n是否立即更新？",
            remote_version, local_version),
        title_align = "center",
        buttons = {
            {
                {text = "取消", callback = function()
                    UIManager:close(dialog)
                end},
                {text = "立即更新", callback = function()
                    UIManager:close(dialog)
                    self:_doUpdate(base_url, remote_version)
                end},
            },
        },
    }
    UIManager:show(dialog)
end

-- 执行更新
function FocusFeedback:_doUpdate(base_url, remote_version)
    if self.update_busy then
        self:_showMessage("更新操作正在进行中，请稍候…", 3)
        return
    end
    local ok, err = pcall(function()
        -- 需要下载的文件列表
        local files = {
            "main.lua",
            "_meta.lua",
            "event_data.lua",
            "dialogue_data.lua",
            "book_data.lua",
            "sentence_pool.lua",
            "bookmark_quotes.lua",
        }

        local plugin_dir = self:_getPluginDir()
        local success_count = 0
        local fail_count = 0
        local fail_list = {}
        local total = #files

        self.update_busy = true

        -- 立即弹下载进度弹窗（timeout=0 不自动关闭，完成后手动关闭）
        local progress = InfoMessage:new{
            text = string.format("正在下载更新…\n(0/%d)", total),
            timeout = 0,
        }
        UIManager:show(progress)

        local function updateProgress()
            UIManager:close(progress)
            progress = InfoMessage:new{
                text = string.format("正在下载更新…\n(%d/%d)", success_count + fail_count, total),
                timeout = 0,
            }
            UIManager:show(progress)
        end

        local function finishUpdate()
            self.update_busy = false
            UIManager:close(progress)

            if fail_count == 0 then
                -- 更新本地版本号
                G_reader_settings:saveSetting(settingKey("last_update_version"), remote_version)
                self:_showMessage(string.format("更新完成！\n成功更新 %d 个文件。\n请重启 KOReader 使更新生效。", success_count), 8)
            else
                local msg = string.format("更新部分失败。\n成功 %d 个，失败 %d 个。\n失败文件：%s\n建议重试或手动更新。",
                    success_count, fail_count, table.concat(fail_list, ", "))
                self:_showMessage(msg, 8)
            end
        end

        -- 逐个文件串行下载（非阻塞，每个文件完成后更新进度并下载下一个）
        local i = 1
        local function downloadNext()
            if i > total then
                finishUpdate()
                return
            end

            local fname = files[i]
            local url = base_url .. "/" .. fname
            self:_httpGetAsync(url, 15, 2, function(body, http_err)
                local ok2, err2 = pcall(function()
                    i = i + 1
                    if body and #body > 0 then
                        local dest = plugin_dir .. fname
                        local f = io.open(dest, "w")
                        if f then
                            f:write(body)
                            f:close()
                            success_count = success_count + 1
                        else
                            fail_count = fail_count + 1
                            table.insert(fail_list, fname)
                        end
                    else
                        fail_count = fail_count + 1
                        table.insert(fail_list, fname)
                    end
                    updateProgress()
                end)
                if not ok2 then
                    -- 单文件处理异常：中止更新，释放 busy
                    self.update_busy = false
                    UIManager:close(progress)
                    self:_showMessage(string.format("更新出错：\n%s", tostring(err2)), 8)
                    return
                end
                downloadNext()
            end)
        end
        downloadNext()
    end)

    if not ok then
        self.update_busy = false
        self:_showMessage(string.format("更新出错：\n%s", tostring(err)), 8)
    end
end

-- 设置更新源
function FocusFeedback:_setUpdateSource()
    local ok, err = pcall(function()
        local current = self:_getUpdateSource()
        local dialog
        dialog = InputDialog:new{
            title = "设置更新源",
            input = current,
            input_hint = "https://raw.githubusercontent.com/用户名/仓库名/分支",
            description = "GitHub raw 链接，不要带末尾斜杠",
            buttons = {
                {
                    {
                        text = "取消",
                        callback = function()
                            UIManager:close(dialog)
                        end,
                    },
                    {
                        text = "保存",
                        is_enter_default = true,
                        callback = function()
                            local url = dialog:getInputText() or ""
                            url = url:gsub("%s", "")  -- 去除空白
                            url = url:gsub("/$", "")   -- 去除末尾斜杠
                            if url:match("^https?://") then
                                self:_saveUpdateSource(url)
                                UIManager:close(dialog)
                                self:_showMessage("更新源已保存。", 2)
                            else
                                self:_showMessage("请输入有效的 HTTP/HTTPS 链接。", 3)
                            end
                        end,
                    },
                },
            },
        }
        UIManager:show(dialog)
    end)

    if not ok then
        self:_showMessage(string.format("设置更新源出错：\n%s", tostring(err)), 6)
    end
end

-- ========== V13 数据备份/迁移 ==========

-- 递归序列化为 Lua 字面量（无损，可用 loadfile 还原）
local function _serializeLuaValue(v, depth)
    depth = depth or 0
    local vt = type(v)
    if vt == "nil" then
        return "nil"
    elseif vt == "boolean" then
        return v and "true" or "false"
    elseif vt == "number" then
        return string.format("%.17g", v)
    elseif vt == "string" then
        return string.format("%q", v)
    elseif vt == "table" then
        local indent = string.rep("  ", depth)
        local child_indent = string.rep("  ", depth + 1)
        local parts = {}
        for k, val in pairs(v) do
            local keyexpr
            local kt = type(k)
            if kt == "string" then
                keyexpr = string.format("[%q]", k)
            elseif kt == "number" then
                keyexpr = string.format("[%.17g]", k)
            elseif kt == "boolean" then
                keyexpr = string.format("[%s]", k and "true" or "false")
            else
                keyexpr = "[nil]"
            end
            table.insert(parts, child_indent .. keyexpr .. " = " .. _serializeLuaValue(val, depth + 1))
        end
        if #parts == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    else
        return "nil"
    end
end

-- 备份文件存放目录（优先用 KOReader 数据目录，USB 可访问）
function FocusFeedback:_getBackupDir()
    local dir = nil
    pcall(function()
        local DS = _G.DataStorage or require("datastorage")
        if DS then
            if type(DS.getDataDir) == "function" then
                local d = DS:getDataDir()
                if type(d) == "string" and d ~= "" then
                    dir = d:match("[/\\]$") and d or (d .. "/")
                end
            end
            if not dir and type(DS.getFullDataDir) == "function" then
                local d = DS:getFullDataDir()
                if type(d) == "string" and d ~= "" then
                    dir = d:match("[/\\]$") and d or (d .. "/")
                end
            end
        end
    end)
    if not dir then
        dir = self:_getPluginDir()
    end
    return dir
end

function FocusFeedback:_exportBackup()
    local ok, err = pcall(function()
        -- 第一步：从底层 data 表枚举键名（键名是可靠的事实来源）
        local keys = {}
        pcall(function()
            local raw = G_reader_settings and G_reader_settings.data
            if type(raw) == "table" then
                for k in pairs(raw) do
                    if type(k) == "string" and k:sub(1, #SETTINGS_PREFIX) == SETTINGS_PREFIX then
                        keys[k] = true
                    end
                end
            end
        end)

        if next(keys) == nil then
            self:_showMessage("未能读取到任何插件数据。\n请先正常使用插件积累数据后再导出。", 5)
            return
        end

        -- 第二步：用公开 API readSetting 读取真实值
        local settings = {}
        local sorted = {}
        for k in pairs(keys) do
            table.insert(sorted, k)
            local val = G_reader_settings:readSetting(k, nil)
            if val ~= nil then
                settings[k] = val
            end
        end
        table.sort(sorted)

        if next(settings) == nil then
            self:_showMessage("未能读取到任何有效数据，导出已取消。", 5)
            return
        end

        -- 第三步：生成备份文件内容
        local body = "-- focus_feedback 数据备份（自动生成，请勿改动）\nreturn {\n"
        body = body .. "  backup_version = 1,\n"
        body = body .. "  exported_at = " .. string.format("%q", os.date("%Y-%m-%d %H:%M:%S")) .. ",\n"
        body = body .. "  settings = {\n"
        for _, k in ipairs(sorted) do
            body = body .. "    [" .. string.format("%q", k) .. "] = " .. _serializeLuaValue(settings[k], 2) .. ",\n"
        end
        body = body .. "  },\n}\n"

        local dir = self:_getBackupDir()
        local path = dir .. "focus_feedback_backup.lua"

        local f = io.open(path, "w")
        if not f then
            self:_showMessage(string.format("无法写入备份文件：\n%s\n\n该目录可能不可写（如只读分区）。", path), 8)
            return
        end
        f:write(body)
        f:close()

        self:_showMessage(string.format("备份已导出（共 %d 项数据）。\n\n文件位置：\n%s\n\n连接电脑后把该文件复制到安全处。换新设备后放回同样位置，再选“从文件恢复”。", #sorted, path), 12)
    end)

    if not ok then
        self:_showMessage(string.format("导出备份出错：\n%s", tostring(err)), 6)
    end
end

function FocusFeedback:_importBackup()
    local ok, err = pcall(function()
        local dir = self:_getBackupDir()
        local path = dir .. "focus_feedback_backup.lua"

        local f = io.open(path, "r")
        if not f then
            self:_showMessage(string.format("未找到备份文件：\n%s\n\n请先把备份文件放到该位置，再执行恢复。", path), 8)
            return
        end
        f:close()

        local dialog
        dialog = ButtonDialog:new{
            title = "确定恢复数据？\n\n将用备份覆盖当前进度：\n积分 / 图鉴 / 任务 / 心情值等\n全部替换为备份内容。",
            title_align = "center",
            buttons = {
                {
                    {
                        text = "取消",
                        callback = function()
                            UIManager:close(dialog)
                        end,
                    },
                    {
                        text = "确认恢复",
                        callback = function()
                            UIManager:close(dialog)
                            self:_doImportBackup(path)
                        end,
                    },
                },
            },
        }
        UIManager:show(dialog)
    end)

    if not ok then
        self:_showMessage(string.format("读取备份出错：\n%s", tostring(err)), 6)
    end
end

function FocusFeedback:_doImportBackup(path)
    local ok, err = pcall(function()
        local chunk = loadfile(path)
        if not chunk then
            self:_showMessage("备份文件格式错误，无法读取。", 6)
            return
        end
        local backup = chunk()
        if type(backup) ~= "table" or type(backup.settings) ~= "table" then
            self:_showMessage("备份文件内容异常，已取消恢复。", 6)
            return
        end

        local count = 0
        for k, v in pairs(backup.settings) do
            if type(k) == "string" and k:sub(1, #SETTINGS_PREFIX) == SETTINGS_PREFIX then
                G_reader_settings:saveSetting(k, v)
                count = count + 1
            end
        end

        pcall(function()
            if G_reader_settings and G_reader_settings.flush then
                G_reader_settings:flush()
            end
        end)

        self:_showMessage(string.format("恢复完成（共 %d 项）。\n请重启 KOReader 使数据完全生效。", count), 8)
    end)

    if not ok then
        self:_showMessage(string.format("恢复数据出错：\n%s", tostring(err)), 6)
    end
end

-- ===================== V14 模式系统 =====================

local function fmtClock(sec)
    sec = math.max(0, math.floor(sec))
    local h = math.floor(sec / 3600)
    local mi = math.floor((sec % 3600) / 60)
    local s = sec % 60
    return string.format("%02d:%02d:%02d", h, mi, s)
end

-- 模式状态读写
function FocusFeedback:_readModeState()
    local ok, v = pcall(function()
        return G_reader_settings:readSetting(settingKey("v14_mode_state"), {})
    end)
    if ok and type(v) == "table" then return v end
    return {}
end

function FocusFeedback:_saveModeState(m)
    G_reader_settings:saveSetting(settingKey("v14_mode_state"), m or {})
end

-- 模式冷却（记录各模式上次结束时间戳）
function FocusFeedback:_readCooldowns()
    local ok, v = pcall(function()
        return G_reader_settings:readSetting(settingKey("v14_cooldowns"), {})
    end)
    if ok and type(v) == "table" then return v end
    return {}
end

function FocusFeedback:_saveCooldowns(cd)
    G_reader_settings:saveSetting(settingKey("v14_cooldowns"), cd or {})
end

-- 当前激活的模式（挑战/摸鱼/夜间/心跳之一，长期模式单独存储）
function FocusFeedback:_getActiveMode()
    local m = self:_readModeState()
    return m.mode or nil
end

-- 沙漏模式：读取用户设定的加成时段列表 [{s_min, e_min}]
-- s_min/e_min 为当日绝对分钟数(0-1439)，单段不跨日，故必有 s_min < e_min
function FocusFeedback:_getSandWindows()
    local m = self:_readModeState()
    local list = m.sand_windows
    if type(list) ~= "table" then return {} end
    return list
end

-- 沙漏模式：当前时刻（分钟精度）是否落在任一时段内（命中→必+1加成）
function FocusFeedback:_isInSandWindow()
    local now = os.date("*t")
    local cur_min = now.hour * 60 + now.min
    for _, w in ipairs(self:_getSandWindows()) do
        if cur_min >= w.s_min and cur_min < w.e_min then
            return true
        end
    end
    return false
end

-- 沙漏模式：时段累计总分钟
function FocusFeedback:_sandTotalMinutes()
    local total = 0
    for _, w in ipairs(self:_getSandWindows()) do
        total = total + (w.e_min - w.s_min)
    end
    return total
end

-- 沙漏模式：把时段列表转成展示文本（HH:MM–HH:MM）
function FocusFeedback:_sandWindowsToText()
    local parts = {}
    for _, w in ipairs(self:_getSandWindows()) do
        table.insert(parts, string.format("%02d:%02d–%02d:%02d",
            math.floor(w.s_min / 60), w.s_min % 60,
            math.floor(w.e_min / 60), w.e_min % 60))
    end
    if #parts == 0 then return "未设定" end
    return table.concat(parts, "、")
end

-- 沙漏模式：向列表追加/合并一段区间（s_min<e_min），返回是否成功（累计≤8h则并入，否则拒绝）
-- 重叠自动合并为并集
function FocusFeedback:_sandAddWindow(s_min, e_min)
    if e_min <= s_min then return false end   -- 空段或跨日（e<=s）直接拒绝
    local merged = {}
    for _, w in ipairs(self:_getSandWindows()) do
        table.insert(merged, { s_min = w.s_min, e_min = w.e_min })
    end
    table.insert(merged, { s_min = s_min, e_min = e_min })
    table.sort(merged, function(a, b) return a.s_min < b.s_min end)
    local final = {}
    for _, w in ipairs(merged) do
        local last = final[#final]
        if last and w.s_min <= last.e_min then
            last.e_min = math.max(last.e_min, w.e_min)  -- 重叠/相邻合并为并集
        else
            table.insert(final, w)
        end
    end
    local total = 0
    for _, w in ipairs(final) do
        total = total + (w.e_min - w.s_min)
    end
    if total > SAND_TOTAL_LIMIT_SEC / 60 then
        return false   -- 累计超8h，拒绝
    end
    local m = self:_readModeState()
    m.sand_windows = final
    self:_saveModeState(m)
    return true
end

-- 夜间时间：18:00 - 次日 3:00
function FocusFeedback:_isNightTime()
    local hh = tonumber(os.date("%H")) or 0
    return hh >= 18 or hh < 3
end

-- 白昼时间：6:00 - 18:00（白天模式的加成时段，与夜间镜像）
function FocusFeedback:_isDayTime()
    local hh = tonumber(os.date("%H")) or 0
    return hh >= DAY_START_HOUR and hh < DAY_END_HOUR
end

-- 昼夜模式周期可关闭窗口（夜间/白天共用）
-- 可关闭窗口位于：开启时刻 ±1h，以及每个 24h 周期边界 ±1h；其余时间锁定
-- 返回 table：{closable=true, from=相对秒, to=相对秒} 或 {closable=false, next_from=相对秒, next_to=相对秒}
function FocusFeedback:_cycleWindow(duration, window)
    local m = self:_readModeState()
    local started = tonumber(m.started_at) or 0
    if started <= 0 then
        return { closable = true, from = 0, to = window }
    end
    local now = os.time()
    local elapsed = now - started
    local k = math.floor(elapsed / duration)
    for i = math.max(0, k - 1), k + 1 do
        local center = i * duration
        if elapsed >= center - window and elapsed <= center + window then
            return { closable = true, from = center - window, to = center + window }
        end
    end
    local next_center = (k + 1) * duration
    return { closable = false, next_from = next_center - window, next_to = next_center + window }
end

-- 昼夜模式状态文本：可关闭时显示剩余时间，锁定中显示下次可关闭窗口时段
function FocusFeedback:_cycleStatusText(mode)
    local duration = NIGHT_DURATION
    if mode == MODE_DAY then duration = DAY_DURATION
    elseif mode == MODE_SAND then duration = SAND_DURATION end
    local m = self:_readModeState()
    local started = tonumber(m.started_at) or os.time()
    local w = self:_cycleWindow(duration, NIGHT_CLOSE_WINDOW)
    if w.closable then
        local remain = (started + w.to) - os.time()
        return string.format("可关闭（剩余%s）", fmtClock(math.max(0, remain)))
    end
    -- 用 os.date 显示绝对时钟，跨天时仍反映"每天的这个时段"
    local f = os.date("%H:%M", started + w.next_from)
    local t = os.date("%H:%M", started + w.next_to)
    return string.format("锁定中，下次可关 %s–%s", f, t)
end

-- 统一进入模式入口：互斥校验 + 可选猫门槛校验
function FocusFeedback:_canEnterMode(mode, need_cat)
    if self:_getActiveMode() then
        self:_showMessage("当前已有其他模式进行中。\n模式互斥，请等待其结束后再开启。", 6)
        return false
    end
    if need_cat then
        local pet = self:_readPet()
        if not pet.cat then
            self:_showMessage((MODE_NAMES[mode] or "该模式") .. "需要养猫后才能开启。\n先去商超买一只小猫吧！", 6)
            return false
        end
    end
    return true
end

-- 返回某模式的剩余冷却秒数（0 表示可开启）
function FocusFeedback:_getCooldownRemain(mode)
    local cooldown = 0
    if mode == MODE_CHALLENGE then
        cooldown = CHALLENGE_COOLDOWN
    elseif mode == MODE_SLACK then
        cooldown = SLACK_COOLDOWN
    elseif mode == MODE_HEARTBEAT then
        cooldown = HEARTBEAT_COOLDOWN
    elseif mode == MODE_SPRINT then
        cooldown = SPRINT_COOLDOWN
    elseif mode == MODE_DRAW then
        cooldown = DRAW_COOLDOWN
    end
    if cooldown <= 0 then return 0 end
    local cd = self:_readCooldowns()
    -- 防御：设置里可能是脏数据（字符串时间戳），tonumber 归一化，避免算术/比较崩溃
    local ended = tonumber(cd[mode]) or 0
    if ended <= 0 then return 0 end
    return math.max(0, ended + cooldown - os.time())
end

-- 冷却提示弹窗
function FocusFeedback:_showCooldownMsg(mode, remain)
    local cd = self:_readCooldowns()
    -- 防御：脏字符串时间戳归一化，避免算术崩溃
    local ended = tonumber(cd[mode]) or 0
    local cooldown = 0
    if mode == MODE_CHALLENGE then cooldown = CHALLENGE_COOLDOWN
    elseif mode == MODE_SLACK then cooldown = SLACK_COOLDOWN
    elseif mode == MODE_HEARTBEAT then cooldown = HEARTBEAT_COOLDOWN
    elseif mode == MODE_SPRINT then cooldown = SPRINT_COOLDOWN
    elseif mode == MODE_DRAW then cooldown = DRAW_COOLDOWN end
    local next_ok = ended + cooldown
    local remain_txt = string.format("%d天%d小时%d分",
        math.floor(remain / 86400), math.floor((remain % 86400) / 3600), math.floor((remain % 3600) / 60))
    self:_showMessage(string.format("%s上一次结束时间：%s\n下一次可开启时间：%s\n请耐心等待！\n（还需 %s）",
        MODE_NAMES[mode] or mode,
        os.date("%Y年%m月%d日 %H时%M分", ended),
        os.date("%Y年%m月%d日 %H时%M分", next_ok),
        remain_txt), 8)
end

-- 手动关闭模式（记录冷却并清空状态）
function FocusFeedback:_closeMode(mode, silent)
    local cd = self:_readCooldowns()
    cd[mode] = os.time()
    self:_saveCooldowns(cd)
    self:_saveModeState({})
    if not silent then
        self:_showMessage("已关闭。", 3)
    end
end

-- ========== V14 模式子菜单 ==========

function FocusFeedback:_buildModeSubmenuItems()
    local items = {}

    -- 长期模式（嵌套菜单，单独存储，可与其他模式共存）
    -- 同样避免 sub_item_table_func（旧版 KOReader 不支持），直接传构建好的 table
    table.insert(items, {
        text = "长期模式",
        sub_item_table = self:_buildLongModeItems(),
    })

    local mode_entries = {
        {key = MODE_CHALLENGE, text = "挑战模式"},
        {key = MODE_SLACK, text = "摸鱼模式"},
        {key = MODE_NIGHT, text = "夜间模式"},
        {key = MODE_DAY, text = "白天模式"},
        {key = MODE_FLOW, text = "心流模式"},
        {key = MODE_SPRINT, text = "短跑模式"},
        {key = MODE_SAND, text = "沙漏模式"},
        {key = MODE_DRAW, text = "抽签模式"},
        {key = MODE_HEARTBEAT, text = "心跳模式"},
    }
    for _, e in ipairs(mode_entries) do
        local k = e.key  -- Lua5.1: 循环变量共享，必须复制到局部变量供闭包捕获
        local entry_text = e.text
        table.insert(items, {
            -- 用 text_func 动态显示状态文本（子菜单只构建一次，必须保证文本实时刷新）
            text_func = function()
                local t = entry_text
                if self:_getActiveMode() == k then
                    local status
                    if k == MODE_CHALLENGE then
                        status = self:_getChallengeStatusText()
                    elseif k == MODE_SLACK then
                        status = self:_getSlackStatusText()
                    elseif k == MODE_NIGHT then
                        status = self:_getNightStatusText()
                    elseif k == MODE_DAY then
                        status = self:_getDayStatusText()
                    elseif k == MODE_FLOW then
                        status = self:_getFlowStatusText()
                    elseif k == MODE_SPRINT then
                        status = self:_getSprintStatusText()
                    elseif k == MODE_SAND then
                        status = self:_getSandStatusText()
                    elseif k == MODE_DRAW then
                        status = self:_getDrawStatusText()
                    elseif k == MODE_HEARTBEAT then
                        status = self:_getHeartbeatStatusText()
                    end
                    if status then
                        t = t .. "（" .. status .. "）"
                    end
                end
                return t
            end,
            checked_func = function() return self:_getActiveMode() == k end,
            callback = function()
                if k == MODE_CHALLENGE then
                    self:_toggleChallengeMode()
                elseif k == MODE_SLACK then
                    self:_toggleSlackMode()
                elseif k == MODE_NIGHT then
                    self:_toggleNightMode()
                elseif k == MODE_DAY then
                    self:_toggleDayMode()
                elseif k == MODE_FLOW then
                    self:_toggleFlowMode()
                elseif k == MODE_SPRINT then
                    self:_toggleSprintMode()
                elseif k == MODE_SAND then
                    self:_toggleSandMode()
                elseif k == MODE_DRAW then
                    self:_toggleDrawMode()
                elseif k == MODE_HEARTBEAT then
                    self:_toggleHeartbeatMode()
                end
            end,
        })
    end
    return items
end

-- ========== V14 挑战模式 ==========

function FocusFeedback:_getChallengeStatusText()
    local m = self:_readModeState()
    local goal_h = math.floor((m.ch_goal_sec or 0) / 3600)
    local read_h = (m.ch_reading_sec or 0) / 3600
    local remain = math.max(0, (m.started_at or 0) + CHALLENGE_DURATION - os.time())
    return string.format("目标%dh，已读%.1fh，倒计时%s", goal_h, read_h, fmtClock(remain))
end

function FocusFeedback:_toggleChallengeMode()
    if self:_getActiveMode() == MODE_CHALLENGE then
        local m = self:_readModeState()
        local remain = math.max(0, (m.started_at or 0) + CHALLENGE_DURATION - os.time())
        self:_showMessage(string.format("挑战模式进行中（不可中途结束）\n\n目标：%d小时\n已读：%s\n寄存积分：%d\n倒计时：%s\n\n倒计时结束后将自动结算。",
            math.floor((m.ch_goal_sec or 0) / 3600),
            secondsToText(m.ch_reading_sec or 0),
            m.ch_escrow or 0,
            fmtClock(remain)), 10)
        return
    end
    local remain = self:_getCooldownRemain(MODE_CHALLENGE)
    if remain > 0 then
        self:_showCooldownMsg(MODE_CHALLENGE, remain)
        return
    end
    if not self:_canEnterMode(MODE_CHALLENGE, true) then
        return
    end
    self:_showChallengeSetup()
end

function FocusFeedback:_showChallengeSetup()
    local dialog
    dialog = InputDialog:new{
        title = "设定24小时内阅读目标\n（最低3小时）",
        input = "5",
        input_hint = "输入目标小时数",
        buttons = {
            {
                {
                    text = "取消",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = "开始挑战",
                    is_enter_default = true,
                    callback = function()
                        local txt = dialog:getInputText()
                        local goal_h = tonumber(txt)
                        UIManager:close(dialog)
                        if not goal_h or goal_h < CHALLENGE_MIN_GOAL_H then
                            self:_showMessage("目标小时数需≥" .. CHALLENGE_MIN_GOAL_H .. "，请重新设置。", 5)
                            return
                        end
                        goal_h = math.floor(goal_h)
                        if goal_h > 24 then goal_h = 24 end
                        self:_startChallenge(goal_h)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_startChallenge(goal_h)
    local m = {
        mode = MODE_CHALLENGE,
        started_at = os.time(),
        ch_goal_sec = goal_h * 3600,
        ch_reading_sec = 0,
        ch_escrow = 0,
        ch_settled = false,
    }
    self:_saveModeState(m)
    self:_showMessage(string.format("挑战开始！\n目标：24小时内阅读%d小时\n挑战所得积分将寄存，结算时统一发放。", goal_h), 7)
end

-- 挑战自动结算（24小时到点由 _checkModeAuto 调用）
function FocusFeedback:_settleChallenge()
    local m = self:_readModeState()
    if m.mode ~= MODE_CHALLENGE or m.ch_settled then return end
    local goal = m.ch_goal_sec or 0
    local read = m.ch_reading_sec or 0
    local escrow = m.ch_escrow or 0
    m.ch_settled = true
    self:_saveModeState(m)
    local now = os.time()
    if read >= goal then
        -- 成功：寄存积分入账 + 礼包 + 心情拉满8h
        local cur = self:_readPoints()
        self:_savePoints(cur + escrow)
        local inv = self:_readInventory()
        for _, k in ipairs(LONG_REWARD_ITEMS) do
            inv[k] = (inv[k] or 0) + 1
        end
        self:_saveInventory(inv)
        G_reader_settings:saveSetting(settingKey("v14_mood_boost_until"), now + CHALLENGE_BOOST_DURATION)
        self:_saveMood(100)
        self:_showMessage(string.format("挑战成功！\n阅读时长 %s ≥ 目标 %s\n寄存积分%d已入账\n获得礼包：棉花糖、饼干、废纸篓、逗书棒、咖啡、四叶草×1\n心情拉满并持续8小时不掉落！",
            secondsToText(read), secondsToText(goal), escrow), 10)
    else
        -- 失败：寄存积分没收，心情跌落至10
        self:_saveMood(10)
        self:_showMessage(string.format("挑战失败……\n阅读时长 %s < 目标 %s\n寄存积分%d已被扣除\n心情跌落至10%%。",
            secondsToText(read), secondsToText(goal), escrow), 10)
    end
    local cd = self:_readCooldowns()
    cd[MODE_CHALLENGE] = now
    self:_saveCooldowns(cd)
    self:_saveModeState({})
end

-- ========== V14 摸鱼模式 ==========

function FocusFeedback:_getSlackStatusText()
    local m = self:_readModeState()
    local remain = math.max(0, (m.started_at or 0) + SLACK_MAX_DURATION - os.time())
    local days = math.floor(remain / 86400) + 1
    return string.format("剩余%d天（可随时手动关闭）", days)
end

function FocusFeedback:_toggleSlackMode()
    if self:_getActiveMode() == MODE_SLACK then
        self:_confirmCloseSlack()
        return
    end
    local remain = self:_getCooldownRemain(MODE_SLACK)
    if remain > 0 then
        self:_showCooldownMsg(MODE_SLACK, remain)
        return
    end
    if self:_getActiveMode() then
        self:_showMessage("当前已有其他模式进行中。\n模式互斥，请等待其结束后再开启。", 6)
        return
    end
    self:_confirmStartSlack()
end

function FocusFeedback:_confirmStartSlack()
    local dialog
    dialog = ButtonDialog:new{
        title = "开启摸鱼模式？\n书进入咸鱼状态：\n· 心情锁死60%、不会弃养\n· 无负面事件、无每日挑战\n· 里程碑积分固定为1（小猫加成关闭）\n最长持续30天，可随时手动关闭",
        title_align = "center",
        buttons = {
            {
                {text = "开启", callback = function()
                    UIManager:close(dialog)
                    local m = { mode = MODE_SLACK, started_at = os.time() }
                    self:_saveModeState(m)
                    self:_saveMood(60)
                    self:_showMessage("摸鱼模式已开启！书开始快乐摸鱼～", 5)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_confirmCloseSlack()
    local dialog
    dialog = ButtonDialog:new{
        title = "手动关闭摸鱼模式？\n关闭后恢复正常机制。",
        title_align = "center",
        buttons = {
            {
                {text = "关闭", callback = function()
                    UIManager:close(dialog)
                    self:_closeMode(MODE_SLACK)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

-- ========== V14 夜间模式 ==========

function FocusFeedback:_getNightStatusText()
    return self:_cycleStatusText(MODE_NIGHT)
end

function FocusFeedback:_toggleNightMode()
    if self:_getActiveMode() == MODE_NIGHT then
        local w = self:_cycleWindow(NIGHT_DURATION, NIGHT_CLOSE_WINDOW)
        if w.closable then
            self:_confirmCloseNight()
        else
            self:_showMessage("夜间模式正处于锁定中。\n" .. self:_cycleStatusText(MODE_NIGHT), 6)
        end
        return
    end
    if not self:_canEnterMode(MODE_NIGHT, true) then
        return
    end
    self:_confirmStartNight()
end

function FocusFeedback:_confirmStartNight()
    local dialog
    dialog = ButtonDialog:new{
        title = "开启夜间模式？（需要先养小猫哦）\n· 一个完整昼夜周期约24小时\n· 夜晚(18:00-3:00)里程碑积分+1\n· 白天阅读将失去小猫的+1加成\n· 开启后倚「可关闭窗口」手动结束，不会自动关",
        title_align = "center",
        buttons = {
            {
                {text = "开启", callback = function()
                    UIManager:close(dialog)
                    local m = { mode = MODE_NIGHT, started_at = os.time() }
                    self:_saveModeState(m)
                    self:_showMessage("夜间模式已开启！\n一个昼夜周期后将进入「可关闭」窗口。", 6)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_confirmCloseNight()
    local dialog
    dialog = ButtonDialog:new{
        title = "手动关闭夜间模式？\n关闭后即可重新选择模式。",
        title_align = "center",
        buttons = {
            {
                {text = "关闭", callback = function()
                    UIManager:close(dialog)
                    self:_closeMode(MODE_NIGHT)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

-- ========== V14 白天模式 ==========

function FocusFeedback:_getDayStatusText()
    return self:_cycleStatusText(MODE_DAY)
end

function FocusFeedback:_toggleDayMode()
    if self:_getActiveMode() == MODE_DAY then
        local w = self:_cycleWindow(DAY_DURATION, NIGHT_CLOSE_WINDOW)
        if w.closable then
            self:_confirmCloseDay()
        else
            self:_showMessage("白天模式正处于锁定中。\n" .. self:_cycleStatusText(MODE_DAY), 6)
        end
        return
    end
    if not self:_canEnterMode(MODE_DAY, true) then
        return
    end
    self:_confirmStartDay()
end

function FocusFeedback:_confirmStartDay()
    local dialog
    dialog = ButtonDialog:new{
        title = "开启白天模式？（需要先养小猫哦）\n· 一个完整昼夜周期约24小时\n· 白昼(6:00-18:00)里程碑积分+1\n· 夜晚阅读将失去小猫的+1加成\n· 开启后倚「可关闭窗口」手动结束，不会自动关",
        title_align = "center",
        buttons = {
            {
                {text = "开启", callback = function()
                    UIManager:close(dialog)
                    local m = { mode = MODE_DAY, started_at = os.time() }
                    self:_saveModeState(m)
                    self:_showMessage("白天模式已开启！\n一个昼夜周期后将进入「可关闭」窗口。", 6)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_confirmCloseDay()
    local dialog
    dialog = ButtonDialog:new{
        title = "手动关闭白天模式？\n关闭后即可重新选择模式。",
        title_align = "center",
        buttons = {
            {
                {text = "关闭", callback = function()
                    UIManager:close(dialog)
                    self:_closeMode(MODE_DAY)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

-- ========== V14 心流模式 ==========

function FocusFeedback:_getFlowStatusText()
    local stat = self:_getDailyStat()
    local sess = math.floor((stat.session_cur or 0) / 60)
    return string.format("持续%d分钟，可随时关闭", sess)
end

function FocusFeedback:_toggleFlowMode()
    if self:_getActiveMode() == MODE_FLOW then
        self:_closeMode(MODE_FLOW)
        return
    end
    if not self:_canEnterMode(MODE_FLOW, false) then return end
    self:_confirmStartFlow()
end

function FocusFeedback:_confirmStartFlow()
    local dialog
    dialog = ButtonDialog:new{
        title = "开启心流模式？\n· 阅读时不产生里程碑积分\n· 单次持续阅读达标给分：\n  30分钟+2 / 60分钟+3 / 90分钟+4（每30分钟+1）\n· 翻页/划笔记、插件内操作不断连\n· 退出文档/熄屏≤2分钟回来不断连，超时要重来\n· 随时可关闭，无冷却",
        title_align = "center",
        buttons = {
            {
                {text = "开启", callback = function()
                    UIManager:close(dialog)
                    local m = { mode = MODE_FLOW, started_at = os.time(), flow_awarded = 0 }
                    self:_saveModeState(m)
                    self:_showMessage("心流模式已开启！\n开始你的持续阅读吧。", 6)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

-- ========== V14 短跑模式 ==========

function FocusFeedback:_getSprintStatusText()
    local m = self:_readModeState()
    local remain = math.max(0, (m.started_at or 0) + SPRINT_WINDOW - os.time())
    return string.format("已读%s / 目标%s，剩余%s", secondsToText(m.spr_read or 0), secondsToText(m.spr_goal_sec or 0), fmtClock(remain))
end

function FocusFeedback:_toggleSprintMode()
    if self:_getActiveMode() == MODE_SPRINT then
        self:_showMessage("短跑模式进行中。\n" .. self:_getSprintStatusText(), 6)
        return
    end
    local remain = self:_getCooldownRemain(MODE_SPRINT)
    if remain > 0 then
        self:_showCooldownMsg(MODE_SPRINT, remain)
        return
    end
    if not self:_canEnterMode(MODE_SPRINT, true) then return end
    self:_showSprintSetup()
end

function FocusFeedback:_showSprintSetup()
    local dialog
    dialog = InputDialog:new{
        title = "短跑模式：设定目标\n（需在开启后5小时内读完，推荐1-5小时）",
        input = "2",
        input_hint = "输入目标小时数",
        buttons = {
            {
                {text = "取消", callback = function() UIManager:close(dialog) end},
                {text = "开始短跑", is_enter_default = true, callback = function()
                    local txt = dialog:getInputText()
                    local goal_h = tonumber(txt)
                    UIManager:close(dialog)
                    if not goal_h or goal_h < SPRINT_MIN_GOAL_H then
                        self:_showMessage("目标小时数需≥" .. SPRINT_MIN_GOAL_H .. "，请重新设置。", 5)
                        return
                    end
                    goal_h = math.floor(goal_h)
                    if goal_h > 24 then goal_h = 24 end
                    self:_startSprint(goal_h)
                end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_startSprint(goal_h)
    local m = {
        mode = MODE_SPRINT,
        started_at = os.time(),
        spr_goal_sec = goal_h * 3600,
        spr_read = 0,
        spr_escrow = 0,
        spr_settled = false,
    }
    self:_saveModeState(m)
    self:_showMessage(string.format("短跑开始！\n目标：5小时内阅读%d小时，积分将寄存，末尾统一发放。", goal_h), 7)
end

-- 短跑结算（成功：寄存积分入账+奖励3件套；失败：清零+心情10%）
function FocusFeedback:_settleSprint()
    local m = self:_readModeState()
    if m.mode ~= MODE_SPRINT or m.spr_settled then return end
    local goal = m.spr_goal_sec or 0
    local read = m.spr_read or 0
    local escrow = m.spr_escrow or 0
    m.spr_settled = true
    self:_saveModeState(m)
    local now = os.time()
    if read >= goal then
        local cur = self:_readPoints()
        self:_savePoints(cur + escrow)
        local inv = self:_readInventory()
        inv.cotton = (inv.cotton or 0) + 1
        inv.biscuit = (inv.biscuit or 0) + 1
        inv.wastebasket = (inv.wastebasket or 0) + 1
        self:_saveInventory(inv)
        self:_showMessage(string.format("短跑成功！\n阅读 %s ≥ 目标 %s\n寄存积分%d已入账\n奖励：棉花糖、饼干、废纸篓各×1",
            secondsToText(read), secondsToText(goal), escrow), 8)
    else
        self:_saveMood(10)
        self:_showMessage(string.format("短跑失败……\n阅读 %s < 目标 %s\n寄存积分%d已清零，心情跌落至10%%。",
            secondsToText(read), secondsToText(goal), escrow), 8)
    end
    local cd = self:_readCooldowns()
    cd[MODE_SPRINT] = now
    self:_saveCooldowns(cd)
    self:_saveModeState({})
end

-- ========== V14 沙漏模式 ==========

function FocusFeedback:_getSandStatusText()
    local txt = self:_sandWindowsToText()
    return string.format("加成时段：%s\n累计 %d 分钟 %s", txt, self:_sandTotalMinutes(), self:_cycleStatusText(MODE_SAND))
end

function FocusFeedback:_toggleSandMode()
    if self:_getActiveMode() == MODE_SAND then
        local w = self:_cycleWindow(SAND_DURATION, NIGHT_CLOSE_WINDOW)
        if w.closable then
            self:_confirmCloseSand()
        else
            self:_showMessage("沙漏模式正处于锁定中。\n" .. self:_cycleStatusText(MODE_SAND), 6)
        end
        return
    end
    if not self:_canEnterMode(MODE_SAND, true) then return end
    self:_showSandSetup()
end

-- 解析 "HH:MM" 为当日分钟数(0-1439)，非法返回 nil
function FocusFeedback:_parseClockMinutes(txt)
    if type(txt) ~= "string" then return nil end
    local hh, mm = txt:match("(%d+):(%d+)")
    hh, mm = tonumber(hh), tonumber(mm)
    if not hh or not mm then return nil end
    if hh < 0 or hh > 23 or mm < 0 or mm > 59 then return nil end
    return hh * 60 + mm
end

function FocusFeedback:_showSandSetup()
    local dialog
    dialog = InputDialog:new{
        title = string.format("沙漏模式：设定加成时段\n每次输入一段「起始-结束」(如 9:30-11:30)\n已设：%s   累计%d分钟\n（每段不跨日，总长≤8小时）",
            self:_sandWindowsToText(), self:_sandTotalMinutes()),
        input = "",
        input_hint = "如 9:30-11:30",
        buttons = {
            {
                {text = "取消/放弃", callback = function()
                    UIManager:close(dialog)
                    -- 放弃则清空本次未启动的设定
                    local m = self:_readModeState()
                    m.sand_windows = nil
                    self:_saveModeState(m)
                end},
                {text = "完成并开始", is_enter_default = true, callback = function()
                    if self:_sandTotalMinutes() <= 0 then
                        self:_showMessage("请先添加至少一个时段。", 4)
                        return
                    end
                    UIManager:close(dialog)
                    self:_startSand()
                end},
                {text = "清空已设", callback = function()
                    local m = self:_readModeState()
                    m.sand_windows = nil
                    self:_saveModeState(m)
                    UIManager:close(dialog)
                    self:_showSandSetup()
                end},
            },
            {
                {text = "添加这一时段", callback = function()
                    local raw = dialog:getInputText()
                    local s_txt, e_txt = raw:match("(%d+:%d+)%s*[%-~:]+%s*(%d+:%d+)")
                    if not s_txt or not e_txt then
                        self:_showMessage("格式错误，请输入如「9:30-11:30」。", 4)
                        return
                    end
                    local s_min = self:_parseClockMinutes(s_txt)
                    local e_min = self:_parseClockMinutes(e_txt)
                    if not s_min or not e_min or e_min <= s_min then
                        self:_showMessage("时段无效：起始需早于结束，且不能跨日。", 4)
                        return
                    end
                    if not self:_sandAddWindow(s_min, e_min) then
                        self:_showMessage("时段累计超过8小时上限，无法添加。", 4)
                        return
                    end
                    -- 成功添加：刷新对话框标题以显示最新累计
                    UIManager:close(dialog)
                    self:_showSandSetup()
                end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_startSand()
    local m = {
        mode = MODE_SAND,
        started_at = os.time(),
    }
    self:_saveModeState(m)
    local total = self:_sandTotalMinutes()
    self:_showMessage(string.format("沙漏已启动！\n加成时段：%s\n（共%d分钟）时段内积分必+1，时段外失去猫加成。",
        self:_sandWindowsToText(), total), 8)
end

function FocusFeedback:_confirmCloseSand()
    local dialog
    dialog = ButtonDialog:new{
        title = "手动关闭沙漏模式？\n关闭后即可重新选择模式。",
        title_align = "center",
        buttons = {
            {
                {text = "关闭", callback = function()
                    UIManager:close(dialog)
                    self:_closeMode(MODE_SAND)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

-- ========== V14 心跳模式 ==========

function FocusFeedback:_getHeartbeatStatusText()
    local m = self:_readModeState()
    local remain = math.max(0, (m.started_at or 0) + HEARTBEAT_DURATION - os.time())
    local days = math.floor(remain / 86400)
    local hh = math.floor((remain % 86400) / 3600)
    local today = todayKey()
    local coin_txt = "今日未抛"
    if m.hb_date == today then
        if m.hb_result == true then coin_txt = "今日正面"
        elseif m.hb_result == false then coin_txt = "今日反面" end
    end
    return string.format("剩余%d天%02d时（%s）", days, hh, coin_txt)
end

function FocusFeedback:_toggleHeartbeatMode()
    if self:_getActiveMode() == MODE_HEARTBEAT then
        local m = self:_readModeState()
        local remain = math.max(0, (m.started_at or 0) + HEARTBEAT_DURATION - os.time())
        local today = todayKey()
        -- V14: 今日尚未抛硬币（弹窗被点掉等）时，提供「立即抛硬币」补救按钮
        if m.hb_date ~= today or m.hb_result == nil then
            local dialog
            dialog = ButtonDialog:new{
                title = string.format("心跳模式进行中（不可中途结束）\n\n剩余：%s\n今日尚未抛硬币，可立即补抛：",
                    fmtClock(remain)),
                title_align = "center",
                buttons = {
                    {
                        {text = "立即抛硬币", is_enter_default = true, callback = function()
                            UIManager:close(dialog)
                            UIManager:show(self:_buildCoinFlipDialog())
                        end},
                        {text = "取消", callback = function() UIManager:close(dialog) end},
                    },
                },
            }
            UIManager:show(dialog)
        else
            self:_showMessage(string.format("心跳模式进行中（不可中途结束）\n\n剩余：%s\n每日首次阅读时抛硬币决定当日里程碑积分。",
                fmtClock(remain)), 8)
        end
        return
    end
    local remain = self:_getCooldownRemain(MODE_HEARTBEAT)
    if remain > 0 then
        self:_showCooldownMsg(MODE_HEARTBEAT, remain)
        return
    end
    if self:_getActiveMode() then
        self:_showMessage("当前已有其他模式进行中。\n模式互斥，请等待其结束后再开启。", 6)
        return
    end
    self:_confirmStartHeartbeat()
end

function FocusFeedback:_confirmStartHeartbeat()
    local dialog
    dialog = ButtonDialog:new{
        title = "开启心跳模式？\n高风险高回报，持续72小时：\n每日首次阅读时抛硬币：\n· 正面：当日里程碑积分+2/+4\n· 反面：当日里程碑无积分\n\n基础概率50%，心情≥90%+5%，≤30%-5%，四叶草+10%\n72小时后自动关闭，冷却15天",
        title_align = "center",
        buttons = {
            {
                {text = "开启", callback = function()
                    UIManager:close(dialog)
                    local m = { mode = MODE_HEARTBEAT, started_at = os.time(), hb_date = "", hb_result = nil }
                    self:_saveModeState(m)
                    self:_showMessage("心跳模式已开启！\n今日首次阅读时抛硬币决定命运！", 6)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

-- 每日首读硬币弹窗（由 _onActivity 触发）
function FocusFeedback:_buildCoinFlipDialog()
    local dialog
    local function do_flip()
        local prob = 0.50
        local mood = self:_readMood()
        if mood >= 90 then prob = prob + 0.05 end
        if mood <= 30 then prob = prob - 0.05 end
        if self:_isCloverActive() then prob = prob + 0.10 end
        prob = math.max(0.05, math.min(0.95, prob))
        local win = math.random() < prob
        local m = self:_readModeState()
        m.hb_date = todayKey()
        m.hb_result = win
        self:_saveModeState(m)
        UIManager:close(dialog)
        if win then
            self:_showMessage("硬币正面！\n今日里程碑积分大幅加成！（概率" .. math.floor(prob * 100) .. "%）", 6)
        else
            self:_showMessage("硬币反面……\n今日里程碑积分归零。（概率" .. math.floor((1 - prob) * 100) .. "%）", 6)
        end
    end
    dialog = ButtonDialog:new{
        title = "心跳硬币：今日首读\n\n正面：当日里程碑积分+2/+4\n反面：当日里程碑无积分",
        title_align = "center",
        buttons = {
            {
                {text = "抛硬币", is_enter_default = true, callback = do_flip},
            },
        },
    }
    return dialog
end

-- ========== V14 长期模式 ==========

function FocusFeedback:_readLongMode()
    local ok, v = pcall(function()
        return G_reader_settings:readSetting(settingKey("v14_long_mode"))
    end)
    if ok and type(v) == "table" then return v end
    return {}
end

function FocusFeedback:_saveLongMode(long)
    G_reader_settings:saveSetting(settingKey("v14_long_mode"), long or {})
end

-- 长期模式子菜单（4个周期）
-- 注意：旧版 KOReader 不支持 sub_item_table_func，本函数只会被构建一次，
-- 因此“进行中/禁用/回调分支”等状态全部改为运行时实时读取
-- （text_func/enabled_func/callback 在每次渲染或点击时才被调用）。
function FocusFeedback:_buildLongModeItems()
    local items = {}

    for i, cfg in ipairs(LONG_CYCLES) do
        local cycle_idx = i
        local item = {
            text_func = function()
                local long = self:_readLongMode()
                local is_active = long.cycle ~= nil and not long.settled
                if is_active and cycle_idx == long.cycle then
                    return "▶ " .. LONG_CYCLE_NAMES[cycle_idx] .. "（进行中）"
                end
                return LONG_CYCLE_NAMES[cycle_idx]
            end,
            enabled_func = function()
                local long = self:_readLongMode()
                local is_active = long.cycle ~= nil and not long.settled
                return not (is_active and cycle_idx ~= long.cycle)
            end,
            callback = function()
                local long = self:_readLongMode()
                local is_active = long.cycle ~= nil and not long.settled
                if is_active and cycle_idx == long.cycle then
                    self:_showLongProgress(cycle_idx)
                elseif is_active then
                    self:_showMessage("已有长期挑战进行中。\n需等待其结束后才能开启其他周期。", 5)
                else
                    self:_showLongConfirm(cycle_idx)
                end
            end,
        }
        table.insert(items, item)
    end

    table.insert(items, {
        text = "查看当前进度",
        separator = true,
        callback = function()
            local long = self:_readLongMode()
            local is_active = long.cycle ~= nil and not long.settled
            if is_active then
                self:_showLongProgress(long.cycle)
            else
                self:_showMessage("当前没有进行中的长期挑战。", 4)
            end
        end,
    })
    return items
end

function FocusFeedback:_showLongConfirm(idx)
    local cfg = LONG_CYCLES[idx]
    local pts = self:_readPoints()
    if pts < cfg.fee then
        self:_showMessage(string.format("开启%s长期挑战需入场费%d积分。\n当前积分不足（%d）。",
            LONG_CYCLE_NAMES[idx], cfg.fee, pts), 6)
        return
    end
    local dialog
    dialog = ButtonDialog:new{
        title = string.format("开启「%s」长期挑战？\n\n周期：%d天\n目标：阅读天数≥%d天，阅读时长≥%s\n入场费：%d积分\n\n奖励：道具×%d%s积分+%d%s%s",
            LONG_CYCLE_NAMES[idx], cfg.days, cfg.target_days, secondsToText(cfg.target_sec), cfg.fee,
            cfg.reward_items,
            (cfg.mood_card > 0) and ("、低落免疫卡×" .. cfg.mood_card) or "",
            cfg.reward_pts,
            (cfg.sleep_card > 0) and ("、睡眠免疫卡×" .. cfg.sleep_card) or "",
            ""),
        title_align = "center",
        buttons = {
            {
                {text = "开启", callback = function()
                    UIManager:close(dialog)
                    self:_startLongCycle(idx)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_startLongCycle(idx)
    local cfg = LONG_CYCLES[idx]
    local long = self:_readLongMode()
    if long.cycle and not long.settled then
        self:_showMessage("已有长期挑战进行中，请等待其结束。", 5)
        return
    end
    local pts = self:_readPoints()
    if pts < cfg.fee then
        self:_showMessage("积分不足，无法开启。", 4)
        return
    end
    self:_savePoints(pts - cfg.fee)
    local now = os.time()
    long.cycle = idx
    long.started_at = now
    long.end_at = now + cfg.days * 86400
    long.read_days = 0
    long.read_seconds = 0
    long.last_read_date = ""
    long.fee_paid = cfg.fee
    long.settled = false
    long.settled_result = nil
    self:_saveLongMode(long)
    self:_showMessage(string.format("「%s」长期挑战已开启！\n周期：%d天（至 %s）\n目标：阅读天数≥%d天，累计阅读时长≥%s",
        LONG_CYCLE_NAMES[idx], cfg.days, os.date("%Y-%m-%d %H:%M", long.end_at),
        cfg.target_days, secondsToText(cfg.target_sec)), 8)
end

function FocusFeedback:_showLongProgress(idx)
    local long = self:_readLongMode()
    if not long or long.cycle ~= idx then return end
    local cfg = LONG_CYCLES[idx]
    local now = os.time()
    local start_ts = long.started_at or 0
    local end_ts = long.end_at or 0
    local remain_days = math.max(0, math.ceil((end_ts - now) / 86400))
    local days_passed = math.max(0, math.floor((now - start_ts) / 86400))
    local tolerance_total = math.max(0, cfg.days - cfg.target_days)
    local used_tolerance = math.min(tolerance_total, math.max(0, days_passed - (long.read_days or 0)))
    local remain_sec = math.max(0, cfg.target_sec - (long.read_seconds or 0))
    local status = long.settled and (long.settled_result and "已完成" or "已失败") or "进行中"
    self:_showMessage(string.format(
        "「%s」长期挑战（%s）\n\n开始时间：%s\n结束时间：%s\n\n剩余天数：%d / %d天\n已阅读天数：%d / 目标%d天\n已使用容错：%d / %d天\n剩余时长：%s / 目标%s",
        LONG_CYCLE_NAMES[idx], status,
        os.date("%Y-%m-%d %H:%M", start_ts),
        os.date("%Y-%m-%d %H:%M", end_ts),
        remain_days, cfg.days,
        long.read_days or 0, cfg.target_days,
        used_tolerance, tolerance_total,
        secondsToText(remain_sec), secondsToText(cfg.target_sec)), 14)
end

function FocusFeedback:_settleLongMode()
    local long = self:_readLongMode()
    if not long or not long.cycle or long.settled then return end
    local idx = long.cycle
    local cfg = LONG_CYCLES[idx]
    local success = (long.read_days or 0) >= cfg.target_days
        and (long.read_seconds or 0) >= cfg.target_sec
    long.settled = true
    long.settled_result = success
    self:_saveLongMode(long)
    if success then
        local inv = self:_readInventory()
        local pool = {}
        for _, k in ipairs(LONG_REWARD_ITEMS) do pool[#pool + 1] = k end
        local names = {}
        for _ = 1, cfg.reward_items do
            if #pool > 0 then
                local ri = math.random(1, #pool)
                local pick = pool[ri]
                table.remove(pool, ri)
                inv[pick] = (inv[pick] or 0) + 1
                names[#names + 1] = self:_getItemDisplayName(pick)
            end
        end
        if cfg.mood_card > 0 then
            inv.mood_immune = (inv.mood_immune or 0) + cfg.mood_card
            names[#names + 1] = string.format("低落免疫卡×%d", cfg.mood_card)
        end
        if cfg.sleep_card > 0 then
            inv.sleep_immune = (inv.sleep_immune or 0) + cfg.sleep_card
            names[#names + 1] = string.format("睡眠免疫卡×%d", cfg.sleep_card)
        end
        self:_saveInventory(inv)
        local pts = self:_readPoints()
        self:_savePoints(pts + cfg.reward_pts)
        self:_showMessage(string.format("「%s」长期挑战达成！\n\n阅读天数 %d/%d，阅读时长 %s/%s\n\n奖励：%s\n积分+%d",
            LONG_CYCLE_NAMES[idx], long.read_days or 0, cfg.target_days,
            secondsToText(long.read_seconds or 0), secondsToText(cfg.target_sec),
            table.concat(names, "、"), cfg.reward_pts), 12)
    else
        self:_showMessage(string.format("「%s」长期挑战未完成……\n\n阅读天数 %d/%d，阅读时长 %s/%s\n入场费已扣除，无奖励。",
            LONG_CYCLE_NAMES[idx], long.read_days or 0, cfg.target_days,
            secondsToText(long.read_seconds or 0), secondsToText(cfg.target_sec)), 10)
    end
end

-- ========== V14 卡片使用 ==========

function FocusFeedback:_useV14Card(key, name)
    local inv = self:_readInventory()
    if (inv[key] or 0) <= 0 then return end
    local desc = (key == "mood_immune")
        and string.format("使用「%s」？\n使用后72小时内心情值维持下限90%%。", name)
        or string.format("使用「%s」？\n使用后免疫接下来的两次睡眠（可跨日）。", name)
    local dialog
    dialog = ButtonDialog:new{
        title = desc,
        title_align = "center",
        buttons = {
            {
                {text = "使用", callback = function()
                    UIManager:close(dialog)
                    inv[key] = inv[key] - 1
                    self:_saveInventory(inv)
                    if key == "mood_immune" then
                        G_reader_settings:saveSetting(settingKey("v14_mood_immune_until"), os.time() + MOOD_IMMUNE_DURATION)
                        self:_showMessage("已使用「低落免疫卡」！\n72小时内心情值不低于90%。", 6)
                    elseif key == "sleep_immune" then
                        local left = G_reader_settings:readSetting(settingKey("v14_sleep_immune_left"), 0) or 0
                        G_reader_settings:saveSetting(settingKey("v14_sleep_immune_left"), left + 2)
                        self:_showMessage("已使用「睡眠免疫卡」！\n接下来两次睡眠将被免疫。", 6)
                    end
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

-- ========== V14 模式自动检查 ==========

-- ========== V14 抽签模式 ==========
-- 六签权重（上上15 / 上吉20 / 中吉20 / 中平10 / 中下20 / 下15）
local DRAW_WEIGHTS = {15, 20, 20, 10, 20, 15}
-- 每签4效果（key + 最终文案，固定台词与效果介绍连成一句；占位词「书的昵称」展示时替换）
local DRAW_EFFECTS = {
    {
        {"super_double", "恭喜抽中上上签-超级加倍，书的昵称已被你貔貅般的运气吓哭……今日阅读积分双倍！"},
        {"happy_day", "恭喜抽中上上签-happy day，书的昵称已被你貔貅般的运气吓哭……今日心情持续满格！"},
        {"good_news", "恭喜抽中上上签-好事来袭，书的昵称已被你貔貅般的运气吓哭……今日必有好事！"},
        {"black_friday", "恭喜抽中上上签-黑色星期五，书的昵称已被你貔貅般的运气吓哭……今日商超物品一律1积分！"},
    },
    {
        {"all_bonus", "恭喜抽中上吉签-全天加成，今天运气超级好，快去刮彩票。今日每个里程碑必+1！"},
        {"luxury_joy", "恭喜抽中上吉签-极速愉悦，今天运气超级好，快去刮彩票。今日心情增长翻倍！"},
        {"good_luck", "恭喜抽中上吉签-好事将至，今天运气超级好，快去刮彩票。今日好运迎面而来！"},
        {"gray_friday", "恭喜抽中上吉签-灰色星期五，今天运气超级好，快去刮彩票。今日较贵物品降至3积分！"},
    },
    {
        {"cat_love", "恭喜抽中中吉签-猫之眷顾，今天运气不错呀！今日小猫加成提升至80%！"},
        {"mood_floor", "恭喜抽中中吉签-心情底线，今天运气不错呀！今日心情底线提升至50%！"},
        {"near_good", "恭喜抽中中吉签-好事临近，今天运气不错呀！今日好事翻倍！"},
        {"ash_friday", "恭喜抽中中吉签-灰白星期五，今天运气不错呀！今日较贵物品降至5积分！"},
    },
    {
        {"nothing", "恭喜抽中中平签-无事发生，今天运气一般般……今日阅读如同回到那个插件停留在v9的时候，很平静，很幸福……"},
        {"cat_eye", "恭喜抽中中平签-猫的眼神，今天运气一般般……今日小猫加成+1%！"},
        {"ten_discount", "恭喜抽中中平签-十折优惠！今天运气一般般……但可以在商超里享受原价的优惠~"},
        {"small_use", "恭喜抽中中平签-有点小用，今天运气一般般……今日商超随机一件物品降至5积分！"},
    },
    {
        {"iron_bowl", "恭喜抽中中下签-公务员一般的铁饭碗，今日运气有点烂、、今日每个里程碑积分固定为1！"},
        {"blue_book", "恭喜抽中中下签-忧郁小书，今日运气有点烂、、今日心情增长减半！"},
        {"robbed", "恭喜抽中中下签-被掠夺者，今日运气有点烂、、今日必遇书飞走与被掠夺！"},
        {"white_friday", "恭喜抽中中下签-白色星期五，今日运气有点烂、、今日低价物品提价至5积分！"},
    },
    {
        {"no_gain", "恭喜抽中下签-越努力越心酸，今日运气超级烂，不要轻举妄动谢谢。今日阅读无任何积分！"},
        {"depression", "恭喜抽中下签-抑郁症晚期，今日运气超级烂，不要轻举妄动谢谢。今日心情锁死10%！"},
        {"no_good", "恭喜抽中下签-好事绝缘中，今日运气超级烂，不要轻举妄动谢谢。今日不遇任何好事！"},
        {"rich_area", "恭喜抽中下签-误入富人区，今日运气超级烂，不要轻举妄动谢谢。今日商超物价一律100积分！"},
    },
}

function FocusFeedback:_readDrawDay()
    local ok, v = pcall(function()
        return G_reader_settings:readSetting(settingKey("v14_draw_day"), {})
    end)
    if ok and type(v) == "table" then return v end
    return {}
end
function FocusFeedback:_saveDrawDay(d)
    G_reader_settings:saveSetting(settingKey("v14_draw_day"), d or {})
end

-- 当前生效效果 key（仅当抽签激活且当日已抽签时返回；否则 nil）
function FocusFeedback:_drawEffect()
    if self:_getActiveMode() ~= MODE_DRAW then return nil end
    local d = self:_readDrawDay()
    if d.date ~= todayKey() then return nil end
    return d.fx
end

-- 双重抽取：一层按六签权重抽签，二层在该签4效果里随机1个作为今日唯一效果
function FocusFeedback:_rollDraw()
    local total = 0
    for _, w in ipairs(DRAW_WEIGHTS) do total = total + w end
    local r = math.random() * total
    local sign_idx = 1
    local acc = 0
    for i, w in ipairs(DRAW_WEIGHTS) do
        acc = acc + w
        if r <= acc then sign_idx = i break end
    end
    local pick = DRAW_EFFECTS[sign_idx][math.random(#DRAW_EFFECTS[sign_idx])]
    local fx, text = pick[1], pick[2]
    local nn = self:_readNickname()
    if nn == "" then nn = "这本未命名之书" end
    text = string.gsub(text, "书的昵称", nn)
    local d = { date = todayKey(), fx = fx, sign = sign_idx, text = text }
    self:_saveDrawDay(d)
    return d
end

-- 抽签弹窗（每日首次阅读自动弹出；开启时立即抽今日第一签）
function FocusFeedback:_showDrawDialog()
    -- 防止同一时刻重复弹窗（用户在操作签筒前不叠加新弹窗）
    -- 兜底：若上次弹窗已超过10分钟未操作（如切书/休眠导致弹窗被系统关闭），视为已关闭可重弹
    if self.draw_dialog_open then
        if self.draw_dialog_at and os.time() - self.draw_dialog_at < 600 then
            return
        end
        self.draw_dialog_open = false
    end
    local d = self:_readDrawDay()
    if d.date == todayKey() then
        return
    end
    self.draw_dialog_open = true
    self.draw_dialog_at = os.time()
    local nn = self:_readNickname()
    if nn == "" then nn = "这本未命名之书" end
    local dialog
    local function close_draw_dialog()
        self.draw_dialog_open = false
        UIManager:close(dialog)
    end
    dialog = ButtonDialog:new{
        title = "书捡到一个神秘小签筒……来为今日读书运势抽支签吧！\n\n「" .. nn .. "」今日运势",
        title_align = "center",
        buttons = {
            {
                {text = "抽签", callback = function()
                    close_draw_dialog()
                    local rd = self:_rollDraw()
                    self:_showMessage("== " .. rd.text, 10)
                end},
                {text = "明日再说", callback = function()
                    close_draw_dialog()
                    -- 今日不抽=无签效果
                    self:_saveDrawDay({ date = todayKey() })
                end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_getDrawStatusText()
    local m = self:_readModeState()
    local remain = math.max(0, (m.started_at or 0) + DRAW_DURATION - os.time())
    local d = self:_readDrawDay()
    if d.date == todayKey() and d.fx then
        return string.format("剩余%d天，今日已抽签", math.floor(remain / 86400) + 1)
    end
    return string.format("剩余%d天，今日待抽签", math.floor(remain / 86400) + 1)
end

function FocusFeedback:_toggleDrawMode()
    if self:_getActiveMode() == MODE_DRAW then
        self:_showDrawInfo()
        return
    end
    local remain = self:_getCooldownRemain(MODE_DRAW)
    if remain > 0 then
        self:_showCooldownMsg(MODE_DRAW, remain)
        return
    end
    if not self:_canEnterMode(MODE_DRAW, true) then return end
    self:_confirmStartDraw()
end

-- 抽签模式进行中：点击菜单项显示今日签运详情
function FocusFeedback:_showDrawInfo()
    local m = self:_readModeState()
    local remain = math.max(0, (m.started_at or 0) + DRAW_DURATION - os.time())
    local remain_days = math.floor(remain / 86400) + 1
    local d = self:_readDrawDay()
    local dialog
    local title
    local buttons
    if d.date == todayKey() and d.fx then
        -- 今日已抽签：显示签型 + 效果详情
        local sign_names = {"上上签", "上吉签", "中吉签", "中平签", "中下签", "下签"}
        local sign_name = sign_names[d.sign] or "未知签"
        local fx_text = d.text or "（无效果）"
        -- 中平「有点小用」：标明具体抽到的物品
        if d.fx == "small_use" then
            local dk = self:_drawDiscountItem()
            local dname = self:_getItemDisplayName(dk)
            fx_text = fx_text .. "\n（今日随机物品：「" .. dname .. "」价格变为5积分）"
        end
        title = string.format("今日签运 · %s\n剩余%d天\n\n%s", sign_name, remain_days, fx_text)
        buttons = {
            {
                {text = "关闭抽签模式", callback = function()
                    UIManager:close(dialog)
                    self:_confirmCloseDraw()
                end},
                {text = "知道了", callback = function() UIManager:close(dialog) end},
            },
        }
    else
        -- 今日未抽签：提供抽签入口
        title = string.format("今日待抽签\n剩余%d天\n\n点击「抽签」抽取今日运势。", remain_days)
        buttons = {
            {
                {text = "抽签", callback = function()
                    UIManager:close(dialog)
                    self:_showDrawDialog()
                end},
                {text = "关闭抽签模式", callback = function()
                    UIManager:close(dialog)
                    self:_confirmCloseDraw()
                end},
            },
        }
    end
    dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function FocusFeedback:_confirmStartDraw()
    local dialog
    dialog = ButtonDialog:new{
        title = "开启抽签模式？（需要先养小猫哦）\n· 持续7天，冷却20天\n· 每天首次阅读自动抽一签定当日运势\n· 签运效果仅当日生效，0点重置\n· 抽签与挑战/摸鱼/心跳等其他模式互斥",
        title_align = "center",
        buttons = {
            {
                {text = "开启", callback = function()
                    UIManager:close(dialog)
                    local m = { mode = MODE_DRAW, started_at = os.time() }
                    self:_saveModeState(m)
                    self:_showMessage("抽签模式已开启！\n先来抽今日第一签。", 6)
                    self:_showDrawDialog()
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_confirmCloseDraw()
    local dialog
    dialog = ButtonDialog:new{
        title = "手动关闭抽签模式？\n关闭后即可重新选择模式。",
        title_align = "center",
        buttons = {
            {
                {text = "关闭", callback = function()
                    UIManager:close(dialog)
                    self:_closeMode(MODE_DRAW)
                end},
                {text = "取消", callback = function() UIManager:close(dialog) end},
            },
        },
    }
    UIManager:show(dialog)
end

function FocusFeedback:_checkModeAuto()
    local now = os.time()
    local m = self:_readModeState()
    local mode = m.mode

    -- 挑战模式：24小时倒计时结束自动结算
    if mode == MODE_CHALLENGE and (m.started_at or 0) > 0 then
        if now - m.started_at >= CHALLENGE_DURATION then
            self:_settleChallenge()
            return
        end
    end

    -- 短跑模式：5小时窗口到期未达目标则失败结算
    if mode == MODE_SPRINT and (m.started_at or 0) > 0 and not m.spr_settled then
        if now - m.started_at >= SPRINT_WINDOW then
            self:_settleSprint()
            return
        end
    end

    -- 摸鱼模式：最长30天自动关闭
    if mode == MODE_SLACK and (m.started_at or 0) > 0 then
        if now - m.started_at >= SLACK_MAX_DURATION then
            self:_closeMode(MODE_SLACK, true)
            self:_showMessage("摸鱼模式已持续30天，自动关闭。", 6)
            return
        end
    end

    -- 心跳模式：72小时自动关闭
    if mode == MODE_HEARTBEAT and (m.started_at or 0) > 0 then
        if now - m.started_at >= HEARTBEAT_DURATION then
            self:_closeMode(MODE_HEARTBEAT, true)
            self:_showMessage("心跳模式已持续72小时，自动关闭。\n冷却15天后可再次开启。", 6)
            return
        end
    end

    -- 抽签模式：7天持续到期自动关闭
    if mode == MODE_DRAW and (m.started_at or 0) > 0 then
        if now - m.started_at >= DRAW_DURATION then
            self:_closeMode(MODE_DRAW, true)
            self:_showMessage("抽签模式已持续7天，自动关闭。\n冷却20天后可再次开启。", 6)
            return
        end
    end

    -- 长期模式：周期结束自动结算
    local long = self:_readLongMode()
    if long.cycle and not long.settled and (long.end_at or 0) > 0 then
        if now >= long.end_at then
            self:_settleLongMode()
        end
    end
end

-- ============================================================
-- V15.1 书之来信（成年书日常事件池 + 离线来信）
-- 仅成年书（翻开后）触发。后果字段值：mood=心情值±%，pts=积分±，item=道具key
-- 事件主体不加任何条件=进通用池；conds={字符串}，每项由引擎 _inboxCondWeight 解析。
-- ============================================================
local INBOX_TEST_MODE = true   -- 测试模式：true 时后果不真正生效（仅展示）
-- 进食类冷却组（3h）：事件4/6/7/8；电影类冷却组（2天）：事件10/11/12
local INBOX_COOLDOWN_EAT = {"eat_4", "eat_6", "eat_7", "eat_8"}
local INBOX_COOLDOWN_MOVIE = {"movie_10", "movie_11", "movie_12"}
local INBOX_COOLDOWN_EAT_SEC = 3 * 3600
local INBOX_COOLDOWN_MOVIE_SEC = 2 * 24 * 3600
local INBOX_MIN_GAP_SEC = 1800   -- 距上次来信至少30分钟才来信（防刷屏；测试可临时调小）
local INBOX_MAX_EVENTS = 8      -- 单次离线来信最多生成条数（防一次性爆量）

local ADULT_INBOX_EVENTS = {
    -- 1 xx失眠了（夜间）
    { bg="xx失眠了。", conds={"夜间high"}, id="insomnia",
      bs={
        { t="无后续", conds={"阅历up"} },
        { t="于是从床上爬起来看星星。", conds={"审美up"} },
        { t="硬睡无果后选择吃了一片褪黑素，成功入睡。", conds={"逻辑up","知识up"} },
        { t="干脆通宵玩电子游戏。", mood=5, conds={"情感up"} },
        { t="决定半夜出门探秘灵异之地。", conds={"辩证up","00:00high"} },
      }
    },
    -- 2 xx睡了个超好的觉（夜间）
    { bg="xx睡了个超好的觉。", conds={"夜间high"}, id="sleep_well",
      bs={
        { t="无后续。" },
        { t="第二天醒来心情很不错。", mood=3 },
        { t="结果睡过头了，忘记了和xx的约定。", conds={"近日阅读较少up","首次上线较晚up"} },
        { t="结果睡过头了，但什么后果也没造成，睡觉好幸福！", mood=10, conds={"情感up","春季up"} },
        { t="意外梦见了一个很奇特的点子……", conds={"审美up","情感up"} },
      }
    },
    -- 3 xx做了个噩梦（夜间）
    { bg="xx做了个噩梦。", conds={"夜间high"}, id="nightmare",
      bs={
        { t="无后续。", conds={"阅历up"} },
        { t="但意外学会了特殊技能清明梦。", conds={"知识up","审美up"} },
        { t="被吓得浑身发抖……", mood=-10, conds={"情感up"} },
        { t="醒来后遇见了鬼压床。", mood=-5, conds={"首次上线较晚up","知识较低up"} },
      }
    },
    -- 4 xx吃了一顿超美味的饭（饭点）
    { bg="xx吃了一顿超美味的饭。", conds={"饭点high"}, id="eat_4", cdgrp="EAT",
      bs={
        { t="无后续。", mood=5, conds={"逻辑up"} },
        { t="但误食了过敏食物，被送进医院抢救半小时后，已经痊愈。", conds={"知识较低up","近日阅读较少up","夏秋up"} },
      }
    },
    -- 5 xx喝了一杯水
    { bg="xx喝了一杯水。", id="drink",
      bs={
        { t="无后续。", conds={"逻辑up"} },
        { t="被呛住，原地咳嗽了五分钟。", conds={"阅历较低up"} },
        { t="遇见凉水塞书缝……", mood=-5, conds={"阅历up","近日阅读较少up"} },
        { t="结果发现水是雪碧假扮的，xx感到很诡异。", conds={"审美up","辩证up","逻辑up"} },
      }
    },
    -- 6 xx独自去了一家餐馆吃饭
    { bg="xx独自去了一家餐馆吃饭。", conds={"饭点high"}, id="eat_6", cdgrp="EAT",
      bs={
        { t="无后续。", conds={"逻辑up"} },
        { t="拍到了自己的书生照片（总感觉会遇见狐狸……）。", mood=5, conds={"审美up"} },
        { t="吃完顺手扫了饮料有奖码，中了三等奖。", pts=3, conds={"阅历up"} },
      }
    },
    -- 7 xx点了个外卖来吃吃！
    { bg="xx点了个外卖来吃吃！", conds={"饭点high"}, id="eat_7", cdgrp="EAT",
      bs={
        { t="无后续。" },
        { t="点到一些美味健康之物。", mood=5, conds={"阅历up"} },
        { t="点到一堆难吃的预制菜……", mood=-5, conds={"近日阅读较少up","审美较低up"} },
        { t="结果骑手派送途中外卖连着电动车一起被抢了……xx善解人意地送了骑手一辆新车。", pts=-5, conds={"情感up"} },
        { t="结果骑手派送途中外卖连着电动车一起被抢了……xx没吃到饭气得半死，抢走了骑手仅剩的二十块钱点了个新外卖。", pts=2, conds={"辩证up","近日阅读较多up"} },
      }
    },
    -- 8 xx决定自己下厨
    { bg="xx决定自己下厨。", conds={"饭点high"}, id="eat_8", cdgrp="EAT",
      bs={
        { t="无后续。" },
        { t="做出一顿色香味俱全之物。", mood=5, conds={"知识up","逻辑up"} },
        { t="把房子烧没了……只好向主人索要财物购入新房子。", pts=-5, conds={"知识较低up"} },
      }
    },
    -- 9 xx决定带猫去做绝育（春秋）
    { bg="xx决定带猫去做绝育。", conds={"春秋high"}, id="cat_neuter",
      bs={
        { t="绝育成功，小猫变得更粘人了！", pts=1, conds={"情感up"} },
        { t="猫生气地抓伤了xx，xx开始思考宠物绝育的伦理问题。最终把猫带回了家。", conds={"知识up","逻辑up","辩证up"} },
        { t="结果因为夜晚天黑看不清路，连书带猫一起滚落到了一处悬崖下面……", conds={"审美up"} },
      }
    },
    -- 10 xx独自观看了电影《Lalaland》
    { bg="xx独自观看了电影《Lalaland》。", conds={"晚间high","深夜up"}, id="movie_10", cdgrp="MOVIE",
      bs={
        { t="无后续。" },
        { t="感觉很无聊，在美丽的歌曲里开始睡觉。", mood=-1, conds={"审美较低up"} },
        { t="感觉很兴奋，并陶醉在洛杉矶的夜晚里。", mood=5, conds={"审美up"} },
        { t="看到一半却突然掉落大量碎纸屑，只好落荒而逃。", conds={"近日阅读较少up","离线时间长up"} },
      }
    },
    -- 11 xx独自观看了电影《战狼2》
    { bg="xx独自观看了电影《战狼2》。", conds={"日中up"}, id="movie_11", cdgrp="MOVIE",
      bs={
        { t="无后续。" },
        { t="很讨厌，发誓再也不看。", mood=-1, conds={"审美up"} },
        { t="结果爱上了男主演……", conds={"审美较低up"} },
      }
    },
    -- 12 xx独自观看了电影《花样年华》
    { bg="xx独自观看了电影《花样年华》。", conds={"晚间high","深夜up"}, id="movie_12", cdgrp="MOVIE",
      bs={
        { t="无后续。" },
        { t="但是感觉看不懂，莫名其妙。", conds={"审美较低up","情感较低up"} },
        { t="这期真是审美积累……", conds={"审美up","情感up"} },
      }
    },
    -- 13 xx在独自观看电影时不小心把可乐弄洒在了电影院的座位上
    { bg="xx在独自观看电影时不小心把可乐弄洒在了电影院的座位上。", conds={"知识较低up"}, id="cola",
      bs={
        { t="无后续。", mood=-1, pts=-1 },
        { t="只好痛哭流涕地找到保洁员道歉。", mood=-5, conds={"情感up","阅历较低up"} },
        { t="趁着无人注意偷偷溜出了影院。", conds={"情感较低up"} },
      }
    },
    -- 14 xx独自观看了一场F1比赛
    { bg="xx独自观看了一场F1比赛。", conds={"夏秋晚间up"}, id="f1",
      bs={
        { t="无后续。", conds={"阅历up","逻辑up"} },
        { t="从此一发不可收拾成为了苦逼的四轮书……", mood=-10, pts=5, conds={"情感up"} },
        { t="感觉好无聊再也不打算看了。", conds={"情感较低up","辩证up"} },
      }
    },
    -- 15 xx生病了……
    { bg="xx生病了……", conds={"流感季high","知识较低up","离线时间长up"}, id="sick",
      bs={
        { t="无后续。", mood=-1 },
        { t="但去医院打了吊针后堂堂痊愈！", mood=10, pts=-5, conds={"阅历up"} },
        { t="但没有去医院。", mood=-10, conds={"知识较低up","阅历较低up"} },
      }
    },
    -- 16 xx在外面被一个很大的东西欺负了……
    { bg="xx在外面被一个很大的东西欺负了……", id="bully",
      bs={
        { t="xx不知道那是什么，xx很害怕地躲回了家。", mood=-5, conds={"知识较低up","阅历较低up"} },
        { t="xx感觉莫名其妙，绕过它离开了。", conds={"知识up","阅历up"} },
        { t="xx拿出电话摇来了xx的主人也就是你，你发现那是一只邪恶斑点狗。", pts=-2, conds={"情感up"} },
        { t="聪明的xx跟随着此物回到它的家，偷拿了两块钱给自己当精神损失费。", pts=2, conds={"辩证high"} },
      }
    },
    -- 17 xx读完了一本书
    { bg="xx读完了一本书。", conds={"近日读完up"}, id="finish",
      bs={
        { t="无后续。", mood=1 },
        { t="发现这本书超级无敌烂。", mood=-5, conds={"情感up"} },
        { t="惊喜地发现这是xx的书生之书……", mood=20, conds={"审美up"} },
        { t="发现了许多逻辑漏洞，怒上豆瓣写了二星辣评，收到了出版社的礼包补偿。", pts=2, conds={"辩证high"} },
      }
    },
    -- 18 xx走入一家神秘小店……
    { bg="xx走入一家神秘小店……", conds={"午夜深high"}, id="mystery_shop",
      bs={
        { t="却因为打扮太土被赶了出来。", mood=-1, conds={"审美较低up"} },
        { t="购入一个盲盒，拆开一看发现是一堆迷你拼豆小鸡。还挺可爱的。", mood=5, item="toy", conds={"情感up"} },
        { t="购入了一碗神秘食物，吃完感觉好难吃不想给钱赶紧跑路。", mood=-1, pts=1, conds={"逻辑up","辩证up"} },
        { t="发现自己什么也买不起于是试图偷东西，被抓住拷打了一顿。", mood=-5, pts=-3, conds={"辩证high"} },
      }
    },
    -- 19 xx网购了一款机器人
    { bg="xx网购了一款机器人。", conds={"知识up","逻辑up"}, id="robot",
      bs={
        { t="无后续。", pts=-2 },
        { t="傻子xx用不懂，扔掉了。", pts=-5, conds={"阅历较低up"} },
        { t="聪明xx利用机器人大大提高了自己的生活水平。", pts=-2, mood=10, conds={"知识up","逻辑up","阅历up"} },
        { t="机器人却偷偷告诉了xx一个惊天大秘密……", conds={"审美up"} },
      }
    },
    -- 20 xx决定开始运动。
    { bg="xx决定开始运动。", id="sport",
      bs={
        { t="一小时过去，xx放弃了。", conds={"阅历较低high"} },
        { t="xx购入了瑜伽球×1。", pts=-2, item="toy", conds={"审美up"} },
        { t="xx每天早晨6：00准时爬起床跑步，却因为起床动静太大遭到了邻居疯狂投诉，只好放弃。", mood=-1, conds={"知识较低up"} },
        { t="xx购入了拳击手套×1。", pts=-2, item="toy", conds={"各项均衡high"} },
      }
    },
    -- 21 xx无聊地待在家里，追起了自己的尾巴。却意外制造了一场龙卷风。
    { bg="xx无聊地待在家里，追起了自己的尾巴。却意外制造了一场龙卷风。", pts=-1, id="tail_tornado" },
    -- 22 xx独自开始哼歌。
    { bg="xx独自开始哼歌。", conds={"审美up"}, id="hum" },
    -- 23 xx网购了一套画具。
    { bg="xx网购了一套画具。", pts=-2, item="toy", conds={"审美up"}, id="art_supplies" },
    -- 24 xx原地跳了一段天鹅湖。
    { bg="xx原地跳了一段天鹅湖。", conds={"审美up"}, id="swan" },
    -- 25 xx来到一片湖旁边，开始坐下钓鱼。
    { bg="xx来到一片湖旁边，开始坐下钓鱼。", conds={"阅历up"}, id="fish",
      bs={
        { t="无后续。" },
        { t="钓到了一条萌萌小鱼，xx将它又放回了湖里。", mood=5, conds={"情感up"} },
        { t="两小时过去了什么也没钓到！xx气急败坏地跑了。", mood=-5, conds={"阅历较低up"} },
        { t="过了一会儿，鱼线开始抖动，xx提起来一看，却发现是一个河神……", conds={"辩证up"} },
      }
    },
    -- 26 xx决定出门走走！心情+2%
    { bg="xx决定出门走走！", mood=2, id="walk" },
    -- 27 xx决定去网吧放纵自己！狂打了两个小时数独。
    { bg="xx决定去网吧放纵自己！狂打了两个小时数独。", conds={"逻辑high"}, id="netcafe" },
    -- 28 xx决定用一辈子来成为自己。
    { bg="xx决定用一辈子来成为自己。", conds={"各项均衡且偏高high"}, id="become_self" },
    -- 29 xx走在路上，捡到了一副塔罗牌。
    { bg="xx走在路上，捡到了一副塔罗牌。", conds={"晚夜high","情感up"}, id="tarot",
      bs={
        { t="xx把玩了一会儿，随手扔在了路边。", conds={"阅历较低up"} },
        { t="xx感到很有意思，随机抽取了一张，逆位宝剑八。" },
        { t="xx把它带回了家。", conds={"审美up","情感up","阅历up","知识up"} },
      }
    },
    -- 30 xx来到了博物馆。
    { bg="xx来到了博物馆。", conds={"午后high","知识high"}, id="museum",
      bs={
        { t="但只是乱逛一圈就走了。", conds={"阅历较低up"} },
        { t="意外被工作人员挖掘，关进了玻璃柜成为新展品。", mood=-2, conds={"审美up"} },
        { t="学到了很多新知识！", pts=2, conds={"知识high"} },
      }
    },
    -- 31 xx看到了一道彩虹。心情+2%（审美up）
    { bg="xx看到了一道彩虹。", mood=2, conds={"审美up"}, id="rainbow" },
    -- 32 xx说："Can I waste all your time here on the sidewalk?"
    { bg="xx说：“Can I waste all your time here on the sidewalk?”", conds={"审美up","情感up"}, id="sidewalk" },
    -- 33 xx路过了一座华美的建筑。
    { bg="xx路过了一座华美的建筑。", conds={"辩证up","逻辑up","知识up","阅历较低up"}, id="building" },
    -- 34 xx小睡了30分钟。
    { bg="xx小睡了30分钟。", conds={"午睡up","春季up"}, id="nap",
      bs={
        { t="醒来后精神好了很多。", mood=5 },
        { t="恰巧梦见了一个温暖的午后……", conds={"情感up"} },
      }
    },
    -- 35 xx被陨石砸中了。心情-10%
    { bg="xx被陨石砸中了。", mood=-10, conds={"知识较低up"}, id="meteor" },
    -- 36 xx骑车在外面玩时，天空突然下起了倾盆大雨。心情-5%
    { bg="xx骑车在外面玩时，天空突然下起了倾盆大雨。", mood=-5, id="rain_bike" },
    -- 37 xx搭乘出租车时，充电宝突然着火了。
    { bg="xx搭乘出租车时，充电宝突然着火了。", id="power_bank",
      bs={
        { t="xx赶紧将其扔到了司机身上。", mood=2, conds={"知识较低up","辩证up"} },
        { t="xx吓得快死了立马跳车。", mood=-2, conds={"阅历较低up"} },
        { t="xx淡定地拿出一瓶矿泉水浇了上去，结果充电宝直接爆炸了！将xx和司机一起送进了医院。", pts=-5, conds={"知识较低up","阅历较低up"} },
        { t="不过还好，xx拿出了干粉灭火器手忙脚乱一通操作化解危机。", pts=3, conds={"知识up","阅历up","逻辑up"} },
      }
    },
    -- 38 xx搭乘电梯时，电梯突然出现了故障。
    { bg="xx搭乘电梯时，电梯突然出现了故障。", id="elevator",
      bs={
        { t="xx淡定地踮起脚按了呼救按键，半小时后脱困。", conds={"逻辑up"} },
        { t="xx急得团团转。晕晕的团团生气地救出了它。", mood=-2, conds={"情感up"} },
        { t="xx躲在电梯里背着主人偷偷玩起了手机。", mood=5, conds={"审美up","辩证up"} },
      }
    },
    -- 39 xx来到一颗树下，顺手挖了个洞。
    { bg="xx来到一颗树下，顺手挖了个洞。", conds={"审美up","辩证up"}, id="hole",
      bs={
        { t="无后续。", mood=1 },
        { t="意外发现了石油，但xx发现报矿没有奖励，遗憾地把它又埋了起来。", conds={"辩证up"} },
        { t="结果发现一个神秘小卷轴……", conds={"审美high"} },
      }
    },
    -- 40 xx路遇了一个冰淇淋并食用之。心情+2%
    { bg="xx路遇了一个冰淇淋并食用之。", mood=2, id="icecream" },
}
local ADULT_INBOX_EVENTS_FLAT = nil  -- 惰性生成（主体+各分支展开）

-- 书信开头/结尾模板：按当前单本最高属性选用
-- 占位符（昵称）会在展示时替换
local INBOX_LETTER_TEMPLATES = {
    grief_high = {
        great = "（昵称）：",
        open = "你不在的日子里我的生活很丰富！也很想你……",
        close = "下次见！！要开心——",
    },
    aesthetic_high = {
        great = "亲爱的朋友：",
        open = "展信佳。当你读这封信的时候，我又将拥有你生命中的三分钟。",
        close = "请停一停，你真美丽。",
    },
    logic_high = {
        great = "朋友：",
        open = "近况汇报如下：",
        close = "一切都还好吗？",
    },
    knowledge_high = {
        great = "亲爱的主人：",
        open = "最近又学到了许多新东西，忍不住向你分享……",
        close = "江南无所有，聊赠一枝春。",
    },
    experience_high = {
        great = "人类：",
        open = "见字如晤。有些好玩的经历，难以抑制分享的心情。",
        close = "真想与这封信一起，跨过千山万水。",
    },
    dialectic_high = {
        great = "人类的女孩：",
        open = "见不到你我急得团团转……最近也有一些小书事发生！请品鉴！",
        close = "真想和你畅聊上一个晚自习呀！",
    },
}
-- 模板对应的最高属性判定
local INBOX_LETTER_PROFILE = {
    { attr="审美", style="aesthetic_high" },
    { attr="逻辑", style="logic_high" },
    { attr="知识", style="knowledge_high" },
    { attr="阅历", style="experience_high" },
    { attr="辩证", style="dialectic_high" },
    { attr="情感", style="grief_high" },  -- 情感兜底
}

-- 惰性展开事件池：每个 (主体×分支) 展开为一个候选
function FocusFeedback:_inboxFlatEvents()
    if ADULT_INBOX_EVENTS_FLAT then return ADULT_INBOX_EVENTS_FLAT end
    local flat = {}
    for _, e in ipairs(ADULT_INBOX_EVENTS) do
        local tail_blanks = { { t="" } }
        local branches = (e.bs and #e.bs > 0) and e.bs or tail_blanks
        for _, b in ipairs(branches) do
            -- 分支结果若为"无后续"（表示没有特别后续），则不再拼入正文，只保留背景句
            local tb = (b.t or ""):gsub("无后续。", ""):gsub("无后续", "")
            table.insert(flat, {
                id = e.id,
                bg = e.bg,
                text = (tb ~= "") and (e.bg .. tb) or e.bg,
                conds = e.conds or {},
                bconds = b.conds or {},
                mood = b.mood or (e.mood or 0),
                pts = b.pts or (e.pts or 0),
                item = b.item or e.item,
                cdgrp = (b.cdgrp or e.cdgrp),
                nap = e.nap,
                is_blank = (not b.t or b.t == ""),
            })
        end
    end
    ADULT_INBOX_EVENTS_FLAT = flat
    return flat
end

-- 依据当前单本六维属性，按属性值加权随机抽取书信风格（与事件触发同一套加权逻辑）
function FocusFeedback:_inboxLetterStyle(entry)
    local a = self:_inboxAttrs(entry)
    -- 每种风格的出现概率 ∝ 它对应属性的当前值；属性为0时给极低权重保底，避免完全消失
    local picked = self:_weightedPick(INBOX_LETTER_PROFILE, function(item)
        return 0.1 + (a[item.attr] or 0)
    end)
    return INBOX_LETTER_TEMPLATES[picked.style] or INBOX_LETTER_TEMPLATES.grief_high
end

-- 季节：3-5春，6-8夏，9-11秋，12-2冬（返回“春/夏/秋/冬”）
function FocusFeedback:_seasonLabel(month)
    if month == 3 or month == 4 or month == 5 then return "春" end
    if month == 6 or month == 7 or month == 8 then return "夏" end
    if month == 9 or month == 10 or month == 11 then return "秋" end
    return "冬"
end

-- 时间段落标签（用于事件选中时的时间锚点；来信时间由时长随机分配）
function FocusFeedback:_inboxPeriodLabel(hour)
    if hour < 3 then return "深夜" end
    if hour < 6 then return "深夜" end
    if hour < 9 then return "早晨" end
    if hour < 12 then return "上午" end
    if hour < 13 then return "午间" end
    if hour < 18 then return "午后" end
    if hour < 21 then return "傍晚" end
    if hour < 24 then return "晚间" end
    return "深夜"
end

-- 六维属性（来自 collection entry 的 attributes，或当前存活书）
function FocusFeedback:_inboxAttrs(entry)
    local a = entry and entry.attributes
    if type(a) == "table" and a["知识"] then return a end
    return self:_initAttributes()  -- 兜底全 0
end

-- 计算某条候选的权重乘数（>=0，0 表示当前不可触发）
function FocusFeedback:_inboxBranchWeight(cand, attrs, ctx)
    local w = 1.0
    local all_conds = {}
    for _, c in ipairs(cand.conds) do table.insert(all_conds, c) end
    for _, c in ipairs(cand.bconds) do table.insert(all_conds, c) end
    for _, c in ipairs(all_conds) do
        local f = self:_inboxCondWeight(c, attrs, ctx)
        w = w * f
        if w <= 0.001 then return 0 end
    end
    return w
end

-- 解析单个条件字符串 → 乘数 [0,3]。dirname 语义：up/high = 属性高加权；较低up/high = 属性低加权
function FocusFeedback:_inboxCondWeight(c, attrs, ctx)
    -- 时间/季节类（不带属性，用 ctx.hour / ctx.season / ctx.periodWeight）
    local hour = ctx.hour or 12
    if c == "夜间high" then return (hour >= 18 or hour < 6) and 3 or 0 end
    if c == "深夜up" then return (hour >= 23 or hour < 3) and 1.8 or 0 end
    if c == "晚间high" then return (hour >= 19 and hour < 23) and 3 or 0 end
    if c == "晚夜high" then return (hour >= 18 or hour < 5) and 3 or 0 end
    if c == "午夜深high" then return (hour >= 22 or hour < 6) and 3 or 0 end
    if c == "日中up" then return (hour >= 12 and hour < 18) and 1.8 or 0 end
    if c == "午后high" then return (hour >= 14 and hour < 18) and 3 or 0 end
    if c == "饭点high" then return (hour >= 7 and hour < 9) or (hour >= 12 and hour < 13) or (hour >= 18 and hour < 19) and 3 or 0 end
    if c == "午睡up" then return (hour >= 12 and hour < 15) and 1.8 or 0 end
    if c == "00:00high" then return (hour == 0) and 3 or 0 end

    -- 季节
    local season = ctx.season or self:_seasonLabel(os.date("*t").month)
    if c == "春季up" then return season == "春" and 1.8 or 1.0 end
    if c == "夏秋up" then return (season == "夏" or season == "秋") and 1.8 or 1.0 end
    if c == "春秋high" then return (season == "春" or season == "秋") and 3 or 0 end
    if c == "流感季high" then return (season == "春" or season == "秋") and 3 or 1.0 end
    if c == "夏秋晚间up" then return (season == "夏" or season == "秋") and (hour >= 21 and hour < 22) and 1.8 or 0 end

    -- 阅读记录
    local recent_less = ctx.recent_read_ge6_less and true or false   -- 近3日较多(<6h? 见下)
    if c == "近日阅读较少up" then return ctx.read_low and 1.8 or 1.0 end
    if c == "近日阅读较多up" then return ctx.read_high and 1.8 or 1.0 end
    if c == "近日读完up" then return ctx.finished_recent and 2.0 or 0 end
    if c == "离线时间长up" then return ctx.offline_long and 1.6 or 0 end
    if c == "首次上线较晚up" then return ctx.first_online_late and 1.8 or 0 end

    -- 属性类：形态 属性名 + up/high/较低
    local attr = c:match("^([知识审美情感阅历逻辑辩证])")
    local attr_ok = attr ~= nil
    if attr_ok and (c:find("较低", 1, true) or c:match("up$") or c:match("high$")) then
        local v = attrs[attr] or 0
        local low = c:find("较低", 1, true) ~= nil
        local level = c:match("high$") and "high" or "up"
        local k = level == "high" and 3 or 1.6
        if low then
            return (v <= 30) and k or (100 - v) / 100   -- 越低越高；>30 时随反比
        else
            return (v >= 70) and k or v / 100
        end
    end
    -- 特殊
    if c == "各项均衡up" then return ctx.balanced and 1.6 or 0 end
    if c == "各项均衡high" then return ctx.balanced and 2.6 or 0 end
    if c == "各项均衡且偏高high" then return ctx.balanced and ctx.high_all and 3 or 0 end
    return 1.0 -- 未知条件视为中性
end

-- 生成两本测试书（注入 collection），属性分布便于观察
function FocusFeedback:_ensureTestBooks()
    -- 开关：关闭则不再注入测试书
    if self:_readEventToggles().inbox == false then return end
    local c = self:_readCollection()
    local hasA, hasB = false, false
    for _, e in ipairs(c) do
        if e.test_book == "A" then hasA = true end
        if e.test_book == "B" then hasB = true end
    end
    if hasA and hasB then return end
    -- 测试书 A：属性均衡且中高（便于测"均衡且偏高"）
    if not hasA then
        table.insert(c, {
            index = 99901, nickname = "测试书·均衡", test_book = "A",
            reveal_date = todayKey(), adopt_date = todayKey(),
            attributes = {知识=65,审美=60,情感=62,阅历=58,逻辑=70,辩证=64},
        })
    end
    -- 测试书 B：属性偏谱（逻辑极高、情感极低，便于观察方向加权差异）
    if not hasB then
        table.insert(c, {
            index = 99902, nickname = "测试书·偏科", test_book = "B",
            reveal_date = todayKey(), adopt_date = todayKey(),
            attributes = {知识=85,审美=75,情感=15,阅历=40,逻辑=90,辩证=80},
        })
    end
    self:_saveCollection(c)
end

-- 为 collection 中每本成年书（含测试书）更新 last_inbox_ts（首次）
function FocusFeedback:_inboxInit()
    local c = self:_readCollection()
    local changed = false
    for _, e in ipairs(c) do
        if e.reveal_date and not e.last_inbox_ts then
            e.last_inbox_ts = os.time()
            changed = true
        end
    end
    if changed then self:_saveCollection(c) end
end

-- 读取近3日阅读时长(秒)，用于"较少/较多"判定（less ≤3h，more ≥6h）
function FocusFeedback:_recentReadSeconds()
    return self:_getDailyStat().reading_seconds or 0
end

-- 读取当前积分
function FocusFeedback:_inboxPoints()
    return self:_readPoints() or 0
end

-- 读取某项道具库存数量
function FocusFeedback:_inboxInv(qty, key)
    local inv = self:_readInventory()
    return (inv and inv[key]) or 0
end

-- 依据离线时长在时间轴内随机撒点，返回升序的时间戳数组
-- keep = 事件条数；offline_sec = 本次离线总长
function FocusFeedback:_inboxRandomTimes(offline_sec, keep)
    local times = {}
    local span = math.max(600, offline_sec)  -- 至少10分钟
    for i = 1, keep do
        local t = math.random(0, span - 600)
        table.insert(times, t)
    end
    table.sort(times)
    return times
end

-- 生成一封来信内容（不落库）。ctx 封装上下文供权重判定。
function FocusFeedback:_genInboxLetter(entry, offline_sec, now)
    local attrs = self:_inboxAttrs(entry)
    local ctx = { hook = entry }
    -- 参数保守填充，避免依赖重构上下文：
    ctx.hour = os.date("*t", now).hour
    ctx.season = self:_seasonLabel(os.date("*t", now).month)
    ctx.offline_long = offline_sec >= 4 * 3600
    ctx.offline_short = offline_sec < 3600
    -- 均衡与偏高判定（标准差≤10 且 均值≥60）
    local vals = {}
    for _, k in ipairs(ATTR_KEYS) do table.insert(vals, attrs[k] or 0) end
    local sum, n = 0, #vals
    for _, v in ipairs(vals) do sum = sum + v end
    local mean = sum / n
    local sd = 0
    for _, v in ipairs(vals) do sd = sd + (v - mean) * (v - mean) end
    sd = math.sqrt(sd / n)
    ctx.balanced = sd <= 10
    ctx.high_all = mean >= 60
    ctx.read_low = self:_recentReadSeconds() <= 3 * 3600
    ctx.read_high = self:_recentReadSeconds() >= 6 * 3600
    ctx.first_online_late = ctx.hour >= 11
    ctx.finished_recent = false

    -- 事件数量：约1条/小时，至少1条（离线稀疏错落；池不足时自动变少）
    local keep = math.max(1, math.floor(offline_sec / 3600))
    if keep > INBOX_MAX_EVENTS then keep = INBOX_MAX_EVENTS end   -- 防一次性爆量

    -- 冷却过滤：进食组3h / 电影组2天 距上次触发
    local cd = entry.inbox_cd or {}
    local flat = self:_inboxFlatEvents()
    local pool = {}
    for _, cand in ipairs(flat) do
        local ok = true
        if cand.cdgrp == "EAT" and (cd.eat and now - cd.eat < INBOX_COOLDOWN_EAT_SEC) then ok = false end
        if cand.cdgrp == "MOVIE" and (cd.mov and now - cd.mov < INBOX_COOLDOWN_MOVIE_SEC) then ok = false end
        if ok then table.insert(pool, cand) end
    end

    -- 加权抽取 keep 条（带近期降权，避免重复）
    local picks = {}
    local used = {}
    for _ = 1, keep do
        local candidates = {}
        for _, cand in ipairs(pool) do
            local w = self:_inboxBranchWeight(cand, attrs, ctx)
            if w > 0 then
                -- 近期已用事件降权（*0.4），反重复
                if used[cand.id] then w = w * 0.4 end
                table.insert(candidates, { cand = cand, w = w })
            end
        end
        if #candidates == 0 then break end
        local total = 0
        for _, ci in ipairs(candidates) do total = total + ci.w end
        local r = math.random() * total
        -- 归一化候选权重到 [0.1,3]（约束边界）
        local sel
        local acc = 0
        for _, ci in ipairs(candidates) do
            acc = acc + ci.w
            if r <= acc then sel = ci.cand break end
        end
        if not sel then sel = candidates[#candidates].cand end
        table.insert(picks, sel)
        used[sel.id] = true
    end

    -- 组装信件：附加随机时间戳（时分）与落款日期区间
    local times = self:_inboxRandomTimes(offline_sec, #picks)
    local events = {}
    for i, cand in ipairs(picks) do
        local sec = times[i] or 0
        local et = os.time({ year = os.date("*t", now).year, month = os.date("*t", now).month, day = os.date("*t", now).day, hour = 0 }) + sec
        table.insert(events, {
            time = os.date("%H:%M", et),
            text = cand.text:gsub("xx", entry.nickname or "它"),
            mood = cand.mood or 0,
            pts = cand.pts or 0,
            item = cand.item,
            flatid = cand.id,
            cand = cand,
        })
    end
    return { events = events }
end

-- 应用来信后果（积分/心情/道具）。测试模式下不真正生效，仅计入展示文本。
function FocusFeedback:_applyInboxResult(e, mood, pts, item)
    if INBOX_TEST_MODE then return end
    -- 心情
    if mood and mood ~= 0 then
        local cur = self:_readMood()
        self:_saveMood(math.max(0, math.min(100, cur + mood)))
    end
    -- 积分（下限0）
    if pts and pts ~= 0 then
        local cur = self:_inboxPoints()
        if pts < 0 and cur <= 0 then
            -- 已为0则不扣
        else
            self:_savePoints(math.max(0, cur + pts))
        end
    end
    -- 道具
    if item then
        local inv = self:_readInventory()
        inv[item] = (inv[item] or 0) + 1
        self:_saveInventory(inv)
    end
end

-- 书之来信主入口：对每本成年书，检查自上次来信以来的离线时长，生成来信并展示
function FocusFeedback:_showInboxLetters()
    -- 开关：关闭则所有成年书来信活动停用
    if self:_readEventToggles().inbox == false then return end
    local c = self:_readCollection()
    local now = os.time()
    local changed = false
    for _, e in ipairs(c) do
        if e.reveal_date and e.last_inbox_ts then
            local gap = now - e.last_inbox_ts
            if gap >= INBOX_MIN_GAP_SEC then  -- 距上次来信至少30分钟才来信
                local letter = self:_genInboxLetter(e, gap, now)
                if #letter.events > 0 then
                    -- 写入该书旅行日志（不再自动弹窗，供"旅行的书"手动查看）
                    local tlog = e.travel_log or {}
                    local n = #letter.events
                    for i, ev in ipairs(letter.events) do
                        table.insert(tlog, {
                            ts = now - gap + math.floor(gap * i / (n + 1)),  -- 在离线窗口内自然错开
                            text = ev.text,
                            mood = ev.mood or 0,
                            pts = ev.pts or 0,
                            item = ev.item,
                        })
                    end
                    table.sort(tlog, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
                    e.travel_log = tlog
                    -- 更新事件冷却（EAT/MOVIE 避免同一事件反复出现）
                    local cd = e.inbox_cd or {}
                    for _, ev in ipairs(letter.events) do
                        if ev.cand and ev.cand.cdgrp == "EAT" then cd.eat = now end
                        if ev.cand and ev.cand.cdgrp == "MOVIE" then cd.mov = now end
                    end
                    e.inbox_cd = cd
                    e.last_inbox_ts = now
                    changed = true
                end
                -- 清理超24h旧日志（每次最多逐条删1条，渐进式）
                if self:_travelCleanup(e, 1) then changed = true end
            end
        end
    end
    if changed then self:_saveCollection(c) end
end

-- 旅行日志清理：每次最多删一条"最早且超过24h"的旧记录（渐进式，不一下子清空）
function FocusFeedback:_travelCleanup(e, max)
    local tlog = e.travel_log
    if not tlog or #tlog == 0 then return false end
    local now = os.time()
    local cutoff = now - 24 * 3600
    max = max or 1
    local removed = false
    for _ = 1, max do
        local idx = nil
        for i, ent in ipairs(tlog) do
            if (ent.ts or 0) < cutoff then idx = i; break end
        end
        if not idx then break end
        table.remove(tlog, idx)
        removed = true
    end
    return removed
end

-- 旅行的书：列出有旅行日志的书昵称（点击进详情）
function FocusFeedback:_showTravelBookList()
    local c = self:_readCollection()
    local entries = {}
    for _, e in ipairs(c) do
        local tlog = e.travel_log
        if e.reveal_date and tlog and #tlog > 0 then
            table.insert(entries, e)
        end
    end
    if #entries == 0 then
        self:_showMessage("还没有旅行日记。\n离线一段时间或阅读中，会有动态悄悄记录下来。", 5)
        return
    end
    local items = {}
    for _, e in ipairs(entries) do
        local book = self.book_data[e.index] or { title = "未知" }
        local last = nil
        for _, _ent in ipairs(e.travel_log or {}) do
            if not last or (_ent.ts or 0) > (last.ts or 0) then last = _ent end
        end
        last = last or {}
        table.insert(items, {
            text = e.nickname or book.title,
            sub = string.format("共 %d 条 · 最近 %d/%d %02d:%02d",
                #e.travel_log or 0,
                last.ts and os.date("*t", last.ts).month or 0,
                last.ts and os.date("*t", last.ts).day or 0,
                last.ts and os.date("*t", last.ts).hour or 0,
                last.ts and os.date("*t", last.ts).min or 0),
            callback = function()
                self:_showTravelLogDialog(e, 1)
            end,
        })
    end
    local menu = Menu:new{
        title = "旅行的书",
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
    }
    menu.show_parent = nil
    UIManager:show(menu)
end

-- 中英混排断行：按可见宽度大致 n 个半角宽度一行
function FocusFeedback:_travelWrap(s, n)
    s = tostring(s or "")
    n = n or 26
    local out = {}
    local line = ""
    local w = 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local cw = 1
        if ch:byte() > 127 then cw = 2 end   -- 中文按2个半角宽
        line = line .. ch
        w = w + cw
        if w >= n then
            table.insert(out, line)
            line = ""
            w = 0
        end
    end
    if line ~= "" then table.insert(out, line) end
    if #out == 0 then out = { "" } end
    return table.concat(out, "\n")
end

-- 旅行的书：单本动态日志的大弹窗（分页查看；右下角落款日期；底部 查看档案/确定）
function FocusFeedback:_showTravelLogDialog(e, page)
    local tlog = e.travel_log or {}
    table.sort(tlog, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    if #tlog == 0 then
        self:_showMessage("（这本书还没有旅行动态）", 3)
        return
    end
    -- 构建行：日期 时分 + 文本 + 心情/积分/道具
    local lines = {}
    for _, ent in ipairs(tlog) do
        local t = os.date("*t", ent.ts or 0)
        local hm = string.format("%02d:%02d", t.hour, t.min)
        local yy = string.format("%02d-%02d", t.month, t.day)
        local suffix = ""
        if (ent.mood or 0) ~= 0 then suffix = suffix .. string.format("  心情%+d%%", ent.mood) end
        if (ent.pts or 0) ~= 0 then suffix = suffix .. string.format("  积分%+d", ent.pts) end
        if ent.item then suffix = suffix .. "  道具+" .. ent.item end
        table.insert(lines, self:_travelWrap((yy .. " " .. hm .. "  " .. (ent.text or "") .. suffix), 40))  -- 调大字号后每行折成 40 半角宽 ≈ 20 汉字
    end
    -- 倒序：最新在顶部
    for i = 1, math.floor(#lines / 2) do
        lines[i], lines[#lines - i + 1] = lines[#lines - i + 1], lines[i]
    end
    local per_page = 8   -- 字号加大后减少每页行数，防止撑破弹窗
    local pages = math.max(1, math.ceil(#lines / per_page))
    if page < 1 then page = 1 elseif page > pages then page = pages end
    local pageLines = {}
    for i = (page - 1) * per_page + 1, math.min(page * per_page, #lines) do
        table.insert(pageLines, lines[i])
    end
    -- 每条动态独立一行：TextWidget 不解析 \n，须一行一个控件竖排
    local bodyParts = {}
    for _, ln in ipairs(pageLines) do
        local w = TextWidget:new{ text = ln, face = Font:getFace("cfont", 18) }
        w.not_focusable = true
        table.insert(bodyParts, w)
    end
    if #bodyParts == 0 then
        local w = TextWidget:new{ text = "（无内容）", face = Font:getFace("cfont", 18) }
        w.not_focusable = true
        table.insert(bodyParts, w)
    end
    local bodyVG = VerticalGroup:new{ align = "left", unpack(bodyParts) }
    bodyVG.not_focusable = true
    local bodyTW = bodyVG  -- 统一变量名，供下方内容组装引用

    -- 底部两行按钮：上一行翻页，下一行 查看档案 / 确定
    local buttons = {}
    local navrow = {}
    if page > 1 then
        table.insert(navrow, { text = "◀ 上一页", callback = function() self:_reopenTravel(e, page - 1) end })
    else
        table.insert(navrow, { text = "上一页", enabled = false })
    end
    table.insert(navrow, { text = string.format("%d / %d", page, pages), enabled = false })
    if page < pages then
        table.insert(navrow, { text = "下一页 ▶", callback = function() self:_reopenTravel(e, page + 1) end })
    else
        table.insert(navrow, { text = "下一页", enabled = false })
    end
    table.insert(buttons, navrow)
    table.insert(buttons, {
        { text = "查看档案", callback = function() self:_showBookInfo(e) end },
        { text = "确定", callback = function() if self._travel_dlg then UIManager:close(self._travel_dlg) end self._travel_dlg = nil end },
    })

    local nick = e.nickname or "它"
    local dialog = ButtonDialog:new{
        title = string.format("旅行的书 · %s", nick),
        title_align = "center",
        width = Screen:scaleBySize(600),
        scrollable_content = false,
        buttons = buttons,
    }
    dialog.show_parent = nil

    -- 内容组装（最后页右下角落款日期）
    local parts = { bodyTW }
    if page == pages then
        local last = tlog[#tlog]
        local sign_dt = os.date("%Y.%m.%d", (last and last.ts) or os.time())
        local signText = TextWidget:new{ text = "—— " .. sign_dt, face = Font:getFace("cfont", 16) }
        signText.not_focusable = true
        local avail_w = dialog.width - 2 * (Size.border.window + Size.padding.default) - 2 * Size.padding.default
        local spacer = HorizontalSpan:new{ width = math.max(0, avail_w - signText:getWidth()) }
        parts[#parts + 1] = VerticalSpan:new{ width = Size.padding.small }
        parts[#parts + 1] = HorizontalGroup:new{ align = "left", spacer, signText }
    end
    local contentVG = VerticalGroup:new{ align = "left", unpack(parts) }
    contentVG.not_focusable = true
    dialog:addWidget(contentVG)

    self._travel_dlg = dialog
    UIManager:show(dialog)
end

function FocusFeedback:_reopenTravel(e, page)
    if self._travel_dlg then UIManager:close(self._travel_dlg) end
    self._travel_dlg = nil
    self:_showTravelLogDialog(e, page)
end

-- 在线阅读时也随机补记录动态（30~90分钟一条，写给当前翻开的书）
function FocusFeedback:_travelInlineCheck()
    if self:_readEventToggles().inbox == false then return end
    if self.suspended or not self.last_page_turn_wall then return end
    local now = os.time()
    if (now - self.last_page_turn_wall) > 180 then return end   -- 超过3分钟没在翻页/标注，视为不在读
    local c = self:_readCollection()
    local changed = false
    for _, e in ipairs(c) do
        if e.reveal_date then   -- 所有已养成（翻开的成年书）各自动态独立
            local next = e.travel_inline or (now + 3600)
            if now >= next then
                local letter = self:_genInboxLetter(e, 3600, now)
                if #letter.events > 0 then
                    local tlog = e.travel_log or {}
                    table.insert(tlog, {
                        ts = now,
                        text = letter.events[1].text,
                        mood = letter.events[1].mood or 0,
                        pts = letter.events[1].pts or 0,
                        item = letter.events[1].item,
                    })
                    e.travel_log = tlog
                    e.travel_inline = now + math.random(2400, 5400)  -- 40~90分钟后再记录一条
                    changed = true
                    if self:_travelCleanup(e, 1) then changed = true end
                end
            end
        end
    end
    if changed then self:_saveCollection(c) end
end

-- 展示一封来信（书信：按最高属性选用开头/结尾模板；底部落款日期可跨日；正文为时分+事件）
function FocusFeedback:_displayInbox(e, letter, gap, now)
    local times = self:_inboxRandomTimes(gap, #letter.events)  -- 复用随机时序，保证展示与数据一致
    local style = self:_inboxLetterStyle(e)
    local nickname = e.nickname or "它"
    local lines = {}

    -- 书信开头：称谓 + 开头语
    table.insert(lines, style.great:gsub("（昵称）", nickname))
    table.insert(lines, style.open:gsub("（昵称）", nickname))
    table.insert(lines, "")

    -- 正文：时分 + 事件
    for i, ev in ipairs(letter.events) do
        local time_str = os.date("%H:%M", now - gap + (times[i] or 0))
        local suffix = ""
        local applied = false
        if ev.mood ~= 0 then suffix = suffix .. (" 心情%+d%%"):format(ev.mood); applied = true end
        if ev.pts ~= 0 then suffix = suffix .. (" 积分%+d"):format(ev.pts); applied = true end
        if ev.item then suffix = suffix .. " 道具+" .. ev.item; applied = true end
        if INBOX_TEST_MODE and applied then
            suffix = suffix .. "【测试·不生效】"
        end
        table.insert(lines, time_str .. "  " .. ev.text .. suffix)
    end

    -- 书信结尾：结尾语
    table.insert(lines, "")
    table.insert(lines, style.close:gsub("（昵称）", nickname))
    table.insert(lines, "")

    -- 落款（昵称 + 真实日期，跨日显示区间）
    local start_dt = os.date("%Y.%m.%d", now - gap)
    local end_dt = os.date("%Y.%m.%d", now)
    local stamp = start_dt
    if start_dt ~= end_dt then stamp = stamp .. "-" .. end_dt end
    table.insert(lines, "落款 · " .. nickname)
    table.insert(lines, "        " .. stamp)
    self:_showMessage(table.concat(lines, "\n"), 0)
end

return FocusFeedback
