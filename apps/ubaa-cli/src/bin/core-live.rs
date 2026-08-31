//! Core-live 真实只读验证入口。
//!
//! 该二进制在一个 `RouteClient` 生命周期内完成一条路线的登录和逐操作读取，
//! 只向 stdout 输出安全摘要；凭据仅从 stdin 读取并只在内存中使用。

use std::io::{self, Read as _};
use std::path::PathBuf;
use std::time::Instant;

use clap::Parser;
use ubaa_core::domain::{ConnectionMode, JudgeAssignmentKey, LoginInput, SecretValue, Week};
use ubaa_core::error::{ErrorCode, Result};
use ubaa_core::facade::RouteClient;

#[derive(Debug, Parser)]
#[command(name = "ubaa-core-live", about = "Core 单路线真实只读验证")]
struct Args {
    /// 只允许显式 Direct 或 WebVPN，真实验证不执行 auto。
    #[arg(long)]
    route: String,
    /// 要验证的功能，或 all。
    #[arg(long, default_value = "all")]
    feature: String,
    /// 临时会话目录。
    #[arg(long)]
    config_dir: PathBuf,
    /// 从 stdin 读取用户名第一行。
    #[arg(long)]
    username_stdin: bool,
    /// 从 stdin 读取密码第二行。
    #[arg(long)]
    password_stdin: bool,
    /// 只读日期参数，由外层安全入口提供。
    #[arg(long)]
    date: String,
    /// 空教室校区编号。
    #[arg(long, default_value_t = 1)]
    campus_id: i32,
}

const FEATURES: &[&str] = &[
    "all",
    "auth",
    "user",
    "schedule",
    "exam",
    "grades",
    "classroom",
    "spoc",
    "judge",
    "signin",
    "ygdk",
    "libbook",
    "bykc",
    "cgyy",
    "evaluation",
];

struct Evidence {
    route: &'static str,
    started: Instant,
    failed: bool,
}

impl Evidence {
    fn pass(&self, feature: &str, operation: &str, count: Option<usize>) {
        self.pass_with_fields(feature, operation, count, &[]);
    }

    fn pass_with_fields(
        &self,
        feature: &str,
        operation: &str,
        count: Option<usize>,
        extra_fields: &[(&str, String)],
    ) {
        emit(
            self.route,
            feature,
            operation,
            "PASS",
            None,
            count,
            None,
            self.started.elapsed().as_millis(),
            extra_fields,
        );
    }

    fn fail(&mut self, feature: &str, operation: &str, code: ErrorCode) {
        self.failed = true;
        emit(
            self.route,
            feature,
            operation,
            "FAIL",
            Some(code),
            None,
            None,
            self.started.elapsed().as_millis(),
            &[],
        );
    }

    fn blocked(&mut self, feature: &str, operation: &str, reason: &str) {
        self.failed = true;
        emit(
            self.route,
            feature,
            operation,
            "BLOCKED",
            None,
            None,
            Some(reason),
            self.started.elapsed().as_millis(),
            &[],
        );
    }

