//! iHome 只读命令分派。
use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{IhomeArgs, IhomeCommand, ihome::query};
use crate::execute::routed_readonly;
use crate::io::schema::{CliFeature, CommandOutput, readonly};
use ubaa_core::facade::{Result, RoutedResult};
pub(in crate::execute) async fn run_ihome<B: CliBackend + Send>(
    arguments: IhomeArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        IhomeCommand::List {
            scope,
            page,
            limit,
            keyword,
            filter,
            category_id,
        } => backend
            .ihome_page(query(scope, page, limit, keyword, filter, category_id))
            .await
            .and_then(|v| readonly(v, CliFeature::Ihome)),
        IhomeCommand::Detail { id, mine } => backend
            .ihome_detail(id, mine)
            .await
            .and_then(|v| readonly(v, CliFeature::Ihome)),
        IhomeCommand::Config => backend
            .ihome_config()
            .await
            .and_then(|v| readonly(v, CliFeature::Ihome)),
        IhomeCommand::Notices => backend
            .ihome_notices()
            .await
            .and_then(|v| readonly(v, CliFeature::Ihome)),
        IhomeCommand::Notice { id } => backend
            .ihome_notice(id)
            .await
            .and_then(|v| readonly(v, CliFeature::Ihome)),
    }
}
pub(in crate::execute) async fn run_routed_ihome<B: RoutedCliBackend + Send>(
    arguments: IhomeArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        IhomeCommand::List {
            scope,
            page,
            limit,
            keyword,
            filter,
            category_id,
        } => routed_readonly(
            backend
                .ihome_page(query(scope, page, limit, keyword, filter, category_id))
                .await,
            CliFeature::Ihome,
        ),
        IhomeCommand::Detail { id, mine } => {
            routed_readonly(backend.ihome_detail(id, mine).await, CliFeature::Ihome)
        }
        IhomeCommand::Config => routed_readonly(backend.ihome_config().await, CliFeature::Ihome),
        IhomeCommand::Notices => routed_readonly(backend.ihome_notices().await, CliFeature::Ihome),
        IhomeCommand::Notice { id } => {
            routed_readonly(backend.ihome_notice(id).await, CliFeature::Ihome)
        }
    }
}
