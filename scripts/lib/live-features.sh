#!/usr/bin/env bash
# Core-live 与 verify-live 共享的受支持功能清单；各入口保留自己的错误文案。

ubaa_live_feature_supported() {
  case "${1:-}" in
    all|auth|user|schedule|exam|grades|classroom|spoc|judge|signin|ygdk|libbook|bykc|cgyy|evaluation)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
