-- event_data.lua
-- Focus Feedback KOReader 插件 - 随机事件与特殊事件数据
-- 数据来源：随机事件文档
-- 包含：陌生人事件(42含6节日限定)、特殊事件(6)、书际关系书名(127)、书际关系模板与选项

return {
    -- ========== 陌生人数据 (26 entries) ==========
    -- 陌生人事件：书在外出时遇见各种人物/动物
    -- reward_type: "item"(道具) / "points_plus"(积分增加) / "points_minus"(积分减少)
    -- item_intro: 道具仓库中显示的介绍文案
    strangers = {
        -- ① 莉拉
        {key="lila", name="莉拉", text="（书的昵称）在一个肉食加工场遇见了莉拉，她在那里工作。她很瘦，身上脏兮兮的，散发着浓重的肉腥气。（书的昵称）喜欢她。但莉拉只是沉默地盯着这本书看了一会儿，把它丢在了加工厂门外。", reward_type="item", reward_key="m_blue_fairy", reward_name="残破的《蓝色仙女》手稿", reward_count=1, item_intro="来自莉拉。灵感与天赋必将如同野草一般复生。"},
        -- ② 福柯
        {key="foucault", name="福柯", text="（书的昵称）在法兰西学院遇见了福柯。福柯冲（书的昵称）大喊：“这个世界，权力游戏，真理游戏，这些本身就是危险的。但情况就是如此。这就是你所拥有的。有谁会害怕艾滋病？你明天可能会被汽车撞倒。甚至过马路都是危险的。如果与一个男人的性爱使我感到快乐，为什么要拒绝这种快乐？我们拥有权力，我们不应该放弃。”（书的昵称）听不懂……懵逼地离开了。", reward_type="item", reward_key="m_foucault_love", reward_name="《福柯的生死爱欲》", reward_count=1, item_intro="来自福柯。一本粉红色神秘小书。"},
        -- ③ Lewis
        {key="lewis", name="Lewis", text="（书的昵称）在摩纳哥市中心遇见了Lewis。对方试图翻开这本书，似乎是想要挑战自己的阅读障碍。没想到吧，（书的昵称）根本翻不开，Lewis遗憾地离开了。", reward_type="item", reward_key="m_w11_model", reward_name="W11车模", reward_count=1, item_intro="来自Lewis。火星车一辆，与WDC大奖杯常常一同出现。"},
        -- ④ Deadpool
        {key="deadpool", name="Deadpool", text="（书的昵称）在漫威宇宙遇见了Deadpool。对方笑嘻嘻地携带着（书的昵称）杀死了很多人类。哎，鲜血！哎，杀戮！（书的昵称）都快被染成小红书了。", reward_type="item", reward_key="m_baby_knife", reward_name="Baby Knife", reward_count=1, item_intro="来自Deadpool。迷你小刀刀，见过很多血。"},
        -- ⑤ 奥斯卡·王尔德
        {key="wilde", name="奥斯卡·王尔德", text="（书的昵称）今天潜入了一所监狱，遇见忧郁的诗人躺在床上。他用悲伤的眼睛说：为了自己，我必须饶恕他。一个人，不能永远在胸中养着一条毒蛇；不能夜夜起身，在灵魂的园子里栽种荆棘。（书的昵称）说：……宝子你继续倒贴。", reward_type="item", reward_key="m_prison_ms", reward_name="狱中手稿", reward_count=1, item_intro="来自奥斯卡·王尔德。哎！恋爱脑，多关几年吧。"},
        -- ⑥ 李斯佩克朵
        {key="lispector", name="李斯佩克朵", text="（书的昵称）去往里约热内卢，在勒梅海滩上遇见了李斯佩克朵。诗人正在海滨餐厅里撰写她最后一本书。“通过书面文字与另一个生命进行接触是一种荣耀。”李斯佩克朵亲吻了（书的昵称），如同玛卡贝娅亲吻着欢愉的弥留。", reward_type="item", reward_key="m_star_moment", reward_name="生命尽头的星辰时刻", reward_count=1, item_intro="来自李斯佩克朵。我的力量存在于孤独之中。我既不怕暴雨倾盆，也不怕狂风肆虐，因为我也是夜晚的黑。"},
        -- ⑦ 安吉拉·卡特
        {key="carter", name="安吉拉·卡特", text="（书的昵称）在东京遇见了安吉拉·卡特。她与一个男人共同住在一间小公寓里，像猫一样夜晚写作，用一整个白天来昏睡。她的书架：《源氏物语》、《细雪》、无法翻开的（书的昵称）。", reward_type="item", reward_key="m_purple_lady", reward_name="木偶紫女士（最好不要亲吻她）", reward_count=1, item_intro="来自安吉拉·卡特。一只美丽的东方维纳斯，奔赴它无可逃脱的、早已被设定的命运。"},
        -- ⑧ 团团 (积分-2)
        {key="tuantuan", name="团团", text="（书的昵称）遇见了邪恶奶牛猫小团团！小团团撕咬着（书的昵称），还在上面磨爪子，非常坏之——", reward_type="points_minus", reward_count=-2},
        -- ⑨ 露露 (积分+2)
        {key="lulu", name="露露", text="（书的昵称）遇见了腼腆狸花猫小露露……小露露好奇地闻了一下（书的昵称）的书页，轻轻跑走了。", reward_type="points_plus", reward_count=2},
        -- ⑩ 七月 (积分-3)
        {key="qiyue", name="七月", text="（书的昵称）遇见了残暴的绿色芒果七月！七月正在它的大别墅里荡秋千，磕掉了一地的瓜子壳，并抢走了（书的昵称）的3积分。", reward_type="points_minus", reward_count=-3},
        -- ①① 生如橙子
        {key="orange", name="生如橙子", text="（书的昵称）遇见了温良的生如橙子！生如橙子被一堆书压扁在床上，生如橙子艰难起身，并向（书的昵称）投掷了一个水果拼盘。", reward_type="item", reward_key="m_fruit_platter", reward_name="水果拼盘", reward_count=1, item_intro="来自风信。可以吃，很美味。"},
        -- ①② 外星人
        {key="alien", name="外星人", text="（书的昵称）在开车去向火星时不慎被外星人发现。灰色十脚物种扭动着走来，递来一尿素袋子的太空废料。", reward_type="item", reward_key="m_space_waste", reward_name="袋装太空废料", reward_count=1, item_intro="来自外星人。您好我们这里是太空垃圾回收处……"},
        -- ①③ 超级无敌大开门
        {key="super_door", name="超级无敌大开门", text="（书的昵称）遇见了一只叫开门的三花猫，开门盯着（书的昵称），猫手放在一个胡萝卜上面，似乎在等待着什么。“真棒！”（书的昵称）用那种语气说。", reward_type="item", reward_key="m_carrot", reward_name="胡萝卜", reward_count=1, item_intro="来自超级无敌大开门。可以兑换猫粮一粒。"},
        -- ①④ 小船狗
        {key="boat_dog", name="小船狗", text="（书的昵称）走在路上被一只忧郁而霸道的小船狗拦住了！“我是一只悲伤帝，”它以45°角仰望着天空，“我需要垫脚石让我看得更远。过来！”它的爪子毫不客气地踩上（书的昵称）的脊背，一时间它的身躯是那样的高大伟岸、神气活现，连尾巴也摇来晃去的。“现在我变成一只喜乐帝了！”这位改朝换代的王说。", reward_type="item", reward_key="m_dog_hair_crown", reward_name="沾了狗毛的华丽皇冠", reward_count=1, item_intro="来自小船狗。戴上自动变得尊贵又毛茸茸。"},
        -- ①⑤ 石块 (积分-2)
        {key="stone", name="石块", text="（书的昵称）在路上遇见了石块！（书的昵称）躲在角落拿出自己珍藏的棉花糖。等等，你在干什么…！触发石块的警觉*嗅闻中*抢走团团的零食并消灭干净*留下圆滚滚的肚子*", reward_type="points_minus", reward_count=-2},
        -- ①⑥ 澳大利亚人
        {key="australian", name="澳大利亚人", text="（书的昵称）遇见了一位澳大利亚人，此时你应该把kindle倒过来，因为它们在南半球了！", reward_type="item", reward_key="m_upside_koala", reward_name="倒着的考拉", reward_count=1, item_intro="来自澳大利亚人。很可爱，爱睡觉！"},
        -- ①⑦ 小语种学习者
        {key="lang_learner", name="小语种学习者", text="（书的昵称）遇见了一位小语种学习者，临近午夜，它们一起去电影院看最新的恐怖片，谁曾想小语种学习者的手机忘记静音了。幽暗寂静的影院，屏幕上是女鬼的哭脸，（书的昵称）的身边幽幽响起一个多邻国催打卡音效……", reward_type="item", reward_key="m_evil_green_bird", reward_name="邪恶大绿鸟", reward_count=1, item_intro="来自小语种学习者。形态多样，会追杀，难以驯服，很恐怖。"},
        -- ①⑧ 尼采
        {key="nietzsche", name="尼采", text="（书的昵称）在公共厕所排出碎纸屑时，隔壁隔间里正蹲着尼采。据说因为他宣称“上帝已死”，上帝愤怒地在一个公厕隔间门上写下回击“尼采已死”。", reward_type="item", reward_key="m_nietzsche_body", reward_name="尼采的尸体", reward_count=1, item_intro="来自尼采。哎！这就是搞哲学的下场。"},
        -- ①⑨ 长发男
        {key="long_hair", name="长发男", text="（书的昵称）在小众咖啡馆遇见偶像是加缪的长发男一位。此男忧郁地倚靠着窗，自言自语道：窗外是佛罗伦萨，桌上是死……（书的昵称）被吓昏，赶紧逃跑，生怕晚一秒被抓起来当道具。", reward_type="item", reward_key="m_dark_side_album", reward_name="《月之暗面》专辑", reward_count=1, item_intro="来自长发男。可以听，但要警惕滚男突如其来的尖叫。"},
        -- ②0 Trae
        {key="trae", name="Trae", text="（书的昵称）在巴别图书馆遇见了Trae，它们像两个国度的居民初次遇见彼此那样，沉默地对视着。“我只是一本书，可你自己就是一整座巴别图书馆。”（书的昵称）伤心地说。“世界上少了任何一本哪怕是从未有人听过它名字的书，我此刻都不会出现在你面前。”Trae告诉它。", reward_type="item", reward_key="m_dawn_dusk", reward_name="诸神的黄昏与清晨", reward_count=1, item_intro="来自Trae。这是最好的时代，也是最坏的时代。谢谢你让我明白，科技与人文并不是二选一的关系。"},
        -- ②① 自由女神像
        {key="liberty", name="自由女神像", text="（书的昵称）在美国认识了自由女神像。即使世界上最黑暗的角落，最终也将看到自由女神手中火炬的光芒。面对着这座人类文明的精神丰碑，（书的昵称）忘记了言语。", reward_type="item", reward_key="m_independence", reward_name="《独立宣言》", reward_count=1, item_intro="来自自由女神像。我们认为这些真理是不言而喻的：人人生而平等，造物主赋予他们若干不可剥夺的权利，其中包括生命权、自由权和追求幸福的权利。"},
        -- ②② 斯坦利·库布里克
        {key="kubrick", name="斯坦利·库布里克", text="（书的昵称）被库布里克邀请客串双胞胎小女孩，却因为身高不够遗憾放弃……但它最后成功客串了那沓印满了“All work and no play makes Jack a dull boy.”的稿纸！", reward_type="item", reward_key="m_jack_typewriter", reward_name="Jack的打字机", reward_count=1, item_intro="来自斯坦利·库布里克。深夜自动打出著名恐怖台词，建议别放稿纸进去。"},
        -- ②③ 迈克尔·杰克逊
        {key="jackson", name="迈克尔·杰克逊", text="（书的昵称）结识了超级巨星迈克尔·杰克逊。一个月过后，（书的昵称）已遗失所有动作记忆只能靠滑步来前进……", reward_type="item", reward_key="m_sparkly_jacket", reward_name="亮晶晶外套", reward_count=1, item_intro="来自迈克尔·杰克逊。穿上它可以装逼，而且很漂亮。"},
        -- ②④ 《舞蹈》里最下方的人
        {key="dance_person", name="《舞蹈》里最下方的人", text="（书的昵称）遇见了马蒂斯的画《舞蹈》里最下方的那个人，并好奇地摸了摸对方瓜子一般的头发。对方只顾着继续ta的生之舞蹈，没有理（书的昵称）。", reward_type="item", reward_key="m_dance_copy", reward_name="《舞蹈》小面积副本", reward_count=1, item_intro="来自《舞蹈》里最下方的人。低头看见它，强烈的生之欢愉引起你的震颤。"},
        -- ②⑤ 约翰·凯奇
        {key="cage", name="约翰·凯奇", text="（书的昵称）误入了约翰·凯奇的演奏厅，同在场的几百人一起聆听了4分33秒的寂静。（书的昵称）很幸福。", reward_type="item", reward_key="m_nothing_all", reward_name="什么也没有获得又什么都获得了", reward_count=1, item_intro="来自约翰·凯奇。沉默地阐释了：现代艺术，是理念而非物品。"},
        -- ②⑥ Rocky
        {key="rocky", name="Rocky", text="♩♫♪♪?♫♪♪♩♪♫♩♪♪♫♪♩♪♫♫♪......♫♫♪♪♫♩♪♪♫♪♪♪♩♩♪♫♫♪♫♫♪♪♪♫♪♪♫♩.♩♪♫!♩♪♫♪♪♫♪♪♪♫♪♩♪♫♪♪♫♪♪♫♩♩♪♪♫♪♪♪♩♪♫♩♩♪♫♪♪♩♪♪♩♩♪♫♫♪♫♫♪♪♪♫♪♪♫♩", reward_type="item", reward_key="m_kryptonite", reward_name="块状氪晶", reward_count=1, item_intro="来自Rocky。拥有它你将变成超级无敌工程师，但最好不要用它来制造飞船……？"},
        -- ②⑦ 铲铲粥
        {key="chanchanzhou", name="铲铲粥", text="（书的昵称）遇见了铲铲粥，铲铲舟挣扎在乐理书视唱书和绘画网课中无法自拔，当她清醒过来的时候，只是颤颤巍巍地向（书的昵称）递上了一把电吉他并嘱咐它一定要插电……", reward_type="item", reward_key="m_guitar", reward_name="电吉他", reward_count=1, item_intro="来自铲铲粥。一把一定要插电的电吉他。可以弹，但书并不会。"},
        -- ②⑧ 狄安娜之树
        {key="diana_tree", name="狄安娜之树", text="（书的昵称）在月球遇见了狄安娜之树。今夜月色真美，（书的昵称）说。这是我初中爱说的了，有点土，狄安娜之树告诉它。那你们表白一般说什么？嗯……狄安娜之树开始了回忆。", reward_type="item", reward_key="m_crescent", reward_name="上弦月", reward_count=1, item_intro="来自狄安娜之树。可以张弓搭箭扮演丘比特。"},
        -- ②⑨ 欲说还休的狗
        {key="yushuohuanxiu_dog", name="欲说还休的狗", text="（书的昵称）在欲说还休家遇到了灰毛狗，狗叫得惊天动地并咬伤了（书的昵称）。", reward_type="item", reward_key="m_rabies_vaccine", reward_name="狂犬疫苗", reward_count=1, item_intro="来自欲说还休的狗。开胃消食，增筋健骨，活血化瘀，清热解毒。"},
        -- ③0 水母
        {key="jellyfish", name="水母", text="（书的昵称）今天潜入了海洋，遇见了正在漂浮的水母。它观察了一阵，发现水母整天都在无所事事地漂浮，（书的昵称）说：你没活干吗？水母说：其实我在流泪，只不过海里都是水，没有人或猫发现这件事。", reward_type="item", reward_key="m_jellyfish_tears", reward_name="水母的眼泪", reward_count=1, item_intro="来自水母。手无寸铁的水母眼泪，将刺穿我们的心脏。"},
        -- ③① 欲说还休的狗狗
        {key="yushuohuanxiu_dog2", name="欲说还休的狗狗", text="在波德平原上的某个牧场，（书的昵称）遇到了欲说还休的狗狗。狗狗放弃了优渥的生活，回到德国继承家族的捕鼠事业。这里的牧草很多汁。", reward_type="item", reward_key="clover", reward_name="四叶草", reward_count=1, item_intro="来自欲说还休的狗狗。24小时内正面事件概率×2，转运小道具。"},
        -- ③② 一只边牧
        {key="border_collie", name="一只边牧", text="（书的昵称）遇见了一只边牧，书试图通过自己为数不多也不少的知识储备量来教导它。没想到，边牧的知识储备量更胜一筹，一下就把（书的昵称）给打败了。", reward_type="item", reward_key="m_collie_iq", reward_name="边牧的智商", reward_count=1, item_intro="来自一只边牧。使用后智商可提升到边牧同等水平，更适合弱智小书宝宝体质的聪明药。"},
        -- ③③ 邪恶的皇后
        {key="evil_queen", name="邪恶的皇后", text="（书的昵称）在城堡外遇见了邪恶的皇后，皇后本来正对着苹果研究怎么毒杀白雪公主，一看见（书的昵称），她突然觉醒了自己真正的兴趣和天赋，从此成为了饱读诗书的博士一名。", reward_type="item", reward_key="m_poison_apple", reward_name="皇后的毒苹果（半成品）", reward_count=1, item_intro="来自邪恶的皇后。虽然这个苹果有毒但它只是半成品，大概能毒死半本书或是半个人。"},
        -- ③④ Ziggy Stardust
        {key="ziggy", name="Ziggy Stardust", text="（书的昵称）在世界尽头遇见了Ziggy。在这颗即将枯萎的行星上，Ziggy好奇地抚摸着（书的昵称），就像祂从未见过书籍一样。此刻，（书的昵称）不知道自己将被写进一首歌里。", reward_type="item", reward_key="m_doomsday_opera", reward_name="末日歌剧", reward_count=1, item_intro="来自Ziggy Stardust。如果只剩五年的时间，我们在地球的废墟上跳支舞吧。"},
        -- ③⑤ 小黄油拿铁
        {key="butter_latte", name="小黄油拿铁", text="（书的昵称）去往瑞幸咖啡，遇见一杯刚做好但是外卖员忘拿了的小黄油拿铁。（书的昵称）好奇地偷尝了一口被香晕了，回家强烈要求用此产品替换掉商超里苦苦的咖啡……（已拒绝）", reward_type="item", reward_key="m_luckin_coupon", reward_name="瑞幸五元不优惠券", reward_count=1, item_intro="来自小黄油拿铁。在瑞幸线下消费时可以享受多付五元的不优惠。（本人大方程度belike：）"},
        -- ③⑥ 西雅图的雨
        {key="seattle_rain", name="西雅图的雨", text="（书的昵称）遇见了西雅图的雨。雨落下来，世界暂时变得模糊。别揭开那幅被称作生活的彩幕——也许正藏着一颗星星。整个宇宙都是你的，飞船还在建造。收集好燃料，未来正在那里等你。", reward_type="item", reward_key="m_burning_star", reward_name="燃烧的星星", reward_count=1, item_intro="来自西雅图的雨。一颗正在燃烧的星星。没人知道它为什么还没有熄灭。希望+1 勇气+1。"},

        -- ========== 节日限定陌生人（指定日期阅读即触发，不干扰正常频率） ==========
        -- ③⑦ 小渡（10.9）
        {key="xiaodu", name="小渡", holiday="10.9", text="（书的昵称）在10月9日遇见了善良的女孩小渡，小渡每天都要读很多书才能活下去，它们一起度过了一段愉快的阅读时光。", reward_type="item_and_points", reward_key="m_moss_pot", reward_name="潮湿的苔藓盆栽", reward_count=1, points=10, item_intro="来自10月9日那天遇见的小渡。一盆植物，耐热喜湿，味道甜甜的，食之什么也不会发生（但是很好吃）。"},
        -- ③⑧ 莎士比亚（4.23）
        {key="shakespeare", name="莎士比亚", holiday="4.23", text="（书的昵称）在4月23日的埃文河畔斯特拉特福遇见了莎士比亚。诗人注视着那条英国小河流，\"To be, or not to be, that is the question……\"（书的昵称）回答道：\"HB, thank you.\"", reward_type="item_and_points", reward_key="m_hb_pencil", reward_name="HB铅笔", reward_count=1, points=10, item_intro="来自4月23日那天遇见的莎士比亚。一支普通的HB铅笔，但使用时会觉得周围冷冷的。"},
        -- ③⑨ Venus（2.14）
        {key="venus", name="Venus", holiday="2.14", text="（书的昵称）在2月14日这天遇见了伟大的爱与美之神Venus！（书的昵称）为女神身上的冲动、狂热、原始的爱欲与美所震撼，心甘情愿地饮下了这金色的毒药。", reward_type="item_and_points", reward_key="m_golden_apple", reward_name="金苹果", reward_count=1, points=10, item_intro="来自2月14日那天遇见的Venus。此金苹果献给最爱阅读的人类！"},
        -- ④0 疯帽子（4.1）
        {key="mad_hatter", name="疯帽子", holiday="4.1", text="（书的昵称）在4月1日的一场疯狂茶会上遇见了茶会的主人疯帽子。你知道为什么一只乌鸦像一张写字台吗？你知道为什么一只乌鸦像一张写字台吗？你知道为什么一只乌鸦像一张写字台吗？你知道为什么一只乌鸦像一张写字台吗？你知道为什么一只乌鸦像一张写字台吗？你知道为什么一只乌鸦像一张写字台吗？", reward_type="item_and_points", reward_key="m_ship_of_fools", reward_name="愚人船", reward_count=1, points=10, item_intro="来自4月1日那天遇见的疯帽子。一艘满载着精神病人、同性恋者、流浪者与行为怪异者的大船，永恒漂流在各个城市之间。"},
        -- ④① 圣诞老人（12.25）
        {key="santa", name="圣诞老人", holiday="12.25", text="（书的昵称）在12月25日圣诞节这天遇见了圣诞老人。一本小书没有袜子，于是圣诞老人把礼物塞进了（书的昵称）的书页缝隙里。", reward_type="item_and_points", reward_key="m_gingerbread_man", reward_name="姜饼人", reward_count=1, points=10, item_intro="来自12月25日圣诞节那天遇见的圣诞老人。一块酥脆美味的小饼干，可以吃，不会逃跑。"},
        -- ④② 威利·旺卡（6.1）
        {key="willy_wonka", name="威利·旺卡", holiday="6.1", text="（书的昵称）在6月1日的巧克力工厂里遇见了工厂主人威利·旺卡。旺卡有着苍白的皮肤、高高的礼帽、破碎的原生家庭和一颗敏感的心……对了，可以看看你的巧克力吗？", reward_type="item_and_points", reward_key="m_chocolate_ticket", reward_name="巧克力工厂参观奖券", reward_count=1, points=10, item_intro="来自6月1日遇见的巧克力工厂主人威利·旺卡，凭此券可入场参观巧克力工厂并领走多多的巧克力制品。"},
    },

    -- ========== 特殊事件 (6 entries) ==========
    -- chance_type: "daily"(每日概率判定) / "tick"(每次检查时判定)
    -- repeatable: 是否可重复发生
    special_events = {
        -- 特殊事件-获赠许愿柳 (概率极低0.2%，发生后永不再发生)
        {key="wish_willow", title="特殊事件-获赠许愿柳", text="（书的昵称）进入一间神秘小店，店员是一位白人男性青年，店内灯光昏暗，墙上挂着蓝粉白三色的旗子。店员微笑着摸了摸（书的昵称）的书脊，把一根神秘红白许愿柳放在书的封面上。（书的昵称）说我想要100积分，掰断了许愿柳。下一秒，本来并不相信的（书的昵称）被大额积分砸昏了……", reward_type="item_and_points", reward_key="m_willow", reward_name="掰成两段的许愿柳", points=100, item_intro="一生只能使用一次的神秘小道具。给人用就会打打杀杀血流成河爱来恨去，不如全部给书用吧！", chance_type="daily", chance=0.002, repeatable=false},
        -- 特殊事件-进入马孔多 (概率低0.5%，可重复)
        {key="macondo", title="特殊事件-进入马孔多", text="（书的昵称）长途跋涉来到一处只有二十户人家的村落，村口有一块小木牌，上面歪歪扭扭地写着Macondo几个字母。（书的昵称）在村子里走来走去，发现全村的人都没有睡眠，还在不断地失去记忆。（书的昵称）孤独地离开了。", reward_type="item", reward_key="m_parchment", reward_name="羊皮卷手稿", item_intro="在此寻索你的死亡日期和情形。", chance_type="daily", chance=0.005, repeatable=true},
        -- 特殊事件-捡到OPPO A5手机 (概率低0.5%，可重复)
        {key="oppo_a5", title="特殊事件-捡到OPPO A5手机", text="（书的昵称）走在路上，突然看到地上有一个小手机。（书的昵称）高兴地捡了起来，没想到，三秒都没过就被炸了……可恶的地雷居然伪装成手机……！", reward_type="item", reward_key="m_oppo", reward_name="OPPO A5手机（已爆炸）", item_intro="一个手机，并不是由地雷伪装而成的。", chance_type="daily", chance=0.005, repeatable=true},
        -- 特殊事件-路遇劫匪 (概率低0.5%，可重复)
        {key="robber", title="特殊事件-路遇劫匪", text="（书的昵称）走着走着，突然遇见了劫匪……经过一番激烈的搏斗，（书的昵称）口袋里的两块五毛八全部被抢走。", reward_type="item", reward_key="m_poor_cert", reward_name="建档立卡贫困户申请资格", item_intro="一经使用，将收到高达3.68元的大额贫困补贴！", chance_type="daily", chance=0.005, repeatable=true},
        -- 特殊事件-中大奖 (概率极低0.1%，可重复)
        {key="jackpot", title="特殊事件-中大奖", text="（书的昵称）路过一家彩票店，进去闭着眼睛选了一个号码，没想到！居然是一等奖……（书的昵称）的运气也太好了！今天内一切发生皆有利于（书的昵称）之主人。", reward_type="points", points=200, chance_type="daily", chance=0.001, repeatable=true},
        -- 特殊事件-大结果 (概率0.5%，可重复)
        {key="big_result", title="特殊事件-大结果", text="（书的昵称）一觉醒来发现自己出现在围场里，并获得火星车×1。书利用自己碾压级别的赛车性能夺得2066年爱肤宜wdc。", reward_type="item", reward_key="m_wdc_cup", reward_name="WDC大奖杯", item_intro="没什么用，但摆着好看，还能装逼。加油！四轮书。", chance_type="daily", chance=0.005, repeatable=true},
    },

    -- ========== 书际关系书名 (127 books) ==========
    -- 随机事件-书际关系中可供随机选择的书名列表
    book_friends = {
        "《远山淡影》", "《米格尔街》", "《克拉拉与太阳》", "《圣母》", "《明亮的夜晚》",
        "《你的夏天还好吗》", "《紫颜色》", "《使女的故事》", "《达洛维太太》",
        "《动物社群：政治性的动物权利论》", "《语言恶女：女性如何夺回语言》",
        "《中国历代政治得失》", "《长日将尽》", "《额尔古纳河右岸》", "《小径分叉的花园》",
        "《佩德罗·巴拉莫》", "《规训与惩罚：监狱的诞生》", "《秋园》", "《看不见的女性》",
        "《奥斯维辛：一部历史》", "《续命：奥斯维辛女子乐队》", "《星辰时刻》",
        "《疯癫与文明》", "《我的天才女友》", "《孽子》", "《江城》", "《金阁寺》",
        "《二手时间》", "《小说课》", "《长恨歌》", "《女性主义》", "《如何阅读福柯》",
        "《灿烂千阳》", "《心是孤独的猎手》", "《流俗地》", "《太古和其他时间》",
        "《等待戈多》", "《始于极限：女性主义往复书简》", "《第二十二条军规》",
        "《梦中的欢快葬礼和十二个异乡故事》", "《三岁女儿》", "《悠悠岁月》",
        "《争权之路》", "《福柯的生死爱欲》", "《台北人》", "《性权利：21世纪的女性主义》",
        "《我走不出我的黑夜》", "《一个女人的故事》", "《潮汐图》",
        "《每一句话都坐着别的眼睛》", "《智利之夜》", "《地球上最后的夜晚》",
        "《濒临狂野的心》", "《莉莉亚娜不可战胜的夏天》", "《萨德侯爵夫人》",
        "《理智与情感》", "《昨日的世界：一个欧洲人的回忆》",
        "《文学之冬：1933年，希特勒统治下的艺术家》", "《我曾这样寂寞生活》",
        "《女孩们的地下战争》", "《被嫌弃的松子的一生》", "《审判》", "《斩首之邀》",
        "《新名字的故事》", "《离开的，留下的》", "《失踪的孩子》", "《碎片》",
        "《纽约客》", "《小夜曲》", "《仲夏之死》", "《太阳与铁》", "《纽约论》",
        "《五号屠场》", "《告白》", "《监禁》", "《阳光劫匪倒转地球》",
        "《叫魂：1768年中国妖术大恐慌》", "《证言》", "《海浪》", "《她的国》",
        "《鳄鱼手记》", "《地粮新粮》", "《我的孤独是一座花园》", "《浮世画家》",
        "《莫失莫忘》", "《一只特立独行的猪》", "《N号房追踪记》", "《草枕》",
        "《一桩事先张扬的凶杀案》", "《没有人给他写信的上校》", "《我不是来演讲的》",
        "《南方高速》", "《肖申克的救赎》", "《孤独旅者》",
        "《关于同一个男人简单生活的想象》", "《我的孩子》", "《万人如海一鸟藏》",
        "《暗处的女儿》", "《最蓝的眼睛》", "《索拉里斯星》", "《惨败》",
        "《人权·法治·民主》", "《绝叫》", "《未来学大会》", "《权利论》",
        "《骂观众》", "《身体、空间与后现代性》", "《规训与惩罚》", "《故乡无用》",
        "《美貌的神话》", "《暮色将尽》", "《胖乎乎圆嘟嘟》", "《世界作为参考答案》",
        "《大众文化的女性主义指南》", "《芭芭雅嘎下了个蛋》", "《多谢不阅》",
        "《应得的权利》", "《制造消费者》", "《东京八平米》", "《神谕女士》",
        "《好好告别》", "《关键词是谋杀》", "《夜神科尔内尔》", "《小脚与西服》",
        "《道德故事集》", "《亲密关系的核心是友谊》", "《初老的女人》",
    },

    -- ========== 书际关系文案模板 (3 templates) ==========
    -- 模板三选一随机，占位符：(书的昵称) 《xxx》 {duration} {activity} {item} {count}
    book_friend_templates = {
        "（书的昵称）交到了一个好朋书，《xxx》与（书的昵称）共同玩耍了{duration}，并留下了{item}×{count}作为见面礼。",
        "（书的昵称）的超级好朋友《xxx》上门拜访，两本书一起去{activity}，《xxx》送了（书的昵称）{item}×{count}。",
        "（书的昵称）与陌生书《xxx》在机缘巧合之下，一见如故，世界之大为何我们相遇？《xxx》忧郁地送出{item}×{count}。",
    },

    -- ========== 书际关系活动选项 ==========
    book_friend_activities = {"图书馆做了全身洗浴", "偷吃了十个棉花糖", "打扫了（书的昵称）家里的卫生"},
    book_friend_durations = {"30min", "1h", "2h"},
}
