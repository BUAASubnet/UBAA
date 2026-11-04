//! 校园账户 fixed/routed handler。
use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{NetworkArgs, NetworkCommand, PortalArgs, PortalCommand};
use crate::execute::routed_readonly;
use crate::io::schema::{CliFeature, CommandOutput, readonly};
use ubaa_core::facade::{Result, RoutedResult};

pub(in crate::execute) async fn portal<B: CliBackend + Send>(
    arguments: PortalArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        PortalCommand::Profile => backend
            .portal_profile()
            .await
            .and_then(|v| readonly(v, CliFeature::Portal)),
        PortalCommand::Metrics => backend
            .campus_metrics()
            .await
            .and_then(|v| readonly(v, CliFeature::Portal)),
    }
}

pub(in crate::execute) async fn network<B: CliBackend + Send>(
    arguments: NetworkArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        NetworkCommand::Usage => backend
            .network_usage()
            .await
            .and_then(|v| readonly(v, CliFeature::Network)),
    }
}

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
