const storageKey = 'ubaa-comment-visitor'

export function prepareGuest(user, storage, createId = () => crypto.randomUUID()) {
  let id = storage.getItem(storageKey)
  if (!id) {
    id = createId()
    storage.setItem(storageKey, id)
  }
  // Artalk 用邮箱字段区分访客；保留域名仅承载匿名标识，不接收邮件。
  user.logout()
  user.update({ email: `${id}@guest.invalid`, link: '' })
}
