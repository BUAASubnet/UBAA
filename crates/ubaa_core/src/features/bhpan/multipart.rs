use super::{object, parse};
use crate::{
    error::Result,
    ports::{HttpMethod, HttpRequest},
};
use serde_json::Value;

pub(crate) const SMALL_MAX: u64 = 100 * 1024 * 1024;
pub(crate) const PART_SIZE: u64 = 20 * 1024 * 1024;
pub(crate) fn parts(bytes: &[u8], count: u64) -> Result<Vec<HttpRequest>> {
    let value: Value = parse::json(bytes)?;
    let auth = value
        .get("authrequests")
        .and_then(Value::as_object)
        .ok_or_else(parse::invalid)?;
    if count == 0 || auth.len() as u64 != count {
        return Err(parse::invalid());
    }
    (1..=count)
        .map(|number| {
            object::authorization(
                auth.get(&number.to_string()).ok_or_else(parse::invalid)?,
                HttpMethod::Put,
            )
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 分片授权必须完整按数字编号且数组方法正确() {
        for bytes in [br#"{"authrequests":{"1":["PUT","https://object.invalid/one"]}}"#.as_slice(),br#"{"authrequests":{"0":["PUT","https://object.invalid/zero"],"2":["PUT","https://object.invalid/two"]}}"#,br#"{"authrequests":{"01":["PUT","https://object.invalid/one"],"2":["PUT","https://object.invalid/two"]}}"#,br#"{"authrequests":{"1":["PUT"],"2":["PUT","https://object.invalid/two"]}}"#] {assert!(parts(bytes,2).is_err());}
        let requests=parts(br#"{"authrequests":{"2":["PUT","https://object.invalid/two"],"1":["PUT","https://object.invalid/one"]}}"#,2).unwrap();
        assert!(requests[0].url.ends_with("/one"));
        assert!(requests[1].url.ends_with("/two"));
    }
}
