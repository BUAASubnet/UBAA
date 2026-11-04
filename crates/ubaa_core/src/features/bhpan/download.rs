use super::parse;
use crate::domain::bhpan::BhpanDownloadPreparation;
use crate::error::Result;

pub(crate) fn inspect(bytes: &[u8], batch: bool) -> Result<BhpanDownloadPreparation> {
    let object: serde_json::Value = parse::json(bytes)?;
    let (raw, headers) = if batch {
        (
            object
                .get("url")
                .and_then(serde_json::Value::as_str)
                .ok_or_else(parse::invalid)?
                .to_owned(),
            Vec::new(),
        )
    } else {
        let a = object
            .get("authrequest")
            .and_then(serde_json::Value::as_array)
            .ok_or_else(parse::invalid)?;
        if a.len() < 2 || a[0].as_str() != Some("GET") {
            return Err(parse::invalid());
        }
        let headers = a
            .iter()
            .skip(2)
            .map(|h| {
                let (name, _) = h
                    .as_str()
                    .and_then(|s| s.split_once(':'))
                    .ok_or_else(parse::invalid)?;
                if name.is_empty() || !name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
                {
                    return Err(parse::invalid());
                }
                Ok(name.to_ascii_lowercase())
            })
            .collect::<Result<Vec<_>>>()?;
        (
            a[1].as_str().ok_or_else(parse::invalid)?.to_owned(),
            headers,
        )
    };
    let url = url::Url::parse(&raw).map_err(|_| parse::invalid())?;
    if url.scheme() != "https"
        || url.port_or_known_default() != Some(443)
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(parse::invalid());
    }
    Ok(BhpanDownloadPreparation {
        host: url.host_str().ok_or_else(parse::invalid)?.into(),
        port: 443,
        method: "GET".into(),
        header_names: headers,
        batch,
        destination_verified: false,
    })
}
