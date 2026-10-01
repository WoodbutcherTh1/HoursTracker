"""Writes the per-language render configs for the final App Store set.

python3 build.py <shots_dir> [export_ready]
"""
import json
import sys

shots = sys.argv[1]
with_export = len(sys.argv) > 2

POP_HOME = {"x": 54, "y": 690, "w": 1212, "h": 520}
POP_SUMMARY = {"x": 84, "y": 1776, "w": 1152, "h": 624}
POP_HISTORY = {"x": 40, "y": 840, "w": 1240, "h": 560}
POP_SETTINGS = {"x": 40, "y": 2070, "w": 1240, "h": 520}

LANGS = {
    "english": {
        "island": {"t": "03:25:16", "v": "₪223.16"},
        "net": "₪215.43",
        "slides": [
            (["See what you ", "earn", "<br>— live"], "One tap to clock in. Watch your pay grow every second."),
            (["Every shift.<br>", "Gross &amp; net.", ""], "125%, 150%, Shabbat — calculated for you."),
            (["All your hours.<br>", "One place.", ""], "Every shift, week and month — at a glance."),
            (["Your report,<br>", "ready to send", ""], "A PDF or CSV for your employer, in seconds."),
            (["Overtime &amp; tax.<br>", "Built in.", ""], "Israeli labor rules. Set your rate once — the app does the math."),
        ],
        "chips": {"net": "Net this shift", "hours": "Hours this month", "ot": "Overtime, automatic"},
    },
    "hebrew": {
        "island": {"t": "03:25:19", "v": "₪223.22"},
        "net": "₪ 215.47",
        "slides": [
            (["רואים כמה ", "מרוויחים", "<br>בזמן אמת"], "לחיצה אחת לכניסה. השכר גדל כל שנייה."),
            (["כל משמרת —<br>", "ברוטו ונטו", ""], "‏125%, 150%, שבת — הכול מחושב בשבילך."),
            (["כל השעות שלך<br>", "במקום אחד", ""], "כל משמרת, שבוע וחודש — במבט אחד."),
            (["הדוח שלך<br>", "מוכן לשליחה", ""], "‏PDF או CSV למעסיק — תוך שניות."),
            (["שעות נוספות ומס —<br>", "מחושב אוטומטית", ""], "לפי חוקי העבודה בישראל. מגדירים שכר פעם אחת."),
        ],
        "chips": {"net": "נטו למשמרת", "hours": "שעות החודש", "ot": "שעות נוספות — אוטומטי"},
    },
    "arabic": {
        "island": {"t": "03:25:17", "v": "₪223.18"},
        "net": "₪ 215.41",
        "slides": [
            (["شوف قديش ", "بتربح", "<br>لحظة بلحظة"], "كبسة وحدة للدخول، وراتبك بكبر كل ثانية."),
            (["كل وردية —<br>", "إجمالي وصافي", ""], "‏125%، 150%، السبت — كله محسوب إلك."),
            (["كل ساعاتك<br>", "بمكان واحد", ""], "كل وردية، أسبوع وشهر — بنظرة وحدة."),
            (["تقريرك<br>", "جاهز للإرسال", ""], "‏PDF أو CSV لصاحب الشغل — بثواني."),
            (["الإضافي والضريبة<br>", "محسوبين تلقائياً", ""], "حسب قوانين العمل بإسرائيل. بتحط راتبك مرة وحدة."),
        ],
        "chips": {"net": "صافي الوردية", "hours": "ساعات الشهر", "ot": "ساعات إضافية — تلقائي"},
    },
}

for lang, c in LANGS.items():
    s = c["slides"]
    slides = [
        {"img": f"{shots}/{lang}-01_Home.jpg", "head": s[0][0], "sub": s[0][1], "island": c["island"], "pop": POP_HOME},
        {"img": f"{shots}/{lang}-02_DaySummary.jpg", "head": s[1][0], "sub": s[1][1], "pop": POP_SUMMARY,
         "chip": {"k": c["chips"]["net"], "v": c["net"]}, "chipTop": 1480},
        {"img": f"{shots}/{lang}-03_History.jpg", "head": s[2][0], "sub": s[2][1], "pop": POP_HISTORY,
         "chip": {"k": c["chips"]["hours"], "v": "202:55"}, "chipTop": 2380},
    ]
    if with_export:
        pop = {"x": 54, "y": 2140 if lang == "arabic" else 2070, "w": 1212, "h": 520}
        gross = {"english": "Gross this month", "hebrew": "ברוטו החודש", "arabic": "إجمالي الشهر"}[lang]
        slides.append({"img": f"{shots}/{lang}-04_Export.jpg", "head": s[3][0], "sub": s[3][1], "pop": pop,
                       "chip": {"k": gross, "v": "₪12,611"}, "chipTop": 1350})
    slides.append({"img": f"{shots}/{lang}-05_Settings.jpg", "head": s[4][0], "sub": s[4][1], "pop": POP_SETTINGS,
                   "chip": {"k": c["chips"]["ot"], "v": "125% · 150%"}, "chipTop": 1500})
    json.dump({"style": "hero", "lang": lang, "out": f"final/{lang}", "slides": slides},
              open(f"cfg-{lang}.json", "w"), ensure_ascii=False, indent=1)
print("ok")
