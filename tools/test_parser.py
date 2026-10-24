# -*- coding: utf-8 -*-
"""
小本记账 OCR 解析算法验证脚本（Python 镜像版）
正则与 Services/ReceiptScanner.swift 保持一致，用于在 Windows 上验证算法逻辑。
"""
import re
from datetime import datetime, timedelta

MAX_AMOUNT = 10_000_000.0

# ---------- 归一化：全角转半角 ----------
def normalize(text):
    out = []
    for ch in text:
        o = ord(ch)
        if 0xFF10 <= o <= 0xFF19:      # ０-９
            out.append(chr(o - 0xFEE0))
        elif ch == '．':
            out.append('.')
        elif ch == '／':
            out.append('/')
        elif ch == '－':
            out.append('-')
        else:
            out.append(ch)
    return ''.join(out)

# ---------- 金额 ----------
KEYWORD_PATTERN = r'(?:实付|实收款?|合计|总计|小计|应付|待付款?|付款|收款|金额|支付)(?!时间|日期|单号|订单|流水|号码|方式|工具|账户)[^0-9¥￥$\n]{0,8}[¥￥$]?\s*([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2})?)'
SYMBOL_PATTERN = r'[¥￥$]\s*([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2})?)'
YUAN_PATTERN    = r'([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2}))\s*元'
BARE_PATTERN    = r'(?<![0-9.])([0-9]{1,7}\.[0-9]{2})(?![0-9%‰年月日时])'

def is_date_fragment(s, text, end):
    """捕获到 '2026' 且后面紧跟 年 - . / 的是日期，不是金额"""
    if len(s) == 4 and (s.startswith('19') or s.startswith('20')) and s.isdigit():
        if end < len(text) and text[end] in '年-./':
            return True
    return False

def collect(pattern, text):
    results = []
    for m in re.finditer(pattern, text):
        cap = m.group(1)
        if is_date_fragment(cap, text, m.end(1)):
            continue
        cleaned = cap.replace(',', '').replace('，', '')
        try:
            v = float(cleaned)
        except ValueError:
            continue
        if 0 < v < MAX_AMOUNT:
            results.append(v)
    return results

def parse_amount(text):
    text = normalize(text)
    r = collect(KEYWORD_PATTERN, text)
    if r: return ('关键词', r[-1])
    r = collect(SYMBOL_PATTERN, text)
    if r: return ('货币符号', max(r))
    r = collect(YUAN_PATTERN, text)
    if r: return ('xx元', max(r))
    r = collect(BARE_PATTERN, text)
    if r: return ('裸数字', max(r))
    return (None, None)

# ---------- 日期 ----------
FULL_DATE = r'(20[0-9]{2})[年/\-.](1[0-2]|0?[1-9])[月/\-.](3[01]|[12][0-9]|0?[1-9])日?\s*(?:([01]?[0-9]|2[0-3])[:：时]([0-5][0-9])(?:[:：分]([0-5][0-9])分?)?)?'
SHORT_DATE = r'(?<![0-9])(1[0-2]|0?[1-9])[月/-](3[01]|[12][0-9]|0?[1-9])日?\s*([01]?[0-9]|2[0-3])[:：]([0-5][0-9])(?![0-9])'

def first_date(pattern, text, default_year=None):
    now = datetime.now()
    for m in re.finditer(pattern, text):
        if pattern is FULL_DATE or pattern == FULL_DATE:
            year, month, day, hour, minute = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4), m.group(5)
        else:
            year, month, day, hour, minute = default_year, int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
        try:
            if hour is not None:
                d = datetime(year, month, day, int(hour), int(minute))
            else:
                d = datetime(year, month, day, now.hour, now.minute)
        except ValueError:
            continue  # 2月30日之类
        if default_year is not None and d - now > timedelta(days=1):
            d = d.replace(year=d.year - 1)
            if d - now > timedelta(days=1):
                continue
        elif d - now > timedelta(days=1):
            continue
        return d
    return None

def parse_date(text):
    text = normalize(text)
    now = datetime.now()
    prio = '\n'.join(l for l in text.split('\n') if '时间' in l or '日期' in l)
    for scope in (prio, text):
        if not scope:
            continue
        d = first_date(FULL_DATE, scope)
        if d: return ('完整日期', d)
        d = first_date(SHORT_DATE, scope, now.year)
        if d: return ('短日期', d)
    return (None, None)

# ---------- 测试样本 ----------
CASES = [
    ("微信支付截图",
     "微信支付\n¥25.50\n付款时间 2026-10-24 12:30:02\n支付成功\n当前状态 已支付\n订单号 2026102412330212345678",
     25.50, datetime(2026, 10, 24, 12, 30)),
    ("裁剪截图只有大字金额",
     "25.50",
     25.50, None),
    ("金额不能被日期污染",
     "支付时间：2026-10-24 15:30\n支付金额：¥9.90",
     9.90, datetime(2026, 10, 24, 15, 30)),
    ("支付宝账单",
     "支付宝 账单详情\n-25.00\n交易时间 2026/10/24 08:05\n交易单号 202610242200140368\n付款方式 余额",
     25.00, datetime(2026, 10, 24, 8, 5)),
    ("无小数点金额",
     "美团订单\n实付款：128\n完成",
     128.0, None),
    ("千位分隔符+中文日期",
     "超市小票\n小计 ￥1,234.56\n2026年10月24日 12时30分",
     1234.56, datetime(2026, 10, 24, 12, 30)),
    ("全角字符",
     "￥１２８．００",
     128.00, None),
    ("金额与订单号混排",
     "金额 ¥0.50\n订单号 202610241530220012345678",
     0.50, None),
    ("x.xx元写法",
     "食堂消费 15.50元\n微信付款",
     15.50, None),
    ("短日期无年份",
     "滴滴出行\n10-24 20:15\n行程结束",
     None, None),  # 日期应解析为今年10月24日20:15
]

passed, failed = 0, 0
for name, sample, want_amt, want_dt in CASES:
    rule, amt = parse_amount(sample)
    drank, dt = parse_date(sample)
    ok = True
    msgs = []
    if want_amt is not None:
        if amt is None or abs(amt - want_amt) > 0.001:
            ok = False; msgs.append(f"金额 期望{want_amt} 实际{amt}({rule})")
    if want_dt is not None:
        if dt is None or (dt.year, dt.month, dt.day, dt.hour, dt.minute) != (want_dt.year, want_dt.month, want_dt.day, want_dt.hour, want_dt.minute):
            ok = False; msgs.append(f"时间 期望{want_dt} 实际{dt}({drank})")
    # 额外硬性断言：任何情况下金额绝不能是 2026 / 20261024 这类日期数字
    if amt in (2026.0, 20261024.0, 1024.0, 20.26):
        ok = False; msgs.append(f"金额被日期污染: {amt}")
    if dt is not None:
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: 金额={amt}({rule}) 时间={dt}({drank})")
    else:
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: 金额={amt}({rule}) 时间=无")
    if not ok:
        for msg in msgs:
            print(f"       -> {msg}")
    passed += ok; failed += (not ok)

print(f"\n通过 {passed}/{len(CASES)}")
