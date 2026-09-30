package numeric

import (
    "js/object"
    "js/str"
    "js/value"
    "math"
    "time"
)

// MARK: the local time zone

/// Zone is what Date needs of the local time zone: the offset from UTC in
/// effect at a UTC time, and the zone's name for toString.
public final class Zone {
    /// Offset is the local offset, in milliseconds, at the UTC time t.
    public let Offset: (float64) -> float64
    /// Name is the zone's long name at t, as toString prints it in
    /// parentheses: "Coordinated Universal Time".
    public let Name: (float64) -> string

    public init(offset: @escaping (float64) -> float64, name: @escaping (float64) -> string) {
        self.Offset = offset
        self.Name = name
    }

    public static let UTC = Zone(offset: { _ in return 0 }, name: { _ in return "Coordinated Universal Time" })
}

/// LocalZone is the zone Date's local-time methods use; a host sets it.
public var LocalZone = Zone.UTC

// MARK: time arithmetic (§21.4.1)

let msPerDay: float64 = 86400000
let msPerHour: float64 = 3600000
let msPerMinute: float64 = 60000
let msPerSecond: float64 = 1000

func Day(_ t: float64) -> float64 { return math.Floor(t / msPerDay) }
func TimeWithinDay(_ t: float64) -> float64 { return math.FloorMod(t, msPerDay) }

func DayFromYear(_ y: float64) -> float64 {
    return 365 * (y - 1970) + math.Floor((y - 1969) / 4) - math.Floor((y - 1901) / 100) + math.Floor((y - 1601) / 400)
}

func TimeFromYear(_ y: float64) -> float64 { return msPerDay * DayFromYear(y) }

func DaysInYear(_ y: float64) -> float64 {
    if math.FloorMod(y, 4) != 0 { return 365 }
    if math.FloorMod(y, 100) != 0 { return 366 }
    if math.FloorMod(y, 400) != 0 { return 365 }
    return 366
}

func YearFromTime(_ t: float64) -> float64 {
    var y = math.Floor(t / (msPerDay * 365.2425)) + 1970
    while TimeFromYear(y) > t { y -= 1 }
    while TimeFromYear(y + 1) <= t { y += 1 }
    return y
}

func InLeapYear(_ t: float64) -> bool { return DaysInYear(YearFromTime(t)) == 366 }

func DayWithinYear(_ t: float64) -> float64 { return Day(t) - DayFromYear(YearFromTime(t)) }

let monthStarts: [float64] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]

func monthStart(_ m: int, _ leap: bool) -> float64 {
    return monthStarts[m] + (leap && m >= 2 ? 1 : 0)
}

func MonthFromTime(_ t: float64) -> float64 {
    let d = DayWithinYear(t)
    let leap = InLeapYear(t)
    var m = 0
    while m < 11 && d >= monthStart(m + 1, leap) { m += 1 }
    return float64(m)
}

func DateFromTime(_ t: float64) -> float64 {
    let m = int(MonthFromTime(t))
    return DayWithinYear(t) - monthStart(m, InLeapYear(t)) + 1
}

func WeekDay(_ t: float64) -> float64 { return math.FloorMod(Day(t) + 4, 7) }
func HourFromTime(_ t: float64) -> float64 { return math.FloorMod(math.Floor(t / msPerHour), 24) }
func MinFromTime(_ t: float64) -> float64 { return math.FloorMod(math.Floor(t / msPerMinute), 60) }
func SecFromTime(_ t: float64) -> float64 { return math.FloorMod(math.Floor(t / msPerSecond), 60) }
func MsFromTime(_ t: float64) -> float64 { return math.FloorMod(t, msPerSecond) }

func toInteger(_ d: float64) -> float64 { return value.ToIntegerOrInfinity(d) }

/// MakeTime (§21.4.1.28).
func MakeTime(_ h: float64, _ m: float64, _ s: float64, _ ms: float64) -> float64 {
    if !h.isFinite || !m.isFinite || !s.isFinite || !ms.isFinite { return float64.nan }
    return toInteger(h) * msPerHour + toInteger(m) * msPerMinute + toInteger(s) * msPerSecond + toInteger(ms)
}

/// MakeDay (§21.4.1.29).
func MakeDay(_ year: float64, _ month: float64, _ date: float64) -> float64 {
    if !year.isFinite || !month.isFinite || !date.isFinite { return float64.nan }
    let y = toInteger(year)
    let m = toInteger(month)
    let dt = toInteger(date)
    let ym = y + math.Floor(m / 12)
    if !ym.isFinite || math.Abs(ym) > 400000 { return float64.nan }
    let mn = int(math.FloorMod(m, 12))
    let t = DayFromYear(ym) + monthStart(mn, DaysInYear(ym) == 366)
    return t + dt - 1
}

