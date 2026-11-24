//! iHome 只读命令分派。
use crate::backend::RoutedCliBackend;
use crate::command::{IhomeArgs, IhomeCommand, ihome::query};
use crate::execute::routed_readonly;
use crate::io::schema::{CliFeature, CommandOutput};
use ubaa_core::facade::RoutedResult;
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
