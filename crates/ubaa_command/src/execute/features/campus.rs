//! 校园账户命令分派。
use crate::backend::RoutedCliBackend;
use crate::command::{
    FinanceArgs, FinanceCommand, NetworkArgs, NetworkCommand, PortalArgs, PortalCommand,
};
use crate::execute::routed_readonly;
use crate::io::schema::{CliFeature, CommandOutput};
use ubaa_core::facade::RoutedResult;

pub(in crate::execute) async fn routed_portal<B: RoutedCliBackend + Send>(
    arguments: PortalArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        PortalCommand::Profile => {
            routed_readonly(backend.portal_profile().await, CliFeature::Portal)
        }
        PortalCommand::Metrics => {
            routed_readonly(backend.campus_metrics().await, CliFeature::Portal)
        }
    }
}

pub(in crate::execute) async fn routed_network<B: RoutedCliBackend + Send>(
    arguments: NetworkArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        NetworkCommand::Usage => {
            routed_readonly(backend.network_usage().await, CliFeature::Network)
        }
    }
}

pub(in crate::execute) async fn routed_finance<B: RoutedCliBackend + Send>(
    arguments: FinanceArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        FinanceCommand::Incomes => {
            routed_readonly(backend.finance_incomes().await, CliFeature::Finance)
        }
    }
}