    fn not_applicable(&self, feature: &str, operation: &str, reason: &str) {
        emit(
            self.route,
            feature,
            operation,
            "NOT_APPLICABLE",
            None,
            None,
            Some(reason),
            self.started.elapsed().as_millis(),
            &[],
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn emit(
    route: &str,
    feature: &str,
    operation: &str,
    status: &str,
    code: Option<ErrorCode>,
    count: Option<usize>,
    reason: Option<&str>,
    elapsed_ms: u128,
    extra_fields: &[(&str, String)],
) {
    let mut fields = vec![
        format!("route={route}"),
        format!("feature={feature}"),
        format!("stage={feature}"),
        format!("operation={operation}"),
        format!("status={status}"),
        format!("elapsed_ms={elapsed_ms}"),
    ];
    if let Some(code) = code {
        fields.push(format!("error={}", error_code(code)));
    }
    if let Some(count) = count {
        fields.push(format!("count={count}"));
    }
    if let Some(reason) = reason {
        fields.push(format!("reason={reason}"));
    }
    for (key, value) in extra_fields {
        fields.push(format!("{key}={value}"));
    }
    println!("{}", fields.join(" "));
}

fn error_code(code: ErrorCode) -> &'static str {
    match code {
        ErrorCode::InvalidInput => "invalid_input",
        ErrorCode::AuthenticationRequired => "authentication_required",
        ErrorCode::InvalidCredentials => "invalid_credentials",
        ErrorCode::PasswordRiskConfirmationFailed => "password_risk_confirmation_failed",
        ErrorCode::PermissionDenied => "permission_denied",
        ErrorCode::NetworkError => "network_error",
        ErrorCode::Timeout => "timeout",
        ErrorCode::UpstreamUnavailable => "upstream_unavailable",
        ErrorCode::UpstreamChanged => "upstream_changed",
        ErrorCode::ParseError => "parse_error",
        ErrorCode::InternalError => "internal_error",
    }
}

#[tokio::main]
async fn main() {
    init_logging();
    let args = match Args::try_parse() {
        Ok(args) => args,
        Err(error) => {
            let _ = error.print();
            std::process::exit(2);
        }
    };
    let code = match run(args).await {
        Ok(evidence) if evidence.failed => 5,
        Ok(_) => 0,
        Err(error) => {
            eprintln!("core-live 启动失败: {}", error_code(error.code));
            5
        }
    };
    std::process::exit(code);
}

fn init_logging() {
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn"));
    let _ = tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .with_ansi(false)
        .try_init();
}

async fn run(args: Args) -> Result<Evidence> {
    if !args.username_stdin || !args.password_stdin {
        eprintln!("core-live 必须通过 stdin 注入用户名和密码");
        std::process::exit(2);
    }
    let (mode, route_name) = match args.route.as_str() {
        "direct" => (ConnectionMode::Direct, "direct"),
        "webvpn" => (ConnectionMode::WebVpn, "webvpn"),
        _ => {
            eprintln!("core-live 只允许 route=direct 或 route=webvpn");
            std::process::exit(2);
        }
    };
    if !FEATURES.contains(&args.feature.as_str()) {
        eprintln!("core-live 不支持 feature={}", args.feature);
        std::process::exit(2);
    }
    let (username, password) = read_credentials()?;
    let mut client = RouteClient::new(mode, &args.config_dir)?;
    let mut evidence = Evidence {
        route: route_name,
        started: Instant::now(),
        failed: false,
    };
    match client.prepare_login().await {
        Ok(()) => evidence.pass_with_fields(
            "auth",
            "prepare",
            None,
            &[("mapping", "embedded_login_state".to_string())],
        ),
        Err(error) => {
            evidence.fail("auth", "prepare", error.code);
            evidence.blocked("auth", "login", "prepare_failed");
            block_after_auth_failure(&mut evidence, &args.feature);
            return Ok(evidence);
        }
    }
    match client
        .login(LoginInput {
            username,
            password: SecretValue::new(password),
        })
        .await
    {
        Ok(_) => evidence.pass("auth", "login", None),
        Err(error) => {
            evidence.fail("auth", "login", error.code);
            block_after_auth_failure(&mut evidence, &args.feature);
            return Ok(evidence);
        }
    }
    run_auth_status(&mut client, &mut evidence).await;
    run_user(&mut client, &mut evidence, &args.feature).await;
    if args.feature == "auth" || args.feature == "user" {
        return Ok(evidence);
    }
    if args.feature == "all"
        || args.feature == "schedule"
        || args.feature == "exam"
        || args.feature == "grades"
    {
        run_schedule(&mut client, &mut evidence, &args.feature).await;
    }
    if args.feature == "all" || args.feature == "classroom" {
        run_classroom(&mut client, &mut evidence, args.campus_id, &args.date).await;
    }
    if args.feature == "all" || args.feature == "spoc" {
        run_spoc(&mut client, &mut evidence).await;
    }
    if args.feature == "all" || args.feature == "judge" {
        run_judge(&mut client, &mut evidence).await;
    }
    if args.feature == "all" || args.feature == "signin" {
        match client.signin_today().await {
            Ok(result) => evidence.pass("signin", "today", Some(result.data.len())),
            Err(error) => evidence.fail("signin", "today", error.code),
        }
    }
    if args.feature == "all" || args.feature == "ygdk" {
        run_ygdk(&mut client, &mut evidence).await;
    }
    if args.feature == "all" || args.feature == "libbook" {
        run_libbook(&mut client, &mut evidence, &args.date).await;
    }
    if args.feature == "all" || args.feature == "bykc" {
        run_bykc(&mut client, &mut evidence).await;
    }
    if args.feature == "all" || args.feature == "cgyy" {
        run_cgyy(&mut client, &mut evidence, &args.date).await;
    }
    if args.feature == "all" || args.feature == "evaluation" {
        run_evaluation(&mut client, &mut evidence).await;
    }
    Ok(evidence)
}

fn block_after_auth_failure(evidence: &mut Evidence, feature: &str) {
    const ALL: &[(&str, &str)] = &[
        ("auth", "status"),
        ("user", "info"),
        ("schedule", "terms"),
        ("schedule", "weeks"),
        ("schedule", "current"),
        ("schedule", "today"),
        ("exam", "arrangement"),
        ("grades", "query"),
        ("classroom", "search"),
        ("spoc", "assignments"),
        ("spoc", "diagnostics"),
        ("spoc", "detail"),
        ("judge", "include_expired"),
        ("judge", "diagnostics"),
        ("judge", "current"),
        ("judge", "detail"),
        ("judge", "details_batch"),
        ("signin", "today"),
        ("ygdk", "overview"),
        ("ygdk", "records"),
        ("libbook", "libraries"),
        ("libbook", "areas"),
        ("libbook", "area_detail"),
        ("libbook", "seats"),
        ("libbook", "bookings"),
        ("bykc", "profile"),
        ("bykc", "courses"),
        ("bykc", "course_detail"),
        ("bykc", "chosen"),
        ("bykc", "statistics"),
        ("cgyy", "sites"),
        ("cgyy", "purposes"),
        ("cgyy", "day"),
        ("cgyy", "orders"),
        ("cgyy", "order_detail"),
        ("cgyy", "lock_code"),
        ("evaluation", "all"),
        ("evaluation", "pending"),
    ];
    for &(operation_feature, operation) in ALL {
        let selected = feature == "all"
            || feature == operation_feature
            || operation_feature == "auth"
            || (matches!(feature, "exam" | "grades") && operation_feature == "schedule");
        if selected && !(operation_feature == "auth" && operation == "login") {
            evidence.blocked(operation_feature, operation, "authentication_failed");
        }
    }
}

fn read_credentials() -> Result<(String, String)> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).map_err(|_| {
        ubaa_core::error::UbaaError::new(
            ErrorCode::InvalidInput,
            ubaa_core::error::ErrorKind::Input,
            false,
            "无法读取凭据",
        )
    })?;
    let mut lines = input.lines();
    let username = lines.next().unwrap_or_default().to_owned();
    let password = lines.next().unwrap_or_default().to_owned();
    if username.is_empty() || password.is_empty() {
        return Err(ubaa_core::error::UbaaError::new(
            ErrorCode::InvalidInput,
            ubaa_core::error::ErrorKind::Input,
            false,
            "凭据输入不完整",
        ));
    }
    Ok((username, password))
}

