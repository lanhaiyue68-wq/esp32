"""simpub.py: AgentLoop.publishes in Python, run over the tasks the tests and the stress test use."""
import re, sys
sys.stdout.reconfigure(encoding='utf-8')
SAID = ["發一", "发一", "發個", "发个", "發條", "发条", "發訊息", "发讯息", "發消息", "发消息", "發信息", "发信息",
        "發到", "发到", "發給", "发给", "發送", "发送", "傳給", "传给", "轉發給", "转发给", "轉發到", "转发到",
        "回覆", "回复", "留言", "發評論", "发评论", "寫評論", "写评论", "評論一", "评论一", "發表評論", "发表评论",
        "發帖", "发帖", "發文", "发文", "發布到", "发布到", "發朋友圈", "发朋友圈", "說一聲", "说一声",
        "說一句", "说一句", "傳送", "传送", "send ", "reply ", "post a", "comment on", "leave a comment"]
STRIP = [r"[誰谁]?[發发]的", r"[轉转][發发](?![給给到這这一那該该])", r"[發发][布佈表](?![到一這这])",
         r"(開|开|出|批|沙|爆|自|激|研|散|揮|挥|蒸|奮|奋|頒|颁|引|啟|启|收|头)[發发]",
         r"[發发](現|现|生|票|貨|货|展|音|燒|烧|型|揮|挥|明|光|行|起|射|電|电|財|财|胖|呆|愁|抖|麻|熱|热|炎|病|作|育|芽|酵|達|达|覺|觉|放|售|件)"]

def publishes(task):
    t = re.sub(r"(不要|不用|不必|別|别|勿|禁止|don't|do not|never)[^，,。.；;！!？?\n]*", " ", task.lower())
    if any(w in t for w in SAID): return True
    if re.search(r"(跟|对|對|和|向)(?!我)[^，,。.；;！!？?\n]{1,12}[说說]|告[訴诉](?!我)|(評論|评论|(?<!我)[說说])[：:「“\"]", t): return True
    rest = t
    for w in STRIP: rest = re.sub(w, " ", rest)
    return "發" in rest or "发" in rest

cases = {
    True: ["在微信打開测试群，發一則訊息：你好", "在小紅書第一篇筆記下留言：好看", "把結果發到微信测试群", "用微信傳送「你好」給测试群",
           "跟張三說一聲明天開會", "告訴大家明天放假", "在测试群发一则消息：你好", "去测试群发这不是简简单单吗", "在测试群发你好",
           "在第一篇筆記下評論：好看", "把這條轉發給張三", "把這個影片轉發到测试群", "在微信打開测试群，發一則訊息：壓力測試 115。發完告訴我有沒有發出去",
           "查 AAPL 和 TSLA 的股價，用計算機算差價，發到测试群", "先去测试群发你好，然后告诉我"],
    False: ["打開抖音第一個影片，告訴我影片是誰發的", "告訴我這個影片的按讚、評論、收藏、轉發各是多少", "給我看這個視頻的點讚評論收藏轉發數據",
            "跟我說一下今天深圳的天氣", "用 Safari 打開 www.163.com，告訴我第一條新聞標題", "打開小紅書搜尋杭州旅遊。不要按讚，不要留言",
            "打開小紅書搜尋杭州旅遊，告訴我第一篇筆記的按讚數。不要按讚，不要留言", "在微信打開验证群，告訴我最後一則訊息的內容。不要發訊息",
            "打開 Safari 進新浪網和網易，告訴我兩邊的頭條，再打開抖音告訴我首頁第一個影片是誰發的", "告訴我這篇筆記的發布時間",
            "在淘寶查發票怎麼開", "跟我說：今天幾號", "打開高德地圖，查從現在位置走路到最近的地鐵站要多久。不要開始導航",
            "打開高德地圖，搜尋深圳灣公園附近的停車場，告訴我第一個停車場的名稱和距離。不要開始導航",
            "打開行事曆，告訴我 2027 年 2 月 14 日是星期幾。不要新增任何東西。", "在淘寶搜尋手機殼，告訴我第一個商品有多少人付款。不要購買",
            "打開美團看最近的奶茶店，出發前告訴我要走多久"],
}
bad = [(want, c) for want, cs in cases.items() for c in cs if publishes(c) != want]
readonly = open(sys.argv[1], encoding='utf-8').read()
start = readonly.index('这是主人从微信会话“\\(chat)”交给这台 iPhone 的只读任务')
ro = readonly[start:readonly.index('"""', start)].replace('\\(chat)', '测试群').replace('\\(task)', '看看这个视频的点赞数和口播文案')
phone_start = readonly.index('这是主人从微信会话“\\(chat)”交给这台 iPhone 的手机任务')
phone = readonly[phone_start:readonly.index('"""', phone_start)]
print('read-only owner task publishes:', publishes(ro), '(want False)')
print('phone owner task publishes:', publishes(phone), '(want True)')
print('wrong:', bad or 'none', f'of {sum(map(len, cases.values()))}')
