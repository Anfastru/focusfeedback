-- 专注计时（番茄钟）模块
-- 全屏专注页：正计时 / 倒计时 / 北京时间三模式 + 横竖屏自适应 + 低功耗看板档
-- 在读书籍库（自输入书名 + 书籍类型）+ 选书 / 结算 / 标记读完并评分流
-- 时长去向：全局专注总时长 + 全体成年书好感度；绑定书名再塑该在读书籍属性。

local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local logger = require("logger")
local Font = require("ui/font")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/container/overlapgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalContainer = require("ui/widget/container/horizontalcontainer")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local GestureRange = require("ui/gesturerange")

-- ========== 常量 ==========
local SETTING = "ff_focus_store"   -- 独立命名空间，避免与主插件状态冲突

local CATS = {"文学", "类型小说", "历史", "哲学", "社会科学", "自然科学", "实用技术", "艺术"}
local CAT_ATTR = {
    ["文学"]     = "情感",
    ["类型小说"] = "阅历",
    ["历史"]     = "辩证",
    ["哲学"]     = "逻辑",
    ["社会科学"] = "知识",
    ["自然科学"] = "辩证",
    ["实用技术"] = "知识",
    ["艺术"]     = "审美",
}
-- 三条零和对轴：审美↔知识、情感↔逻辑、阅历↔辩证
local OPP = {
    ["审美"]="知识", ["知识"]="审美", ["情感"]="逻辑", ["逻辑"]="情感",
    ["阅历"]="辩证", ["辩证"]="阅历",
}
local ATTRS6 = {"知识", "审美", "情感", "阅历", "逻辑", "辩证"}
local AXIS_CAP = 100
local GAIN_PER_H = 0.5      -- 专注1h 该书对应属性 +0.5%（与主插件阅读成长一致）

local MODE_LABELS = { count = "正计时", down = "倒计时", clock = "北京时间" }
local BULK_TEXTS = {
    "阅读，是与一位智者的深夜长谈。",
    "每一页翻过，都是成长的一小步。",
    "专注，是把散落的星光聚成一片星河。",
    "此刻的沉浸，正在塑造明天的你。",
    "好书如良师，静默却有力。",
    "坚持，是最安静也最有力量的温柔。",
}

-- ========== 存储层 ==========

local store = {}

function store.read()
    local s = G_reader_settings:readSetting(SETTING)
    if type(s) ~= "table" then
        s = { today_key = "", today_sec = 0, total_sec = 0, books = {}, sessions = {} }
    end
    if type(s.books) ~= "table" then s.books = {} end
    if type(s.sessions) ~= "table" then s.sessions = {} end
    local tk = os.date("%Y-%m-%d", os.time())
    if s.today_key ~= tk then
        s.today_key = tk
        s.today_sec = s.today_sec or 0
        s.today_sec = 0
    end
    s.total_sec = s.total_sec or 0
    return s
end

function store.save(s)
    G_reader_settings:saveSetting(SETTING, s)
end

function store.books(s)
    return type(s.books) == "table" and s.books or {}
end

function store.newBook(name, cat)
    return {
        id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999)),
        name = name,
        category = cat,
        total_sec = 0,
        attrs = {知识 = 0, 审美 = 0, 情感 = 0, 阅历 = 0, 逻辑 = 0, 辩证 = 0},
        status = "reading",   -- reading | finished
        rating = nil,
        created = os.time(),
    }
end

function store.find(s, id)
    if not id then return nil end
    for _, b in ipairs(store.books(s)) do
        if b.id == id then return b end
    end
    return nil
end

function store.addMinutes(s, id, sec)
    -- 全局：专注总时长 + 今日
    s.total_sec = (s.total_sec or 0) + sec
    s.today_sec = (s.today_sec or 0) + sec
    -- 全局：今日累计阅读（主插件展示）
    if s.ff then
        pcall(function()
            local ok, first, today, notified = pcall(function()
                return s.ff:_readToday()
            end)
            if ok and today then
                local nd, nf = today + sec, notified
                pcall(function() s.ff:_saveToday(nd, nf) end)
            end
        end)
    end
    -- 好感度：全体成年书，专注满 1h +1
    if s.ff then
        local hours = math.floor((sec or 0) / 3600)
        if hours > 0 then
            pcall(function() s.ff:_favorAll(hours) end)
        end
    end
    -- 绑定书：累计该在读书籍时长 + 塑造其属性
    if id then
        local b = store.find(s, id)
        if b then
            b.total_sec = (b.total_sec or 0) + sec
            local cat = b.category
            local attr = CAT_ATTR[cat]
            if attr then
                local gain = (sec / 3600) * GAIN_PER_H
                b.attrs = growAttrs(b.attrs, attr, gain)
            end
        end
    end