async fn run_auth_status(client: &mut RouteClient, evidence: &mut Evidence) {
    match client.auth_status().await {
        Ok(_) => evidence.pass("auth", "status", None),
        Err(error) => evidence.fail("auth", "status", error.code),
    }
}

async fn run_user(client: &mut RouteClient, evidence: &mut Evidence, feature: &str) {
    if feature != "all" && feature != "user" {
        return;
    }
    match client.get_user_info().await {
        Ok(_) => evidence.pass("user", "info", None),
        Err(error) => evidence.fail("user", "info", error.code),
    }
}

async fn run_schedule(client: &mut RouteClient, evidence: &mut Evidence, feature: &str) {
    let terms = match client.schedule_terms().await {
        Ok(result) => {
            evidence.pass("schedule", "terms", Some(result.data.len()));
            result.data
        }
        Err(error) => {
            evidence.fail("schedule", "terms", error.code);
            evidence.blocked("schedule", "weeks", "terms_failed");
            evidence.blocked("schedule", "current", "terms_failed");
            evidence.blocked("schedule", "today", "terms_failed");
            if feature == "all" || feature == "exam" {
                evidence.blocked("exam", "arrangement", "terms_failed");
            }
            if feature == "all" || feature == "grades" {
                evidence.blocked("grades", "query", "terms_failed");
            }
            return;
        }
    };
    let Some(term) = terms
        .iter()
        .find(|term| term.selected)
        .or_else(|| terms.first())
        .map(|term| term.item_code.clone())
    else {
        evidence.blocked("schedule", "weeks", "no_term");
        evidence.blocked("schedule", "current", "no_term");
        evidence.blocked("schedule", "today", "no_term");
        if feature == "all" || feature == "exam" {
            evidence.blocked("exam", "arrangement", "no_term");
        }
        if feature == "all" || feature == "grades" {
            evidence.blocked("grades", "query", "no_term");
        }
        return;
    };
    let weeks = match client.schedule_weeks(&term).await {
        Ok(result) => {
            evidence.pass("schedule", "weeks", Some(result.data.len()));
            result.data
        }
        Err(error) => {
            evidence.fail("schedule", "weeks", error.code);
            evidence.blocked("schedule", "current", "weeks_failed");
            evidence.blocked("schedule", "today", "weeks_failed");
            if feature == "all" || feature == "exam" {
                evidence.blocked("exam", "arrangement", "weeks_failed");
            }
            if feature == "all" || feature == "grades" {
                evidence.blocked("grades", "query", "weeks_failed");
            }
            return;
        }
    };
    if let Some(week) = select_valid_week(&weeks) {
        match client.schedule_week(&term, week).await {
            Ok(_) => evidence.pass("schedule", "current", None),
            Err(error) => evidence.fail("schedule", "current", error.code),
        }
    } else {
        evidence.not_applicable("schedule", "current", "no_valid_week_id");
    }
    match client.schedule_today().await {
        Ok(result) => evidence.pass("schedule", "today", Some(result.data.len())),
        Err(error) => evidence.fail("schedule", "today", error.code),
    }
    if feature == "all" || feature == "exam" {
        match client.exam_arrangement(&term).await {
            Ok(_) => evidence.pass("exam", "arrangement", None),
            Err(error) => evidence.fail("exam", "arrangement", error.code),
        }
    }
    if feature == "all" || feature == "grades" {
        match client.grades(&term).await {
            Ok(_) => evidence.pass("grades", "query", None),
            Err(error) => evidence.fail("grades", "query", error.code),
        }
    }
}

