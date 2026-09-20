import Foundation

// Local-only secrets for the Contact Support feedback feature (Telegram Bot API).
// This file is committed with EMPTY values on purpose — the repo is public, so the
// real token/chat id must never be typed in here and pushed.
//
// Unlike Secrets.xcconfig (the previous mechanism, kept around for other future
// build-setting-based secrets), this is read directly as a Swift constant — no
// xcconfig, no Info.plist $(VAR) substitution, no build-setting inheritance to get
// wrong. Edit the two values below, rebuild, done.
//
// One-time local setup:
//   1. Fill in the two values below with your own bot token and chat id
//      (see HoursTracker/Utilities/TelegramFeedbackConfig.swift for how to get them).
//   2. Run this once so git stops tracking further edits to this file:
//        git update-index --skip-worktree HoursTracker/Config/LocalSecrets.swift
//
// If you ever need to bring your local edits back under git's radar (e.g. to
// intentionally update the committed placeholder), run:
//        git update-index --no-skip-worktree HoursTracker/Config/LocalSecrets.swift
enum LocalSecrets {
    static let telegramBotToken = ""
    static let telegramChatID = ""
}