/// MakeDate (§21.4.1.30).
func MakeDate(_ day: float64, _ time: float64) -> float64 {
    if !day.isFinite || !time.isFinite { return float64.nan }
    let tv = day * msPerDay + time
    if !tv.isFinite { return float64.nan }
    return tv
}

/// TimeClip (§21.4.1.31).
func TimeClip(_ t: float64) -> float64 {
    if !t.isFinite || math.Abs(t) > 8.64e15 { return float64.nan }
    return toInteger(t) + 0
}

func LocalTime(_ t: float64) -> float64 { return t + LocalZone.Offset(t) }

/// UTCFromLocal is UTC(t) (§21.4.1.26): the offset at the earlier of the
/// candidate instants, as a repeated local time resolves.
func UTCFromLocal(_ t: float64) -> float64 {
    if !t.isFinite { return float64.nan }
    let guess = t - LocalZone.Offset(t)
    return t - LocalZone.Offset(guess)
}

// MARK: formatting

let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func pad(_ n: float64, _ width: int) -> string {
    var s = "\(int64(math.Abs(n)))"
    while s.count < width { s = "0" + s }
    return s
}

func yearString(_ y: float64) -> string {
    return y < 0 ? "-" + pad(y, 6) : pad(y, 4)
}

func dateString(_ lt: float64) -> string {
    return "\(dayNames[int(WeekDay(lt))]) \(monthNames[int(MonthFromTime(lt))]) \(pad(DateFromTime(lt), 2)) \(yearString(YearFromTime(lt)))"
}

func timeString(_ lt: float64) -> string {
    return "\(pad(HourFromTime(lt), 2)):\(pad(MinFromTime(lt), 2)):\(pad(SecFromTime(lt), 2))"
}

func zoneString(_ tv: float64) -> string {
    let off = LocalZone.Offset(tv)
    let mins = math.Abs(off) / msPerMinute
    let sign = off >= 0 ? "+" : "-"
    return "GMT\(sign)\(pad(math.Floor(mins / 60), 2))\(pad(math.FloorMod(mins, 60), 2)) (\(LocalZone.Name(tv)))"
}

/// DateString is ToDateString (§21.4.4.41.4): Date.prototype.toString.
public func DateString(_ tv: float64) -> string {
    if tv.isNaN { return "Invalid Date" }
    let lt = LocalTime(tv)
    return "\(dateString(lt)) \(timeString(lt)) \(zoneString(tv))"
}

/// ISOString is Date.prototype.toISOString's format.
public func ISOString(_ tv: float64) -> string {
    let y = YearFromTime(tv)
    var ys = pad(y, 4)
    if y < 0 || y > 9999 { ys = (y < 0 ? "-" : "+") + pad(y, 6) }
    return "\(ys)-\(pad(MonthFromTime(tv) + 1, 2))-\(pad(DateFromTime(tv), 2))T\(timeString(tv)).\(pad(MsFromTime(tv), 3))Z"
}

func utcString(_ tv: float64) -> string {
    return "\(dayNames[int(WeekDay(tv))]), \(pad(DateFromTime(tv), 2)) \(monthNames[int(MonthFromTime(tv))]) \(yearString(YearFromTime(tv))) \(timeString(tv)) GMT"
}

/// localeDate and localeTime are en-US's numeric forms, as ICU writes
/// toLocaleString without options: "1/2/2024" and "3:04:05 AM".
func localeDate(_ lt: float64) -> string {
    let y = YearFromTime(lt)
    let ys = y <= 0 ? "\(int64(1 - y)) BC" : "\(int64(y))"
    return "\(int(MonthFromTime(lt)) + 1)/\(int(DateFromTime(lt)))/\(ys)"
}

func localeTime(_ lt: float64) -> string {
    let h = int(HourFromTime(lt))
    let h12 = h % 12 == 0 ? 12 : h % 12
    return "\(h12):\(pad(MinFromTime(lt), 2)):\(pad(SecFromTime(lt), 2))\u{202F}\(h < 12 ? "AM" : "PM")"
}

// MARK: parsing

/// Parse is Date.parse: the date time string format (§21.4.1.32), then
/// the forms V8 also accepts -- its own toString and toUTCString output
/// and the common "Month day, year [time]" and "year/month/day" forms.
public func Parse(_ s: string) -> float64 {
    let t = parseISO(s)
    if !t.isNaN { return t }
    return parseLegacy(s)
}