fn select_valid_week(weeks: &[Week]) -> Option<i32> {
    weeks
        .iter()
        .find(|week| week.cur_week && week.serial_number > 0)
        .or_else(|| weeks.iter().find(|week| week.serial_number > 0))
        .map(|week| week.serial_number)
}

async fn run_classroom(
    client: &mut RouteClient,
    evidence: &mut Evidence,
    campus_id: i32,
    date: &str,
) {
    match client.classroom_search(campus_id, date).await {
        Ok(result) => evidence.pass(
            "classroom",
            "search",
            Some(result.data.floors.values().map(Vec::len).sum()),
        ),
        Err(error) => evidence.fail("classroom", "search", error.code),
    }
}

async fn run_spoc(client: &mut RouteClient, evidence: &mut Evidence) {
    let result = match client.spoc_assignments_diagnostics().await {
        Ok(result) => {
            evidence.pass_with_fields(
                "spoc",
                "assignments",
                Some(result.data.result.assignments.len()),
                &[(
                    "global_page_count",
                    result.data.global_page_count.to_string(),
                )],
            );
            evidence.pass_with_fields(
                "spoc",
                "diagnostics",
                Some(result.data.global_page_count as usize),
                &[("reuse_from", "assignments".to_string())],
            );
            result.data
        }
        Err(error) => {
            evidence.fail("spoc", "assignments", error.code);
            evidence.fail("spoc", "diagnostics", error.code);
            evidence.blocked("spoc", "detail", "assignments_failed");
            return;
        }
    };
    if let Some(assignment) = result.result.assignments.first() {
        match client.spoc_assignment(&assignment.assignment_id).await {
            Ok(_) => evidence.pass("spoc", "detail", None),
            Err(error) => evidence.fail("spoc", "detail", error.code),
        }
    } else {
        evidence.not_applicable("spoc", "detail", "no_assignment_id");
    }
}

