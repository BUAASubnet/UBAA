//! 范围快照的内容行写入边界；组件时间、状态和属性类型仍由 icalendar 构造。
use icalendar::{Component, Property, ValueType};
use std::fmt::{self, Write};

pub(super) fn component(out: &mut impl Write, c: &impl Component) -> fmt::Result {
    // 调用方已经显式设置 UID/DTSTAMP，不在写出时生成随机身份或当前时间。
    writeln_crlf(out, &format!("BEGIN:{}", c.component_kind()))?;
    for p in c
        .properties()
        .values()
        .chain(c.multi_properties().values().flatten())
    {
        property(out, p)?;
    }
    for child in c.components() {
        component(out, child)?;
    }
    writeln_crlf(out, &format!("END:{}", c.component_kind()))
}

pub(super) fn property(out: &mut impl Write, p: &Property) -> fmt::Result {
    let mut line = FoldedLine { out, octets: 0 };
    line.write_str(p.key())?;
    for param in p.params().values() {
        write!(line, ";{}=", param.key())?;
        let value = param.value();
        let quoted = value.starts_with('"') && value.ends_with('"');
        let quote = !quoted && value.contains([':', ';', ',']);
        if quote {
            line.write_char('"')?;
        }
        line.write_str(value)?;
        if quote {
            line.write_char('"')?;
        }
    }
    line.write_char(':')?;
    // TEXT 列表由 typed 构造器预先转义；当前范围快照只构造标量属性。
    if p.value_type() == Some(ValueType::Text)
        && !p.key().eq_ignore_ascii_case("CATEGORIES")
        && !p.key().eq_ignore_ascii_case("RESOURCES")
    {
        write_text(&mut line, p.value().chars())?;
    } else {
        line.write_str(p.value())?;
    }
    line.out.write_str("\r\n")
}

fn writeln_crlf(out: &mut impl Write, value: &str) -> fmt::Result {
    let mut line = FoldedLine { out, octets: 0 };
    line.write_str(value)?;
    line.out.write_str("\r\n")
}

fn write_text(out: &mut impl Write, chars: impl Iterator<Item = char>) -> fmt::Result {
    for c in chars {
        match c {
            '\\' => out.write_str("\\\\")?,
            ',' => out.write_str("\\,")?,
            ';' => out.write_str("\\;")?,
            '\n' => out.write_str("\\n")?,
            _ => out.write_char(c)?,
        }
    }
    Ok(())
}

struct FoldedLine<'a, W> {
    out: &'a mut W,
    octets: usize,
}

impl<W: Write> Write for FoldedLine<'_, W> {
    fn write_str(&mut self, mut s: &str) -> fmt::Result {
        while !s.is_empty() {
            let mut end = s.len().min(75 - self.octets);
            // 只检查当前边界，最多回退三个字节，不从字符串开头重新扫描。
            while !s.is_char_boundary(end) {
                end -= 1;
            }
            if end == 0 {
                self.out.write_str("\r\n ")?;
                self.octets = 1; // 续行空格同样占用 75 octets 的预算。
            } else {
                self.out.write_str(&s[..end])?;
                self.octets += end;
                s = &s[end..];
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use icalendar::EventLike;

    #[test]
    fn capacity_failure_stops_consuming_text_before_the_rest_is_escaped() {
        struct Budget(usize);
        impl Write for Budget {
            fn write_str(&mut self, s: &str) -> fmt::Result {
                self.0 = self.0.checked_sub(s.len()).ok_or(fmt::Error)?;
                Ok(())
            }
        }
        for c in ['长', '🙂', '\\', ',', ';', '\n', ' '] {
            let mut consumed = 0;
            let chars = std::iter::repeat_n(c, 1_000_000).inspect(|_| consumed += 1);
            let mut budget = Budget(150);
            let mut line = FoldedLine {
                out: &mut budget,
                octets: 0,
            };
            assert!(write_text(&mut line, chars).is_err());
            assert!(consumed <= 151, "超出输出预算后仍消耗了 {consumed} 个字符");
        }
    }

    #[test]
    fn typed_properties_match_dependency_without_using_its_long_line_folder() {
        let mut event = icalendar::Event::new();
        event
            .timestamp(chrono::DateTime::UNIX_EPOCH)
            .uid("合成身份");
        event.summary("中文🙂\\路径,分号;换行\n尾部空格 ");
        event.starts(chrono::NaiveDate::from_ymd_opt(2026, 3, 1).unwrap());
        event.ends(chrono::NaiveDate::from_ymd_opt(2026, 3, 2).unwrap());
        event.append_property(Property::new("X-TEST", "值,;").add_parameter("PARAM", "甲,乙"));
        let mut actual = String::new();
        component(&mut actual, &event).unwrap();
        // 短内容与原 typed 格式化一致，覆盖 DATE 参数、TEXT 和参数引号。
        assert_eq!(actual, event.to_string());
    }
}
