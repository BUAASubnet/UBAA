import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'UBAAHarmonySmoke', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, 'UBAAHarmonySmoke', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'UBAAHarmonySmoke', 'Failed to load page: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'UBAAHarmonySmoke', 'Page loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'UBAAHarmonySmoke', 'Window stage destroyed');
  }

  onForeground(): void {
    hilog.info(0x0000, 'UBAAHarmonySmoke', 'Ability foreground');
  }

  onBackground(): void {
    hilog.info(0x0000, 'UBAAHarmonySmoke', 'Ability background');
  }
}
