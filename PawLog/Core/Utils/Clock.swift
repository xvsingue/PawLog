//
//  Clock.swift
//  PawLog
//
//  可注入的时间源，便于测试时固定「当前时间」。
//

import Foundation

/// 时间源协议
protocol Clock {
    /// 当前时间
    var now: Date { get }
}

/// 系统时钟，返回真实当前时间
struct SystemClock: Clock {
    var now: Date { Date() }
}

/// 固定时钟，测试用
struct FixedClock: Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
}