func parseISO(_ s: string) -> float64 {
    let b = Array(s.utf8)
    var i = 0
    func digits(_ n: int) -> float64? {
        if i + n > b.count { return nil }
        var v: float64 = 0
        var k = 0
        while k < n {
            let c = b[i + k]
            if c < 48 || c > 57 { return nil }
            v = v * 10 + float64(c - 48)
            k += 1
        }
        i += n
        return v
    }
    func eat(_ c: uint8) -> bool {
        if i < b.count && b[i] == c { i += 1; return true }
        return false
    }
    var year: float64 = 0
    if i < b.count && (b[i] == 43 || b[i] == 45) {
        let neg = b[i] == 45
        i += 1
        guard let y = digits(6) else { return float64.nan }
        if neg && y == 0 { return float64.nan }
        year = neg ? -y : y
    } else {
        guard let y = digits(4) else { return float64.nan }
        year = y
    }
    var month: float64 = 1
    var day: float64 = 1
    if eat(45) {
        guard let m = digits(2) else { return float64.nan }
        month = m
        if eat(45) {
            guard let d = digits(2) else { return float64.nan }
            day = d
        }
    }
    var h: float64 = 0
    var mi: float64 = 0
    var sec: float64 = 0
    var ms: float64 = 0
    var hasTime = false
    var offset: float64? = nil
    if eat(84) || eat(116) {
        hasTime = true
        guard let hh = digits(2) else { return float64.nan }
        h = hh
        if !eat(58) { return float64.nan }
        guard let mm = digits(2) else { return float64.nan }
        mi = mm
        if eat(58) {
            guard let ss = digits(2) else { return float64.nan }
            sec = ss
            if eat(46) || eat(44) {
                var frac: float64 = 0
                var scale: float64 = 100
                var any = false
                while i < b.count && b[i] >= 48 && b[i] <= 57 {
                    frac += float64(b[i] - 48) * scale
                    scale /= 10
                    i += 1
                    any = true
                }
                if !any { return float64.nan }
                ms = math.Floor(frac)
            }
        }
        if eat(90) || eat(122) {
            offset = 0
        } else if i < b.count && (b[i] == 43 || b[i] == 45) {
            let sign: float64 = b[i] == 45 ? -1 : 1
            i += 1
            guard let oh = digits(2) else { return float64.nan }
            _ = eat(58)
            guard let om = digits(2) else { return float64.nan }
            offset = sign * (oh * 60 + om) * msPerMinute
        }
    } else if eat(90) {
        offset = 0
    }
    if i != b.count { return float64.nan }
    if month < 1 || month > 12 || day < 1 || day > 31 { return float64.nan }
    if h > 24 || mi > 59 || sec > 59 || (h == 24 && (mi > 0 || sec > 0 || ms > 0)) { return float64.nan }
    let dayNum = MakeDay(year, month - 1, day)
    if DateFromTime(MakeDate(dayNum, 0)) != day { return float64.nan }
    var t = MakeDate(dayNum, MakeTime(h, mi, sec, ms))
    if let off = offset {
        t -= off
    } else if hasTime {
        t = UTCFromLocal(t)
    }
    return TimeClip(t)
}

