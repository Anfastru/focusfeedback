--[[--
双书关系系统（V25）
A 为点击出门的主体书，B 为邀请同行/偶遇的对象书。昵称以 A/B 占位替换。
- 有向双边变量：AB(A对B)、BA(B对A) 独立，-5..+5，0 居中
- 隐藏点数→等级：层级越深所需点数越多（0→1 约3.5 … 4→5 约8）
- 出门邀请：基础10 → 邀同行+5 → 指定对象+5
- 随机修正：情感高更易得正展开；辩证高可"转负为正"；属性标签正delta微增
- 持久关系：双向+5持续10天→恋人/QPR →100天→soulmates；单向+5→追随者；双向-5→宿敌(低概率救赎恋人)
- 等级不排他、持久排他、多候选先到先得
- 出门事件写入双方旅行日志（不占普通事件频率）
]]

local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local Size = require("ui/size")
local Font = require("ui/font")
local VerticalGroup = require("ui/widget/verticalgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Menu = require("ui/widget/menu")
local Device = require("device")
local Screen = Device.screen
local logger = require("logger")

local SETTING_REL = "v25_relations"
local SETTING_PERS = "v25_persistent"
local SETTING_NOTICE = "v25_notice"

-- 与 main.lua 相同的设置前缀，供本模块读写持久化
local SETTINGS_PREFIX = "focus_feedback_"
local function settingKey(name)
    return SETTINGS_PREFIX .. name
end

local TH = { 0, 3.5, 4, 5, 6.5, 8 }        -- TH[k] = 相邻到 |等级|=k 所需点数
local CAP = 5
local DAY_SEC = 86400
local HOUR_SEC = 3600
local STABLE_DAY_FREE = 10
local STABLE_DAY_HELD = 20
local SOULMATE_DAY = 100
local HOUR_DELAY = 1        -- 等级提示延时小时数

local LEVEL_NAMES = {
    [0] = "完全不认识",
    [1] = "认识", [2] = "有点熟悉", [3] = "喜欢", [4] = "很喜欢", [5] = "超级喜欢",
    [-1] = "不舒服", [-2] = "不喜欢", [-3] = "有点讨厌", [-4] = "很讨厌", [-5] = "超级讨厌",
}
local PNAMES = { lover = "恋人", qpr = "QPR", crush = "追随者", rival = "宿敌", soulmate = "soulmates" }

local Pair = {}
Pair.config = { STABLE_DAY_FREE = STABLE_DAY_FREE, STABLE_DAY_HELD = STABLE_DAY_HELD, SOULMATE_DAY = SOULMATE_DAY }

-- ============ 事件数据 ============
-- chapters：{ text, attr=标签, AB, BA }。AB=A对B增减 / BA=B对A增减。
-- 语义：闯祸方记到"受害者对闯祸者"账上（A伤B→BA减）；送礼记为"收礼者对送礼者"增。
local EVENTS = {
  { id = "1_restaurant", name = "餐厅", chapters = {
      { text = "它们在烛光下进行了一次浪漫晚餐。", attr = "审美", AB = 2, BA = 2 },
      { text = "很遗憾，餐厅的味道并不让B喜欢。", AB = -1, BA = -1 },
      { text = "A打碎了盘子，碎片溅到了B身上。", AB = 0, BA = -2 },
      { text = "味道超级棒！！！", attr = "审美", AB = 2, BA = 2 },
      { text = "发现B吃东西乱七八糟的像未成年。", attr = "辩证", AB = -2, BA = 0 },
  } },
  { id = "2_museum", name = "博物馆", chapters = {
      { text = "它们各自发现了自己喜欢的恐龙类型。", attr = "知识", AB = 1, BA = 1 },
      { text = "它们计划偷走一个展品。", attr = "辩证", AB = 2, BA = 2 },
      { text = "B认真地观看了每一个展品，但A只是绕着一团鸵鸟化石走来走去。", AB = 0, BA = -1 },
  } },
  { id = "3_mall", name = "购物中心", chapters = {
      { text = "开启一场购物大比拼，付款时却发现两个人都余额不足……", AB = 1, BA = 1 },
      { text = "A给B买了一管荧光色剂作为礼物。", AB = 0, BA = 2 },
      { text = "B给A买了一团海藻作为礼物。", AB = 2, BA = 0 },
      { text = "A给B买了一些猫粮作为礼物。", AB = 0, BA = 2 },
      { text = "B给A买了一些猫薄荷作为礼物。", AB = 2, BA = 0 },
  } },
  { id = "4_badminton", name = "羽毛球", chapters = {
      { text = "却忘了它们两个都非常矮，一起在拥挤的体育馆被人类踩扁了。", attr = "辩证", AB = 1, BA = 1 },
      { text = "度过了一段愉快的运动时光。", AB = 2, BA = 2 },
      { text = "A把羽毛球砸到了B头上，让B得了脑震荡。", AB = 0, BA = -2 },
      { text = "B把羽毛球砸到了A头上，让A得了脑震荡。", AB = -2, BA = 0 },
  } },
  { id = "5_bbq", name = "户外烧烤", chapters = {
      { text = "结果来到户外才发现什么都没带……只好尴尬地一起欣赏风景。", attr = "审美", AB = 1, BA = 1 },
      { text = "亚米亚米，两本书都吃成了巨书观。", AB = 2, BA = 2 },
      { text = "A邪恶地用烧烤签烫了B。", AB = 0, BA = -2 },
      { text = "B邪恶地把A烤好的东西全部吃掉。", AB = -2, BA = 0 },
  } },
  { id = "6_wolf", name = "狼人杀", chapters = {
      { text = "两本书怎么玩？！它们在桌游店面面相觑。", AB = 1, BA = 1 },
      { text = "新手B精准地每局都能抽到狼人，被杀了好多次。", AB = 1, BA = -1 },
      { text = "神奇的是，它俩每次都能抽到同阵营……", AB = 2, BA = 2 },
  } },
  { id = "7_walk", name = "散步", chapters = {
      { text = "它们看到了美丽的夕阳，好幸福！", AB = 2, BA = 2 },
      { text = "半途中B不小心摔倒了，二级伤残。", AB = 0, BA = -2 },
      { text = "半途中A不小心落水了……", AB = -2, BA = 0 },
      { text = "碰到了B的好朋友，A恐惧地发现那是它最讨厌的人！", AB = -1, BA = 0 },
  } },
  { id = "8_cake", name = "杀糕局", chapters = {
      { text = "A带来一块巧克力蛋糕，B带来一块抹茶蛋糕，它们愉快地分食了。", AB = 2, BA = 2 },
      { text = "A带来一块草莓蛋糕，B带来了高先生的头颅。", AB = 1, BA = 1 },
      { text = "B带来了一块蓝莓蛋糕，A带来了高女士的头颅。", AB = 1, BA = 1 },
      { text = "A带来高先生的头颅，B带来高女士的身体，双方组装完成后成功完成了一个非常后现代的艺术装置。", attr = "辩证", AB = 2, BA = 2 },
  } },
  { id = "9_perler", name = "拼豆店", chapters = {
      { text = "A和B互相拼了对方的照片，好可爱！", AB = 2, BA = 2 },
      { text = "结果A不小心撞到了B拼好的超级大图……", AB = 0, BA = -2 },
      { text = "结果B不小心撞到了A拼好的超级大图……", AB = -2, BA = 0 },
      { text = "结果它们都发现对方想拼的图纸丑陋得让自己难以置信。", attr = "审美", AB = -1, BA = -1 },
  } },
  { id = "13_fall", name = "跌倒", chapters = {
      { text = "A出门后跌倒了，B将它温柔地扶了起来。", attr = "情感", AB = 2, BA = 2 },
  } },
  { id = "14_milktea", name = "奶茶", chapters = {
      { text = "它们愉悦地在奶茶店畅聊了一个下午。", AB = 2, BA = 2 },
      { text = "B并不喜欢奶茶，无聊地用吸管搅动珍珠听A说话。", AB = 1, BA = -1 },
      { text = "结果奶茶店发生了大爆炸，A和B都焦了。", AB = 1, BA = 1 },
  } },
  { id = "15_journal", name = "手账集市", chapters = {
      { text = "它们挑选了许多美萌小东西，进行了一波审美积累……", attr = "审美", AB = 2, BA = 2 },
      { text = "B并不喜欢手账，无聊地走来走去。", AB = -1, BA = 0 },
      { text = "B不小心撞到了架子，结果一堆贴纸把A埋在了下面。", AB = -1, BA = 0 },
  } },
  { id = "16_race", name = "赛跑", chapters = {
      { text = "两本书蹦蹦跳跳地跑过了终点线，非常可爱(o^^o)。", AB = 2, BA = 2 },
      { text = "B摔倒了，A赶紧去扶它，收获了B的感谢！", AB = 1, BA = 2 },
      { text = "跑着跑着，赛道下的地雷突然爆炸了，把它们炸成了焦炭……", AB = 1, BA = 1 },
  } },
  { id = "17_livehouse", name = "livehouse", chapters = {
      { text = "它们发现音乐真是情感的催化剂。", attr = "情感", AB = 2, BA = 2 },
      { text = "B的耳朵被震聋了。", AB = 0, BA = -1 },
  } },
  { id = "18_cook", name = "做饭", chapters = {
      { text = "A邀请B一起做饭，一起把厨房点着了。", AB = 1, BA = 1 },
  } },
  { id = "19_forward", name = "男生女生向前冲", chapters = {
      { text = "它们一起在第一关落水了。", AB = 1, BA = 1 },
      { text = "两本身手敏捷的小东西一起冲过了终点线。", AB = 2, BA = 2 },
      { text = "在极度兴奋的时候，B把A推到了水里。", AB = -2, BA = 0 },
      { text = "B落水的时候，A兴奋得大喊大叫。", AB = 1, BA = -1 },
  } },
  { id = "20_haunted", name = "鬼屋", chapters = {
      { text = "两本书一起被NPC吓得大喊大叫。", AB = 1, BA = 1 },
      { text = "B却意外应聘上了鬼屋NPC……", AB = 1, BA = 1 },
      { text = "A被吓得大喊大叫，B却平静地走完了全程。", attr = "阅历", AB = 0, BA = 1 },
  } },
  { id = "21_haunt", name = "灵异地点", chapters = {
      { text = "全程直播，它们成为了全网最大的双人探险博主，一夜暴富。", AB = 2, BA = 2 },
      { text = "结果双双被吓得在老楼里瑟瑟发抖到天亮才敢回家。", AB = 1, BA = 1 },
  } },
  { id = "22_climb", name = "攀岩", chapters = {
      { text = "两本书在攀岩馆爬来爬去的样子真的非常搞笑。", AB = 2, BA = 2 },
      { text = "B不小心摔了下来，好疼痛……", AB = 0, BA = -1 },
  } },
  { id = "10_snow", name = "爬雪山", chapters = {
      { text = "你以为它俩会遇到什么意外吧，其实不然，它们顺利爬上去又爬下来了。", AB = 1, BA = 1 },
      { text = "遇到了雪崩，幸好它们只是书，身体失温也不会死，最终成为了整座山唯二生还的活物。", AB = 2, BA = 2 },
      { text = "在半山腰上，A失手把B推了下去……", AB = 0, BA = -2 },
      { text = "在半山腰上，B失手把A推了下去……", AB = -2, BA = 0 },
      { text = "它们被可怕的天气困在山顶，只能靠食用人类来生活。", AB = 1, BA = 1 },
  } },
  { id = "11_movie", name = "看电影", chapters = {
      { text = "它们一起观看了《战狼2》，B发现A是吴京超话十级粉丝。", AB = 1, BA = 1 },
      { text = "它们一起观看了《爱乐之城》，同时轻轻哼唱起City of Stars……", attr = "情感", AB = 2, BA = 2 },
      { text = "它们一起观看了《发条橙》，两个文艺小众比觉得找到了知己。", attr = "审美", AB = 2, BA = 2 },
      { text = "它们一起观看了一部电影，但都没有认真看，而是在电影结束后合伙偷走了一排座椅。", attr = "辩证", AB = 2, BA = 2 },
  } },
  { id = "12_travel", name = "外出旅行", chapters = {
      { text = "B说你搞错了吧？！我们不应该都是宅宅的吗……", AB = 0, BA = -1 },
      { text = "B愉快地答应了，它们一起去富士山看了雪景。", AB = 2, BA = 2 },
  } },
}

-- 宿敌关系限定
local EVENTS_ENEMY = {
  { id = "e1", name = "登门", chapters = { { text = "A邀请B来自己家玩。结果刚打开门，就被B捅了一刀。", AB = 0, BA = -2 } } },
  { id = "e2", name = "蛋糕", chapters = { { text = "A邀请B去吃蛋糕，B吃出来一堆碎玻璃……", AB = 0, BA = -2 } } },
  { id = "e3", name = "酒店", chapters = { { text = "A邀请B一起去酒店，B在枕头下面发现一把水果刀……", AB = 0, BA = -1 } } },
  { id = "e4", name = "酒吧", chapters = { { text = "A邀请B一起去酒吧，去之前给了B一颗头孢骗它说是糖，还好B心怀警惕没有上当……", AB = 0, BA = -1 } } },
  { id = "e5", name = "摩天轮", chapters = { { text = "A邀请B一起去做浪漫摩天轮，在摩天轮到达顶点时，试图把B扔下去。", AB = 0, BA = -2 } } },
  { id = "e6", name = "超市", chapters = { { text = "A邀请B一起去超市偷东西，把赃物都放B口袋里，大摇大摆吹着口哨离开，留下身后的B被工作人员控制住。", AB = 0, BA = -2 } } },
}

-- 恋人/QPR 关系限定
local EVENTS_LOVER = {
  { id = "l1", name = "安静相坐", chapters = { { text = "A和B安静地坐在一起。", AB = 1, BA = 1 } } },
  { id = "l2", name = "摩天轮", chapters = { { text = "A和B去坐了摩天轮，一起观察下面的人类。", AB = 1, BA = 1 } } },
  { id = "l3", name = "看星星", chapters = { { text = "A和B去看了星星，并发现它们很美丽。", AB = 2, BA = 2 } } },
  { id = "l4", name = "封面漫步", chapters = { { text = "A和B轮流在彼此封面上走来走去。", AB = 1, BA = 1 } } },
  { id = "l5", name = "摩挲纸张", chapters = { { text = "A和B愉悦地互相摩擦着对方的纸张。", AB = 2, BA = 2 } } },
  { id = "l6", name = "嗅闻", chapters = { { text = "A和B不断好奇地嗅闻着对方。", AB = 1, BA = 1 } } },
  { id = "l7", name = "共进美餐", chapters = { { text = "A和B一起做了一顿美味的饭，并一起吃掉了它。", AB = 2, BA = 2 } } },
  { id = "l8", name = "重来", chapters = { { text = "A和B一起把它们的房子烧掉了。A说我们可以重新开始。", AB = 2, BA = 2 } } },
  { id = "l9", name = "骄傲游行", chapters = { { text = "A与B一起参加了一场骄傲游行。", AB = 2, BA = 2 } } },
  { id = "l10", name = "怪叫", chapters = { { text = "A和B在大声怪叫。", AB = 1, BA = 1 } } },
}

-- 单恋(追随者)限定 —— 只有主体书是单恋方时触发
local CRUSH_EVENT = {
  id = "wish_willow", name = "许愿柳",
  text = "A捡到一根许愿柳，许愿B爱自己胜过其他一切……",
}

-- ============ 存储 ============
function Pair:_relKey(i, j)
    if i > j then return tostring(j) .. "|" .. tostring(i) end
    return tostring(i) .. "|" .. tostring(j)
end

function Pair:_readRelations()
    return G_reader_settings:readSetting(settingKey(SETTING_REL), nil)
end

function Pair:_saveRelations(r)
    G_reader_settings:saveSetting(settingKey(SETTING_REL), r or {})
end

function Pair:_getRel(ff, i, j)
    local r = self:_readRelations()
    if not r then r = {} end
    local key = self:_relKey(i, j)
    local node = r[key]
    if not node then
        node = { ab = 0, ba = 0, abp = 0, bap = 0, s0 = 0, s1 = 0, s2 = 0, rel = nil, rel_side = nil, pair_ts = nil }
        r[key] = node
        self:_saveRelations(r)
    end
    return node, key, r
end

function Pair:_parseKey(key)
    local i, j = (key or ""):match("^([^|]+)|([^|]+)$")
    return tonumber(i), tonumber(j)
end

-- 点数累计（signed delta 施于 lv, pt）
function Pair:_moveAxis(lv, pt, delta)
    if not lv then lv = 0 end
    if not pt then pt = 0 end
    if delta == 0 then return lv, pt end
    while delta ~= 0 do
        -- 若 pt 与本次移动方向相反，先把进度走回 0
        if (pt > 0 and delta < 0) or (pt < 0 and delta > 0) then
            local h = math.abs(pt)
            if math.abs(delta) <= h then
                pt = pt + delta
                delta = 0
            else
                local r = math.abs(delta) - h
                pt = 0
                delta = (delta < 0) and -r or r
            end
            if delta == 0 then break end
        end
        local ds = 1
        if delta < 0 then ds = -1 end
        local tar = lv + ds
        if math.abs(tar) > CAP then break end
        local ta, tb = math.abs(lv), math.abs(tar)
        local thr = TH[math.max(ta, tb)] or 8
        local remaining = thr - math.abs(pt)
        if remaining < 0 then remaining = 0 end
        if math.abs(delta) <= remaining then
            pt = pt + ds * math.abs(delta)
            delta = 0
        else
            delta = delta - ds * remaining
            lv = tar
            pt = 0
        end
    end
    return lv, pt
end

function Pair:_entryOf(ff, idx)
    for _, e in ipairs(ff:_readCollection()) do
        if e.index == idx then return e end
    end
    return nil
end

function Pair:_name(ff, e)
    return e and e.nickname or "它"
end
function Pair:_nameIdx(ff, idx)
    return self:_name(ff, self:_entryOf(ff, idx))
end

function Pair:_attrsOf(ff, entry)
    local attrs = entry and entry.attributes
    if not attrs or next(attrs) == nil then attrs = ff:_readAttributes() end
    if not attrs then attrs = {} end
    return attrs
end

-- ============ 修正层 ============
function Pair:_modDelta(attrs, tag, d)
    d = d or 0
    local bz = attrs["辩证"] or 0
    local emo = attrs["情感"] or 0
    if d < 0 then
        -- 只保留"转负为正"：概率控制得较小，辩证越高越容易触发
        local p = 0.02 + bz / 100 * 0.05
        if p > 0.08 then p = 0.08 end
        if math.random() < p then d = -d end
        return d
    end
    if d > 0 then
        if emo >= 60 then d = d + 0.5
        elseif emo >= 40 then d = d + 0.2 end
    end
    if tag and d > 0 then
        local tv = attrs[tag] or 0
        if tv >= 60 then d = d + 0.5
        elseif tv >= 35 then d = d + 0.2 end
    end
    if d < 0 then d = 0 end
    return d
end

-- 好感修正（玩家主动出门）
function Pair:_favorMod(favor, d)
    if d == 0 then return 0 end
    local sign = d > 0 and 1 or -1
    local mag = math.abs(d)
    local boost = math.floor(math.abs(favor or 0) / 50)
    if boost > 1 then boost = 1 end
    if (favor or 0) >= 0 then
        mag = mag + (sign > 0 and boost or -boost * 0.5)
    else
        mag = mag + (sign < 0 and boost or -boost * 0.5)
    end
    if mag < 1 and mag > 0 then mag = 1 end
    if mag < 0 then mag = 0 end
    return sign * mag
end

-- ============ 施加 delta ============
function Pair:_applyDelta(ff, ia, ib, dAB, dBA, tag)
    self:setTag(tag)
    local node, key, r = self:_getRel(ff, ia, ib)
    -- 已有持久关系：点数锁定，不增减、不解除（soulmates 同理）
    if node.rel ~= nil then return node, false, false end
    local aEntry = self:_entryOf(ff, ia)
    local bEntry = self:_entryOf(ff, ib)
    local aA = self:_attrsOf(ff, aEntry)
    local bA = self:_attrsOf(ff, bEntry)
    local rAB = self:_modDelta(aA, tag, dAB or 0)
    local rBA = self:_modDelta(bA, tag, dBA or 0)
    -- 好感修正：书对玩家的好感影响其支出
    local fa = (ff._getFavor and ff:_getFavor(aEntry)) or 0
    local fb = (ff._getFavor and ff:_getFavor(bEntry)) or 0
    rAB = rAB + self:_favorMod(fa, dAB or 0)
    rBA = rBA + self:_favorMod(fb, dBA or 0)
    local old_ab, old_ba = node.ab or 0, node.ba or 0
    node.ab, node.abp = self:_moveAxis(node.ab or 0, node.abp or 0, rAB)
    node.ba, node.bap = self:_moveAxis(node.ba or 0, node.bap or 0, rBA)
    local ab_changed = node.ab ~= old_ab
    local ba_changed = node.ba ~= old_ba
    self:_saveRelations(r)
    -- 等级变化 → 延时写提示语
    if ab_changed then self:_queueNotice(ff, ia, ib, "AB", node.ab) end
    if ba_changed then self:_queueNotice(ff, ia, ib, "BA", node.ba) end
    -- 稳定性检查
    self:_checkStable(ff, ia, ib)
    return node, ab_changed, ba_changed
end

-- 延时提示队列（1 小时后写旅行日志）
function Pair:_queueNotice(ff, ia, ib, side, lv)
    local notices = G_reader_settings:readSetting(settingKey(SETTING_NOTICE), {}) or {}
    local aN = self:_nameIdx(ff, ia)
    local bN = self:_nameIdx(ff, ib)
    local tag
    if side == "AB" then tag = string.format("%s对%s", aN, bN) else tag = string.format("%s对%s", bN, aN) end
    local word = (lv >= 0 and "亲近" or "隔阂")
    local text = string.format("%s与%s之间，「%s · %s」似乎悄悄%s了。", aN, bN, tag, LEVEL_NAMES[lv] or tostring(lv), word)
    table.insert(notices, { due = os.time() + HOUR_DELAY * HOUR_SEC, ia = ia, ib = ib, text = text })
    G_reader_settings:saveSetting(settingKey(SETTING_NOTICE), notices)
end

-- ============ 持久关系分化 ============
function Pair:_bookHasPersistent(ff, idx)
    local p = G_reader_settings:readSetting(settingKey(SETTING_PERS), {}) or {}
    return p[tostring(idx)] ~= nil
end

function Pair:_checkStable(ff, ia, ib)
    local node, key = self:_getRel(ff, ia, ib)
    local ab, ba = node.ab or 0, node.ba or 0
    local now = os.time()
    if node.rel ~= nil then return end   -- 已有持久（含soulmate）：不再重复分化
    local held = self:_bookHasPersistent(ff, ia) or self:_bookHasPersistent(ff, ib)
    local stable_day = (held and STABLE_DAY_HELD or STABLE_DAY_FREE) * DAY_SEC

    if ab == 5 and ba == 5 then
        if node.s0 == 0 then node.s0 = now end
        if now - node.s0 >= stable_day then
            self:_differentiate(ff, ia, ib, "mutual_positive", node)
            node.s0 = 0
        end
    else
        node.s0 = 0
    end

    if ab == -5 and ba == -5 then
        if node.s2 == 0 then node.s2 = now end
        if now - node.s2 >= stable_day then
            self:_differentiate(ff, ia, ib, "mutual_negative", node)
            node.s2 = 0
        end
    else
        node.s2 = 0
    end

    local single = (ab == 5 and ba < 5) or (ba == 5 and ab < 5)
    if single then
        local dir = (ab == 5) and "ab" or "ba"
        if node.s1_dir ~= dir then node.s1_dir = dir; node.s1 = now end
        if now - node.s1 >= stable_day then
            self:_differentiate(ff, ia, ib, "single_positive", node, dir)
            node.s1 = 0
        end
    else
        node.s1 = 0; node.s1_dir = nil
    end
    self:_saveRelations(self:_readRelations())
end

function Pair:_setPersistent(ff, ia, ib, typ, holder)
    local p = G_reader_settings:readSetting(settingKey(SETTING_PERS), {}) or {}
    p[tostring(holder)] = { rel = typ }
    G_reader_settings:saveSetting(settingKey(SETTING_PERS), p)
end

function Pair:_breakPersistent(ff, ia, ib)
    local node, key = self:_getRel(ff, ia, ib)
    if node.rel == "soulmate" then return end
    if node.rel then
        local aN = self:_nameIdx(ff, ia)
        local bN = self:_nameIdx(ff, ib)
        local old = PNAMES[node.rel] or "关系"
        self:_logPair(ff, ia, ib, string.format("%s与%s的%s关系结束了。", aN, bN, old))
    end
    node.rel = nil
    node.rel_side = nil
    node.pair_ts = nil
    local p = G_reader_settings:readSetting(settingKey(SETTING_PERS), {}) or {}
    p[tostring(ia)] = nil
    p[tostring(ib)] = nil
    G_reader_settings:saveSetting(settingKey(SETTING_PERS), p)
end

function Pair:_differentiate(ff, ia, ib, kind, node, dir)
    local aN = self:_nameIdx(ff, ia)
    local bN = self:_nameIdx(ff, ib)
    if kind == "mutual_positive" then
        if node.rel and node.rel ~= "soulmate" then self:_breakPersistent(ff, ia, ib) end
        if node.rel ~= "soulmate" then
            local typ = (math.random() < 0.5) and "lover" or "qpr"
            node.rel = typ; node.pair_ts = os.time()
            self:_setPersistent(ff, ia, ib, typ, ia)
            local copy
            if typ == "lover" then
                copy = string.format("经过多日的相处，%s深深地爱上了%s，对%s进行了表白，在朋友们的欢呼中它们成为了恋人。", aN, bN, bN)
            else
                copy = string.format("%s发现自己与%s十分契合，它严肃地询问%s是否愿意成为自己的QPR（Queer Platonic Relationship）对象，%s愉快地同意了！", aN, bN, bN, bN)
            end
            self:_logPair(ff, ia, ib, copy)
            self:_msg(ff, string.format("（%s）一组新关系诞生：%s 与 %s 成为了%s。", os.date("%m-%d %H:%M"), aN, bN, (typ == "lover" and "恋人" or "QPR对象")))
        end
    elseif kind == "single_positive" then
        if node.rel and node.rel ~= "soulmate" then self:_breakPersistent(ff, ia, ib) end
        if node.rel ~= "soulmate" then
            local pursuer, target_ = (dir == "ab") and { ia, ib } or { ib, ia }
            node.rel = "crush"; node.rel_side = pursuer[1]; node.pair_ts = os.time()
            self:_setPersistent(ff, ia, ib, "crush", pursuer[1])
            local pN = self:_nameIdx(ff, pursuer[1])
            local tN = self:_nameIdx(ff, pursuer[2])
            self:_logPair(ff, ia, ib, string.format("%s迷恋%s许久，成为了对方的追随者。", pN, tN))
            self:_msg(ff, string.format("（%s）%s 成为了 %s 的追随者。", os.date("%m-%d %H:%M"), pN, tN))
        end
    elseif kind == "mutual_negative" then
        if node.rel and node.rel ~= "soulmate" then self:_breakPersistent(ff, ia, ib) end
        if node.rel ~= "soulmate" then
            -- 冰释前嫌（双向-5 → 恋人/QPR）：辩证越高越容易触发，取双方辩证较高者
            local attrsA = self:_attrsOf(ff, self:_entryOf(ff, ia))
            local attrsB = self:_attrsOf(ff, self:_entryOf(ff, ib))
            local bz = math.max(attrsA["辩证"] or 0, attrsB["辩证"] or 0)
            local rev_p = 0.02 + bz / 100 * 0.10
            if rev_p > 0.18 then rev_p = 0.18 end
            if math.random() < rev_p then
                local typ = (math.random() < 0.5) and "lover" or "qpr"
                node.rel = typ; node.pair_ts = os.time()
                self:_setPersistent(ff, ia, ib, typ, ia)
                self:_logPair(ff, ia, ib, string.format("命运开了个玩笑——%s与%s冰释前嫌，成为了%s。", aN, bN, (typ == "lover" and "恋人" or "QPR对象")))
                self:_msg(ff, string.format("（%s）%s 与 %s 竟冰释前嫌、成为了%s！", os.date("%m-%d %H:%M"), aN, bN, (typ == "lover" and "恋人" or "QPR对象")))
            else
                node.rel = "rival"; node.pair_ts = os.time()
                self:_setPersistent(ff, ia, ib, "rival", ia)
                self:_logPair(ff, ia, ib, string.format("%s与%s非常非常非常讨厌彼此，它们成为了宿敌。", aN, bN))
                self:_msg(ff, string.format("（%s）%s 与 %s 成为了宿敌。", os.date("%m-%d %H:%M"), aN, bN))
            end
        end
    end
    self:_saveRelations(self:_readRelations())
end

-- ============ 旅行日志 ============
function Pair:_logPair(ff, ia, ib, text)
    local now = os.time()
    local c = ff:_readCollection()
    for _, e in ipairs(c) do
        if e.index == ia or e.index == ib then
            local tlog = e.travel_log or {}
            table.insert(tlog, { ts = now, text = text or "", mood = 0, pts = 0 })
            table.sort(tlog, function(x, y) return (x.ts or 0) < (y.ts or 0) end)
            e.travel_log = tlog
        end
    end
    ff:_saveCollection(c)
end

function Pair:setTag(tag)
    self._cur_tag = tag
end

function Pair:_msg(ff, text)
    if ff._showMessage then ff:_showMessage(text, 4) end
end

-- ============ 弹窗辅助 ============
local function _btnDialog(title, body, buttons, self_ref)
    local dlg = ButtonDialog:new{
        title = title or "", title_align = "center",
        info_text = body or "",
        width = Screen:scaleBySize(560),
        buttons = buttons,
    }
    return dlg
end

-- ============ 出门邀请流程 ============
-- 由 main.lua 的 _outdoorStart 在扣完基础10分后调用
function Pair:partnerAsk(ff, entry)
    if not entry then
        if ff._outdoorSoloDialog then ff:_outdoorSoloDialog(entry or {}) end
        return
    end
    local c = ff:_readCollection()
    local others = {}
    for _, e in ipairs(c) do
        if e.index ~= entry.index and e.reveal_date then table.insert(others, e) end
    end
    local function solo()
        if ff._outdoorSoloDialog then ff:_outdoorSoloDialog(entry) end
    end
    if #others == 0 then solo() return end
    local dlg
    local btns = {
        { text = "是", callback = function()
            if dlg then UIManager:close(dlg) end
            -- 预留：邀请(+5)后还需至少 10 分用于出发（否则选完书出发时会"0事件"却白扣分）
            if ff:_readPoints() - 5 < 10 then
                self:_msg(ff, "积分不足：邀请同行需预留 10 积分用于出发。")
                return
            end
            self:_charge(ff, 5, "邀请同行")
            self:specifyAsk(ff, entry, others)
        end },
        { text = "否", callback = function()
            if dlg then UIManager:close(dlg) end
            solo()
        end },
    }
    dlg = _btnDialog("是否邀请其他书同行？", "是否邀请其他书同行？（消耗 5 积分）", { btns }, self)
    UIManager:show(dlg)
end

function Pair:specifyAsk(ff, entry, others)
    local function proceed(partner)
        self:_runPair(ff, entry, partner)
    end
    local function randomPartner()
        local p = others[math.random(1, #others)]
        self:_runPair(ff, entry, p)
    end
    local dlg
    local btns = {
        { text = "是", callback = function()
            if dlg then UIManager:close(dlg) end
            -- 预留：指定(+5)后还需至少 10 分用于出发
            if ff:_readPoints() - 5 < 10 then
                self:_msg(ff, "积分不足：指定同行需预留 10 积分用于出发。")
                return
            end
            self:_charge(ff, 5, "指定对象")
            self:pickPartner(ff, entry, others)
        end },
        { text = "否", callback = function()
            if dlg then UIManager:close(dlg) end
            randomPartner()
        end },
    }
    dlg = _btnDialog("是否指定同行对象？", "是否指定邀请对象？（消耗 5 积分）", { btns }, self)
    UIManager:show(dlg)
end

function Pair:pickPartner(ff, entry, others)
    local items = {}
    for _, e in ipairs(others) do
        items[#items + 1] = {
            text = self:_name(ff, e),
            callback = function()
                if logger then logger.warn("Pair:pickPartner PICK", entry.index, e.index) end
                self:_runPair(ff, entry, e)
            end,
        }
    end
    local m = Menu:new{
        title = "选择同行的书",
        item_table = items,
        width = Screen:getWidth(),
        is_borderless = true,
        is_popout = false,
    }
    UIManager:show(m)
end

function Pair:_charge(ff, n, why)
    local cur = ff:_readPoints()
    ff:_savePoints(math.max(0, cur - n))
end

-- ============ 双人事件引擎 ============
function Pair:_buildPool(ff, ia, ib)
    local node, key = self:_getRel(ff, ia, ib)
    local pool = {}
    for _, ev in ipairs(EVENTS) do table.insert(pool, ev) end
    if node.rel == "rival" then
        for _, ev in ipairs(EVENTS_ENEMY) do table.insert(pool, ev) end
    elseif node.rel == "lover" or node.rel == "qpr" or node.rel == "soulmate" then
        for _, ev in ipairs(EVENTS_LOVER) do table.insert(pool, ev) end
    end
    return pool
end

function Pair:_runPair(ff, aEntry, bEntry)
    if logger then logger.warn("Pair:_runPair ENTER", aEntry and aEntry.index, bEntry and bEntry.index) end
    if not aEntry or not bEntry then return end
    -- 真正出发时扣除基础 10 分（主书结算时扣，弹窗/取消不扣）
    local pnow = ff:_readPoints()
    if pnow < 10 then
        if logger then logger.warn("Pair:_runPair POINTSUFF", pnow) end
        if ff._showMessage then ff:_showMessage("积分不足，出门需要 10 积分。", 4) end
        return
    end
    ff:_savePoints(pnow - 10)
    local ia, ib = aEntry.index, bEntry.index
    local node = self:_getRel(ff, ia, ib)
    -- 单恋彩蛋：主体书是单恋方时，小概率触发许愿柳
    if node.rel == "crush" and node.rel_side == ia then
        if math.random() < 0.08 then
            if logger then logger.warn("Pair:_runPair CRUSH") end
            self:_runCrush(ff, aEntry, bEntry)
            return
        end
    end
    local pool = self:_buildPool(ff, ia, ib)
    local evt = pool[math.random(1, #pool)]
    local ch = evt.chapters[math.random(1, #evt.chapters)]
    if logger then logger.warn("Pair:_runPair EVT", evt.id, ch.text) end
    local aN = self:_name(ff, aEntry)
    local bN = self:_name(ff, bEntry)
    local text = (ch.text or ""):gsub("A", aN):gsub("B", bN)
    -- 施加 delta
    local node2, ab_changed, ba_changed = self:_applyDelta(ff, ia, ib, ch.AB, ch.BA, ch.attr)
    -- 写双方旅行日志
    local ab_lv, ba_lv = node2.ab or 0, node2.ba or 0
    local sub1 = string.format("%s对%s：%s（%s）", aN, bN, LEVEL_NAMES[ab_lv] or tostring(ab_lv), (ch.AB > 0 and "+" or tostring(ch.AB or 0)))
    local sub2 = string.format("%s对%s：%s（%s）", bN, aN, LEVEL_NAMES[ba_lv] or tostring(ba_lv), (ch.BA > 0 and "+" or tostring(ch.BA or 0)))
    self:_logPair(ff, ia, ib, text)
    self:_logPair(ff, ia, ib, "关系：" .. sub1 .. "  ·  " .. sub2)
    -- 结果弹窗
    local body = text .. "\n\n" .. sub1 .. "\n" .. sub2
    if logger then logger.warn("Pair:_runPair BEFORE_SHOW") end
    self:_showResult(body)
    if logger then logger.warn("Pair:_runPair AFTER_SHOW") end
end

function Pair:_showResult(body)
    if logger then logger.warn("Pair:_showResult ENTER", body) end
    local dlg
    local btns = { { text = "确定", callback = function()
        if dlg then UIManager:close(dlg) end
    end } }
    dlg = _btnDialog("双人事件", body, { btns }, self)
    UIManager:show(dlg)
    if logger then logger.warn("Pair:_showResult SHOWN") end
end

-- ============ 许愿柳彩蛋（单恋限定） ============
function Pair:_runCrush(ff, aEntry, bEntry)
    if not aEntry or not bEntry then return end
    local messages = {
        "No、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、no、" .. "Don't do that!!!!",
        "I thought we were having a nice date……",
    }
    local steps = 8
    local aN = self:_name(ff, aEntry)
    local bN = self:_name(ff, bEntry)
    local text0 = (CRUSH_EVENT.text or ""):gsub("A", aN):gsub("B", bN)
    local click = 0
    local dlg
    local function bodyFor(i)
        if i <= 2 then return messages[1] end
        if i == 3 then return messages[2] end
        if i > 3 and click % 2 == 1 then return messages[2] end
        return messages[1]
    end
    local function show(current)
        local msgs = (current >= 2 and current <= 3) and { messages[(current == 2) and 1 or 2] } or nil
        -- 简化：按步骤交替
        local body
        if current == 1 then body = messages[1]
        elseif current == 2 then body = messages[1]
        else body = messages[2] end
        dlg = _btnDialog("许愿柳", body, { { text = "确定", callback = function()
            if dlg then UIManager:close(dlg) end
            click = click + 1
            if click >= 8 then
                -- 结束：A对B 微增（单恋加深）
                self:_logPair(ff, aEntry.index, bEntry.index, string.format("%s的许愿并未被回应，但它仍执拗地喜欢着%s。", aN, bN))
                return
            end
            show(click + 1)
        end } }, self)
        UIManager:show(dlg)
    end
    show(1)
end

-- soulmates 判定（供 _tick 调用）
function Pair:soulcheck(ff)
    local r = self:_readRelations() or {}
    local now = os.time()
    for key, node in pairs(r) do
        if node and (node.rel == "lover" or node.rel == "qpr") and node.pair_ts then
            if (node.ab or 0) == 5 and (node.ba or 0) == 5 and now - node.pair_ts >= SOULMATE_DAY * DAY_SEC then
                local ia, ib = self:_parseKey(key)
                local aN = self:_nameIdx(ff, ia)
                local bN = self:_nameIdx(ff, ib)
                node.rel = "soulmate"
                self:_saveRelations(r)
                self:_logPair(ff, ia, ib, string.format("%s与%s已经完全深入了彼此的人生，这一刻，它们都认为对方是自己的soulmates。", aN, bN))
            end
        end
    end
end

-- 延时提示队列刷新
function Pair:flushNotices(ff)
    local notices = G_reader_settings:readSetting(settingKey(SETTING_NOTICE), {}) or {}
    local now = os.time()
    local left = {}
    local changed = false
    for _, n in ipairs(notices) do
        if n.due and now >= n.due then
            self:_logPair(ff, n.ia, n.ib, n.text or "")
            changed = true
        else
            table.insert(left, n)
        end
    end
    if changed then G_reader_settings:saveSetting(settingKey(SETTING_NOTICE), left) end
end

-- 关系图谱（"书的关系"菜单）
function Pair:showRelationMap(ff)
    local collection = ff:_readCollection()
    if #collection < 2 then
        ff:_showMessage("至少需要两本养成书才会产生书与书的关系。", 4)
        return
    end
    local items = {}
    local r = self:_readRelations() or {}
    for key, node in pairs(r) do
        local ia, ib = self:_parseKey(key)
        if ia and ib then
            local aE = self:_entryOf(ff, ia)
            local bE = self:_entryOf(ff, ib)
            if aE and bE then
                local aN = self:_name(ff, aE)
                local bN = self:_name(ff, bE)
                local line = string.format("%s ⇄ %s   |  %s→%s %s / %s→%s %s",
                    aN, bN,
                    aN, bN, LEVEL_NAMES[node.ab or 0] or tostring(node.ab or 0),
                    bN, aN, LEVEL_NAMES[node.ba or 0] or tostring(node.ba or 0))
                if node.rel then line = line .. "  ·  [" .. (PNAMES[node.rel] or node.rel) .. "]" end
                items[#items + 1] = {
                    text = line,
                    callback = function() end,
                }
            end
        end
    end
    if #items == 0 then
        ff:_showMessage("还没有书与书之间的关系。\n带两本书一起出门，或让它们偶遇吧。", 5)
        return
    end
    table.sort(items, function(a, b) return a.text < b.text end)
    local m = Menu:new{ title = "书的关系", item_table = items, width = Screen:getWidth(), is_borderless = true, is_popout = false }
    UIManager:show(m)
end

-- 旅行日志偶发双人事件：某本书有新旅行记录时调用。基础5%，随其对任意书的关系等级微增
function Pair:maybeTravelPair(ff, entry)
    if not entry or not entry.reveal_date then return end
    local c = ff:_readCollection()
    local others = {}
    for _, e in ipairs(c) do
        if e.index ~= entry.index and e.reveal_date then table.insert(others, e) end
    end
    if #others == 0 then return end
    -- 取缘分最高的对方：关系等级绝对值最高的组合
    local best, bestAbs = others[math.random(1, #others)], 0
    for _, e in ipairs(others) do
        local node = self:_getRel(ff, entry.index, e.index)
        local abs = math.abs(node.ab or 0) + math.abs(node.ba or 0)
        if abs > bestAbs then bestAbs = abs; best = e end
    end
    local node = self:_getRel(ff, entry.index, best.index)
    local lv = math.abs(node.ab or 0) + math.abs(node.ba or 0)
    -- 已有持久关系：双人事件概率大幅提升；否则基础5%，每级+0.8%
    local p = 0.05 + lv * 0.008
    if node.rel then
        p = 0.35 + lv * 0.012
        if p > 0.60 then p = 0.60 end
    else
        if p > 0.20 then p = 0.20 end
    end
    if math.random() < p then
        -- 后台偶发：静默结算（写双方旅行日志、推进关系点数），不弹窗打扰
        local ia, ib = entry.index, best.index
        local pool = self:_buildPool(ff, ia, ib)
        local evt = pool[math.random(1, #pool)]
        local ch = evt.chapters[math.random(1, #evt.chapters)]
        local aN = self:_nameIdx(ff, ia)
        local bN = self:_nameIdx(ff, ib)
        local text = (ch.text or ""):gsub("A", aN):gsub("B", bN)
        self:_applyDelta(ff, ia, ib, ch.AB, ch.BA, ch.attr)
        self:_logPair(ff, ia, ib, text)
        local sub1 = string.format("%s对%s：%s", aN, bN, LEVEL_NAMES[(self:_getRel(ff, ia, ib)).ab or 0] or "")
        local sub2 = string.format("%s对%s：%s", bN, aN, LEVEL_NAMES[(self:_getRel(ff, ia, ib)).ba or 0] or "")
        self:_logPair(ff, ia, ib, "关系：" .. sub1 .. "  ·  " .. sub2)
    end
end

-- 供 main.lua 的 _tick 周期调用：soulmate判定 + 延时提示刷新
function Pair:tick(ff)
    self:soulcheck(ff)
    self:flushNotices(ff)
    -- 兜底：周期清理各书超72h旅行日志（不依赖"书之来信"开关/翻页，保证按序淘汰）
    if ff and ff._travelCleanup then
        local c = (ff._readCollection and ff:_readCollection()) or {}
        local changed = false
        for _, ee in ipairs(c) do
            if ee.reveal_date and ff._travelCleanup(ff, ee, 1) then changed = true end
        end
        if changed and ff._saveCollection then ff:_saveCollection(c) end
    end
end

return Pair