async fn run_judge(client: &mut RouteClient, evidence: &mut Evidence) {
    match client.judge_assignments_diagnostics(true).await {
        Ok(result) => {
            evidence.pass_with_fields(
                "judge",
                "include_expired",
                Some(result.data.summaries.len()),
                &[
                    ("course_count", result.data.course_count.to_string()),
                    ("raw_anchor_count", result.data.raw_anchor_count.to_string()),
                    (
                        "filtered_unique_count",
                        result.data.filtered_unique_count.to_string(),
                    ),
                ],
            );
            evidence.pass_with_fields(
                "judge",
                "diagnostics",
                Some(result.data.summaries.len()),
                &[("reuse_from", "include_expired".to_string())],
            );
            result.data
        }
        Err(error) => {
            evidence.fail("judge", "include_expired", error.code);
            evidence.fail("judge", "diagnostics", error.code);
            evidence.blocked("judge", "current", "include_expired_failed");
            evidence.blocked("judge", "detail", "include_expired_failed");
            evidence.blocked("judge", "details_batch", "include_expired_failed");
            return;
        }
    };
    let current = match client.judge_assignments(false).await {
        Ok(result) => {
            evidence.pass("judge", "current", Some(result.data.len()));
            result.data
        }
        Err(error) => {
            evidence.fail("judge", "current", error.code);
            evidence.blocked("judge", "detail", "current_failed");
            evidence.blocked("judge", "details_batch", "current_failed");
            return;
        }
    };
    let keys: Vec<_> = current
        .iter()
        .map(|item| JudgeAssignmentKey {
            course_id: item.course_id.clone(),
            assignment_id: item.assignment_id.clone(),
        })
        .collect();
    if keys.is_empty() {
        evidence.not_applicable("judge", "detail", "no_assignment_id");
        evidence.not_applicable("judge", "details_batch", "no_assignment_id");
    } else {
        let first = &keys[0];
        match client
            .judge_assignment(&first.course_id, &first.assignment_id)
            .await
        {
            Ok(_) => evidence.pass("judge", "detail", None),
            Err(error) => evidence.fail("judge", "detail", error.code),
        }
        match client.judge_assignment_details(&keys).await {
            Ok(result) => evidence.pass("judge", "details_batch", Some(result.data.len())),
            Err(error) => evidence.fail("judge", "details_batch", error.code),
        }
    }
}

async fn run_ygdk(client: &mut RouteClient, evidence: &mut Evidence) {
    match client.ygdk_overview().await {
        Ok(result) => evidence.pass("ygdk", "overview", Some(result.data.items.len())),
        Err(error) => evidence.fail("ygdk", "overview", error.code),
    }
    match client.ygdk_records(1, 20).await {
        Ok(result) => evidence.pass("ygdk", "records", Some(result.data.content.len())),
        Err(error) => evidence.fail("ygdk", "records", error.code),
    }
}

