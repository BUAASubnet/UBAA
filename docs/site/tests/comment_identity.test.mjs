import test from 'node:test'
import assert from 'node:assert/strict'
import { prepareGuest } from '../components/comment_identity.js'

function fixture() {
  const values = new Map()
  let data = { name: '同学', email: 'old@example.com', link: 'https://example.com', token: 'old-token' }
  return {
    storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value) },
    user: { getData: () => data, logout: () => { data.token = '' }, update: patch => { data = { ...data, ...patch } } },
  }
}

test('访客保留昵称，清除原邮箱、网址和登录状态，并在再次打开时复用匿名标识', () => {
  const { storage, user } = fixture()
  prepareGuest(user, storage, () => 'visitor-one')
  assert.equal(user.getData().name, '同学')
  assert.equal(user.getData().email, 'visitor-one@guest.invalid')
  assert.equal(user.getData().link, '')
  assert.equal(user.getData().token, '')
  prepareGuest(user, storage, () => { throw new Error('不应重新生成标识') })
  assert.equal(user.getData().email, 'visitor-one@guest.invalid')
})

test('同名访客在不同浏览器使用独立标识', () => {
  const a = fixture(), b = fixture()
  prepareGuest(a.user, a.storage, () => 'visitor-a')
  prepareGuest(b.user, b.storage, () => 'visitor-b')
  assert.notEqual(a.user.getData().email, b.user.getData().email)
})
