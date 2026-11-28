import { HomeCardSmallItem } from '../HomeCardStore';

interface CardAction {
  action: string;
  bundleName: string;
  abilityName: string;
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct HomeCard {
  @LocalStorageProp('statusLine') statusLine: string = '';
  @LocalStorageProp('dateLabel') dateLabel: string = '';
  @LocalStorageProp('smallItems') smallItems: Array<HomeCardSmallItem> = [];

  private openApp(): void {
    const action: CardAction = {
      action: 'router',
      bundleName: 'cn.edu.ubaa',
      abilityName: 'EntryAbility',
    };
    postCardAction(this, action);
  }

  private labelColor(category: string): string {
    if (category === '待办') return '#9A4317';
    if (category === '作业') return '#593CB9';
    return '#174CB6';
  }

  private labelBackground(category: string): string {
    if (category === '待办') return '#FFF0E8';
    if (category === '作业') return '#F1EDFF';
    return '#EAF1FF';
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text('今日')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1B1B1F')
        Blank()
        if (this.dateLabel.length > 0) {
          Text(this.dateLabel)
            .fontSize(10)
            .fontColor('#174CB6')
            .backgroundColor('#EAF1FF')
            .borderRadius(8)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')

      if (this.smallItems.length === 0) {
        Text(this.statusLine)
          .fontSize(12)
          .fontColor('#60636E')
          .margin({ top: 6 })
      } else {
        List() {
          ForEach(this.smallItems, (item: HomeCardSmallItem) => {
            ListItem() {
              Row({ space: 6 }) {
                Text(item.category)
                  .fontSize(9)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.labelColor(item.category))
                  .backgroundColor(this.labelBackground(item.category))
                  .borderRadius(6)
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                Column() {
                  Text(item.title)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1B1B1F')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(item.time)
                      .fontSize(10)
                      .fontColor('#174CB6')
                    if (item.location && item.location.length > 0) {
                      Text(` · ${item.location}`)
                        .fontSize(10)
                        .fontColor('#60636E')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                  }
                  .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ top: 2, bottom: 2 })
            }
          }, (item: HomeCardSmallItem, index: number) => `${index}:${item.category}:${item.title}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.openApp())
  }
}
