use super::{object, parse};
use crate::domain::bhpan::BhpanDownloadPreparation;
use crate::error::Result;

pub(crate) fn inspect(bytes: &[u8], batch: bool) -> Result<BhpanDownloadPreparation> {
    let request = object::download(bytes, batch)?;
    let url = url::Url::parse(&request.url).map_err(|_| parse::invalid())?;
    Ok(BhpanDownloadPreparation {
        host: url.host_str().ok_or_else(parse::invalid)?.into(),
        port: url.port_or_known_default().ok_or_else(parse::invalid)?,
        method: "GET".into(),
        header_names: request.headers.into_keys().collect(),
        batch,
        destination_verified: false,
    })
}