end

function growAttrs(cur, attr, gain)
    if type(cur) ~= "table" then cur = {} end
    for _, k in ipairs(ATTRS6) do
        if not cur[k] then cur[k] = 0 end
    end
    if not attr or gain <= 0 then return cur end
    local opp = OPP[attr]
    if not opp then
        cur[attr] = math.min(100, math.max(0, (cur[attr] or 0) + gain))
        return cur
    end
    local ca, co = cur[attr] or 0, cur[opp] or 0
    if ca >= AXIS_CAP then return cur end
    local added = math.min(gain, AXIS_CAP - ca)
    local nc = ca + added
    local sum = nc + co
    local over = sum - AXIS_CAP
    if over > 0 then
        if co >= over then
            co = co - over
        else
            local back = over - co
            nc = nc - back
            co = 0
        end
    end
    cur[attr], cur[opp] = nc, co
    return cur
end

-- ========== 显示工具 ==========

local function fmtSec(sec)
    sec = math.floor(math.max(0, sec or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

local function bjClockStr()
    -- 北京时间 GTM+8
    local t = os.time() + 8 * 3600
    return os.date("%H:%M:%S", t), os.date("%Y-%m-%d", t)
end

-- ========== 专注页 ==========

local FocusPage = InputContainer:extend{
    ff = nil,
    mode = "count",          -- count | down | clock
    down_target = 25 * 60,   -- 倒计时默认 25 分钟
    stage = "focus",         -- focus | booksel | newbook | shelf | settle
    running = false,
    session_start = 0,       -- 本段开始墙钟（os.time）
    session_sec = 0,         -- 本段已累计秒（结算依据）
    bound_id = nil,          -- 绑定在读书籍 id；nil=跳过
    skip_session = false,    -- true：本段明确跳过选书
    lowpower = false,
    quote = "",
    quote_wall = 0,
    _timerid = nil,
    _last_disp = nil,
    w = 0, h = 0,
    not_focusable = true,
}

function FocusPage:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.w, self.h = W, H
    self.dimen = Geom:new{ w = W, h = H }
    self.s = store.read()
    self.s.ff = self.ff
    self.quote = self:_pickQuote()
    self.quote_wall = os.time()
    self.ges_events = {
        Tap = {
            GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = W, h = H } }
        },
    }
    self:_rebuild()
end

function FocusPage:getSize()
    return self.dimen
end

function FocusPage:onResize()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.w, self.h = W, H
    self.dimen = Geom:new{ w = W, h = H }
    self:_rebuild()
    return true
end

function FocusPage:onShow()
    self._running = true
    self:_schedule()
    UIManager:setDirty(self, "full")
    return true
end

function FocusPage:onCloseWidget()
    self._running = false
    if self._timerid then
        UIManager:unschedule(self._timerid)
        self._timerid = nil
    end
    return true
end

function FocusPage:_schedule()
    if not self._running then return end
    if self._timerid then
        UIManager:unschedule(self._timerid)
        self._timerid = nil
    end
    -- 低功耗档：整分钟 + 心跳；正常档：每秒
    local interval = self.lowpower and 15 or 1
    local fn = function()
        self._timerid = nil
        if not self._running then return end
        local disp = self:_tick()
        if self.stage == "focus" then
            if disp and disp ~= self._last_disp then
                self._last_disp = disp
                self:_refreshTimer()
            end
        end
        self:_schedule()
    end
    self._timerid = UIManager:scheduleIn(interval, fn)
end