func parseLegacy(_ s: string) -> float64 {
    // Split into words of letters, numbers and the punctuation between.
    var words: [string] = []
    var cur = ""
    var kind = 0 // 1 letters, 2 digits
    for ch in s {
        var k = 0
        if ch.isLetter { k = 1 } else if ch.isNumber { k = 2 }
        if k != 0 && k == kind {
            cur.append(ch)
            continue
        }
        if !cur.isEmpty { words.append(cur) }
        cur = ""
        kind = k
        if k != 0 {
            cur.append(ch)
        } else if ch == ":" || ch == "/" || ch == "+" || ch == "-" || ch == "." {
            words.append(string(ch))
        }
    }
    if !cur.isEmpty { words.append(cur) }

    var year: float64? = nil
    var month: float64? = nil
    var day: float64? = nil
    var h: float64 = 0
    var mi: float64 = 0
    var sec: float64 = 0
    var pm: bool? = nil
    var offset: float64? = nil
    var numbers: [float64] = []
    var i = 0
    while i < words.count {
        let w = words[i]
        let lower = w.lowercased()
        if let first = w.first, first.isNumber {
            let n = float64(int(w) ?? 0)
            if i + 2 < words.count && words[i + 1] == ":" {
                h = n
                mi = float64(int(words[i + 2]) ?? 0)
                i += 3
                if i + 1 < words.count && words[i] == ":" {
                    sec = float64(int(words[i + 1]) ?? 0)
                    i += 2
                }
                if i + 1 < words.count && words[i] == "." { i += 2 }
                continue
            }
            if i + 4 < words.count && words[i + 1] == "/" && words[i + 3] == "/" {
                let a = n
                let b = float64(int(words[i + 2]) ?? 0)
                let c = float64(int(words[i + 4]) ?? 0)
                if w.count >= 3 {
                    year = a; month = b - 1; day = c
                } else {
                    month = a - 1; day = b; year = c
                }
                i += 5
                continue
            }
            numbers.append(n)
            i += 1
            continue
        }
        if lower == "am" || lower == "pm" {
            pm = lower == "pm"
        } else if lower == "gmt" || lower == "utc" || lower == "z" {
            offset = 0
        } else if (w == "+" || w == "-") && i + 1 < words.count, let v = int(words[i + 1]) {
            let sign: float64 = w == "-" ? -1 : 1
            var hh = float64(v)
            var mm: float64 = 0
            if words[i + 1].count == 4 {
                hh = float64(v / 100)
                mm = float64(v % 100)
            } else if i + 3 < words.count && words[i + 2] == ":" {
                mm = float64(int(words[i + 3]) ?? 0)
                i += 2
            }
            if offset == nil || offset == 0 { offset = sign * (hh * 60 + mm) * msPerMinute }
            i += 2
            continue
        } else if w.count >= 3 {
            let p3 = string(lower.prefix(3))
            var mIdx = 0
            while mIdx < 12 {
                if monthNames[mIdx].lowercased() == p3 { break }
                mIdx += 1
            }
            if mIdx < 12 && month == nil { month = float64(mIdx) }
        } else if w == "(" {
            break
        }
        i += 1
    }
    for n in numbers {
        if day == nil && n >= 1 && n <= 31 && month != nil && year == nil && numbers.count >= 2 && n == numbers[0] {
            day = n
        } else if year == nil && (n > 31 || day != nil) {
            year = n
        } else if day == nil {
            day = n
        } else if year == nil {
            year = n
        }
    }
    guard var y = year, let m = month else { return float64.nan }
    if y < 50 { y += 2000 } else if y < 100 { y += 1900 }
    if let p = pm {
        if h > 12 { return float64.nan }
        if p && h < 12 { h += 12 }
        if !p && h == 12 { h = 0 }
    }
    let d = day ?? 1
    var t = MakeDate(MakeDay(y, m, d), MakeTime(h, mi, sec, 0))
    if let off = offset { t -= off } else { t = UTCFromLocal(t) }
    return TimeClip(t)
}

// MARK: Date (§21.4)

func thisTime(_ v: Value, _ method: string) throws -> float64 {
    if case .object(let o) = v, o.Kind == .date, case .number(let t) = o.PrimitiveValue { return t }
    throw object.ThrowTypeError("this is not a Date object.")
}

func setThisTime(_ v: Value, _ t: float64) -> Value {
    if case .object(let o) = v { o.PrimitiveValue = .number(t) }
    return .number(t)
}

func now() -> float64 {
    return float64(time.Timestamp.Now().AsUnixMilliseconds())
}

