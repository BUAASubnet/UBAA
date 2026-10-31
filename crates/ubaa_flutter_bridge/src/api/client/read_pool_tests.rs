use super::*;
use futures_util::FutureExt;

#[tokio::test]
async fn 读取限制八组且同组互斥_写方等待并阻止新读取插队() {
    let root = std::env::temp_dir().join(format!("ubaa-read-pool-{}", std::process::id()));
    let pool = ClientPool::new(UbaaClient::open(&root).unwrap());
    let academic = pool.read(Some(ReadGroup::Academic)).await.unwrap();
    let signin = pool.read(Some(ReadGroup::Signin)).await.unwrap();
    let spoc = pool.read(Some(ReadGroup::Spoc)).await.unwrap();
    let judge = pool.read(Some(ReadGroup::Judge)).await.unwrap();
    assert!(
        pool.read(Some(ReadGroup::Academic))
            .now_or_never()
            .is_none()
    );
    let ygdk = pool.read(Some(ReadGroup::Ygdk)).await.unwrap();
    let bykc = pool.read(Some(ReadGroup::Bykc)).await.unwrap();
    let cgyy = pool.read(Some(ReadGroup::Cgyy)).await.unwrap();
    let profile = pool.read(Some(ReadGroup::Profile)).await.unwrap();
    assert!(pool.permits.try_acquire().is_err());
    let writer = pool.lock();
    tokio::pin!(writer);
    assert!(writer.as_mut().now_or_never().is_none());
    drop(academic);
    // 已有空闲名额仍不能跨过等待读取收尾的写方。
    assert!(
        pool.read(Some(ReadGroup::Academic))
            .now_or_never()
            .is_none()
    );
    drop((signin, spoc, judge, ygdk, bykc, cgyy, profile));
    let mut exclusive = writer.await;
    pool.clear_readers().await;
    assert!(
        pool.read(Some(ReadGroup::Academic))
            .now_or_never()
            .is_none()
    );
    *exclusive = None;
    drop(exclusive);
    assert!(pool.read(Some(ReadGroup::Academic)).await.is_err());
    std::fs::remove_dir_all(root).unwrap();
}
