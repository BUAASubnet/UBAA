use super::*;

// 用合成值保留站点的并排项目、空格缺项、零分和负数结构。
const RESULTS: &str = r#"
<li class="white"><a href="?module=stu&amp;title=stu_ht_score&amp;year=2024-2025_1">2024年</a></li>
<li class="white menu4l_active"><a href="?module=stu&amp;title=stu_ht_score&amp;year=2025-2026_1">2025年</a></li>
<li><a href="https://invalid.example/main.php?module=stu&amp;title=stu_ht_score&amp;year=2099-2100_1">2099年</a></li>
<table class="table_bg">
<tr><td>测试年度</td><td>2025</td><td>最后更新</td><td></td><td>成绩</td><td>49.9(缺项)</td><td>等级</td><td>不及格(缺项)</td></tr>
<tr><td>年级</td><td>大二</td><td>班级</td><td>保留项</td><td>身高</td><td>1.65米</td><td>体重</td><td>56.5千克</td></tr>
</table>
<table class="table_bg">
<tr><td>项目</td><td>成绩</td><td>得分</td><td>等级</td><td>项目</td><td>成绩</td><td>得分</td><td>等级</td></tr>
<tr><td>身体形态(BMI)</td><td>20.8</td><td>100</td><td>正常</td><td>立定跳远</td><td>&nbsp;</td><td></td><td></td></tr>
<tr><td>身体机能(肺活量)</td><td>3900毫升</td><td>84</td><td>良好</td><td>引体向上</td><td>0次</td><td>0</td><td>不及格</td></tr>
<tr><td>50米跑</td><td>7.4秒</td><td>80</td><td>良好</td><td>1000米跑</td><td>4.27分</td><td>60</td><td>及格</td></tr>
<tr><td>坐立体前屈</td><td>-2.3厘米</td><td>20</td><td>不及格</td><td>加分</td><td></td><td>加分原因</td><td></td></tr>
</table>
"#;

#[test]
fn years_metrics_and_zero_are_read_without_fabricating_missing_scores() {
    let data = parse(RESULTS, None, SCORE).unwrap();
    assert_eq!(
        data.years.iter().map(|year| year.year).collect::<Vec<_>>(),
        [2025, 2024]
    );
    assert_eq!(data.selected_year.as_deref(), Some("2025-2026_1"));
    let report = data.report.unwrap();
    assert_eq!(report.height_cm, Some(165.0));
    assert_eq!(report.weight_kg, Some(56.5));
    assert_eq!(report.lung_ml, Some(3900.0));
    assert_eq!(report.reach_cm, Some(-2.3));
    let find = |name: &str| {
        report
            .events
            .iter()
            .find(|event| event.name == name)
            .unwrap()
    };
    assert_eq!(find("立定跳远").result, None);
    assert_eq!(find("引体向上").score, Some(0.0));
    assert_eq!(find("引体向上").result.as_deref(), Some("0次"));
    assert_eq!(find("1000米跑").result.as_deref(), Some("4′27″"));
    assert_eq!(find("1000米跑").grade.as_deref(), Some("及格"));
}

#[test]
fn mismatched_year_and_arbitrary_html_do_not_read_as_requested_scores() {
    assert!(parse(RESULTS, Some("2024-2025_1"), SCORE).is_err());
    assert!(parse("<title>健康云</title><p>上游维护</p>", None, SCORE).is_err());
}

#[test]
fn gateway_wrapped_year_links_keep_the_same_origin_filter() {
    let gateway_year = |key| {
        crate::connection::to_webvpn_url(score_url(Some(key)).as_str())
            .unwrap()
            .replace('&', "&amp;")
    };
    let html = RESULTS
        .replace("?module=stu&amp;title=stu_ht_score&amp;year=2025-2026_1", &gateway_year("2025-2026_1"))
        .replace("?module=stu&amp;title=stu_ht_score&amp;year=2024-2025_1", gateway_year("2024-2025_1").strip_prefix("https://d.buaa.edu.cn").unwrap())
        .replace("https://invalid.example/main.php?module=stu&amp;title=stu_ht_score&amp;year=2099-2100_1",
            &crate::connection::to_webvpn_url("https://invalid.example/main.php?module=stu&title=stu_ht_score&year=2099-2100_1")
                .unwrap().replace('&', "&amp;"));
    let wrapped_page = crate::connection::to_webvpn_url(SCORE).unwrap();
    let page = parse(&html, Some("2025-2026_1"), &wrapped_page).unwrap();
    assert_eq!(
        page.years.iter().map(|year| year.year).collect::<Vec<_>>(),
        [2025, 2024]
    );
}

#[test]
fn alternate_events_keep_the_actual_names() {
    let html = RESULTS
        .replace("1000米跑", "800米跑")
        .replace("引体向上", "仰卧起坐");
    let report = parse(&html, None, SCORE).unwrap().report.unwrap();
    assert!(report.events.iter().any(|event| event.name == "800米跑"));
    assert!(report.events.iter().any(|event| event.name == "仰卧起坐"));
}

#[test]
fn redirects_restrict_authority_and_business_paths() {
    use crate::domain::ConnectionMode::{Direct, WebVpn};
    let entry = score_url(None);
    let callback = entry.join("/index.php?module=user&title=logout").unwrap();
    assert!(redirect(&entry, callback.as_str(), Direct).is_ok());
    assert!(
        redirect(
            &entry,
            "http://10.212.28.38/index.php?action=userLogOut",
            Direct
        )
        .is_err()
    );
    assert!(redirect(&entry, "http://10.212.28.38:8080/main.php", Direct).is_err());
    assert!(redirect(&entry, "https://foreign.example/login", Direct).is_err());
    let wrapped = crate::connection::to_webvpn_url(entry.as_str()).unwrap();
    let wrapped = url::Url::parse(&wrapped).unwrap();
    assert_eq!(
        redirect(&wrapped, callback.as_str(), WebVpn).unwrap(),
        callback
    );
    assert!(redirect(&wrapped, "https://d.buaa.edu.cn/login", WebVpn).is_err());
}