-- 返回当前应显示的计时字符串
function FocusPage:_tick()
    local now = os.time()
    -- 3 分钟刷一句
    if (now - self.quote_wall) >= 180 then
        self.quote_wall = now
        local q = self:_pickQuote()
        if q ~= self.quote then
            self.quote = q
            if self.stage == "focus" then self:_refreshQuote() end
        end
    end
    if self.mode == "clock" then
        return bjClockStr()
    end
    if not self.running then
        return fmtSec(0)
    end
    local el = now - self.session_start
    if self.mode == "down" then
        local left = self.down_target - el
        if left <= 0 then
            -- 倒计时结束：自动结算
            self.session_sec = self.down_target
            self:_finishSession()
            return fmtSec(0)
        end
        return fmtSec(left)
    end
    -- count
    return fmtSec(self.session_sec + el)
end

function FocusPage:_pickQuote()
    local ff = self.ff
    local pool = {}
    if ff and ff.quotes_normal and type(ff.quotes_normal) == "table" then
        for _, q in ipairs(ff.quotes_normal) do pool[#pool + 1] = q end
    end
    if ff and ff.quotes_rare and type(ff.quotes_rare) == "table" then
        for _, q in ipairs(ff.quotes_rare) do pool[#pool + 1] = q end
    end
    if #pool == 0 then
        for _, q in ipairs(BULK_TEXTS) do pool[#pool + 1] = q end
    end
    if #pool == 0 then return "专注中……" end
    return pool[math.random(1, #pool)]
end

-- ========== 构建与渲染 ==========

function FocusPage:_mkTimer(txt)
    local size = math.max(48, math.floor(math.min(self.w, self.h) * 0.16))
    local face = Font:getFace("tfont", size)
    local tw = TextWidget:new{ text = txt, face = face, fgcolor = Blitbuffer.COLOR_BLACK, bold = true }
    return CenterContainer:new{ dimen = Geom:new{ w = self.w, h = size + Size.padding.default * 2 }, child = tw }
end

function FocusPage:_mkMid()
    local W, H, pad = self.w, self.h, Size.padding.default
    local imgW = math.max(90, math.floor(W * 0.16))
    local imgH = math.max(120, math.floor(H * 0.28))
    local cover = self:_mkCover(imgW, imgH)
    local gap = 0
    local dialogW = W - imgW - pad * 3
    if dialogW < 140 then dialogW = 140 end
    local dbox = FrameContainer:new{
        dimen = Geom:new{ w = dialogW, h = imgH },
        bordersize = 1,
        padding = pad,
    }
    dbox:addWidget(TextBoxWidget:new{
        text = self.quote,
        width = dialogW - pad * 2,
        height = imgH - pad * 2,
        face = Font:getFace("ffont", 20),
    })
    local row = HorizontalContainer:new{ dimen = Geom:new{ w = W, h = imgH } }
    row:addWidget(dbox)
    -- 封面靠右：用一个右对齐填充
    local fill = HorizontalContainer:new{
        dimen = Geom:new{ w = W - dialogW - pad, h = imgH },
    }
    fill:addWidget(cover)
    row:addWidget(fill)
    return row
end

function FocusPage:_mkCover(w, h)
    local dir = self.ff and self.ff.plugin_dir or ""
    local path
    local p1 = dir .. "book_img_cropped.jpg"
    local f = io.open(p1, "rb")
    if f then path = p1; f:close()
    else
        local p2 = dir .. "book_img.jpg"
        f = io.open(p2, "rb")
        if f then path = p2; f:close() end
    end
    if not path then
        return FrameContainer:new{
            dimen = Geom:new{ w = w, h = h }, bordersize = 1,
            padding = Size.padding.default,
        }
    end
    local ok, img = pcall(function()
        return ImageWidget:new{ file = path, width = w, height = h }
    end)
    if ok and img then return img end
    return FrameContainer:new{ dimen = Geom:new{ w = w, h = h }, bordersize = 1 }
end

function FocusPage:_mkBottom()
    local W, H, pad = self.w, self.h, Size.padding.default
    -- 目标 chip
    local boundName = "未绑定（跳过）"
    if self.bound_id then
        local b = store.find(self.s, self.bound_id)
        if b then boundName = "《" .. (b.name or "?") .. "》" .. " · " .. (b.category or "") end
    end
    local chip = FrameContainer:new{
        dimen = Geom:new{ w = W - pad * 2, h = Size.item.height_default * 0.8 },
        bordersize = 1, padding = pad * 0.7,
    }
    chip:addWidget(TextBoxWidget:new{
        text = self.running and ("专注中 · 目标：" .. boundName) or ("目标：" .. boundName),
        width = W - pad * 4,
        height = Size.item.height_default * 0.7,
        face = Font:getFace("cfont", 18),
    })
    -- 按钮排
    local b1 = self.running and "结束并结算" or "开始专注"
    local btnRow = HorizontalGroup:new{ padding = pad }
    local bw = math.floor((W - pad * 5) / 4)
    local btm = Size.item.height_default
    local zoneBaseY = 0

    local selfBtn = self:_mkBtn(b1)
    local shelfBtn = self:_mkBtn("在读书籍")
    local lowBtn = self:_mkBtn(self.lowpower and "低功耗：开" or "低功耗：关")
    local exitBtn = self:_mkBtn("退出")
    btnRow:addWidget(selfBtn.outer)
    btnRow:addWidget(shelfBtn.outer)
    btnRow:addWidget(lowBtn.outer)
    btnRow:addWidget(exitBtn.outer)

    local bottom = VerticalGroup:new{ padding = pad }
    bottom:addWidget(chip)
    bottom:addWidget(btnRow)
    return bottom
end

function FocusPage:_mkBtn(text)
    local out = HorizontalContainer:new{}
    -- 简化：用带边框的容器承载文本（点击命中由 _hit 统一处理）
    local w = math.max(60, math.floor((self.w - Size.padding.default * 5) / 4))
    local h = Size.item.height_default
    local f = FrameContainer:new{
        dimen = Geom:new{ w = w, h = h },
        bordersize = 1,
        padding = Size.padding.default * 0.6,
    }
    f:addWidget(TextWidget:new{ text = text })
    out:addWidget(f)
    return { outer = out }
end

function FocusPage:_refreshQuote()
    UIManager:setDirty(self, "partial")
end

-- 命中处理（依赖模式/阶段）
function FocusPage:onTap(ges)
    local p = ges.pos
    if not p then return true end
    local x, y = p.x, p.y
    self:_hit(x, y)
    return true
end

function FocusPage:_setMode(m)
    if m == "down" then
        self.mode = "down"
        self:_editDownTarget()
        return
    end
    if self.mode ~= m then
        self.mode = m
        self._last_disp = nil
        self:_rebuild()
        UIManager:setDirty(self, "full")
    end
end

function FocusPage:_editDownTarget()
    local cur = math.floor(self.down_target / 60)
    local dialog = InputDialog:new{
        title = "倒计时时长（分钟）",
        input = tostring(cur),
        description = "专注结束后将自动结算",
        buttons = {
            {
                { text = "取消", callback = function() if dialog then UIManager:close(dialog) end end },
                { text = "确定",
                  is_enter_default = true,
                  callback = function()
                    local t = tonumber(dialog:getInputText())
                    if t and t > 0 then
                        self.down_target = t * 60
                    end
                    UIManager:close(dialog)
                    if not self.running then
                        self._last_disp = nil
                        self:_rebuild()
                        UIManager:setDirty(self, "full")
                    end
                  end },
            },
        },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function FocusPage:_onExit()
    UIManager:close(self)
end

function FocusPage:_toggleLow()
    self.lowpower = not self.lowpower
    self:_schedule()
    self:_rebuild()
    UIManager:setDirty(self, "full")
end

function FocusPage:_onPrimary()
    if self.running then
        self:_finishSession()
    else
        -- 开始：先选书（或跳过）
        self:_goBooksel()
    end
end

function FocusPage:_onShelf()
    self.stage = "shelf"
    self:_rebuildShelf()
end

-- 选书阶段
function FocusPage:_goBooksel()
    self.stage = "booksel"
    self:_rebuildBooksel()
end

function FocusPage:_rebuildBooksel()
    self._last_disp = nil
    local W, H, pad = self.w, self.h, Size.padding.default
    self.stage = "booksel"
    self:_frameStage()
end

function FocusPage:_rebuildShelf()
    self._last_disp = nil
    self.stage = "shelf"
    self:_frameStage()
end

function FocusPage:_frameStage()
    local W, H, pad = self.w, self.h, Size.padding.default
    local ov = OverlapGroup:new{ dimen = Geom:new{ w = W, h = H } }

    -- 上部内容（顶部对齐）
    local list, hits = self:_stageContentPad(W, H)
    self._stage_hits = hits
    local cont = FrameContainer:new{
        dimen = Geom:new{ w = W, h = H }, bordersize = 0, padding = pad, position = "north",
    }
    cont:addWidget(list)
    ov:addWidget(cont)

    -- 底部按钮（底部对齐）
    local btnH = math.ceil(Size.item.height_default * 1.1)
    local labels
    if self.stage == "booksel" then
        labels = { { t = "自输入新书", fn = self._onNewBook }, { t = "跳过", fn = self._onSkip }, { t = "取消", fn = self._backToFocus } }
    else
        labels = { { t = "回到专注", fn = self._backToFocus }, { t = "开始专注", fn = self._onPrimary } }
    end
    local row = HorizontalContainer:new{ dimen = Geom:new{ w = W, h = btnH }, padding = pad }
    local bw = math.floor((W - pad * (#labels + 1)) / #labels)
    for _, it in ipairs(labels) do
        local f = FrameContainer:new{ dimen = Geom:new{ w = bw, h = btnH - pad }, bordersize = 1, padding = pad * 0.5 }
        f:addWidget(TextWidget:new{ text = it.t })
        row:addWidget(f)
    end
    local bwrap = CenterContainer:new{ dimen = Geom:new{ w = W, h = btnH }, position = "south" }
    bwrap:addWidget(row)
    ov:addWidget(bwrap)

    self._root = ov
    self._stage_topY = pad
    self._stage_btnY = H - btnH
    self._stage_btnCount = #labels
    UIManager:setDirty(self, "full")
end

function FocusPage:_stageContentPad(W, H)
    local pad = Size.padding.default
    local titleH = math.ceil(Size.item.height_default * 1.3)
    local title = (self.stage == "booksel") and "选择专注目标" or "在读书籍"
    local itH = Size.item.height_default
    local vg = VerticalGroup:new{ padding = 0 }
    vg:addWidget(CenterContainer:new{
        dimen = Geom:new{ w = W, h = titleH },
        child = TextWidget:new{ text = title, bold = true },
    })
    local hits, y = {}, titleH
    if self.stage == "booksel" then
        local books = store.books(self.s)
        local reading = 0
        for _, b in ipairs(books) do
            if b.status == "reading" then reading = reading + 1 end
        end
        if reading == 0 then
            vg:addWidget(CenterContainer:new{ dimen = Geom:new{ w = W, h = 90 }, child = TextWidget:new{ text = "暂无在读书籍，可自输入一本" } })
        else
            for _, b in ipairs(books) do
                if b.status == "reading" then
                    local item = FrameContainer:new{ dimen = Geom:new{ w = W, h = itH }, bordersize = 1, padding = pad * 0.8 }
                    item:addWidget(TextBoxWidget:new{
                        text = "《" .. (b.name or "?") .. "》 " .. (b.category or "") .. "  · 累计 " .. fmtSec(b.total_sec or 0) .. "　[点击选这本]",
                        width = W - pad * 2, height = itH, face = Font:getFace("cfont", 18),
                    })
                    vg:addWidget(item)
                    hits[#hits + 1] = { y = y, h = itH, id = b.id }
                    y = y + itH
                end
            end
        end
    else
        local books = store.books(self.s)
        if #books == 0 then
            vg:addWidget(CenterContainer:new{ dimen = Geom:new{ w = W, h = 90 }, child = TextWidget:new{ text = "还没有在读书籍" } })
        else
            for _, b in ipairs(books) do
                local st = (b.status == "reading") and "在读" or "已读完"
                local rat = b.rating and (" ★" .. b.rating) or ""
                local item = FrameContainer:new{ dimen = Geom:new{ w = W, h = itH }, bordersize = 1, padding = pad * 0.8 }
                item:addWidget(TextBoxWidget:new{
                    text = ("《%s》 %s · %s%s · 累计 %s"):format(b.name or "?", b.category or "", st, rat, fmtSec(b.total_sec or 0)),
                    width = W - pad * 2, height = itH, face = Font:getFace("cfont", 18),
                })
                vg:addWidget(item)
                y = y + itH
            end
        end
    end
    return vg, hits
end

function FocusPage:_frameStageHit(x, y)
    -- 底部按钮区
    if self._stage_btnY and y >= self._stage_btnY then
        if self.stage == "booksel" then
            local col = math.floor(x / (self.w / 3))
            if col == 0 then self:_onNewBook()
            elseif col == 1 then self:_onSkip()
            else self:_backToFocus() end
        else
            if x < self.w / 2 then self:_backToFocus()
            else self:_onPrimary() end
        end
        return
    end
    -- 在读书籍点选该本
    if self.stage == "booksel" and self._stage_hits then
        local top = self._stage_topY
        for _, hit in ipairs(self._stage_hits) do
            local hy = top + hit.y
            if y >= hy and y <= hy + hit.h then
                self:_selectBook(hit.id)
                return
            end
        end
    end
end

function FocusPage:_backToFocus()
    self.stage = "focus"
    self:_rebuild()
    UIManager:setDirty(self, "full")
end

function FocusPage:_onSkip()
    self.skip_session = true
    self.bound_id = nil
    self:_startTiming()
end

function FocusPage:_onNewBook()
    self:_promptNewBook()
end

function FocusPage:_promptNewBook()
    local dialog = InputDialog:new{
        title = "自输入书名",
        input = "",
        description = "输入书名（不可为空）",
        buttons = {
            {
                { text = "取消", callback = function() if dialog then UIManager:close(dialog) end end },
                { text = "下一步：选类型",
                  is_enter_default = true,
                  callback = function()
                    local name = dialog:getInputText()
                    if name and name:match("%S") then
                        UIManager:close(dialog)
                        self:_pickCategory(name)
                    end
                  end },
            },
        },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function FocusPage:_pickCategory(name)
    local buttons, row = {}, {}
    for i, cat in ipairs(CATS) do
        table.insert(row, {
            text = cat,
            callback = function()
                local b = store.newBook(name, cat)
                table.insert(self.s.books, b)
                store.save(self.s)
                self.bound_id = b.id
                self.skip_session = false
                UIManager:close(cdialog)
                self:_startTiming()
            end,
        })
        if #row == 2 then table.insert(buttons, row); row = {} end
    end
    if #row > 0 then table.insert(buttons, row) end
    local cdialog = ButtonDialog:new{
        title = ("为《%s》选择书籍类型"):format(name),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(cdialog)
end

function FocusPage:_selectBook(id)
    self.bound_id = id
    self.skip_session = false
    self:_startTiming()
end

function FocusPage:_startTiming()
    self.running = true
    self.session_start = os.time()
    self.session_sec = 0
    self.stage = "focus"
    self._last_disp = nil
    -- 防休眠（看板长时间亮屏）
    if Device:hasSoftwareLights() then end
    if Device.screen and Device.screen.suspend then end
    self:_rebuild()
    UIManager:setDirty(self, "full")
end

function FocusPage:_finishSession()
    if not self.running then return end
    local now = os.time()
    local dur = self.session_sec + (now - self.session_start)
    self.running = false
    if not self.bound_id then self.bound_id = nil end
    -- 落账
    store.addMinutes(self.s, self.bound_id, dur)
    table.insert(self.s.sessions, { t = now, dur = dur, book = self.bound_id, skip = (not self.bound_id) })
    store.save(self.s)
    self._last_dur = dur
    if self.bound_id then
        self:_promptSettle(dur)
    else
        self:_msgTo("跳过的一段已计入专注总时长与全体好感度。")
        self:_resetSessionView()
    end
end

function FocusPage:_promptSettle(dur)
    local b = store.find(self.s, self.bound_id)
    local bt
    local buttons = {}
    local name = b and b.name or "本书"
    bt = ButtonDialog:new{
        title = ("本次专注 %s\n《%s》已累计时长并塑造属性。").format(fmtSec(dur), name),
        buttons = {
            { { text = "标记读完并评分",
                callback = function()
                    UIManager:close(bt)
                    self:_rateBook(self.bound_id)
                end } },
            { { text = "取消", callback = function()
                UIManager:close(bt)
                self:_resetSessionView()
            end } },
        },
    }
    UIManager:show(bt)
end

function FocusPage:_rateBook(id)
    local b = store.find(self.s, id)
    if not b then self:_resetSessionView() return end
    local bt
    bt = ButtonDialog:new{
        title = ("为《%s》评分（完成后将移出在读书籍）"):format(b.name or "?"),
        buttons = {
            { { text = "1★", callback = function() UIManager:close(bt); self:_applyFinish(id, 1) end },
              { text = "2★", callback = function() UIManager:close(bt); self:_applyFinish(id, 2) end },
              { text = "3★", callback = function() UIManager:close(bt); self:_applyFinish(id, 3) end },
              { text = "4★", callback = function() UIManager:close(bt); self:_applyFinish(id, 4) end },
              { text = "5★", callback = function() UIManager:close(bt); self:_applyFinish(id, 5) end } },
            { { text = "取消", callback = function() UIManager:close(bt); self:_resetSessionView() end } },
        },
    }
    UIManager:show(bt)
end

function FocusPage:_applyFinish(id, rating)
    local b = store.find(self.s, id)
    if b then
        b.status = "finished"
        b.rating = rating
        store.save(self.s)
    end
    self:_msgTo("《" .. (b and b.name or "?") .. "》已读完并评分，移出在读书籍。")
    self.bound_id = nil
    self:_resetSessionView()
end

function FocusPage:_msgTo(txt)
    if self.ff and self.ff._showMessage then
        pcall(function() self.ff:_showMessage(txt, 3) end)
    end
end

function FocusPage:_resetSessionView()
    self._last_disp = nil
    self.stage = "focus"
    self.bound_id = nil
    self.skip_session = false
    self._rebuild()
    UIManager:setDirty(self, "full")
end

function FocusPage:_rebuild()
    self._root = nil
    if self.stage == "booksel" or self.stage == "shelf" then
        self:_frameStage()
        return
    end
    self:_frameFocusReal()
end

function FocusPage:_frameFocusReal()
    local W, H, pad = self.w, self.h, Size.padding.default
    local vg = VerticalGroup:new{ align = "center", padding = pad }
    -- 顶部模式栏
    local modeRow = HorizontalContainer:new{ dimen = Geom:new{ w = W - pad * 2, h = Size.item.height_default }, padding = pad * 0.5 }
    local mw = math.floor((W - pad * 4) / 3)
    for i, m in ipairs({"count", "down", "clock"}) do
        local sel = (self.mode == m)
        local f = FrameContainer:new{
            dimen = Geom:new{ w = mw, h = Size.item.height_default }, bordersize = sel and 2 or 1, padding = pad * 0.5,
        }
        f:addWidget(TextWidget:new{ text = MODE_LABELS[m], bold = sel })
        modeRow:addWidget(f)
    end
    vg:addWidget(modeRow)

    -- 大计时
    local disp = (self.mode == "clock") and bjClockStr() or fmtSec(self.session_sec)
    self._last_disp = disp
    vg:addWidget(self:_mkTimer(disp))

    -- 中：对话 + 封面
    vg:addWidget(self:_mkMid())

    -- 底：目标 + 按钮
    vg:addWidget(self:_mkBottom())

    local box = FrameContainer:new{ dimen = Geom:new{ w = W, h = H }, bordersize = 0, padding = pad }
    box:addWidget(CenterContainer:new{ dimen = Geom:new{ w = W, h = H }, child = vg })
    self._root = box
end

function FocusPage:_refreshTimer()
    self.vg = nil
    self.stage = "focus"
    self:_frameFocusReal()
    if self._root then UIManager:setDirty(self, self.lowpower and "full" or "partial") end
end

function FocusPage:_hit(x, y)
    if self.stage == "booksel" or self.stage == "shelf" then
        self:_frameStageHit(x, y)
        return
    end
    -- 模式区
    local trigY = Size.item.height_default + Size.padding.default
    if y <= trigY then
        if x < self.w / 3 then self:_setMode("count")
        elseif x < self.w * 2 / 3 then self:_setMode("down")
        else self:_setMode("clock") end
        return
    end
    -- 底部按钮
    local btnH = Size.item.height_default + Size.padding.default
    if y >= self.h - btnH then
        local bw = math.floor((self.w - Size.padding.default * 5) / 4)
        local col = math.floor(x / bw)
        if col == 0 then self:_onPrimary()
        elseif col == 1 then self:_onShelf()
        elseif col == 2 then self:_toggleLow()
        else self:_onExit() end
        return
    end
end

local FocusTimer = {
    FocusPage = FocusPage,
    store = store,
    open = function(ff)
        local page = FocusPage:new{ ff = ff }
        UIManager:show(page)
    end,
}

return FocusTimer