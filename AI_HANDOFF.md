# AI Handoff — Grok → Claude

**التاريخ:** 27 Sep 2026
**آخر commit:** 509dc8a

## ما تم إنجازه
- Step 0.d: طقم QA (3/5 نجحت)
- Step 1.a: Dynamic Type للـ Timer + Live Pay + Clock Out ✅
- Step 1.b.1: greetingHeader → .title2
- Step 1.b.2: HomeCompactStatsStrip → @ScaledMetric
- Step 1.b.3: Wide layout للـ Stat Cards عند AX4+ (جزئي)

## المشكلة الحالية
Compact Layout (3 أعمدة) يقصّ العناوين حتى على AX2:
- SE + AX2: "This mon..."
- Pro + AX2: "This mo..."
Wide Layout (عمود عند AX4+): يعمل بشكل كامل.

## القرار المطلوب
تعديل النصوص في Compact Layout:
- "This month" → "Month"
- "This week" → "Week"
- "Today" → "Today"
Wide Layout يستخدم النص الكامل.

## ملفات مهمة
- HoursTracker/Views/HomeView.swift
- HoursTracker/Views/HomeVitalityViews.swift
- HoursTracker/Resources/Localizable.xcstrings

## قواعد صارمة
1. لا تلمس Timer, Live Pay, Clock Out, Footer
2. لا تلمس تحية Clocked In
3. لا تلمس HomeCompactStatsStrip
4. commit منفصل لكل تعديل
5. اختبار بعد كل commit

## Step 1.c (مؤجل)
Clock In يُقص على SE + AX4/AX5. يحتاج sticky footer.
