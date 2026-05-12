import { Compose } from 'compose';
import { MainArkUIViewController } from 'libentry.so';

@Entry
@Component
struct Index {
  private controller = MainArkUIViewController()

  onPageShow(): void {
    this.controller.onPageShow()
  }

  onPageHide(): void {
    this.controller.onPageHide()
  }

  onBackPress(): boolean | void {
    return this.controller.onBackPress()
  }

  build() {
    Stack() {
      Compose({
        controller: this.controller,
        libraryName: 'entry',
        onBackPressed: () => false
      }).width('100%').height('100%')
    }.width('100%').height('100%')
  }
}
