use super::parse_response;
use crate::error::ErrorCode;

#[test]
fn classroom_parser_preserves_empty_results() {
    let classroom = parse_response(r#"{"e":0,"m":"ok","d":{"list":{}}}"#).unwrap();
    assert!(classroom.floors.is_empty());
}

#[test]
fn classroom_parser_preserves_nonzero_legacy_code_in_decoded_response() {
    let classroom = parse_response(r#"{"e":1,"m":"legacy status","d":{"list":{"Main":[]}}}"#)
        .expect("frozen classroom parser decodes e without gating its value");
    assert_eq!(classroom.code, 1);
    assert_eq!(classroom.message, "legacy status");
}

#[test]
fn classroom_parser_requires_the_complete_frozen_envelope_and_room_strings() {
    for incomplete in [
        r#"{"m":"ok","d":{"list":{}}}"#,
        r#"{"e":0,"d":{"list":{}}}"#,
        r#"{"e":0,"m":"ok"}"#,
        r#"{"e":0,"m":"ok","d":{}}"#,
        r#"{"e":0,"m":"ok","d":{"list":{"Main":[{"id":"1","floorid":"101","name":"Room"}]}}}"#,
        r#"{"e":0,"m":"ok","d":{"list":{"Main":[{"id":1,"floorid":"101","name":"Room","kxsds":"1,2"}]}}}"#,
    ] {
        let error = parse_response(incomplete)
            .expect_err("missing or non-string frozen fields must not become empty success");
        assert_eq!(error.code, ErrorCode::ParseError);
    }
}