async fn run_libbook(client: &mut RouteClient, evidence: &mut Evidence, date: &str) {
    let mut libraries_failed = false;
    let libraries = match client.libbook_libraries(date).await {
        Ok(result) => {
            evidence.pass("libbook", "libraries", Some(result.data.len()));
            result.data
        }
        Err(error) => {
            evidence.fail("libbook", "libraries", error.code);
            evidence.blocked("libbook", "areas", "libraries_failed");
            evidence.blocked("libbook", "area_detail", "libraries_failed");
            evidence.blocked("libbook", "seats", "libraries_failed");
            libraries_failed = true;
            Vec::new()
        }
    };
    if let Some(library) = libraries.first() {
        if let Some(storey) = library.storeys.first() {
            match client
                .libbook_areas(&library.id, Some(&storey.id), date)
                .await
            {
                Ok(result) => {
                    evidence.pass("libbook", "areas", Some(result.data.len()));
                    if let Some(area) = result.data.first() {
                        match client.libbook_area_detail(&area.id).await {
                            Ok(detail) => evidence.pass(
                                "libbook",
                                "area_detail",
                                Some(detail.data.time_slots.len()),
                            ),
                            Err(error) => evidence.fail("libbook", "area_detail", error.code),
                        }
                        match client.libbook_seats(&area.id, date, "00:00", "23:59").await {
                            Ok(result) => {
                                evidence.pass("libbook", "seats", Some(result.data.len()));
                            }
                            Err(error) => evidence.fail("libbook", "seats", error.code),
                        }
                    } else {
                        evidence.not_applicable("libbook", "area_detail", "no_area_id");
                        evidence.not_applicable("libbook", "seats", "no_area_id");
                    }
                }
                Err(error) => {
                    evidence.fail("libbook", "areas", error.code);
                    evidence.blocked("libbook", "area_detail", "areas_failed");
                    evidence.blocked("libbook", "seats", "areas_failed");
                }
            }
        } else {
            evidence.not_applicable("libbook", "areas", "no_storey_id");
            evidence.not_applicable("libbook", "area_detail", "no_storey_id");
            evidence.not_applicable("libbook", "seats", "no_storey_id");
        }
    } else if !libraries_failed {
        evidence.not_applicable("libbook", "areas", "no_library_id");
        evidence.not_applicable("libbook", "area_detail", "no_library_id");
        evidence.not_applicable("libbook", "seats", "no_library_id");
    }
    match client.libbook_bookings(1, 20).await {
        Ok(result) => evidence.pass("libbook", "bookings", Some(result.data.bookings.len())),
        Err(error) => evidence.fail("libbook", "bookings", error.code),
    }
}

async fn run_bykc(client: &mut RouteClient, evidence: &mut Evidence) {
    match client.bykc_profile().await {
        Ok(_) => evidence.pass("bykc", "profile", None),
        Err(error) => evidence.fail("bykc", "profile", error.code),
    }
    let mut courses_failed = false;
    let courses = match client.bykc_courses(1, 20, true).await {
        Ok(result) => {
            evidence.pass("bykc", "courses", Some(result.data.content.len()));
            result.data
        }
        Err(error) => {
            evidence.fail("bykc", "courses", error.code);
            evidence.blocked("bykc", "course_detail", "courses_failed");
            courses_failed = true;
            ubaa_core::domain::BykcCoursePage::default()
        }
    };
    if let Some(course) = courses.content.first() {
        match client.bykc_course_detail(course.id).await {
            Ok(_) => evidence.pass("bykc", "course_detail", None),
            Err(error) => evidence.fail("bykc", "course_detail", error.code),
        }
    } else if !courses_failed {
        evidence.not_applicable("bykc", "course_detail", "no_course_id");
    }
    match client.bykc_chosen_courses().await {
        Ok(result) => evidence.pass("bykc", "chosen", Some(result.data.len())),
        Err(error) => evidence.fail("bykc", "chosen", error.code),
    }
    match client.bykc_statistics().await {
        Ok(_) => evidence.pass("bykc", "statistics", None),
        Err(error) => evidence.fail("bykc", "statistics", error.code),
    }
}