func installDate(_ r: object.Realm) {
    let dp = r.DatePrototype
    let ctor = r.Constructor("Date", 7, prototype: dp) { _, args, nt in
        guard let n = nt else { return .string(str.JSString.From(DateString(now()))) }
        var tv: float64 = 0
        if args.count == 0 {
            tv = now()
        } else if args.count == 1 {
            let v = args[0]
            if case .object(let o) = v, o.Kind == .date, case .number(let t) = o.PrimitiveValue {
                tv = t
            } else {
                let p = try object.ToPrimitive(v)
                if case .string(let s) = p {
                    tv = Parse(s.String)
                } else {
                    tv = try object.ToNumber(p)
                }
            }
            tv = TimeClip(tv)
        } else {
            var nums: [float64] = []
            for a in args { nums.append(try object.ToNumber(a)) }
            tv = TimeClip(UTCFromLocal(fromComponents(nums)))
        }
        let o = try object.OrdinaryCreateFromConstructor(n, r.DatePrototype)
        o.Kind = .date
        o.PrimitiveValue = .number(tv)
        return .object(o)
    }
    r.Method(ctor, "now", 0) { _, _, _ in return .number(now()) }
    r.Method(ctor, "parse", 1) { _, args, _ in
        return .number(Parse(try object.ToString(object.Arg(args, 0)).String))
    }
    r.Method(ctor, "UTC", 7) { _, args, _ in
        var nums: [float64] = []
        for a in args { nums.append(try object.ToNumber(a)) }
        if nums.isEmpty { return .number(float64.nan) }
        return .number(TimeClip(fromComponents(nums)))
    }

    // Getters.
    let getters: [(string, bool, (float64) -> float64)] = [
        ("getDate", true, DateFromTime), ("getDay", true, WeekDay), ("getFullYear", true, YearFromTime),
        ("getHours", true, HourFromTime), ("getMilliseconds", true, MsFromTime), ("getMinutes", true, MinFromTime),
        ("getMonth", true, MonthFromTime), ("getSeconds", true, SecFromTime),
        ("getUTCDate", false, DateFromTime), ("getUTCDay", false, WeekDay), ("getUTCFullYear", false, YearFromTime),
        ("getUTCHours", false, HourFromTime), ("getUTCMilliseconds", false, MsFromTime), ("getUTCMinutes", false, MinFromTime),
        ("getUTCMonth", false, MonthFromTime), ("getUTCSeconds", false, SecFromTime),
        ("getYear", true, { t in return YearFromTime(t) - 1900 }),
    ]
    for (name, local, f) in getters {
        r.Method(dp, name, 0) { thisV, _, _ in
            let t = try thisTime(thisV, name)
            if t.isNaN { return .number(float64.nan) }
            return .number(f(local ? LocalTime(t) : t))
        }
    }
    r.Method(dp, "getTime", 0) { thisV, _, _ in return .number(try thisTime(thisV, "getTime")) }
    r.Method(dp, "valueOf", 0) { thisV, _, _ in return .number(try thisTime(thisV, "valueOf")) }
    r.Method(dp, "getTimezoneOffset", 0) { thisV, _, _ in
        let t = try thisTime(thisV, "getTimezoneOffset")
        if t.isNaN { return .number(float64.nan) }
        return .number((t - LocalTime(t)) / msPerMinute)
    }

    // Setters: each reads its arguments first, then rebuilds the time.
    r.Method(dp, "setTime", 1) { thisV, args, _ in
        _ = try thisTime(thisV, "setTime")
        return setThisTime(thisV, TimeClip(try object.ToNumber(object.Arg(args, 0))))
    }
    for local in [true, false] {
        let p = local ? "set" : "setUTC"
        func install(_ name: string, _ length: int, _ build: @escaping (float64, [float64], int) -> float64, nanStays: bool) {
            r.Method(dp, p + name, length) { thisV, args, _ in
                let t = try thisTime(thisV, p + name)
                var nums: [float64] = []
                var k = 0
                while k < max(args.count, 1) && k < length {
                    nums.append(try object.ToNumber(object.Arg(args, k)))
                    k += 1
                }
                if t.isNaN && nanStays { return .number(float64.nan) }
                var base = t.isNaN ? 0 : (local ? LocalTime(t) : t)
                if t.isNaN { base = 0 }
                var nt = build(base, nums, args.count)
                if local { nt = UTCFromLocal(nt) }
                return setThisTime(thisV, TimeClip(nt))
            }
        }
        func arg(_ nums: [float64], _ i: int, _ count: int, _ dflt: float64) -> float64 {
            return i < count && i < nums.count ? nums[i] : dflt
        }
        install("Milliseconds", 1, { t, n, c in
            return MakeDate(Day(t), MakeTime(HourFromTime(t), MinFromTime(t), SecFromTime(t), n[0]))
        }, nanStays: true)
        install("Seconds", 2, { t, n, c in
            return MakeDate(Day(t), MakeTime(HourFromTime(t), MinFromTime(t), n[0], arg(n, 1, c, MsFromTime(t))))
        }, nanStays: true)
        install("Minutes", 3, { t, n, c in
            return MakeDate(Day(t), MakeTime(HourFromTime(t), n[0], arg(n, 1, c, SecFromTime(t)), arg(n, 2, c, MsFromTime(t))))
        }, nanStays: true)
        install("Hours", 4, { t, n, c in
            return MakeDate(Day(t), MakeTime(n[0], arg(n, 1, c, MinFromTime(t)), arg(n, 2, c, SecFromTime(t)), arg(n, 3, c, MsFromTime(t))))
        }, nanStays: true)
        install("Date", 1, { t, n, c in
            return MakeDate(MakeDay(YearFromTime(t), MonthFromTime(t), n[0]), TimeWithinDay(t))
        }, nanStays: true)
        install("Month", 2, { t, n, c in
            return MakeDate(MakeDay(YearFromTime(t), n[0], arg(n, 1, c, DateFromTime(t))), TimeWithinDay(t))
        }, nanStays: true)
        install("FullYear", 3, { t, n, c in
            return MakeDate(MakeDay(n[0], arg(n, 1, c, MonthFromTime(t)), arg(n, 2, c, DateFromTime(t))), TimeWithinDay(t))
        }, nanStays: false)
    }
    r.Method(dp, "setYear", 1) { thisV, args, _ in
        let t = try thisTime(thisV, "setYear")
        var y = try object.ToNumber(object.Arg(args, 0))
        if y.isNaN { return setThisTime(thisV, float64.nan) }
        let yi = toInteger(y)
        if yi >= 0 && yi <= 99 { y = 1900 + yi }
        let lt = t.isNaN ? 0 : LocalTime(t)
        let d = MakeDay(y, MonthFromTime(lt), DateFromTime(lt))
        return setThisTime(thisV, TimeClip(UTCFromLocal(MakeDate(d, TimeWithinDay(lt)))))
    }

    // Strings.
    func stringMethod(_ name: string, _ f: @escaping (float64) throws -> string) {
        r.Method(dp, name, 0) { thisV, _, _ in
            let t = try thisTime(thisV, name)
            if t.isNaN && name != "toISOString" { return .string(str.Name("Invalid Date")) }
            return .string(str.JSString.From(try f(t)))
        }
    }
    stringMethod("toString", DateString)
    stringMethod("toDateString", { t in return dateString(LocalTime(t)) })
    stringMethod("toTimeString", { t in return "\(timeString(LocalTime(t))) \(zoneString(t))" })
    stringMethod("toUTCString", utcString)
    stringMethod("toISOString", { t in
        if t.isNaN { throw object.ThrowRangeError("Invalid time value") }
        return ISOString(t)
    })
    stringMethod("toLocaleString", { t in
        let lt = LocalTime(t)
        return "\(localeDate(lt)), \(localeTime(lt))"
    })
    stringMethod("toLocaleDateString", { t in return localeDate(LocalTime(t)) })
    stringMethod("toLocaleTimeString", { t in return localeTime(LocalTime(t)) })
    if let utc = dp.OwnSlot(key("toUTCString")) {
        dp.DefineData(key("toGMTString"), utc.Value, writable: true, enumerable: false, configurable: true)
    }
    r.Method(dp, "toJSON", 1) { thisV, _, _ in
        let o = try object.ToObject(thisV)
        let tv = try object.ToPrimitive(.object(o), .number)
        if case .number(let d) = tv, !d.isFinite { return .null }
        return try object.Invoke(.object(o), key("toISOString"), [])
    }
    r.SymbolMethod(dp, value.SymToPrimitive, 1, writable: false, configurable: true) { thisV, args, _ in
        guard case .object(let o) = thisV else {
            throw object.ThrowTypeError("Date.prototype [ @@toPrimitive ] called on non-object")
        }
        let hint = object.Arg(args, 0)
        guard case .string(let h) = hint else { throw object.ThrowTypeError("Invalid hint: \(object.Describe(hint))") }
        let hs = h.String
        if hs == "string" || hs == "default" { return try object.OrdinaryToPrimitive(o, .string) }
        if hs == "number" { return try object.OrdinaryToPrimitive(o, .number) }
        throw object.ThrowTypeError("Invalid hint: \(hs)")
    }
}

/// fromComponents is the Date constructor's and Date.UTC's reading of
/// year, month[, date, hours, minutes, seconds, ms] (§21.4.2.1 step 5).
func fromComponents(_ n: [float64]) -> float64 {
    var y = n[0]
    let m = n.count > 1 ? n[1] : 0
    let dt = n.count > 2 ? n[2] : 1
    let h = n.count > 3 ? n[3] : 0
    let mi = n.count > 4 ? n[4] : 0
    let s = n.count > 5 ? n[5] : 0
    let ms = n.count > 6 ? n[6] : 0
    if !y.isNaN {
        let yi = toInteger(y)
        if yi >= 0 && yi <= 99 { y = 1900 + yi }
    }
    return MakeDate(MakeDay(y, m, dt), MakeTime(h, mi, s, ms))
}
