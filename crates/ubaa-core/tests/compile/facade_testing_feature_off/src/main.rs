use ubaa_core::facade::testing::{
    ConnectionMode, FileSessionStore, GatewayProbe, HttpTransport, RouteConfig, SessionStore,
};
use ubaa_core::facade::{RouteClient, UbaaClient};

#[allow(dead_code)]
fn route_client_with_transport<T, S>(mode: ConnectionMode, transport: T, store: S)
where
    T: HttpTransport + 'static,
    S: SessionStore + 'static,
{
    let _ = RouteClient::with_transport(mode, transport, store);
}

#[allow(dead_code)]
fn ubaa_client_with_transports<TDirect, TWebVpn>(
    direct: TDirect,
    webvpn: TWebVpn,
    store: FileSessionStore,
) where
    TDirect: HttpTransport + 'static,
    TWebVpn: HttpTransport + 'static,
{
    let _ = UbaaClient::with_transports(direct, webvpn, store);
}

#[allow(dead_code)]
fn ubaa_client_with_routing<TDirect, TWebVpn, P>(
    direct: TDirect,
    webvpn: TWebVpn,
    store: FileSessionStore,
    config: RouteConfig,
    probe: P,
) where
    TDirect: HttpTransport + 'static,
    TWebVpn: HttpTransport + 'static,
    P: GatewayProbe + 'static,
{
    let _ = UbaaClient::with_routing(direct, webvpn, store, config, probe);
}

fn main() {}