async fn run_cgyy(client: &mut RouteClient, evidence: &mut Evidence, date: &str) {
    let mut sites_failed = false;
    let sites = match client.cgyy_sites().await {
        Ok(result) => {
            evidence.pass("cgyy", "sites", Some(result.data.len()));
            result.data
        }
        Err(error) => {
            evidence.fail("cgyy", "sites", error.code);
            sites_failed = true;
            Vec::new()
        }
    };
    match client.cgyy_purpose_types_diagnostics().await {
        Ok(result) => evidence.pass_with_fields(
            "cgyy",
            "purposes",
            Some(result.data.items.len()),
            &[(
                "source",
                purpose_source_name(result.data.source).to_string(),
            )],
        ),
        Err(error) => evidence.fail("cgyy", "purposes", error.code),
    }
    if let Some(site) = sites.first() {
        match client.cgyy_day_info(site.id, date).await {
            Ok(_) => evidence.pass("cgyy", "day", None),
            Err(error) => evidence.fail("cgyy", "day", error.code),
        }
    } else if sites_failed {
        evidence.blocked("cgyy", "day", "sites_failed");
    } else {
        evidence.not_applicable("cgyy", "day", "no_site_id");
    }
    let mut orders_failed = false;
    let orders = match client.cgyy_orders(0, 20).await {
        Ok(result) => {
            evidence.pass("cgyy", "orders", Some(result.data.content.len()));
            result.data
        }
        Err(error) => {
            evidence.fail("cgyy", "orders", error.code);
            orders_failed = true;
            ubaa_core::domain::CgyyOrdersPage::default()
        }
    };
    if let Some(order) = orders.content.first() {
        match client.cgyy_order_detail(order.id).await {
            Ok(_) => evidence.pass("cgyy", "order_detail", None),
            Err(error) => evidence.fail("cgyy", "order_detail", error.code),
        }
    } else if orders_failed {
        evidence.blocked("cgyy", "order_detail", "orders_failed");
    } else {
        evidence.not_applicable("cgyy", "order_detail", "no_order_id");
    }
    match client.cgyy_lock_code().await {
        Ok(result) => evidence.pass(
            "cgyy",
            "lock_code",
            Some(usize::from(result.data.available)),
        ),
        Err(error) => evidence.fail("cgyy", "lock_code", error.code),
    }
}

fn purpose_source_name(source: ubaa_core::domain::CgyyPurposeSource) -> &'static str {
    match source {
        ubaa_core::domain::CgyyPurposeSource::Upstream => "upstream",
        ubaa_core::domain::CgyyPurposeSource::StaticFallback => "static_fallback",
    }
}

async fn run_evaluation(client: &mut RouteClient, evidence: &mut Evidence) {
    match client.evaluation_all().await {
        Ok(result) => {
            let pending = result
                .data
                .courses
                .iter()
                .filter(|course| !course.is_evaluated)
                .count();
            evidence.pass("evaluation", "all", Some(result.data.courses.len()));
            evidence.pass("evaluation", "pending", Some(pending));
        }
        Err(error) => {
            evidence.fail("evaluation", "all", error.code);
            evidence.blocked("evaluation", "pending", "all_failed");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::select_valid_week;
    use ubaa_core::domain::Week;

    fn week(serial_number: i32, cur_week: bool) -> Week {
        Week {
            serial_number,
            cur_week,
            ..Week::default()
        }
    }

    #[test]
    fn 选择当前且为正数的周次() {
        assert_eq!(select_valid_week(&[week(0, true), week(3, true)]), Some(3));
    }

    #[test]
    fn 当前周无效时选择第一个正数周次() {
        assert_eq!(
            select_valid_week(&[week(0, true), week(-1, false), week(4, false)]),
            Some(4)
        );
    }

    #[test]
    fn 没有有效周次时不猜测默认值() {
        assert_eq!(select_valid_week(&[week(0, false), week(-2, true)]), None);
        assert_eq!(select_valid_week(&[]), None);
    }
}
