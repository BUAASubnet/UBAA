use clap::{CommandFactory, Parser};
use ubaa_cli::{BykcCommand, Cli, Command};

#[test]
fn 博雅课程命令可显式包含已结束课程() {
    let cli = Cli::try_parse_from(["ubaa", "bykc", "courses", "--all"]).unwrap();

    assert!(matches!(
        cli.command,
        Command::Bykc(arguments)
            if matches!(arguments.command, BykcCommand::Courses { all: true, .. })
    ));
}

#[test]
fn clap_has_no_plaintext_password_option() {
    let error = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--mode",
        "direct",
        "--password",
        "forbidden",
    ])
    .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("unexpected argument '--password'")
    );
}

#[test]
fn ordinary_help_hides_route_override_and_lists_readonly_groups() {
    let mut command = Cli::command();
    let help = command.render_long_help().to_string();
    assert!(help.contains("北航统一认证命令行客户端"));
    assert!(help.contains("认证并管理持久化会话"));
    assert!(!help.contains("BUAA unified authentication client"));
    assert!(!help.contains("--mode"));
    for command in ["schedule", "exam", "grades", "classroom", "spoc", "judge"] {
        assert!(
            help.contains(command),
            "missing {command} from top-level help"
        );
    }
    for group in ["spoc", "judge"] {
        let help = command
            .find_subcommand_mut(group)
            .expect("read-only group")
            .render_long_help()
            .to_string();
        assert!(
            !help.contains("diagnostics"),
            "diagnostic command leaked into ordinary {group} help"
        );
    }
}

#[test]
fn cli_debug_formatting_redacts_sensitive_login_arguments() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "USERNAME-SENTINEL",
        "--password-stdin",
    ])
    .unwrap();

    let formatted = format!("{cli:?}");
    let sentinel = "USERNAME-SENTINEL";
    assert!(
        !formatted.contains(sentinel),
        "leaked {sentinel} in {formatted}"
    );
}
