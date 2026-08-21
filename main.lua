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
        t = {bookmark=true, stranger=true, book_friend=true, babel=true, fly_away=true, special=true}
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

-- 里程碑时获得积分（替换原 _awardFood）
function FocusFeedback:_awardPoints(minute)
    if not self:_readAdopted() then return end
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
    -- V7: 小猫在身边时，40%概率积分入账+1
    local pet = self:_readPet()
    if pet.cat and math.random() < 0.4 then
        points = points + 1
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
    local mood = self:_readMood()
    local now = os.time()
    local last_update = self:_readLastMoodUpdate()

    if last_update and last_update > 0 then
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
    self:_saveSleepState({type = nil, reading_at_start = 0,
        deep_date = sleep.deep_date, nap_date = sleep.nap_date})

    -- V8: 今日咖啡唤醒计数（每日任务 n7/s6 判定）
    local stat = self:_getDailyStat()
    stat.coffee = (stat.coffee or 0) + 1
    stat.wake_coffee = (stat.wake_coffee or 0) + 1
    self:_saveDailyStat(stat)

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

    self._pending_dialogue = "凡事发生皆利于我！"
    if callback then callback() end
end

-- ========== V4 商超界面 ==========

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

    -- V6: 商超物品数据（2×4 布局，上排基础物品，下排新增）
    local shop_items = {
        {key = "cotton", name = "棉花糖", price = PRICE_COTTON, icon = "shop_cotton.jpg"},
        {key = "biscuit", name = "饼干", price = PRICE_BISCUIT, icon = "shop_biscuit.jpg"},
        {key = "wastebasket", name = "废纸篓", price = PRICE_WASTEBASKET, icon = "shop_wastebasket.jpg"},
        {key = "toy", name = "逗书棒", price = PRICE_TOY, icon = "shop_toy.jpg"},
        {key = "coffee", name = "咖啡", price = PRICE_COFFEE, icon = "shop_coffee.jpg"},
        {key = "clover", name = "四叶草", price = PRICE_CLOVER, icon = "shop_clover.jpg"},
        {key = "cat", name = "小猫", price = PRICE_CAT, icon = "shop_cat.jpg", pet = "cat", pet_dialogue = "我终于不是野书了，我被小猫收养了＞＜！"},
        {key = "rabbit", name = "小兔", price = PRICE_RABBIT, icon = "shop_rabbit.jpg", pet = "rabbit", pet_dialogue = "呕兔就像喝水一样简单！"},
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
            {text = "棉花糖 2", callback = function() buyItem(shop_items[1]) end},
            {text = "饼干 3", callback = function() buyItem(shop_items[2]) end},
            {text = "废纸篓 3", callback = function() buyItem(shop_items[3]) end},
            {text = "逗书棒 5", callback = function() buyItem(shop_items[4]) end},
        },
        {
            {text = "咖啡 8", callback = function() buyItem(shop_items[5]) end},
            {text = "四叶草 10", callback = function() buyItem(shop_items[6]) end},
            {text = "小猫 50", callback = function() buyItem(shop_items[7]) end},
            {text = "小兔 35", callback = function() buyItem(shop_items[8]) end},
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
            if is_test then
                table.insert(items, {
                    key = key,
                    text = name,
                    mandatory = string.format("×%d", count),
                    callback = function()
                        self:_useTestCard(key, name)
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
        if key == "wastebasket" or key == "toy" or key == "coffee" or key == "clover" then return 2 end
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
    if #normal == 0 then
        return "书在静静等待。"
    end
    return normal[math.random(1, #normal)]
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

    -- 3. 昵称
    local nick_w = TextWidget:new{
        text = nickname,
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
    local idx = self:_readBookIndex()
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
    })
    self:_saveCollection(collection)

    -- 设置翻开状态
    self.reveal_book = book
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
            text = string.format("《%s》 %s", book.title, book.author),
            mandatory = entry.reveal_date,
            callback = function()
                self:_showBookDetail(entry)
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
                -- 累计领养期间的阅读时长
                if self:_readAdopted() then
                    self:_saveAdoptReadingSeconds(self:_readAdoptReadingSeconds() + diff)
                    -- V8: 长期任务「累计阅读」全局累计（跨书不受弃养/重领养影响）
                    local lstat = self:_readLongStat()
                    lstat.read_seconds = (lstat.read_seconds or 0) + diff
                    self:_saveLongStat(lstat)
                    -- V4: 阅读增加心情值 0.4%/分钟
                    local mood = self:_readMood()
                    mood = math.min(100, mood + (diff / 60) * MOOD_PER_READ_MIN)
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
        stat.session_cur = 0
        self:_saveDailyStat(stat)
    end

    self.last_event_wall = now
end

function FocusFeedback:_tick()
    self:_onActivity(os.time())
    -- V5: 随机事件检查
    pcall(function() self:_checkRandomEvents() end)
    -- V8: 轮询标注数量（某些阅读器后端不触发 onAnnotationsUpdated）
    pcall(function() self:_checkAnnotationCount() end)
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
            local start_mood = self:_readMood()
            -- V6: 小兔在身边时，心情值掉落速度×0.5
            local decay = MOOD_DECAY_SUSPEND
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
        self:_saveSuspendTs(0)
        -- 更新心情时间戳，防止 _updateMood 重复计算休眠期间的衰减
        self:_saveLastMoodUpdate(os.time())
    end
    -- V9: 唤醒后需翻页才恢复计时，避免休眠后短暂操作被计入阅读
    self.last_page_turn_wall = nil
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

    local stranger = pool[math.random(1, #pool)]
    local nickname = self:_readNickname()

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
            local mood = self:_readMood()
            self:_saveMood(mood - 10)
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
                local mood = self:_readMood()
                self:_saveMood(math.max(MOOD_MIN, mood - 20))
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
            if clover and evt.key == "robber" then
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

    for _, evt in ipairs(tick_events) do
        if evt.enabled then
            -- V6: 四叶草生效期间，书飞走不触发（跳过负面事件）
            if clover and evt.key == "fly_away" then
                -- 跳过
            else
                local chance = evt.chance
                -- V6: 四叶草生效期间，正面事件概率×2
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
                text = "清零今日统计",
                callback = function(menu)
                    self:_resetToday(menu)
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
                text = "图鉴",
                callback = function()
                    self:_showCollection()
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
                },
            },
        },
    }
end

-- ========== V9 在线更新系统 ==========

-- 获取插件目录路径
function FocusFeedback:_getPluginDir()
    local source = debug.getinfo(1, "S").source
    local path = source:gsub("^@", "")
    local dir = path:match("^(.*[/\\])")
    return dir or "./"
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
    local meta = require("plugins/focus_feedback.koplugin/_meta")
    if meta and meta.version then
        return tonumber(meta.version) or 0
    end
    return 0
end

-- V10: HTTP GET 请求（pcall防崩溃 + 超时设置 + 自动重试）
function FocusFeedback:_httpGet(url, timeout_sec)
    timeout_sec = timeout_sec or 15
    local max_retries = 3  -- 共尝试 3 次，解决 Kindle 网络不稳定导致的偶发超时
    local last_err = "未知错误"

    for attempt = 1, max_retries do
        -- 全程 pcall 包裹，任何异常都不会导致闪退
        local ok, ret_or_err = pcall(function()
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
            local body, err = ret_or_err
            if body then
                return body, nil
            end
            last_err = err or "未知错误"
        else
            last_err = tostring(ret_or_err)
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

-- 检查更新
function FocusFeedback:_checkUpdate()
    local base_url = self:_getUpdateSource()
    if not base_url or base_url == "" then
        self:_showMessage("未设置更新源。\n请在菜单中设置 GitHub 仓库地址。", 5)
        return
    end

    -- 去掉末尾斜杠
    base_url = base_url:gsub("/$", "")

    self:_showMessage("正在检查更新…", 2)

    -- 下载 version.json
    local version_url = base_url .. "/version.json"
    local body, err = self:_httpGet(version_url, 15)

    if not body then
        self:_showMessage(string.format("检查更新失败：\n%s\n\n请确认网络和更新源地址是否正确。", err or "未知错误"), 6)
        return
    end

    -- 解析 JSON（简单解析，不依赖外部库）
    local remote_version = tonumber(body:match('"version"%s*:%s*"?([0-9]+)"?'))
    if not remote_version then
        self:_showMessage("无法解析远端版本号。\n请确认 version.json 格式正确。", 5)
        return
    end

    local local_version = self:_getLocalVersion()
    if local_version == 0 then
        local_version = 9  -- 兜底
    end

    if remote_version <= local_version then
        self:_showMessage(string.format("当前已是最新版本 V%d。", local_version), 3)
        return
    end

    -- 发现新版本
    local dialog
    dialog = ButtonDialog:new{
        title = string.format("发现新版本 V%d！\n当前版本 V%d\n是否立即更新？", remote_version, local_version),
        title_align = "center",
        buttons = {
            {
                {
                    text = "稍后",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = "立即更新",
                    callback = function()
                        UIManager:close(dialog)
                        self:_doUpdate(base_url, remote_version)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

-- 执行更新
function FocusFeedback:_doUpdate(base_url, remote_version)
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

    for _, fname in ipairs(files) do
        local url = base_url .. "/" .. fname
        local body, err = self:_httpGet(url, 30)
        if body and #body > 0 then
            -- 写入本地文件
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
    end

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

-- 设置更新源
function FocusFeedback:_setUpdateSource()
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
end

return FocusFeedback
